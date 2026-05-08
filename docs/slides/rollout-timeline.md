# Rollout Timeline — Review Session Slides

> **Presenter:** Distinguished Engineering  
> **Date:** Monday, 2026-05-12  
> **Duration:** 90 minutes  
> **Audience:** Engineering Leads

---

## Slide 1: The Problem

### Every team rebuilds deployment from scratch

- 5+ teams maintaining separate deployment pipelines
- No standard config contract → onboarding takes days
- Infrastructure assumed to exist → manual provisioning before first deploy
- Environment-specific logic scattered → config drift → prod incidents
- No unified approach to secrets, IAM, or networking

**Cost:** Engineering hours wasted, inconsistent security posture, slow time-to-deploy.

---

## Slide 2: The Solution

### One workflow. Any GCP target. Config-driven.

```
deploy.json → Validate → Terraform Plan → Apply → Deploy → Healthcheck
```

- **Single reusable GitHub Actions workflow** — all services call the same workflow
- **JSON config file** — teams describe _what_, not _how_
- **Create-then-deploy** — no pre-existing infrastructure assumed
- **Terraform** — idempotent, auditable, industry standard

---

## Slide 3: How It Works

### Service team provides TWO things:

1. **`deploy.json`** — 40 lines of configuration
2. **Caller workflow** — 25 lines of YAML

### That's it. Everything else is handled by the platform.

```
Service Repo                    CI/CD Repo (shared)
┌──────────────┐               ┌─────────────────────┐
│ deploy.json  │──calls──────→ │ Reusable workflow    │
│ .github/     │               │ Terraform modules    │
│   deploy.yml │               │ Validation scripts   │
│ src/         │               │ Healthcheck scripts  │
│ /health      │               └─────────────────────┘
└──────────────┘
```

---

## Slide 4: Config Contract

### `deploy.json` — The single source of truth

```json
{
  "service":      { "name": "...", "team": "..." },
  "target":       { "platform": "appengine", "gcp_project_id": "...", "region": "..." },
  "environments": { "staging": {...}, "production": {...} },
  "build":        { "runtime": "nodejs22", "build_command": "..." },
  "deploy":       { "health_check_path": "/health", "min_instances": 1 },
  "platform_config": { /* platform-specific settings */ }
}
```

- Validated against JSON Schema before Terraform runs
- Environment overrides merged at build time
- Platform-specific config isolated in `platform_config`

---

## Slide 5: Platform Targets

| Target | Status | Use Case |
|--------|--------|----------|
| **App Engine** | Week 1–2 | Web APIs, lightweight services |
| **Compute Engine** | Week 3–4 | Workers, custom runtimes |
| **Compute MIG** | Week 5–6 | High-traffic APIs, autoscaling |

### Each target is a self-contained Terraform module

Adding a new target (e.g., Cloud Run, GKE) = new module + one `count` block. No workflow changes.

---

## Slide 6: Create-Then-Deploy

### The pipeline NEVER assumes infrastructure exists

| Scenario | Behaviour |
|----------|-----------|
| Resource doesn't exist | Creates it |
| Resource exists, matches config | No-op |
| Resource exists, differs from config | Updates it |
| Resource exists, removed from config | Warns (with `prevent_destroy`) |

Powered by Terraform's declarative model:
```
Current State → Desired State → Plan → Apply
```

---

## Slide 7: Environment Guardrails

| Guardrail | Staging | Production |
|-----------|---------|------------|
| Auto-deploy on push | ✅ | ❌ |
| Manual approval required | ❌ | ✅ (2 reviewers) |
| Terraform plan as PR comment | ✅ | ✅ |
| `prevent_destroy` on infra | ❌ | ✅ |
| Post-deploy healthcheck | ✅ | ✅ |
| Drift detection (daily) | — | ✅ |
| Slack notifications | ✅ | ✅ |

---

## Slide 8: Onboarding Path

### 5 minutes to first deploy

```
1. Copy deploy.json template          (30 seconds)
2. Fill in service + target details    (2 minutes)
3. Add 25-line caller workflow         (1 minute)
4. Push to main                        (30 seconds)
5. Pipeline creates infra + deploys    (automatic)
```

### What teams DON'T need:
- ❌ Terraform knowledge
- ❌ Infrastructure provisioning scripts
- ❌ GCP project setup
- ❌ Deployment scripts

---

## Slide 9: Rollout Timeline

```
Week 0   (Now)     ━━━ Foundation: workflow scaffold, config schema, state backend
Week 1–2           ━━━ App Engine: module + pilot service + GA
Week 3–4           ━━━ Compute Engine: module + pilot service + GA
Week 5–6           ━━━ Compute MIG: module + autoscaler + LB + GA
Week 7–8           ━━━ Hardening: drift detection, cost estimation, docs, training
```

### Key Milestones

| Date | Milestone |
|------|-----------|
| **2026-05-21** | App Engine GA — first service deployed via pipeline |
| **2026-06-04** | Compute Engine GA — VM-based service deployed |
| **2026-06-18** | Compute MIG GA — autoscaling group deployed |
| **2026-07-02** | All targets GA — documentation + training complete |

---

## Slide 10: Discussion & Decisions Needed

1. **Pilot service for App Engine** — Which team volunteers? Low-risk, well-understood service preferred.

2. **GCP project structure** — One project per env? Shared projects? This affects Terraform state isolation.

3. **Networking architecture** — VPC connectors, Shared VPC, private Google access — what's our standard?

4. **Secret Manager structure** — Per-service secrets vs shared secrets? Naming conventions?

5. **Cost ownership** — Who owns the Terraform state bucket? How do we allocate platform costs?

6. **Migration priority** — In what order do existing services migrate to the new pipeline?

---

## Slide 11: Action Items

| Action | Owner | Due |
|--------|-------|-----|
| Approve architecture & config contract | All leads | End of this session |
| Identify App Engine pilot service | Volunteer team | 2026-05-14 |
| Set up Workload Identity Federation | Platform team | 2026-05-14 |
| Create Terraform state GCS bucket | Platform team | 2026-05-14 |
| Configure GitHub org-level secrets | Platform team | 2026-05-14 |
| First App Engine deployment | DE + pilot team | 2026-05-21 |
