################################################################################
# Compute Engine Module — Main (Single VM)
#
# CREATE-THEN-DEPLOY STRATEGY:
#   1. Creates a dedicated service account for the VM (least privilege).
#   2. Provisions the VM with a startup script for application bootstrap.
#   3. Sets up firewall rules for health checks and service traffic.
#   4. Optionally allocates a static external IP.
#
# The actual application deployment (uploading code, restarting the service)
# is handled by the GitHub Actions workflow AFTER Terraform ensures the
# VM and networking are ready.
#
# DEPLOYMENT METHOD for Compute Engine:
#   After Terraform creates/verifies the VM, the workflow:
#   1. Uploads the build artifact to a GCS bucket.
#   2. SSHs into the VM (or uses `gcloud compute ssh`) to:
#      a. Pull the artifact from GCS.
#      b. Run the deployment/restart script.
#   3. Runs a healthcheck against the VM's IP.
################################################################################

locals {
  config = jsondecode(var.platform_config)

  machine_type          = try(local.config.machine_type, "e2-medium")
  disk_size_gb          = try(local.config.disk_size_gb, 20)
  disk_type             = try(local.config.disk_type, "pd-ssd")
  image_family          = try(local.config.image_family, "ubuntu-2204-lts")
  image_project         = try(local.config.image_project, "ubuntu-os-cloud")
  network               = try(local.config.network, "default")
  subnet                = try(local.config.subnet, "default")
  tags                  = try(local.config.tags, ["http-server", "https-server"])
  startup_script_path   = try(local.config.startup_script_path, null)
  service_account_email = try(local.config.service_account_email, null)
  zone                  = try(local.config.zone, "${var.region}-a")
  enable_static_ip      = try(local.config.enable_static_ip, true)
  service_port          = try(local.config.service_port, 8080)
}

# ─── Enable Required APIs ────────────────────────────────────────────────────

resource "google_project_service" "compute" {
  project = var.gcp_project_id
  service = "compute.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "iam" {
  project = var.gcp_project_id
  service = "iam.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# ─── Service Account ─────────────────────────────────────────────────────────
# WHY: Each service gets its own SA for least-privilege access.
# The SA is only created if one isn't specified in the config.

resource "google_service_account" "vm_sa" {
  count = local.service_account_email == null ? 1 : 0

  project      = var.gcp_project_id
  account_id   = "sa-${var.service_name}"
  display_name = "Service Account for ${var.service_name} (${var.environment})"

  depends_on = [google_project_service.iam]
}

# Grant the SA permission to pull from GCS (for artifact downloads)
resource "google_project_iam_member" "sa_storage_viewer" {
  count = local.service_account_email == null ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

# Grant the SA permission to write logs
resource "google_project_iam_member" "sa_log_writer" {
  count = local.service_account_email == null ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

# Grant the SA permission to export metrics
resource "google_project_iam_member" "sa_metric_writer" {
  count = local.service_account_email == null ? 1 : 0

  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_sa[0].email}"
}

# ─── Static External IP ──────────────────────────────────────────────────────

resource "google_compute_address" "static_ip" {
  count = local.enable_static_ip ? 1 : 0

  name    = "${var.service_name}-${var.environment}-ip"
  project = var.gcp_project_id
  region  = var.region

  depends_on = [google_project_service.compute]
}

# ─── Firewall Rules ──────────────────────────────────────────────────────────
# WHY: Explicit firewall rules instead of relying on the default network's
# default rules. This makes the security posture auditable.

resource "google_compute_firewall" "allow_http" {
  name    = "${var.service_name}-${var.environment}-allow-http"
  project = var.gcp_project_id
  network = local.network

  allow {
    protocol = "tcp"
    ports    = [tostring(local.service_port)]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = local.tags

  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "allow_health_check" {
  name    = "${var.service_name}-${var.environment}-allow-hc"
  project = var.gcp_project_id
  network = local.network

  allow {
    protocol = "tcp"
    ports    = [tostring(local.service_port)]
  }

  # Google Cloud health check IP ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = local.tags

  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.service_name}-${var.environment}-allow-ssh"
  project = var.gcp_project_id
  network = local.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP tunnel IP range — allows SSH via `gcloud compute ssh` without
  # exposing port 22 to the public internet.
  source_ranges = ["35.235.240.0/20"]
  target_tags   = local.tags

  depends_on = [google_project_service.compute]
}

# ─── GCS Bucket for Deployment Artifacts ─────────────────────────────────────

resource "google_storage_bucket" "deploy_artifacts" {
  name     = "${var.gcp_project_id}-${var.service_name}-deploy"
  project  = var.gcp_project_id
  location = var.region

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels
}

# ─── Compute Instance ────────────────────────────────────────────────────────

resource "google_compute_instance" "vm" {
  name         = "${var.service_name}-${var.environment}"
  project      = var.gcp_project_id
  zone         = local.zone
  machine_type = local.machine_type
  tags         = local.tags
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = "projects/${local.image_project}/global/images/family/${local.image_family}"
      size  = local.disk_size_gb
      type  = local.disk_type
    }
  }

  network_interface {
    network    = local.network
    subnetwork = local.subnet

    # Only attach an external IP if static IP is enabled
    dynamic "access_config" {
      for_each = local.enable_static_ip ? [1] : []
      content {
        nat_ip = google_compute_address.static_ip[0].address
      }
    }
  }

  # Metadata for passing environment variables and config to the VM
  metadata = merge(
    {
      "service-name"     = var.service_name
      "environment"      = var.environment
      "deploy-bucket"    = google_storage_bucket.deploy_artifacts.name
      "health-check-path" = var.health_check_path
    },
    { for k, v in var.env_variables : "env-${k}" => v }
  )

  # Startup script — runs on every boot
  metadata_startup_script = local.startup_script_path != null ? file(local.startup_script_path) : <<-EOF
    #!/bin/bash
    # Default startup script — installs basic dependencies
    set -euo pipefail

    # Install ops agent for logging and monitoring
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    sudo bash add-google-cloud-ops-agent-repo.sh --also-install

    echo "Startup complete for ${var.service_name} (${var.environment})"
  EOF

  service_account {
    email  = local.service_account_email != null ? local.service_account_email : google_service_account.vm_sa[0].email
    scopes = ["cloud-platform"]
  }

  # Allow stopping the VM for updates (machine type changes, etc.)
  allow_stopping_for_update = true

  lifecycle {
    # Prevent accidental deletion in production
    prevent_destroy = false  # Set to true for production via environment override
  }

  depends_on = [
    google_project_service.compute,
    google_storage_bucket.deploy_artifacts,
  ]
}
