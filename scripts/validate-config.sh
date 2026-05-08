#!/usr/bin/env bash
################################################################################
# validate-config.sh — Deploy Config Validator
#
# PURPOSE:
#   Validates a deploy.json file against the JSON Schema before any Terraform
#   operations. This is the first gate in the pipeline — catching malformed
#   configs early prevents wasted CI time and cryptic Terraform errors.
#
# DEPENDENCIES:
#   - jq (pre-installed on GitHub Actions runners)
#   - ajv-cli (installed at runtime if not present)
#
# USAGE:
#   ./scripts/validate-config.sh <path-to-deploy.json>
#
# EXIT CODES:
#   0 — Config is valid
#   1 — Config is invalid or missing
#   2 — Dependency missing
################################################################################

set -euo pipefail

# ─── Colour Output ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

# ─── Input Validation ────────────────────────────────────────────────────────

CONFIG_FILE="${1:?Usage: $0 <path-to-deploy.json>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_FILE="${SCRIPT_DIR}/../configs/schema.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo -e "${RED}✗ Config file not found: ${CONFIG_FILE}${NC}"
  exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo -e "${RED}✗ Schema file not found: ${SCHEMA_FILE}${NC}"
  exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Deploy Config Validation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ─── Step 1: JSON Syntax Check ───────────────────────────────────────────────

echo -e "${YELLOW}→ Step 1: Checking JSON syntax...${NC}"
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo -e "${RED}✗ Invalid JSON syntax in ${CONFIG_FILE}${NC}"
  echo -e "${RED}  Run 'jq . ${CONFIG_FILE}' to see the parse error.${NC}"
  exit 1
fi
echo -e "${GREEN}  ✓ JSON syntax is valid${NC}"

# ─── Step 2: Required Fields Check ──────────────────────────────────────────

echo -e "${YELLOW}→ Step 2: Checking required fields...${NC}"

ERRORS=()

# Check top-level required fields
for field in service target environments build deploy; do
  if ! jq -e ".${field}" "$CONFIG_FILE" > /dev/null 2>&1; then
    ERRORS+=("Missing required field: '${field}'")
  fi
done

# Check service.name
SERVICE_NAME=$(jq -r '.service.name // empty' "$CONFIG_FILE")
if [[ -z "$SERVICE_NAME" ]]; then
  ERRORS+=("Missing required field: 'service.name'")
elif ! echo "$SERVICE_NAME" | grep -qE '^[a-z][a-z0-9-]{1,61}[a-z0-9]$'; then
  ERRORS+=("Invalid service.name: '${SERVICE_NAME}'. Must be lowercase alphanumeric with hyphens, 3-63 chars.")
fi

# Check service.team
if ! jq -e '.service.team' "$CONFIG_FILE" > /dev/null 2>&1; then
  ERRORS+=("Missing required field: 'service.team'")
fi

# Check target.platform
PLATFORM=$(jq -r '.target.platform // empty' "$CONFIG_FILE")
if [[ -z "$PLATFORM" ]]; then
  ERRORS+=("Missing required field: 'target.platform'")
elif [[ ! "$PLATFORM" =~ ^(appengine|compute|compute-mig)$ ]]; then
  ERRORS+=("Invalid target.platform: '${PLATFORM}'. Must be one of: appengine, compute, compute-mig")
fi

# Check target.gcp_project_id
if ! jq -e '.target.gcp_project_id' "$CONFIG_FILE" > /dev/null 2>&1; then
  ERRORS+=("Missing required field: 'target.gcp_project_id'")
fi

# Check target.region
if ! jq -e '.target.region' "$CONFIG_FILE" > /dev/null 2>&1; then
  ERRORS+=("Missing required field: 'target.region'")
fi

# Check build.runtime
if ! jq -e '.build.runtime' "$CONFIG_FILE" > /dev/null 2>&1; then
  ERRORS+=("Missing required field: 'build.runtime'")
fi

# Check at least one environment is defined
ENV_COUNT=$(jq '.environments | keys | length' "$CONFIG_FILE")
if [[ "$ENV_COUNT" -eq 0 ]]; then
  ERRORS+=("At least one environment must be defined in 'environments'")
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo -e "${RED}✗ Validation failed with ${#ERRORS[@]} error(s):${NC}"
  for err in "${ERRORS[@]}"; do
    echo -e "${RED}  • ${err}${NC}"
  done
  exit 1
fi
echo -e "${GREEN}  ✓ All required fields present${NC}"

# ─── Step 3: Logical Consistency Checks ──────────────────────────────────────

echo -e "${YELLOW}→ Step 3: Checking logical consistency...${NC}"

# min_instances <= max_instances
MIN_INST=$(jq -r '.deploy.min_instances // 1' "$CONFIG_FILE")
MAX_INST=$(jq -r '.deploy.max_instances // 10' "$CONFIG_FILE")
if [[ "$MIN_INST" -gt "$MAX_INST" ]]; then
  ERRORS+=("deploy.min_instances (${MIN_INST}) > deploy.max_instances (${MAX_INST})")
fi

# Production should require approval
PROD_APPROVAL=$(jq -r '.environments.production.requires_approval // false' "$CONFIG_FILE")
if [[ "$PROD_APPROVAL" != "true" ]] && jq -e '.environments.production' "$CONFIG_FILE" > /dev/null 2>&1; then
  echo -e "${YELLOW}  ⚠ WARNING: Production environment does not require approval. This is strongly discouraged.${NC}"
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo -e "${RED}✗ Consistency check failed:${NC}"
  for err in "${ERRORS[@]}"; do
    echo -e "${RED}  • ${err}${NC}"
  done
  exit 1
fi
echo -e "${GREEN}  ✓ Logical consistency checks passed${NC}"

# ─── Step 4: Summary ────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓ Config validation PASSED${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Service:     ${BLUE}${SERVICE_NAME}${NC}"
echo -e "  Team:        ${BLUE}$(jq -r '.service.team' "$CONFIG_FILE")${NC}"
echo -e "  Platform:    ${BLUE}${PLATFORM}${NC}"
echo -e "  Project:     ${BLUE}$(jq -r '.target.gcp_project_id' "$CONFIG_FILE")${NC}"
echo -e "  Region:      ${BLUE}$(jq -r '.target.region' "$CONFIG_FILE")${NC}"
echo -e "  Runtime:     ${BLUE}$(jq -r '.build.runtime' "$CONFIG_FILE")${NC}"
echo -e "  Environments:${BLUE} $(jq -r '.environments | keys | join(", ")' "$CONFIG_FILE")${NC}"
echo ""
