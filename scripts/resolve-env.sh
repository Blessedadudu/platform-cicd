#!/usr/bin/env bash
################################################################################
# resolve-env.sh — Environment Variable Resolver
#
# PURPOSE:
#   Merges the base deploy.json config with environment-specific overrides.
#   Produces a flat set of Terraform variables for the target environment.
#
# HOW:
#   1. Reads the base config (target.gcp_project_id, target.region, etc.)
#   2. Overlays environment-specific values (environments.<env>.gcp_project_id)
#   3. Merges environment variables (base + env-specific)
#   4. Outputs as Terraform-compatible tfvars JSON
#
# USAGE:
#   ./scripts/resolve-env.sh <deploy.json> <environment>
#
# OUTPUT:
#   Writes resolved config to stdout as JSON (pipe to file for -var-file)
################################################################################

set -euo pipefail

CONFIG_FILE="${1:?Usage: $0 <deploy.json> <environment>}"
ENVIRONMENT="${2:?Usage: $0 <deploy.json> <environment>}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Config file not found: ${CONFIG_FILE}" >&2
  exit 1
fi

# Validate environment exists in config
if ! jq -e ".environments.${ENVIRONMENT}" "$CONFIG_FILE" > /dev/null 2>&1; then
  echo "Error: Environment '${ENVIRONMENT}' not found in config" >&2
  echo "Available environments: $(jq -r '.environments | keys | join(", ")' "$CONFIG_FILE")" >&2
  exit 1
fi

# ─── Resolve Values ──────────────────────────────────────────────────────────
# Environment-specific values override base values.
# This is the "overlay" pattern — common in Kubernetes (Kustomize) and
# other config-driven systems.

jq --arg env "$ENVIRONMENT" '{
  service_name:     .service.name,
  team:             .service.team,
  environment:      $env,
  gcp_project_id:   (.environments[$env].gcp_project_id // .target.gcp_project_id),
  region:           (.environments[$env].region // .target.region),
  platform:         .target.platform,
  runtime:          .build.runtime,
  health_check_path: (.deploy.health_check_path // "/health"),
  min_instances:    (.deploy.min_instances // 1),
  max_instances:    (.deploy.max_instances // 10),
  env_variables:    ((.environments[$env].variables // {}) as $env_vars | $env_vars),
  platform_config:  (.platform_config // {} | tostring),
  labels: {
    service:     .service.name,
    team:        .service.team,
    environment: $env,
    managed_by:  "terraform"
  }
}' "$CONFIG_FILE"
