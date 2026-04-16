# ocp-resilience-toolkit

Deterministic data collection + AI-guided report generation + PDF rendering for
**OpenShift workload resilience and pod disruption analysis**.

Platform-agnostic — works on Silver, Gold, and Emerald clusters.  
Complements `ocp-migration-toolkit` (focus on migration gaps) with deep resilience posture.

---

## Architecture

```
ocp-resilience-toolkit/
├── collect/
│   └── collect.sh          # Phase 1: OCP namespace resilience data collection
├── templates/
│   ├── report-sections.md  # AI section-by-section generation guide
│   └── style/
│       └── report-style.css
├── render/
│   └── render.sh           # pandoc + chromium → PDF
├── action.yml              # GitHub Composite Action entry point
└── .github/
    ├── workflows/
    │   └── on-demand-analysis.yml   # Manual workflow_dispatch
    └── prompts/
        └── ocp-resilience-analysis.prompt.md  # VS Code prompt template
```

---

## Three-tier usage

| Tier | Where | How |
|------|-------|-----|
| **1 — VS Code** | Any project | Open `.github/prompts/ocp-resilience-analysis.prompt.md` in Copilot Chat agent mode |
| **2 — GitHub Actions** | Any BC Gov repo | Add the composite action to your workflow |
| **3 — Copilot Chat** | Any team | `@bc-resilience analyze namespace:f1b263` |

---

## Quick start

### Option A — Local CLI

```bash
# Prerequisites: oc CLI logged in, pandoc, chromium, gh CLI

# 1. Collect namespace data
./collect/collect.sh \
  --namespace f1b263 \
  --cluster   silver \
  --envs      dev,test,prod \
  --output    ./data

# 2. Generate report (AI-guided — use Claude Code or Copilot agent mode)
# Open .github/prompts/ocp-resilience-analysis.prompt.md in VS Code

# 3. Render PDF
./render/render.sh \
  --input  ./data/report/MYAPP-Resilience-Report.md \
  --output ./data/report
```

### Option B — GitHub Actions (on-demand)

```yaml
# In your repo's workflow
uses: rloisell/ocp-resilience-toolkit@main
with:
  namespace:     f1b263
  cluster:       silver
  oc-server-url: ${{ secrets.OC_SILVER_URL }}
  oc-token:      ${{ secrets.OC_SILVER_SA_TOKEN }}
  gh-token:      ${{ secrets.GITHUB_TOKEN }}
  llm-api-key:   ${{ secrets.GITHUB_MODELS_API_KEY }}
```

Or trigger manually via **Actions → On-Demand Resilience Analysis → Run workflow**.

### Option C — VS Code Copilot Chat

Open `.github/prompts/ocp-resilience-analysis.prompt.md` → fill in the input variables →
Copilot agent runs the full five-phase analysis in your workspace.

### Option D — Copilot Extension

```
@bc-resilience analyze namespace:f1b263
@bc-resilience analyze namespace:f1b263 repo:bcgov-c/myapp cluster:silver
```

---

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `namespace` | ✅ | — | OCP license plate prefix (e.g. `f1b263`) |
| `cluster` | ❌ | `silver` | `silver` \| `gold` \| `emerald` |
| `envs` | ❌ | `dev,test,prod,tools` | Comma-separated environment suffixes |
| `repo` | ❌ | — | GitHub repo `owner/name` — included for Deployment YAML cross-reference |
| `output` | ❌ | `./resilience-output` | Output directory |

---

## Output structure

```
<output>/
├── <namespace>-dev/
│   ├── workloads.yaml
│   ├── pdbs.yaml
│   ├── hpas.yaml
│   ├── pods-wide.txt
│   ├── workload-detail.json
│   ├── disruption-events.txt
│   └── ...
├── <namespace>-test/ ...
├── <namespace>-prod/ ...
├── manifest-summary.md
└── report/
    ├── <APP>-Resilience-Report.md
    └── <APP>-Resilience-Report.pdf
```

---

## Report sections

1. Executive Summary & Resilience Scorecard (grade A–F per category)
2. Workload Inventory
3. PodDisruptionBudget Analysis
4. Scaling & Autoscaling Configuration (HPA/VPA/KEDA)
5. Health Probe Analysis
6. Pod Scheduling & Anti-Affinity
7. Graceful Termination & Deployment Strategy
8. Resource Quality of Service (QoS classes)
9. Storage Resilience (PVC, StatefulSet)
10. Disruption Simulation (node drain / zone failure / OCP upgrade)
11. Remediation Tasks (`RES-NN` numbered, prioritised by severity)
12. Appendix

---

## Related tools

| Tool | Purpose |
|------|---------|
| `ocp-migration-toolkit` | Migration gap analysis (Silver/Gold → Emerald) |
| `bc-migrate-service` | `@bc-migrate` Copilot Extension — migration analysis |
| `bc-resilience-service` | `@bc-resilience` Copilot Extension — this toolkit as a service |
