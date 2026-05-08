#!/usr/bin/env bash
################################################################################
# post-deploy-healthcheck.sh — Post-Deployment Health Verification
#
# PURPOSE:
#   Verifies the deployed service is healthy after deployment completes.
#   Uses exponential backoff to account for cold starts and propagation delays.
#
# WHY:
#   A successful `terraform apply` or `gcloud app deploy` doesn't guarantee
#   the application is actually serving traffic correctly. This script
#   confirms end-to-end readiness.
#
# USAGE:
#   ./scripts/post-deploy-healthcheck.sh <url> <health_path> [max_attempts]
#
# EXIT CODES:
#   0 — Service is healthy
#   1 — Service did not become healthy within the timeout
################################################################################

set -euo pipefail

# ─── Colour Output ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Configuration ───────────────────────────────────────────────────────────

BASE_URL="${1:?Usage: $0 <base-url> <health-path> [max-attempts]}"
HEALTH_PATH="${2:-/health}"
MAX_ATTEMPTS="${3:-10}"
INITIAL_DELAY=5
MAX_DELAY=60

# Remove trailing slash from URL and leading slash from path
BASE_URL="${BASE_URL%/}"
HEALTH_PATH="/${HEALTH_PATH#/}"
FULL_URL="${BASE_URL}${HEALTH_PATH}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Post-Deploy Health Check${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  URL:          ${BLUE}${FULL_URL}${NC}"
echo -e "  Max attempts: ${BLUE}${MAX_ATTEMPTS}${NC}"
echo ""

# ─── Health Check Loop (Exponential Backoff) ─────────────────────────────────

attempt=1
delay=$INITIAL_DELAY

while [[ $attempt -le $MAX_ATTEMPTS ]]; do
  echo -e "${YELLOW}→ Attempt ${attempt}/${MAX_ATTEMPTS}...${NC}"

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 10 \
    --max-time 30 \
    "$FULL_URL" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo -e "${GREEN}  ✓ Health check passed (HTTP ${HTTP_CODE})${NC}"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✓ Service is HEALTHY${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
  fi

  echo -e "${YELLOW}  ✗ Got HTTP ${HTTP_CODE}, retrying in ${delay}s...${NC}"
  sleep "$delay"

  # Exponential backoff with cap
  delay=$((delay * 2))
  if [[ $delay -gt $MAX_DELAY ]]; then
    delay=$MAX_DELAY
  fi

  attempt=$((attempt + 1))
done

# ─── Failure ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  ✗ Health check FAILED after ${MAX_ATTEMPTS} attempts${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  Last HTTP status: ${HTTP_CODE}${NC}"
echo -e "${RED}  URL: ${FULL_URL}${NC}"
echo ""
echo -e "${YELLOW}  Troubleshooting:${NC}"
echo -e "${YELLOW}  1. Check application logs in Cloud Logging${NC}"
echo -e "${YELLOW}  2. Verify the health endpoint returns HTTP 200${NC}"
echo -e "${YELLOW}  3. Check if firewall rules allow health check traffic${NC}"
exit 1
