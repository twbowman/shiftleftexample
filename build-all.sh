#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="shiftleft"

images=(
  "stage0-code"
  "stage0-iac"
  "stage0-pwsh"
  "stage1-build"
  "stage3-sca"
  "stage9-sbom"
  "stage10-compliance"
)

echo "==> Building ${#images[@]} images..."

for stage in "${images[@]}"; do
  tag="${PREFIX}/${stage}:latest"
  context="${REPO_DIR}/${stage}"
  echo ""
  echo "--- Building ${tag} from ${context} ---"
  docker build -t "${tag}" "${context}"
done

echo ""
echo "==> All images built:"
docker images --filter "reference=${PREFIX}/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
