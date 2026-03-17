#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="DockerShiftLeft"
CERT_DIR="certs"
CERT_FILE="corporate-ca.crt"

# ── Argument Parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--prefix) PREFIX="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--prefix <prefix>]"
            echo "  -p, --prefix <prefix>  Image name prefix (default: DockerShiftLeft)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

images=(
  "stage0-code"
  "stage0-iac"
  "stage0-pwsh"
  "stage1-build"
  "stage3-sca"
  "stage9-sbom"
  "stage10-compliance"
)

# ── Locate corporate CA cert ─────────────────────────────────────────────────
CERT_SRC="${REPO_DIR}/${CERT_DIR}/${CERT_FILE}"
HAS_CERT=false
if [[ -f "$CERT_SRC" ]] && [[ -s "$CERT_SRC" ]]; then
  echo "==> Found ${CERT_DIR}/${CERT_FILE}"
  HAS_CERT=true
else
  echo "==> NOTE: ${CERT_DIR}/${CERT_FILE} not found — building without corporate CA cert."
fi

# ── Proxy build args (forwarded if set in environment) ───────────────────────
BUILD_ARGS=()
for var in HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy; do
  if [[ -n "${!var:-}" ]]; then
    BUILD_ARGS+=(--build-arg "${var}=${!var}")
    echo "==> Forwarding ${var} to builds"
  fi
done

# ── Clean up stage certs on exit ──────────────────────────────────────────────
cleanup() {
  for stage in "${images[@]}"; do
    rm -rf "${REPO_DIR}/${stage}/${CERT_DIR}"
  done
}
trap cleanup EXIT

echo "==> Building ${#images[@]} images..."

for stage in "${images[@]}"; do
  tag="${PREFIX}/${stage}:latest"
  stage_dir="${REPO_DIR}/${stage}"

  # Copy cert into stage's certs/ directory (or create empty placeholder)
  mkdir -p "${stage_dir}/${CERT_DIR}"
  if $HAS_CERT; then
    cp "$CERT_SRC" "${stage_dir}/${CERT_DIR}/${CERT_FILE}"
  else
    touch "${stage_dir}/${CERT_DIR}/${CERT_FILE}"
  fi

  echo ""
  echo "--- Building ${tag} (context: ${stage}/) ---"
  docker build "${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}" -t "${tag}" "${stage_dir}"
done

echo ""
echo "==> All images built:"
docker images --filter "reference=${PREFIX}/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
