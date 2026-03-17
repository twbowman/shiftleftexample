# Stage 9: SBOM & Signing

Generates a Software Bill of Materials (SBOM) from a container image using Trivy, signs the image with cosign, and attaches the SBOM as an attestation.

## Run via Pipeline

```bash
# Bash
./pipeline.sh --stage 9
./pipeline.sh --stage 9 --skip-sign
./pipeline.sh --stage 9 --keyless
./pipeline.sh --stage 9 --key cosign.key
```

```powershell
# PowerShell
.\pipeline.ps1 -Stage 9
.\pipeline.ps1 -Stage 9 -SkipSign
.\pipeline.ps1 -Stage 9 -Keyless
.\pipeline.ps1 -Stage 9 -Key cosign.key
```

> If no key or `-Keyless` is specified, the pipeline automatically adds `--skip-sign` and generates the SBOM only.

## Usage

### Native (requires trivy + cosign)

```bash
# Generate SBOM only (no signing)
./sbom-sign.sh --image myapp:1.0.0 --output ./artifacts/stage9 --skip-sign

# Keyless signing (Sigstore/Fulcio - requires OIDC auth)
./sbom-sign.sh --image myapp:1.0.0 --output ./artifacts/stage9 --keyless

# Sign with a private key
./sbom-sign.sh --image myapp:1.0.0 --key cosign.key --output ./artifacts/stage9

# Push to registry, then sign
./sbom-sign.sh --image myapp:1.0.0 --registry jfrog.io/docker-local --keyless --output ./artifacts/stage9

# Use SPDX format instead of CycloneDX
./sbom-sign.sh --image myapp:1.0.0 --format spdx-json --skip-sign --output ./artifacts/stage9
```

### Docker

```bash
# Build the stage9 image
docker build -t stage9-sbom ./stage9-sbom

# Generate SBOM only
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)/artifacts":/artifacts \
    stage9-sbom \
    --image myapp:1.0.0 \
    --output /artifacts/stage9 \
    --skip-sign

# Keyless signing (interactive - opens browser for OIDC)
docker run --rm -it \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)/artifacts":/artifacts \
    stage9-sbom \
    --image myapp:1.0.0 \
    --output /artifacts/stage9 \
    --keyless

# Sign with key file
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)/artifacts":/artifacts \
    -v "$(pwd)/cosign.key":/cosign.key:ro \
    -e COSIGN_PASSWORD \
    stage9-sbom \
    --image myapp:1.0.0 \
    --key /cosign.key \
    --output /artifacts/stage9
```

### GitHub Actions (Keyless)

```yaml
- name: Stage 9 - SBOM & Sign
  env:
    COSIGN_EXPERIMENTAL: 1
  run: |
    docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${{ github.workspace }}/artifacts:/artifacts \
      -e ACTIONS_ID_TOKEN_REQUEST_URL \
      -e ACTIONS_ID_TOKEN_REQUEST_TOKEN \
      stage9-sbom \
      --image ${{ env.IMAGE_TAG }} \
      --registry ${{ env.REGISTRY }} \
      --keyless \
      --output /artifacts/stage9
```

## Options

| Flag | Description |
|------|-------------|
| `-i, --image <tag>` | Image to process (required) |
| `-o, --output <dir>` | Output directory for SBOM and metadata |
| `-f, --format <fmt>` | SBOM format: `cyclonedx` or `spdx-json` (default: `cyclonedx`) |
| `-k, --key <path>` | Cosign private key for signing |
| `--keyless` | Use keyless signing (Sigstore/Fulcio OIDC) |
| `--skip-sign` | Generate SBOM only, skip signing |
| `--registry <url>` | Push image to registry before signing |

## Artifacts

```
<output>/
├── sbom.cyclonedx.json   # SBOM in CycloneDX format
└── sbom-metadata.json    # Stage metadata for downstream
```

## Signing Modes

### Keyless (Sigstore/Fulcio)
Uses OIDC identity (GitHub Actions, Google, Microsoft) to sign without managing keys. Signatures are recorded in the Rekor transparency log.

### Key-based
Traditional signing with a cosign key pair. Generate keys with:
```bash
cosign generate-key-pair
```

## What Gets Signed

1. **Image signature** — proves the image hasn't been tampered with
2. **SBOM attestation** — the SBOM is attached to the image as an in-toto attestation, verifiable with `cosign verify-attestation`

Downstream Stage 10 can verify both the signature and the SBOM attestation before allowing deployment.
