# Report Generation Guide — OCP Resilience Analysis
# Ryan Loisell — Developer / Architect | GitHub Copilot | April 2026
#
# This file instructs the AI on WHAT to write in each section of the resilience report.
# Feed this as the system prompt alongside the manifest-summary.md collected data.

---

## Document Header Template

```markdown
# <APP_NAME> — OpenShift Resilience Posture Report

**Namespace prefix:** <NAMESPACE>
**Cluster:** <CLUSTER>
**Environments analysed:** <ENVS>
**Analysis date:** <DATE>
**Overall Grade:** <A|B|C|D|F>
**Prepared by:** Ryan Loisell — Developer / Architect | GitHub Copilot

> <One-sentence summary of the most critical finding, e.g.:
> "Three production Deployments have no PodDisruptionBudget — a single node drain
> will cause complete service interruption for jrcc-transformer and jrcc-receiver.">
```

---

## Section 1 — Executive Summary & Resilience Scorecard

**Generate from:** All collected data  
**Must include:**
- Overall resilience grade (A–F) with rationale
- Scorecard table — one row per Resilience Check Category (R01–R15) with grade and status
- Top 3 CRITICAL findings prominently flagged ⛔
- Total RES-NN remediation tasks by severity

**Scorecard table format:**

| ID | Category | Grade | Status | CRITICAL workloads |
|----|----------|-------|--------|-------------------|
| R01 | PDB missing | F | ⛔ CRITICAL | jrcc-receiver, jrcc-transformer |
| R02 | PDB misconfigured | A | ✅ Pass | — |
| R03 | Single replica | D | ⛔ CRITICAL | redis |
| ... | | | | |

**Quality check:** Every row must have a concrete status — never "N/A" without explanation.

---

## Section 2 — Workload Inventory

**Generate from:** `workload-summary.txt` per environment  
**Must include:**
- Table: Workload name | Kind | Replicas | Strategy | Environment | PDB? | HPA?
- Flag workloads with `replicas: 1` as ⚠ 
- Flag Deployments using `Recreate` strategy as ⚠
- StatefulSets noted separately (ordered termination)

**Table format:**

| Name | Kind | Replicas | Strategy | Env | PDB | HPA |
|------|------|----------|----------|-----|-----|-----|
| jrcc-receiver | Deployment | 1 | RollingUpdate | dev | ❌ | ❌ |

---

## Section 3 — PodDisruptionBudget Analysis

**Generate from:** `pdbs.yaml` + `pdb-summary.txt` + `workload-detail.json`  
**Must include:**
- Per-workload PDB status — covered / missing / misconfigured
- For each existing PDB: `minAvailable`, `maxUnavailable`, `disruptionsAllowed`, `currentHealthy`
- Flag PDBs that block all disruptions (minAvailable == replicas) — these cause hung node drains
- Flag workloads with `replicas > 1` and NO PDB as ⛔ CRITICAL
- Recommended PDB spec for each uncovered workload (copy-paste ready YAML)

**Per-workload analysis block:**
```
### jrcc-receiver
- Replicas: 2
- PDB: ❌ MISSING
- Risk: Node drain will evict both replicas simultaneously → full outage
- Recommended fix: (include YAML)
```

---

## Section 4 — Scaling & Autoscaling Configuration

**Generate from:** `hpas.yaml`, `vpas.yaml`, `workload-detail.json`  
**Must include:**
- HPA coverage per workload: min replicas, max replicas, target metric
- VPA presence (updateMode — Off/Initial/Auto)
- Static replica count analysis — which workloads never scale?
- Recommended HPA configuration for user-facing workloads without one
- Flag `minReplicas: 1` on HPAs as ⚠ (still allows single-replica during scale-down)

---

## Section 5 — Health Probe Analysis

**Generate from:** `workload-detail.json` (containers[].livenessProbe / readinessProbe / startupProbe)  
**Must include:**
- Per-container probe table: container name | liveness | readiness | startup
- Flag missing liveness probes as ⚠ HIGH (R04)
- Flag missing readiness probes as ⚠ HIGH (R05) — without readiness, traffic hits unready pods
- Flag long-starting containers without startupProbe as ℹ LOW (R11)
- For misconfigured probes: note `initialDelaySeconds`, `periodSeconds`, `failureThreshold`
- Recommend probe config for each gap

**Probe table:**

| Container | Liveness | Readiness | Startup | Issues |
|-----------|----------|-----------|---------|--------|
| jrcc-receiver | ✅ HTTP /health | ❌ Missing | ❌ Missing | R05 |

---

## Section 6 — Pod Scheduling & Anti-Affinity

**Generate from:** `workload-detail.json` (affinity, topologySpreadConstraints), `pod-node-distribution.txt`  
**Must include:**
- Current node distribution for multi-replica workloads (from `pod-node-distribution.txt`)
- Anti-affinity rules: none / preferred / required, topology key
- TopologySpreadConstraints presence and configuration
- Flag multi-replica workloads with all pods on same node as ⚠ HIGH (R07)
- Recommended affinity rule for each gap (copy-paste YAML)
- Zone resilience assessment: are pods spread across availability zones?

---

## Section 7 — Graceful Termination & Deployment Strategy

**Generate from:** `workload-detail.json` (terminationGracePeriodSeconds, lifecycle.preStop, spec.strategy)  
**Must include:**
- Per-workload: strategy | terminationGracePeriodSeconds | preStop hook?
- Flag `terminationGracePeriodSeconds < 10` as ⚠ HIGH (R08)
- Flag missing `preStop` hooks on TCP-serving workloads as ⚠ (connections may be dropped on pod termination)
- Flag `strategy: Recreate` on user-facing workloads as ⚠ HIGH (R12)
- Rolling update parameters: `maxUnavailable` / `maxSurge` — flag `maxUnavailable: 1` when replicas < 3
- Recommended preStop hook and terminationGracePeriodSeconds values

---

## Section 8 — Resource Quality of Service (QoS)

**Generate from:** `workload-detail.json` (containers[].resources), `quota.yaml`  
**Must include:**
- QoS class per container: Guaranteed / Burstable / BestEffort
- Flag BestEffort containers as ⚠ HIGH (R09) — first evicted under node memory pressure
- Resource requests vs limits table: CPU/memory requests | CPU/memory limits | QoS class
- LimitRange defaults that may affect unset containers
- ResourceQuota remaining capacity per namespace
- Recommended requests/limits for BestEffort containers

**QoS table:**

| Workload | Container | CPU Req | CPU Lim | Mem Req | Mem Lim | QoS |
|----------|-----------|---------|---------|---------|---------|-----|
| redis | redis | 100m | 500m | 128Mi | 512Mi | Burstable |
| mail-it | mail-it | ❌ | ❌ | ❌ | ❌ | BestEffort ⚠ |

---

## Section 9 — Storage Resilience

**Generate from:** `pvcs.yaml`, `pvc-summary.txt`, `workload-detail.json`  
**Must include:**
- Per-PVC: name | access mode | storage class | bound workload | size
- Flag `ReadWriteOnce` PVCs on Deployments with `replicas > 1` as ⛔ CRITICAL (R10) — scheduling failure
- Flag PVCs without a bound workload (abandoned PVCs) as ℹ
- StatefulSet PVC templates: access modes, reclaim policy
- Storage class reclaim policy: Retain vs Delete (data protection)
- Backup annotation presence (e.g. `backup.velero.io/backup-volumes`)

---

## Section 10 — Disruption Simulation

**Generate from:** All collected data + Phase 2 gap analysis  
**Must include three sub-sections:**

### 10.1 Node Drain Simulation
- For each namespace: which workloads would be disrupted by a single node drain?
- Which PDBs would block the drain? (flag as blocking if `disruptionsAllowed: 0`)
- Expected impact per workload (complete outage / degraded / no impact)
- OCP upgrade readiness: can all nodes drain without hanging?

**Impact table:**

| Workload | PDB? | Drain Impact | Disruptions Allowed | Upgrade Blocker? |
|----------|------|--------------|---------------------|-----------------|
| jrcc-receiver | ❌ | ⛔ Complete outage | N/A | No (but risky) |
| rabbitmq | ✅ minAvailable:2 | ✅ 1 pod down max | 1 | No |

### 10.2 Zone Failure Simulation
- Are pods spread across multiple availability zones?
- Which workloads would be completely lost in a single-zone failure?
- Services with session affinity — what happens when the affinity-pinned pod is lost?

### 10.3 Rolling OCP Upgrade Impact
- Total nodes estimated in namespace's node pool
- Number of nodes that would be drained per upgrade wave
- Which workloads have `disruptionsAllowed: 0` during the upgrade window?
- Recommendation: "Run `oc adm drain <node> --dry-run` to validate before the upgrade window"

---

## Section 11 — Remediation Tasks

**Generate from:** Sections 3–10 findings  
**Must include:** All identified gaps as numbered tasks.  
**Format:** `RES-NN` — each task has priority, effort, owner category.

| Task | Priority | Category | Description | Effort |
|------|----------|----------|-------------|--------|
| RES-01 | ⛔ CRITICAL | PDB | Add PodDisruptionBudget to jrcc-receiver (minAvailable: 1) | 1h |
| RES-02 | ⛔ CRITICAL | PDB | Add PodDisruptionBudget to jrcc-transformer (minAvailable: 1) | 1h |
| RES-03 | ⚠ HIGH | Probes | Add readinessProbe to mail-it container | 2h |

**Priority ordering:** CRITICAL → HIGH → LOW  
**Effort estimates:** Use t-shirt sizes (1h, 2h, 4h, 1d, 2d)

---

## Section 12 — Appendix

Include:
- Raw PDB status (`pdb-summary.txt`)
- Raw HPA status (`hpa-summary.txt`)
- Raw disruption events (`disruption-events.txt`)
- Collection metadata (namespace, cluster, date, tool version)

---

## Quality Gate Checklist

Before finalising the report, verify:

- [ ] Every workload in the inventory appears in at least one analysis section
- [ ] Every ⛔ CRITICAL finding has a corresponding RES-NN task
- [ ] Every RES-NN task has enough detail to be actionable (includes YAML or command)
- [ ] Section 10 Disruption Simulation covers all three scenarios
- [ ] No placeholder text — every table cell has real data or "N/A (reason)"
- [ ] Scorecard in Section 1 matches the findings in Sections 3–9
- [ ] Overall grade is correctly derived from the worst-category grade
