#!/usr/bin/env bash
# render/render.sh — pandoc + headless Chromium PDF renderer
# Ryan Loisell — Developer / Architect | GitHub Copilot | April 2026
#
# Identical to ocp-migration-toolkit/render/render.sh — shared pattern.
# Usage:
#   render.sh --input <file.md> --output <dir> [--css <style.css>] [--open]

set -euo pipefail

INPUT=""
OUTPUT_DIR=""
CSS_PATH=""
OPEN_AFTER=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)  INPUT="$2";      shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --css)    CSS_PATH="$2";   shift 2 ;;
    --open)   OPEN_AFTER=true; shift   ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${INPUT}" || -z "${OUTPUT_DIR}" ]]; then
  echo "Usage: render.sh --input <file.md> --output <dir> [--css <style.css>] [--open]" >&2
  exit 1
fi

if ! command -v pandoc &>/dev/null; then
  echo "ERROR: pandoc not found. Install with: brew install pandoc (macOS) or apt-get install pandoc (Linux)" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
BASENAME="$(basename "${INPUT}" .md)"
HTML_FILE="${OUTPUT_DIR}/${BASENAME}.html"
PDF_FILE="${OUTPUT_DIR}/${BASENAME}.pdf"

# Determine CSS argument
CSS_ARG=""
if [[ -n "${CSS_PATH}" && -f "${CSS_PATH}" ]]; then
  CSS_ARG="--css=${CSS_PATH}"
fi

# Run pandoc from the input file's directory so relative image paths resolve
INPUT_DIR="$(cd "$(dirname "${INPUT}")" && pwd)"
INPUT_FILE="$(basename "${INPUT}")"

echo "Rendering HTML with pandoc..." >&2
(cd "${INPUT_DIR}" && pandoc "${INPUT_FILE}" \
  --from markdown+tables+fenced_code_blocks+pipe_tables \
  --to html5 \
  --standalone \
  --embed-resources \
  ${CSS_ARG} \
  -o "${HTML_FILE}")

echo "Rendering PDF with headless Chromium..." >&2

# Find chromium/chrome binary
CHROME=""
for candidate in \
  google-chrome-stable google-chrome chromium chromium-browser \
  /usr/bin/chromium /usr/bin/chromium-browser \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
  if command -v "${candidate}" &>/dev/null 2>&1 || [[ -x "${candidate}" ]]; then
    CHROME="${candidate}"
    break
  fi
done

if [[ -z "${CHROME}" ]]; then
  echo "ERROR: Chromium/Chrome not found. Install with:" >&2
  echo "  macOS: brew install --cask chromium" >&2
  echo "  Linux: apt-get install chromium" >&2
  echo "Markdown report is available at: ${INPUT}" >&2
  exit 1
fi

"${CHROME}" \
  --headless \
  --disable-gpu \
  --no-sandbox \
  --disable-dev-shm-usage \
  --print-to-pdf="${PDF_FILE}" \
  --no-pdf-header-footer \
  --print-to-pdf-no-header \
  "file://${HTML_FILE}" 2>/dev/null

echo "✅ PDF written: ${PDF_FILE}" >&2

if [[ "${OPEN_AFTER}" == "true" && "$(uname)" == "Darwin" ]]; then
  open "${PDF_FILE}"
fi
