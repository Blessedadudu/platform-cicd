################################################################################
# Root Module Outputs
#
# These outputs are consumed by the GitHub Actions workflow for:
#   1. Displaying deployment info in the PR comment / job summary.
#   2. Passing values to downstream jobs (e.g., the deploy + healthcheck jobs).
#   3. Audit trail — what was created, where is it accessible.
################################################################################

output "deployment_target" {
  description = "The platform that was provisioned"
  value       = var.platform
}

output "service_url" {
  description = "The URL where the service is accessible"
  value = (
    var.platform == "appengine" ? module.appengine[0].service_url :
    var.platform == "compute" ? module.compute[0].external_ip :
    var.platform == "compute-mig" ? module.compute_mig[0].load_balancer_ip :
    "unknown"
  )
}

output "resource_ids" {
  description = "Map of created resource identifiers for audit trail"
  value = (
    var.platform == "appengine" ? module.appengine[0].resource_ids :
    var.platform == "compute" ? module.compute[0].resource_ids :
    var.platform == "compute-mig" ? module.compute_mig[0].resource_ids :
    {}
  )
}
