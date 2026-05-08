# Config-Driven CI/CD Pipeline

> A single, reusable GitHub Actions workflow that deploys any service to GCP by reading a JSON config file.

## Quick Start

See [docs/ONBOARDING.md](docs/ONBOARDING.md) for the step-by-step onboarding guide.

## Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Full architecture design & rationale |
| [ONBOARDING.md](docs/ONBOARDING.md) | How to onboard a new service |
| [RUNBOOK.md](docs/RUNBOOK.md) | Operations & troubleshooting guide |
| [Rollout Timeline](docs/slides/rollout-timeline.md) | Slide deck for the review session |

## Directory Structure

```
cicd/
├── .github/workflows/       # GitHub Actions workflows
│   ├── deploy.yml            # THE reusable deployment workflow
│   ├── caller-example.yml    # Example: how to call from your repo
│   └── drift-detection.yml   # Scheduled drift detection
├── terraform/                # Terraform infrastructure code
│   ├── main.tf               # Root module (platform router)
│   ├── modules/
│   │   ├── appengine/        # GCP App Engine
│   │   ├── compute/          # GCP Compute Engine (single VM)
│   │   └── compute-mig/      # GCP Compute Engine (autoscaling MIG)
├── configs/
│   ├── schema.json           # JSON Schema for validation
│   └── examples/             # Example deploy.json files
├── scripts/                  # Validation & utility scripts
└── docs/                     # Documentation
```

## Supported Platforms

| Platform | Module | Status |
|----------|--------|--------|
| GCP App Engine | `modules/appengine` | Phase 1 (Weeks 1-2) |
| GCP Compute Engine | `modules/compute` | Phase 2 (Weeks 3-4) |
| GCP Compute Engine MIG | `modules/compute-mig` | Phase 3 (Weeks 5-6) |
# platform-cicd
