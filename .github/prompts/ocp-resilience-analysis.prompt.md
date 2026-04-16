---
mode: agent
description: OCP Resilience Posture Analysis — full data collection, AI gap analysis, PDF report
---

# OCP Resilience Posture Analysis

Perform a complete OpenShift workload resilience analysis for the namespace below.

**Namespace prefix:** ${input:namespace:OCP license plate prefix (e.g. f1b263)}
**Cluster:** ${input:cluster:Source cluster (silver | gold | emerald)}
**Environments:** ${input:envs:Comma-separated environment suffixes (e.g. dev,test,prod,tools)}
**Output directory:** ${input:outputDir:Where to write the report (e.g. ./resilience-report)}
**Repository (optional):** ${input:repo:GitHub repo owner/name for cross-reference}

---

## Instructions

Load the skill at:
`/Users/rloisell/Documents/developer/rl-agents-n-skills/ocp-resilience-analyst/SKILL.md`

Then load:
- `bc-gov-devops/SKILL.md`
- `bc-gov-emerald/SKILL.md`
- `observability/SKILL.md`

Follow the four-phase workflow:

### Phase 1 — Collect
Run all Phase 1 collection commands from the skill against each environment suffix.
Store output in `${input:outputDir}/<namespace>-<env>/`.
Generate `manifest-summary.md`.

> Do NOT skip Phase 1 or fabricate data. If `oc` is not logged in, report the gap.

### Phase 2 — Gap Analysis
Assess every workload against R01–R15.
Build a per-workload findings table.
Assign an overall grade (A–F).

### Phase 3 — Draft Report
Generate the full 12-section resilience report.
Follow `ocp-resilience-toolkit/templates/report-sections.md` for each section.
Write to: `${input:outputDir}/report/<NAMESPACE_UPPER>-Resilience-Report.md`

### Phase 4 — Render PDF
```bash
bash ocp-resilience-toolkit/render/render.sh \
  --input  "${input:outputDir}/report/<NAMESPACE_UPPER>-Resilience-Report.md" \
  --output "${input:outputDir}/report" \
  --open
```

---

## Final output

- `${input:outputDir}/report/<NAMESPACE_UPPER>-Resilience-Report.md`
- `${input:outputDir}/report/<NAMESPACE_UPPER>-Resilience-Report.pdf`
