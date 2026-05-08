################################################################################
# Terraform & Provider Version Constraints
#
# WHY: Pinning versions prevents unexpected breaking changes when providers
# release new versions. The pessimistic constraint operator (~>) allows only
# patch-level updates, ensuring stability while still receiving bug fixes.
################################################################################

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}
