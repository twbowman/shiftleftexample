#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="shiftleft"
CERT_FILE="corporate-ca.crt"

images=(
  "stage0-code"
  "stage0-iac"
  "stage0-pwsh"
  "stage1-build"
  "stage3-sca"
  "stage9-sbom"
  "stage10-compliance"
)

# ── Distribute cert into each stage build context ────────────────────────────
if [[ -f "${REPO_DIR}/${CERT_FILE}" ]]; then
  echo "==> Found ${CERT_FILE}, copying into each stage directory..."
  for stage in "${images[@]}"; do
    cp "${REPO_DIR}/${CERT_FILE}" "${REPO_DIR}/${stage}/${CERT_FILE}"
  done
else
  echo "==> WARNING: ${CERT_FILE} not found in repo root. Builds will fail."
  echo "    Place your corporate CA PEM at: ${REPO_DIR}/${CERT_FILE}"
  exit 1
fi

echo "==> Building ${#images[@]} images..."

for stage in "${images[@]}"; do
  tag="${PREFIX}/${stage}:latest"
  context="${REPO_DIR}/${stage}"
  echo ""
  echo "--- Building ${tag} from ${context} ---"
  docker build -t "${tag}" "${context}"
done

# ── Clean up copied certs ────────────────────────────────────────────────────
for stage in "${images[@]}"; do
  rm -f "${REPO_DIR}/${stage}/${CERT_FILE}"
done

echo ""
echo "==> All images built:"
docker images --filter "reference=${PREFIX}/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
