################################################################################
# GCP Provider Configuration
#
# WHY we configure both `google` and `google-beta`:
#   - `google` — Stable API resources (most things).
#   - `google-beta` — Required for certain features like App Engine
#     flexible environment settings, advanced MIG features, etc.
#
# Authentication:
#   In CI (GitHub Actions), authentication is handled via Workload Identity
#   Federation — no JSON key files. The GOOGLE_CREDENTIALS or
#   GOOGLE_APPLICATION_CREDENTIALS environment variable is set by the
#   `google-github-actions/auth` action.
#
#   For local development, use `gcloud auth application-default login`.
################################################################################

provider "google" {
  project = var.gcp_project_id
  region  = var.region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.region
}
