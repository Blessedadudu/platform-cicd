################################################################################
# App Engine Module — Variables
################################################################################

variable "service_name" {
  description = "The service name (used as the App Engine service ID)"
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

variable "runtime" {
  description = "App Engine runtime (e.g., nodejs22, python312)"
  type        = string
}

variable "environment" {
  description = "Deployment environment (staging, production)"
  type        = string
}

variable "env_variables" {
  description = "Environment variables for the App Engine service"
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
