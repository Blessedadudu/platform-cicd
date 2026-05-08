################################################################################
# Root Module Variables
#
# These variables are populated from the service's deploy.json config file.
# The GitHub Actions workflow extracts values with `jq` and passes them
# to Terraform as -var or -var-file arguments.
#
# Design principle: Keep root variables minimal. Platform-specific config
# is passed as a JSON-encoded string and decoded within each module.
################################################################################

# ─── Service Identity ─────────────────────────────────────────────────────────

variable "service_name" {
  description = "The unique name of the service being deployed (e.g., 'payments-api')"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.service_name))
    error_message = "Service name must be lowercase alphanumeric with hyphens, 3-63 chars."
  }
}

variable "team" {
  description = "The team that owns this service (used for labelling and cost allocation)"
  type        = string
}

variable "environment" {
  description = "The deployment environment (staging, production)"
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

# ─── GCP Target ───────────────────────────────────────────────────────────────

variable "gcp_project_id" {
  description = "The GCP project ID to deploy into"
  type        = string
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
}

# ─── Platform Selection ──────────────────────────────────────────────────────

variable "platform" {
  description = "The deployment target platform"
  type        = string

  validation {
    condition     = contains(["appengine", "compute", "compute-mig"], var.platform)
    error_message = "Platform must be one of: appengine, compute, compute-mig."
  }
}

# ─── Build Configuration ─────────────────────────────────────────────────────

variable "runtime" {
  description = "The application runtime (e.g., nodejs22, python312, go122)"
  type        = string
  default     = "nodejs22"
}

# ─── Deployment Configuration ────────────────────────────────────────────────

variable "health_check_path" {
  description = "HTTP path for health checks"
  type        = string
  default     = "/health"
}

variable "min_instances" {
  description = "Minimum number of instances"
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

# ─── Platform-Specific Configuration ─────────────────────────────────────────

variable "platform_config" {
  description = <<-EOT
    JSON-encoded string of platform-specific configuration.
    This is decoded within the target module to extract platform-specific values.
    Using a JSON string here keeps the root module interface stable regardless
    of which platform is selected.
  EOT
  type        = string
  default     = "{}"
}

# ─── Environment Variables ───────────────────────────────────────────────────

variable "env_variables" {
  description = "Environment variables to set on the deployed service"
  type        = map(string)
  default     = {}
}

# ─── Labels ──────────────────────────────────────────────────────────────────

variable "labels" {
  description = "Labels to apply to all created resources (for cost allocation, filtering)"
  type        = map(string)
  default     = {}
}
