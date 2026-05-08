################################################################################
# Root Module — Platform Router
#
# HOW this works:
#   The `count` meta-argument acts as a conditional toggle. Only the module
#   matching `var.platform` is instantiated. The others have count = 0,
#   meaning Terraform completely skips them — no API calls, no resources.
#
# WHY this pattern:
#   1. Single entry point — `terraform apply` always runs from the root.
#   2. Platform selection at config time — no branching in CI.
#   3. Each module is self-contained — can be developed/tested independently.
#   4. Adding a new platform = add a new module + one `count` block here.
################################################################################

locals {
  # Standard labels applied to ALL resources for cost tracking and ownership
  common_labels = merge(
    {
      managed_by  = "terraform"
      service     = var.service_name
      team        = var.team
      environment = var.environment
    },
    var.labels
  )
}

# ─── App Engine ───────────────────────────────────────────────────────────────

module "appengine" {
  source = "./modules/appengine"
  count  = var.platform == "appengine" ? 1 : 0

  service_name    = var.service_name
  gcp_project_id  = var.gcp_project_id
  region          = var.region
  runtime         = var.runtime
  environment     = var.environment
  env_variables   = var.env_variables
  platform_config = var.platform_config
  labels          = local.common_labels

  health_check_path = var.health_check_path
  min_instances     = var.min_instances
  max_instances     = var.max_instances
}

# ─── Compute Engine (Single VM) ──────────────────────────────────────────────

module "compute" {
  source = "./modules/compute"
  count  = var.platform == "compute" ? 1 : 0

  service_name    = var.service_name
  gcp_project_id  = var.gcp_project_id
  region          = var.region
  environment     = var.environment
  env_variables   = var.env_variables
  platform_config = var.platform_config
  labels          = local.common_labels

  health_check_path = var.health_check_path
}

# ─── Compute Engine — Managed Instance Group (Autoscaling) ───────────────────

module "compute_mig" {
  source = "./modules/compute-mig"
  count  = var.platform == "compute-mig" ? 1 : 0

  service_name    = var.service_name
  gcp_project_id  = var.gcp_project_id
  region          = var.region
  environment     = var.environment
  env_variables   = var.env_variables
  platform_config = var.platform_config
  labels          = local.common_labels

  health_check_path = var.health_check_path
  min_instances     = var.min_instances
  max_instances     = var.max_instances
}
