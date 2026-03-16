#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="shiftleft"
CERT_DIR="certs"
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

# ── Distribute cert — no longer needed, Dockerfiles reference certs/ directly ─

echo "==> Checking for ${CERT_DIR}/${CERT_FILE}..."
if [[ ! -f "${REPO_DIR}/${CERT_DIR}/${CERT_FILE}" ]]; then
  echo "==> NOTE: ${CERT_DIR}/${CERT_FILE} not found — building without corporate CA cert."
  mkdir -p "${REPO_DIR}/${CERT_DIR}"
  touch "${REPO_DIR}/${CERT_DIR}/${CERT_FILE}"
  CERT_PLACEHOLDER=true
else
  echo "==> Found ${CERT_DIR}/${CERT_FILE}"
  CERT_PLACEHOLDER=false
fi

# ── Proxy build args (forwarded if set in environment) ───────────────────────
BUILD_ARGS=()
for var in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
  if [[ -n "${!var:-}" ]]; then
    BUILD_ARGS+=(--build-arg "${var}=${!var}")
    echo "==> Forwarding ${var} to builds"
  fi
done

echo "==> Building ${#images[@]} images..."

for stage in "${images[@]}"; do
  tag="${PREFIX}/${stage}:latest"
  echo ""
  echo "--- Building ${tag} (context: repo root, dockerfile: ${stage}/Dockerfile) ---"
  docker build "${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}" -f "${REPO_DIR}/${stage}/Dockerfile" -t "${tag}" "${REPO_DIR}"
done

echo ""
echo "==> All images built:"
docker images --filter "reference=${PREFIX}/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# ── Clean up placeholder cert if we created one ──────────────────────────────
if $CERT_PLACEHOLDER; then
  rm -f "${REPO_DIR}/${CERT_DIR}/${CERT_FILE}"
fi
