################################################################################
# Compute Engine MIG Module — Outputs
################################################################################

output "load_balancer_ip" {
  description = "The MIG region (LB IP to be added when LB module is wired)"
  value       = var.region
}

output "instance_group" {
  description = "The URL of the managed instance group"
  value       = google_compute_region_instance_group_manager.mig.instance_group
}

output "resource_ids" {
  description = "Map of created resource identifiers"
  value = {
    mig_name          = google_compute_region_instance_group_manager.mig.name
    instance_template = google_compute_instance_template.tmpl.name
    health_check      = google_compute_health_check.hc.name
    autoscaler        = google_compute_region_autoscaler.autoscaler.name
    deploy_bucket     = google_storage_bucket.deploy_artifacts.name
    service_account   = google_service_account.mig_sa.email
  }
}

output "deploy_bucket" {
  description = "GCS bucket for deployment artifacts"
  value       = google_storage_bucket.deploy_artifacts.name
}
