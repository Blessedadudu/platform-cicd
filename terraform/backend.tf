################################################################################
# Remote State Backend — GCS
#
# WHY GCS over local state:
#   1. State locking prevents concurrent applies (race conditions).
#   2. State is shared across team members and CI runners.
#   3. Versioning on the bucket provides state history/rollback.
#   4. No additional vendor (Terraform Cloud) — stays within GCP.
#
# HOW: The bucket name and prefix are injected at runtime via:
#   terraform init \
#     -backend-config="bucket=<BUCKET>" \
#     -backend-config="prefix=<SERVICE_NAME>/<ENV>"
#
# This allows each service + environment combination to have its own
# isolated state file within a shared bucket.
################################################################################

terraform {
  backend "gcs" {
    # These values are populated at runtime via -backend-config flags.
    # See the GitHub Actions workflow for how they are set.
    #
    # bucket = "my-org-terraform-state"
    # prefix = "my-service/staging"
  }
}
