# Onboarding a New Service

> **Time to first deploy: ~5 minutes** (once prerequisites are in place)

---

## Prerequisites

Before onboarding, ensure your GCP organization has:

1. **Workload Identity Federation** configured for GitHub Actions  
2. **Terraform state bucket** created in GCS  
3. **GitHub Organization secrets** configured:
   - `GCP_WORKLOAD_IDENTITY_PROVIDER`
   - `GCP_SERVICE_ACCOUNT`
   - `TERRAFORM_STATE_BUCKET`

---

## Step 1: Create `deploy.json`

Copy the appropriate template from `configs/examples/` into your service repository root:

```bash
# For an App Engine service:
cp configs/examples/appengine-service.json ./deploy.json

# For a Compute Engine service:
cp configs/examples/compute-service.json ./deploy.json

# For an autoscaling MIG service:
cp configs/examples/compute-mig-service.json ./deploy.json
```

Edit `deploy.json` to match your service:

```json
{
  "service": {
    "name": "YOUR-SERVICE-NAME",    // ← lowercase with hyphens
    "team": "YOUR-TEAM-NAME",
    "repository": "org/YOUR-REPO"
  },
  "target": {
    "platform": "appengine",         // ← appengine | compute | compute-mig
    "gcp_project_id": "YOUR-PROJECT-STAGING",
    "region": "us-central1"
  },
  ...
}
```

### Validation

Run the validation script locally to check your config:

```bash
./cicd/scripts/validate-config.sh ./deploy.json
```

---

## Step 2: Add the Caller Workflow

Create `.github/workflows/deploy.yml` in your service repository:

```yaml
name: "Deploy"

on:
  push:
    branches: [main]
  release:
    types: [published]

jobs:
  deploy-staging:
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    uses: YOUR_ORG/cicd/.github/workflows/deploy.yml@main
    with:
      config_path: "./deploy.json"
      environment: "staging"
      auto_approve: true
    secrets: inherit

  deploy-production:
    if: github.event_name == 'release'
    uses: YOUR_ORG/cicd/.github/workflows/deploy.yml@main
    with:
      config_path: "./deploy.json"
      environment: "production"
      auto_approve: false
    secrets: inherit
```

> **That's it.** This 25-line YAML is the only CI/CD file your team maintains.

---

## Step 3: Add a Health Endpoint

Your service MUST expose a health endpoint:

```
GET /health → HTTP 200
```

This is used by:
- Post-deployment healthchecks
- App Engine liveness checks
- Compute Engine health checks (MIG auto-healing)

### Minimal Implementation

**Node.js (Express):**
```javascript
app.get('/health', (req, res) => res.status(200).json({ status: 'ok' }));
```

**Python (Flask):**
```python
@app.route('/health')
def health():
    return {'status': 'ok'}, 200
```

---

## Step 4: Push and Deploy

```bash
git add deploy.json .github/workflows/deploy.yml
git commit -m "feat: add CI/CD pipeline configuration"
git push origin main
```

The pipeline will:
1. ✅ Validate your `deploy.json`
2. 📋 Run `terraform plan` (shows what infrastructure will be created)
3. 🏗️ Run `terraform apply` (creates the infrastructure)
4. 🚀 Deploy your application
5. 💚 Verify health

---

## What Happens on First Deploy?

Since this pipeline supports **create-then-deploy**, the first run will:

| Platform | What Gets Created |
|----------|-------------------|
| App Engine | App Engine application, service, deploy bucket |
| Compute | VM, service account, firewall rules, static IP, deploy bucket |
| Compute MIG | Instance template, MIG, autoscaler, health check, deploy bucket |

On subsequent deploys, only the application code is updated. Infrastructure changes only occur if you modify `deploy.json`.

---

## Troubleshooting

### "Terraform state lock"
Someone else is deploying. Wait for their deployment to finish, or check the GitHub Actions concurrency group.

### "App Engine application already exists"
This is expected. Terraform will import it into state on the next run. App Engine apps are singleton per project.

### "Permission denied"
Check that the GCP service account has the required IAM roles for your target platform.

### "Health check failed"
1. Check your application logs in Cloud Logging
2. Verify your `/health` endpoint returns HTTP 200
3. Check firewall rules allow health check traffic from Google's IP ranges
