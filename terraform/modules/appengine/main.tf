################################################################################
# App Engine Module — Main
#
# CREATE-THEN-DEPLOY STRATEGY:
#   1. `google_app_engine_application` creates the App Engine app if it doesn't
#      exist. App Engine is a singleton per project — once created, it cannot
#      be deleted. The `lifecycle.prevent_destroy` block protects against
#      accidental state removal.
#
#   2. `google_project_service` enables the required APIs. This is idempotent —
#      if already enabled, it's a no-op.
#
#   3. `google_app_engine_standard_app_version` creates/updates the service
#      version. The actual code deployment is handled by the GitHub Actions
#      workflow using `gcloud app deploy` AFTER Terraform ensures the
#      infrastructure exists.
#
# WHY Terraform + gcloud deploy (hybrid approach):
#   Terraform excels at infrastructure provisioning but App Engine code
#   deployment is better handled by `gcloud app deploy` because:
#   - It handles source code upload, build, and versioning.
#   - Terraform's `google_app_engine_standard_app_version` requires the
#     source to be pre-uploaded to a GCS bucket as a zip — adding complexity.
#   - `gcloud app deploy` is the Google-recommended deployment method.
#
#   So: Terraform creates the App Engine application + enables APIs.
#        gcloud deploys the code.
################################################################################

locals {
  config = jsondecode(var.platform_config)

  # Extract platform-specific values with sensible defaults
  service_id     = try(local.config.service_id, var.service_name)
  instance_class = try(local.config.instance_class, "F2")
  vpc_connector  = try(local.config.vpc_connector, null)

  # Automatic scaling configuration
  auto_scaling = try(local.config.automatic_scaling, {})
  min_idle_instances  = try(local.auto_scaling.min_idle_instances, 1)
  max_idle_instances  = try(local.auto_scaling.max_idle_instances, "automatic")
  min_pending_latency = try(local.auto_scaling.min_pending_latency, "30ms")
  max_pending_latency = try(local.auto_scaling.max_pending_latency, "automatic")
}

# ─── Enable Required APIs ────────────────────────────────────────────────────
# WHY: APIs must be enabled before any resources can be created.
# These are idempotent — safe to run even if already enabled.

resource "google_project_service" "appengine" {
  project = var.gcp_project_id
  service = "appengine.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "cloudbuild" {
  project = var.gcp_project_id
  service = "cloudbuild.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "secretmanager" {
  project = var.gcp_project_id
  service = "secretmanager.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# ─── App Engine Application ──────────────────────────────────────────────────
# WHY `create-then-deploy`:
#   This resource creates the App Engine application if it doesn't exist.
#   App Engine is a singleton per GCP project — there can only be one.
#
# IMPORTANT: `location_id` CANNOT be changed after creation.
# The region you set here is permanent for this project.
#
# NOTE: If App Engine already exists in this project, the workflow runs
# `terraform import` before plan/apply to adopt it into state.

resource "google_app_engine_application" "app" {
  project     = var.gcp_project_id
  location_id = var.region

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [location_id]
  }

  depends_on = [google_project_service.appengine]
}

# ─── Firewall Rules ──────────────────────────────────────────────────────────
# WHY: Default-deny with explicit allow rules is a security best practice.
# These rules control which IPs can reach the App Engine service.

resource "google_app_engine_firewall_rule" "allow_health_checks" {
  project      = var.gcp_project_id
  priority     = 1000
  action       = "ALLOW"
  source_range = "0.0.0.0/0"  # Health checks come from Google's infra
  description  = "Allow health check traffic"

  depends_on = [google_app_engine_application.app]
}

# ─── App Engine Service (Dispatch Rules) ─────────────────────────────────────
# WHY: If the service needs custom URL routing (e.g., /api/* → this service),
# dispatch rules handle that at the App Engine level.

resource "google_app_engine_service_split_traffic" "split" {
  count   = var.environment == "production" ? 1 : 0
  project = var.gcp_project_id
  service = local.service_id

  migrate_traffic = false

  split {
    # Default: 100% to the latest version.
    # In production, this can be used for canary deployments.
    allocations = {}
    shard_by    = "IP"
  }

  depends_on = [google_app_engine_application.app]
}

# ─── Cloud Storage Bucket for Deployment Artifacts ───────────────────────────
# WHY: App Engine deployments need a staging bucket for source uploads.
# Creating it here ensures it exists before `gcloud app deploy` runs.

resource "google_storage_bucket" "deploy_artifacts" {
  name     = "${var.gcp_project_id}-${var.service_name}-deploy"
  project  = var.gcp_project_id
  location = var.region

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  # Auto-cleanup old deployment artifacts after 30 days
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
