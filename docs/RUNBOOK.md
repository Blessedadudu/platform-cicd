# Operational Runbook

> Reference guide for operating and troubleshooting the CI/CD pipeline.

---

## Table of Contents

1. [Architecture Quick Reference](#architecture-quick-reference)
2. [Common Operations](#common-operations)
3. [Troubleshooting Guide](#troubleshooting-guide)
4. [Emergency Procedures](#emergency-procedures)
5. [Terraform State Management](#terraform-state-management)

---

## Architecture Quick Reference

```
Service Repo (deploy.json + caller workflow)
        │
        ▼
Reusable Workflow (cicd/.github/workflows/deploy.yml)
        │
        ├── 1. Validate Config
        ├── 2. Terraform Plan
        ├── 3. Terraform Apply  ←── Creates infra if absent
        ├── 4. Deploy App       ←── Platform-specific
        └── 5. Healthcheck
```

### Key Files

| File | Purpose |
|------|---------|
| `deploy.json` | Service's deployment config (lives in service repo) |
| `.github/workflows/deploy.yml` | Reusable workflow (lives in cicd repo) |
| `terraform/main.tf` | Root module — routes to platform modules |
| `terraform/modules/*/` | Platform-specific Terraform modules |
| `scripts/validate-config.sh` | Config validation script |
| `scripts/resolve-env.sh` | Environment variable resolver |
| `scripts/post-deploy-healthcheck.sh` | Post-deploy health verification |

---

## Common Operations

### Manually Trigger a Deployment

```bash
gh workflow run deploy.yml \
  -f config_path=./deploy.json \
  -f environment=staging
```

### View Terraform State

```bash
# List resources in state
terraform -chdir=terraform state list

# Show a specific resource
terraform -chdir=terraform state show google_app_engine_application.app
```

### View Terraform Plan Locally

```bash
# 1. Resolve config for the target environment
./scripts/resolve-env.sh deploy.json staging > terraform/resolved.auto.tfvars.json

# 2. Init with the correct backend
cd terraform
terraform init \
  -backend-config="bucket=YOUR_STATE_BUCKET" \
  -backend-config="prefix=YOUR_SERVICE/staging"

# 3. Plan
terraform plan
```

### Add a New Service to Drift Detection

Edit `.github/workflows/drift-detection.yml` and add to the matrix:

```yaml
matrix:
  include:
    - service: "new-service-name"
      environment: "production"
      config_path: "path/to/deploy.json"
```

---

## Troubleshooting Guide

### Pipeline Failures

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Validation fails | Invalid `deploy.json` | Run `validate-config.sh` locally |
| Terraform init fails | Wrong state bucket or permissions | Check `TERRAFORM_STATE_BUCKET` secret |
| Terraform plan fails | Provider version mismatch | Check `versions.tf` constraints |
| Terraform apply fails | IAM permissions insufficient | Check SA roles |
| App deploy fails | `app.yaml` malformed | Check generated `app.yaml` in job logs |
| Healthcheck fails | App not starting | Check Cloud Logging |

### Terraform State Issues

**State Lock Stuck:**
```bash
# Find the lock ID from the error message
terraform force-unlock <LOCK_ID>
```

**State Corrupted:**
```bash
# Pull state from GCS
gsutil cp gs://STATE_BUCKET/SERVICE/ENV/default.tfstate ./backup.tfstate

# Import resources back into state
terraform import google_app_engine_application.app <PROJECT_ID>
```

### GCP Permission Errors

Required IAM roles per platform:

| Platform | Required Roles |
|----------|---------------|
| App Engine | `roles/appengine.appAdmin`, `roles/cloudbuild.builds.editor`, `roles/storage.admin` |
| Compute Engine | `roles/compute.instanceAdmin.v1`, `roles/iam.serviceAccountUser`, `roles/storage.admin` |
| Compute MIG | All Compute roles + `roles/compute.loadBalancerAdmin` |

---

## Emergency Procedures

### Rollback a Deployment

**App Engine:**
```bash
# List versions
gcloud app versions list --service=SERVICE_ID --project=PROJECT

# Route traffic to previous version
gcloud app services set-traffic SERVICE_ID \
  --splits=PREVIOUS_VERSION=1 \
  --project=PROJECT
```

**Compute Engine:**
```bash
# SSH in and rollback manually
gcloud compute ssh INSTANCE_NAME --zone=ZONE --project=PROJECT

# Or restore from previous artifact
gsutil cp gs://BUCKET/previous-artifact.tar.gz /tmp/
sudo tar -xzf /tmp/previous-artifact.tar.gz -C /opt/SERVICE
sudo systemctl restart SERVICE
```

**Compute MIG:**
```bash
# The MIG keeps the previous instance template.
# To rollback, update the MIG to use the previous template:
gcloud compute instance-groups managed rolling-action start-update MIG_NAME \
  --version=template=PREVIOUS_TEMPLATE \
  --region=REGION \
  --project=PROJECT
```

### Destroy Infrastructure (Emergency Only)

```bash
# WARNING: This destroys ALL resources managed by Terraform for this service.
# Only use in emergencies. Requires removing lifecycle.prevent_destroy first.

cd terraform
terraform init -backend-config="bucket=BUCKET" -backend-config="prefix=SERVICE/ENV"
terraform destroy -auto-approve
```

---

## Terraform State Management

### State Structure

```
gs://terraform-state-bucket/
├── payments-api/
│   ├── staging/default.tfstate
│   └── production/default.tfstate
├── worker-service/
│   ├── staging/default.tfstate
│   └── production/default.tfstate
└── api-gateway/
    ├── staging/default.tfstate
    └── production/default.tfstate
```

### State Backup

GCS bucket versioning is enabled, so every state change creates a new version. To access a previous state version:

```bash
# List versions
gsutil ls -la gs://STATE_BUCKET/SERVICE/ENV/

# Download a specific version
gsutil cp gs://STATE_BUCKET/SERVICE/ENV/default.tfstate#VERSION ./previous.tfstate
```
