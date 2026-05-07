#!/usr/bin/env bash
# collect/collect.sh — OCP resilience data collection
# Ryan Loisell — Developer / Architect | GitHub Copilot | April 2026
#
# Collects all data needed for resilience posture analysis from one or more
# OpenShift namespaces. Produces a manifest-summary.md for AI consumption.
#
# Usage:
#   collect.sh --namespace <prefix> [--cluster <name>] [--envs <list>]
#              [--repo <owner/name>] [--output <dir>] [--oc-token <token>]
#              [--oc-url <url>]
#
# Prerequisites: oc CLI (logged in or --oc-token provided), jq, gh CLI (optional)

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────
NAMESPACE=""
CLUSTER="silver"
ENVS="dev,test,prod,tools"
REPO=""
OUTPUT="./resilience-output"
OC_TOKEN=""
OC_URL=""
SKIP_REPO=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)  NAMESPACE="$2";  shift 2 ;;
    --cluster)    CLUSTER="$2";    shift 2 ;;
    --envs)       ENVS="$2";       shift 2 ;;
    --repo)       REPO="$2";       shift 2 ;;
    --output)     OUTPUT="$2";     shift 2 ;;
    --oc-token)   OC_TOKEN="$2";   shift 2 ;;
    --oc-url)     OC_URL="$2";     shift 2 ;;
    --skip-repo)  SKIP_REPO=true;  shift   ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${NAMESPACE}" ]]; then
  echo "ERROR: --namespace is required" >&2
  exit 1
fi

# Validate namespace is a 6-char alphanumeric license plate
if ! [[ "${NAMESPACE}" =~ ^[a-z0-9]{6}$ ]]; then
  echo "ERROR: namespace must be a 6-character alphanumeric license plate (e.g. f1b263)" >&2
  exit 1
fi

# ── OC login ──────────────────────────────────────────────────────────────────
if [[ -n "${OC_TOKEN}" && -n "${OC_URL}" ]]; then
  echo "Logging in to OpenShift ${OC_URL}..." >&2
  oc login --token="${OC_TOKEN}" --server="${OC_URL}" --insecure-skip-tls-verify=false 2>/dev/null
elif [[ -n "${OC_TOKEN}" ]]; then
  # Try to infer URL from cluster name
  case "${CLUSTER}" in
    silver)  OC_URL="https://api.silver.devops.gov.bc.ca:6443" ;;
    gold)    OC_URL="https://api.gold.devops.gov.bc.ca:6443" ;;
    emerald) OC_URL="https://api.emerald.devops.gov.bc.ca:6443" ;;
    *)       echo "WARNING: unknown cluster '${CLUSTER}', using token without login" >&2 ;;
  esac
  if [[ -n "${OC_URL}" ]]; then
    oc login --token="${OC_TOKEN}" --server="${OC_URL}" 2>/dev/null || true
  fi
fi

mkdir -p "${OUTPUT}"

IFS=',' read -ra ENV_LIST <<< "${ENVS}"

# ── Per-environment collection ────────────────────────────────────────────────
collect_environment() {
  local ENV="$1"
  local NS="${NAMESPACE}-${ENV}"
  local OUT="${OUTPUT}/${NS}"
  mkdir -p "${OUT}"

  echo "▶ Collecting resilience data from ${NS}..." >&2

  # Verify namespace exists
  if ! oc get namespace "${NS}" &>/dev/null; then
    echo "  WARNING: namespace ${NS} not found — skipping" >&2
    echo "namespace_missing=true" > "${OUT}/.status"
    return 0
  fi

  # ── Core workloads (includes legacy DeploymentConfig) ────────────────────
  oc get deployment,statefulset,daemonset,cronjob,deploymentconfig -n "${NS}" -o yaml \
    > "${OUT}/workloads.yaml" 2>/dev/null || echo "# No workloads" > "${OUT}/workloads.yaml"

  oc get deployment,statefulset,daemonset,deploymentconfig -n "${NS}" \
    -o custom-columns='NAME:.metadata.name,KIND:.kind,REPLICAS:.spec.replicas,STRATEGY:.spec.strategy.type' \
    --no-headers 2>/dev/null > "${OUT}/workload-summary.txt" \
    || echo "(none)" > "${OUT}/workload-summary.txt"

  # ── PodDisruptionBudgets (PRIMARY) ────────────────────────────────────────
  oc get pdb -n "${NS}" -o yaml > "${OUT}/pdbs.yaml" 2>/dev/null \
    || echo "# No PDBs" > "${OUT}/pdbs.yaml"

  {
    oc get pdb -n "${NS}" \
      -o custom-columns='NAME:.metadata.name,MIN-AVAIL:.spec.minAvailable,MAX-UNAVAIL:.spec.maxUnavailable,CURRENT-HEALTHY:.status.currentHealthy,DESIRED-HEALTHY:.status.desiredHealthy,DISRUPTIONS-ALLOWED:.status.disruptionsAllowed' \
      --no-headers 2>/dev/null \
    || echo "(no PDBs found)"
  } > "${OUT}/pdb-summary.txt"

  # ── HPAs ─────────────────────────────────────────────────────────────────
  oc get hpa -n "${NS}" -o yaml > "${OUT}/hpas.yaml" 2>/dev/null \
    || echo "# No HPAs" > "${OUT}/hpas.yaml"

  {
    oc get hpa -n "${NS}" \
      -o custom-columns='NAME:.metadata.name,TARGET:.spec.scaleTargetRef.name,MIN:.spec.minReplicas,MAX:.spec.maxReplicas,CURRENT:.status.currentReplicas' \
      --no-headers 2>/dev/null \
    || echo "(no HPAs found)"
  } > "${OUT}/hpa-summary.txt"

  # ── VPA (optional) ────────────────────────────────────────────────────────
  oc get vpa -n "${NS}" -o yaml > "${OUT}/vpas.yaml" 2>/dev/null \
    || echo "# VPA not available or no VPAs" > "${OUT}/vpas.yaml"

  # ── Pods ─────────────────────────────────────────────────────────────────
  oc get pod -n "${NS}" -o wide --no-headers > "${OUT}/pods-wide.txt" 2>/dev/null \
    || echo "(no pods)" > "${OUT}/pods-wide.txt"

  oc get pod -n "${NS}" -o yaml > "${OUT}/pods.yaml" 2>/dev/null \
    || echo "# No pods" > "${OUT}/pods.yaml"

  # Pod → node distribution (anti-affinity analysis)
  oc get pod -n "${NS}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\t"}{.metadata.labels.app}{"\n"}{end}' \
    2>/dev/null > "${OUT}/pod-node-distribution.txt" \
    || echo "" > "${OUT}/pod-node-distribution.txt"

  # Priority class per pod
  oc get pod -n "${NS}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.priorityClassName}{"\n"}{end}' \
    2>/dev/null > "${OUT}/priority-classes.txt" \
    || echo "" > "${OUT}/priority-classes.txt"

  # ── Resource quotas / limits ──────────────────────────────────────────────
  oc get resourcequota,limitrange -n "${NS}" -o yaml > "${OUT}/quota.yaml" 2>/dev/null \
    || echo "# No quotas or limit ranges" > "${OUT}/quota.yaml"

  # ── PVCs (storage resilience) ─────────────────────────────────────────────
  oc get pvc -n "${NS}" -o yaml > "${OUT}/pvcs.yaml" 2>/dev/null \
    || echo "# No PVCs" > "${OUT}/pvcs.yaml"

  {
    oc get pvc -n "${NS}" \
      -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.status.capacity.storage,ACCESS:.spec.accessModes[0],STORAGECLASS:.spec.storageClassName' \
      --no-headers 2>/dev/null \
    || echo "(no PVCs)"
  } > "${OUT}/pvc-summary.txt"

  # ── Services ─────────────────────────────────────────────────────────────
  oc get svc -n "${NS}" -o yaml > "${OUT}/services.yaml" 2>/dev/null \
    || echo "# No services" > "${OUT}/services.yaml"

  # ── Disruption events (last 72h) ──────────────────────────────────────────
  {
    oc get events -n "${NS}" \
      --field-selector "reason=Evicted" \
      --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true
    oc get events -n "${NS}" \
      --field-selector "reason=OOMKilling" \
      --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true
    oc get events -n "${NS}" \
      --field-selector "reason=BackOff" \
      --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true
    oc get events -n "${NS}" \
      --field-selector "reason=Unhealthy" \
      --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true
  } > "${OUT}/disruption-events.txt" 2>/dev/null || echo "(no disruption events)" > "${OUT}/disruption-events.txt"

  oc get events -n "${NS}" --sort-by='.lastTimestamp' 2>/dev/null | tail -50 \
    > "${OUT}/recent-events.txt" || echo "(no events)" > "${OUT}/recent-events.txt"

  # ── Rollout history ───────────────────────────────────────────────────────
  oc rollout history deployment -n "${NS}" 2>/dev/null \
    > "${OUT}/rollout-history.txt" || echo "(no deployments)" > "${OUT}/rollout-history.txt"

  # ── Detailed workload JSON (probes, affinity, resources) ──────────────────
  # Includes DeploymentConfig (legacy OpenShift) where strategy lives at .spec.strategy
  # and template at .spec.template (no .spec.template.spec wrapper difference vs Deployment).
  if command -v jq &>/dev/null; then
    {
      oc get deployment,statefulset,deploymentconfig -n "${NS}" -o json 2>/dev/null \
        | jq '[.items[] | {
            name:       .metadata.name,
            kind:       .kind,
            replicas:   .spec.replicas,
            strategy:   .spec.strategy,
            terminationGracePeriodSeconds: .spec.template.spec.terminationGracePeriodSeconds,
            priorityClassName: .spec.template.spec.priorityClassName,
            containers: [.spec.template.spec.containers[] | {
              name:          .name,
              image:         .image,
              livenessProbe: .livenessProbe,
              readinessProbe: .readinessProbe,
              startupProbe:  .startupProbe,
              resources:     .resources,
              lifecycle:     .lifecycle
            }],
            affinity:                   .spec.template.spec.affinity,
            topologySpreadConstraints:  .spec.template.spec.topologySpreadConstraints,
            nodeSelector:               .spec.template.spec.nodeSelector,
            tolerations:                .spec.template.spec.tolerations
          }]' 2>/dev/null
    } > "${OUT}/workload-detail.json"
    # If empty or invalid, fall back to []
    if ! jq -e 'type == "array"' "${OUT}/workload-detail.json" >/dev/null 2>&1; then
      echo "[]" > "${OUT}/workload-detail.json"
    fi
  fi

  echo "  ✓ ${NS}" >&2
}

# Collect each environment
for ENV in "${ENV_LIST[@]}"; do
  ENV="${ENV// /}"  # trim whitespace
  collect_environment "${ENV}"
done

# ── Optional: GitHub repo data ────────────────────────────────────────────────
if [[ -n "${REPO}" && "${SKIP_REPO}" == "false" ]]; then
  echo "▶ Collecting GitHub repo data from ${REPO}..." >&2
  REPO_OUT="${OUTPUT}/repo"
  mkdir -p "${REPO_OUT}"

  if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    # Check for Deployment YAML with PDB, HPA, probe definitions
    gh api "repos/${REPO}/git/trees/HEAD?recursive=1" \
      --jq '.tree[].path' 2>/dev/null \
      | grep -E '\.(yaml|yml)$' \
      | grep -iv 'node_modules\|vendor' \
      > "${REPO_OUT}/yaml-files.txt" || true

    # Count PDB, HPA, probe occurrences in repo
    {
      echo "# PDB references in repo"
      gh search code "PodDisruptionBudget" --repo "${REPO}" --json path,textMatches 2>/dev/null || echo "(gh search unavailable)"
    } > "${REPO_OUT}/pdb-in-repo.txt"
    echo "  ✓ Repo data collected" >&2
  else
    echo "  WARNING: gh CLI not authenticated — skipping repo collection" >&2
  fi
fi

# ── Generate manifest-summary.md ──────────────────────────────────────────────
echo "▶ Generating manifest-summary.md..." >&2

SUMMARY_FILE="${OUTPUT}/manifest-summary.md"

{
  echo "# Resilience Collection Summary"
  echo ""
  echo "**Namespace prefix:** ${NAMESPACE}"
  echo "**Cluster:** ${CLUSTER}"
  echo "**Environments:** ${ENVS}"
  echo "**Repository:** ${REPO:-not provided}"
  echo "**Collection date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  for ENV in "${ENV_LIST[@]}"; do
    ENV="${ENV// /}"
    NS="${NAMESPACE}-${ENV}"
    OUT="${OUTPUT}/${NS}"

    echo "---"
    echo ""
    echo "## Environment: ${NS}"
    echo ""

    if [[ -f "${OUT}/.status" && "$(cat "${OUT}/.status")" == "namespace_missing=true" ]]; then
      echo "> ⚠️ Namespace not found — skipped."
      echo ""
      continue
    fi

    echo "### Workloads"
    echo '```'
    cat "${OUT}/workload-summary.txt" 2>/dev/null || echo "(no data)"
    echo '```'
    echo ""

    echo "### PodDisruptionBudgets"
    echo '```'
    cat "${OUT}/pdb-summary.txt" 2>/dev/null || echo "(no data)"
    echo '```'
    echo ""

    echo "### HorizontalPodAutoscalers"
    echo '```'
    cat "${OUT}/hpa-summary.txt" 2>/dev/null || echo "(no data)"
    echo '```'
    echo ""

    echo "### PVCs"
    echo '```'
    cat "${OUT}/pvc-summary.txt" 2>/dev/null || echo "(no data)"
    echo '```'
    echo ""

    echo "### Pod Node Distribution"
    echo '```'
    cat "${OUT}/pod-node-distribution.txt" 2>/dev/null || echo "(no data)"
    echo '```'
    echo ""

    echo "### Recent Disruption Events"
    echo '```'
    head -30 "${OUT}/disruption-events.txt" 2>/dev/null || echo "(no data)"
    echo '```'
    echo ""
  done

} > "${SUMMARY_FILE}"

echo ""
echo "✅ Collection complete." >&2
echo "   Summary: ${SUMMARY_FILE}" >&2
echo "   Working data: ${OUTPUT}/" >&2
