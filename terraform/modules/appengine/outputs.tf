################################################################################
# App Engine Module — Outputs
################################################################################

output "service_url" {
  description = "The URL of the App Engine service"
  value       = "https://${local.service_id}-dot-${var.gcp_project_id}.appspot.com"
}

output "resource_ids" {
  description = "Map of created resource identifiers"
  value = {
    app_engine_application = google_app_engine_application.app.id
    deploy_bucket          = google_storage_bucket.deploy_artifacts.name
    project                = var.gcp_project_id
    region                 = var.region
    service_id             = local.service_id
  }
}

output "deploy_bucket" {
  description = "GCS bucket for deployment artifacts"
  value       = google_storage_bucket.deploy_artifacts.name
}
