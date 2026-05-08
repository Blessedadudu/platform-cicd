################################################################################
# Compute Engine Module — Variables
################################################################################

variable "service_name" {
  description = "The service name (used for instance naming)"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "env_variables" {
  description = "Environment variables to inject via metadata"
  type        = map(string)
  default     = {}
}

variable "platform_config" {
  description = "JSON-encoded platform-specific config"
  type        = string
  default     = "{}"
}

variable "labels" {
  description = "Labels for resources"
  type        = map(string)
  default     = {}
}

variable "health_check_path" {
  description = "HTTP path for health checks"
  type        = string
  default     = "/health"
}
