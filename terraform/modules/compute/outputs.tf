################################################################################
# Compute Engine Module — Outputs
################################################################################

output "external_ip" {
  description = "The external IP address of the VM"
  value       = local.enable_static_ip ? google_compute_address.static_ip[0].address : google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "instance_name" {
  description = "The name of the Compute Engine instance"
  value       = google_compute_instance.vm.name
}

output "instance_zone" {
  description = "The zone of the Compute Engine instance"
  value       = google_compute_instance.vm.zone
}

output "resource_ids" {
  description = "Map of created resource identifiers"
  value = {
    instance_name    = google_compute_instance.vm.name
    instance_id      = google_compute_instance.vm.instance_id
    zone             = google_compute_instance.vm.zone
    external_ip      = local.enable_static_ip ? google_compute_address.static_ip[0].address : "ephemeral"
    deploy_bucket    = google_storage_bucket.deploy_artifacts.name
    service_account  = local.service_account_email != null ? local.service_account_email : google_service_account.vm_sa[0].email
  }
}

output "deploy_bucket" {
  description = "GCS bucket for deployment artifacts"
  value       = google_storage_bucket.deploy_artifacts.name
}
