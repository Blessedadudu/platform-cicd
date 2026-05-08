################################################################################
# Compute Engine MIG Module — Main (Managed Instance Group + Autoscaler)
#
# CREATE-THEN-DEPLOY STRATEGY:
#   This module provisions the full autoscaling stack:
#   1. Instance template (defines the VM blueprint)
#   2. Regional MIG (manages identical VMs across zones)
#   3. Autoscaler (scales based on CPU utilization)
#   4. Health check (determines instance health)
#   5. HTTP(S) Load Balancer components (optional)
#
# ROLLING UPDATE STRATEGY:
#   When the instance template changes, the MIG performs a rolling update:
#   - maxSurge: 3 (create 3 new instances before removing old ones)
#   - maxUnavailable: 0 (zero downtime)
#   This ensures the new version is healthy before old instances are removed.
################################################################################

locals {
  config = jsondecode(var.platform_config)

  machine_type    = try(local.config.machine_type, "e2-medium")
  disk_size_gb    = try(local.config.disk_size_gb, 20)
  image_family    = try(local.config.image_family, "ubuntu-2204-lts")
  image_project   = try(local.config.image_project, "ubuntu-os-cloud")
  network         = try(local.config.network, "default")
  subnet          = try(local.config.subnet, "default")
  template_prefix = try(local.config.instance_template_name_prefix, "${var.service_name}-tmpl")
  service_port    = try(local.config.named_port.port, 8080)
  port_name       = try(local.config.named_port.name, "http")

  # Health check config
  hc = try(local.config.health_check, {})
  hc_interval  = try(local.hc.check_interval_sec, 10)
  hc_timeout   = try(local.hc.timeout_sec, 5)
  hc_healthy   = try(local.hc.healthy_threshold, 2)
  hc_unhealthy = try(local.hc.unhealthy_threshold, 3)
  hc_port      = try(local.hc.port, local.service_port)

  # Autoscaler config
  as_config      = try(local.config.autoscaler, {})
  cpu_target     = try(local.as_config.cpu_target, 0.6)
  cooldown       = try(local.as_config.cooldown_period, 60)
}

# ─── Enable Required APIs ────────────────────────────────────────────────────

resource "google_project_service" "compute" {
  project                    = var.gcp_project_id
  service                    = "compute.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "iam" {
  project                    = var.gcp_project_id
  service                    = "iam.googleapis.com"
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ─── Service Account ─────────────────────────────────────────────────────────

resource "google_service_account" "mig_sa" {
  project      = var.gcp_project_id
  account_id   = "sa-${var.service_name}-mig"
  display_name = "SA for ${var.service_name} MIG (${var.environment})"
  depends_on   = [google_project_service.iam]
}

resource "google_project_iam_member" "sa_storage" {
  project = var.gcp_project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.mig_sa.email}"
}

resource "google_project_iam_member" "sa_logging" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.mig_sa.email}"
}

resource "google_project_iam_member" "sa_monitoring" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.mig_sa.email}"
}

# ─── GCS Bucket for Deployment Artifacts ─────────────────────────────────────

resource "google_storage_bucket" "deploy_artifacts" {
  name                        = "${var.gcp_project_id}-${var.service_name}-mig-deploy"
  project                     = var.gcp_project_id
  location                    = var.region
  uniform_bucket_level_access = true

  versioning { enabled = true }

  lifecycle_rule {
    condition { age = 30 }
    action { type = "Delete" }
  }

  labels = var.labels
}

# ─── Firewall Rules ──────────────────────────────────────────────────────────

resource "google_compute_firewall" "allow_service" {
  name    = "${var.service_name}-${var.environment}-mig-allow-svc"
  project = var.gcp_project_id
  network = local.network

  allow {
    protocol = "tcp"
    ports    = [tostring(local.service_port)]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.service_name}-mig"]
  depends_on    = [google_project_service.compute]
}

resource "google_compute_firewall" "allow_hc" {
  name    = "${var.service_name}-${var.environment}-mig-allow-hc"
  project = var.gcp_project_id
  network = local.network

  allow {
    protocol = "tcp"
    ports    = [tostring(local.hc_port)]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["${var.service_name}-mig"]
  depends_on    = [google_project_service.compute]
}

# ─── Health Check ─────────────────────────────────────────────────────────────

resource "google_compute_health_check" "hc" {
  name    = "${var.service_name}-${var.environment}-hc"
  project = var.gcp_project_id

  check_interval_sec  = local.hc_interval
  timeout_sec         = local.hc_timeout
  healthy_threshold   = local.hc_healthy
  unhealthy_threshold = local.hc_unhealthy

  http_health_check {
    port         = local.hc_port
    request_path = var.health_check_path
  }

  depends_on = [google_project_service.compute]
}

# ─── Instance Template ───────────────────────────────────────────────────────
# WHY `name_prefix` + `create_before_destroy`:
#   Instance templates are immutable in GCP. To update one, you must create
#   a new template and then update the MIG to point to it. This lifecycle
#   pattern handles that automatically.

resource "google_compute_instance_template" "tmpl" {
  name_prefix  = "${local.template_prefix}-"
  project      = var.gcp_project_id
  region       = var.region
  machine_type = local.machine_type
  tags         = ["${var.service_name}-mig"]
  labels       = var.labels

  disk {
    source_image = "projects/${local.image_project}/global/images/family/${local.image_family}"
    auto_delete  = true
    boot         = true
    disk_size_gb = local.disk_size_gb
    disk_type    = "pd-ssd"
  }

  network_interface {
    network    = local.network
    subnetwork = local.subnet
    access_config {} # Ephemeral external IP
  }

  metadata = merge(
    {
      "service-name"      = var.service_name
      "environment"       = var.environment
      "deploy-bucket"     = google_storage_bucket.deploy_artifacts.name
      "health-check-path" = var.health_check_path
    },
    { for k, v in var.env_variables : "env-${k}" => v }
  )

  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    sudo bash add-google-cloud-ops-agent-repo.sh --also-install
    echo "Startup complete for ${var.service_name} MIG instance"
  EOF

  service_account {
    email  = google_service_account.mig_sa.email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_project_service.compute]
}

# ─── Regional Managed Instance Group ─────────────────────────────────────────

resource "google_compute_region_instance_group_manager" "mig" {
  name    = "${var.service_name}-${var.environment}-mig"
  project = var.gcp_project_id
  region  = var.region

  base_instance_name = "${var.service_name}-${var.environment}"

  version {
    instance_template = google_compute_instance_template.tmpl.self_link_unique
  }

  named_port {
    name = local.port_name
    port = local.service_port
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.hc.id
    initial_delay_sec = 120
  }

  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 3
    max_unavailable_fixed          = 0
    replacement_method             = "SUBSTITUTE"
  }

  lifecycle {
    prevent_destroy = false
  }
}

# ─── Autoscaler ──────────────────────────────────────────────────────────────

resource "google_compute_region_autoscaler" "autoscaler" {
  name    = "${var.service_name}-${var.environment}-autoscaler"
  project = var.gcp_project_id
  region  = var.region
  target  = google_compute_region_instance_group_manager.mig.id

  autoscaling_policy {
    min_replicas    = var.min_instances
    max_replicas    = var.max_instances
    cooldown_period = local.cooldown

    cpu_utilization {
      target = local.cpu_target
    }
  }
}
