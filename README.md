# DevSecOps Pipeline

A containerised, shift-left DevSecOps pipeline covering code quality, security scanning, IaC compliance, SBOM generation, image signing, and policy enforcement.

Each stage runs in its own Docker container and passes artifacts to the next stage via a shared volume. Stages can be run individually or orchestrated together using the pipeline scripts.

---

## Pipeline Stages

```
Stage 0-code  →  Stage 0-iac  →  Stage 0-pwsh  →  Stage 1  →  Stage 3  →  Stage 9  →  Stage 10
(code quality)   (IaC lint)      (PowerShell)      (build)     (SCA)       (SBOM+sign)  (compliance)
```

Stages 0-code, 0-iac, and 0-pwsh are designed to run in parallel.

| Stage | Directory | Purpose | Tools |
|-------|-----------|---------|-------|
| 0-code | `stage0-code/` | Code quality & general security | ruff, bandit, hadolint, shellcheck, gitleaks |
| 0-iac | `stage0-iac/` | IaC linting & compliance | tflint, checkov, ansible-lint |
| 0-pwsh | `stage0-pwsh/` | PowerShell linting | PSScriptAnalyzer |
| 1 | `stage1-build/` | Container image build | docker build |
| 3 | `stage3-sca/` | Software Composition Analysis | Trivy |
| 9 | `stage9-sbom/` | SBOM generation & image signing | Trivy, cosign |
| 10 | `stage10-compliance/` | Policy enforcement | cosign verify, conftest/OPA |

---

## Quick Start

### Prerequisites

- Docker (via [Rancher Desktop](https://rancherdesktop.io) or Docker Desktop)
- bash or PowerShell Core (pwsh)

### Build all stage images

Place your corporate CA certificate (PEM format) at `certs/corporate-ca.crt`, then:

```bash
./build-all.sh
```

This copies the cert into each stage's build context, builds all images with the `shiftleft/` prefix, and cleans up after. If `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` are set in your environment, they are forwarded as build args automatically.

You can also build individually from the repo root:

```bash
docker build -f stage0-code/Dockerfile -t stage0-code .
docker build -f stage0-iac/Dockerfile -t stage0-iac .
docker build -f stage0-pwsh/Dockerfile -t stage0-pwsh .
docker build -f stage1-build/Dockerfile -t stage1-build .
docker build -f stage3-sca/Dockerfile -t stage3-sca .
docker build -f stage9-sbom/Dockerfile -t stage9-sbom .
docker build -f stage10-compliance/Dockerfile -t stage10-compliance .
```

> **Note:** All builds must use the repo root as the build context (`.`) so Dockerfiles can access `certs/corporate-ca.crt`.

### Run the full pipeline

```bash
# Bash
./pipeline.sh --target ./myapp --tag myapp:1.0.0

# PowerShell
./pipeline.ps1 -Target ./myapp -Tag myapp:1.0.0
```

---

## Pipeline Orchestrator

`pipeline.sh` / `pipeline.ps1` orchestrates all stages. Both scripts are equivalent.

### Options

| Flag (bash) | Flag (PowerShell) | Description |
|-------------|-------------------|-------------|
| `--target <path\|url>` | `-Target` | Local path or git URL to scan |
| `--stage <list>` | `-Stage` | Comma-separated stages (default: `all`) |
| `--tag <tag>` | `-Tag` | Image tag for build/scan (default: `app:latest`) |
| `--registry <url>` | `-Registry` | Container registry (e.g. `jfrog.io/docker-local`) |
| `--output <dir>` | `-Output` | Artifacts directory (default: `./artifacts`) |
| `--fix` | `-Fix` | Apply auto-fixes (ruff, tflint) |
| `--strict` | `-Strict` | Treat warnings as errors |
| `--fail-on <severity>` | `-FailOn` | Fail stage 3 on severity (e.g. `CRITICAL`) |
| `--skip-sign` | `-SkipSign` | Skip image signing in stage 9 |
| `--keyless` | `-Keyless` | Keyless signing via Sigstore/Fulcio |
| `--key <path>` | `-Key` | Cosign private key for signing |
| `--skip-verify` | `-SkipVerify` | Skip signature verification in stage 10 |
| `--dry-run` | `-DryRun` | Preview commands without executing |

### Valid stage values

`0-code`, `0-iac`, `0-pwsh`, `1`, `3`, `9`, `10`, `all`

### Examples

```bash
# Scan a local directory (code + IaC only)
./pipeline.sh --target ./myapp --stage 0-code,0-iac

# Scan a git repo
./pipeline.sh --target https://github.com/org/repo.git

# Full pipeline with JFrog registry
./pipeline.sh --target ./myapp --tag myapp:1.0.0 --registry jfrog.io/docker-local --keyless

# Build, scan, and generate SBOM (no signing)
./pipeline.sh --stage 1,3,9 --tag myapp:1.0.0 --skip-sign

# Auto-fix code issues
./pipeline.sh --stage 0-code --target ./myapp --fix

# Dry run to preview
./pipeline.sh --dry-run
```

---

## Corporate Network / Proxy

If you're behind a corporate proxy or firewall with TLS interception, two things are needed:

### 1. CA Certificate

All Dockerfiles expect a `corporate-ca.crt` file in their build context. The `build-all.sh` script handles distributing it from the central `certs/` directory:

```
certs/
└── corporate-ca.crt    # Your corporate root CA (PEM format)
```

- Ubuntu images: installed via `update-ca-certificates`
- Alpine images: appended to `/etc/ssl/certs/ca-certificates.crt`
- pip-using images also set `PIP_CERT` to the system bundle

The cert is baked into the images at build time, so runtime tools (Trivy, checkov, curl, etc.) will trust your corporate CA automatically.

### 2. Proxy Environment Variables

Set these in your shell before running `build-all.sh` or the pipeline scripts:

```bash
export HTTP_PROXY=http://proxy.corp.example.com:8080
export HTTPS_PROXY=http://proxy.corp.example.com:8080
export NO_PROXY=localhost,127.0.0.1,.corp.example.com
```

- `build-all.sh` forwards them as `--build-arg` to `docker build`
- `pipeline.sh` / `pipeline.ps1` forward them as `-e` flags to `docker run`

---

## Artifacts

Each stage writes outputs to the shared artifacts directory:

```
artifacts/
├── stage1/
│   ├── app_latest.tar          # Built image tarball
│   └── build-metadata.json
├── stage3/
│   ├── vuln-report.json        # Trivy vulnerability report
│   └── scan-metadata.json
├── stage9/
│   ├── sbom.cyclonedx.json     # SBOM
│   └── sbom-metadata.json
└── stage10/
    └── compliance-report.json  # Policy evaluation results
```

---

## Registry (JFrog)

To use images from JFrog instead of local builds:

```bash
# Login
docker login your-instance.jfrog.io

# Push images
REGISTRY=your-instance.jfrog.io/docker-local
docker tag stage0-code ${REGISTRY}/stage0-code && docker push ${REGISTRY}/stage0-code
docker tag stage0-iac  ${REGISTRY}/stage0-iac  && docker push ${REGISTRY}/stage0-iac
docker tag stage0-pwsh ${REGISTRY}/stage0-pwsh && docker push ${REGISTRY}/stage0-pwsh
docker tag stage1-build ${REGISTRY}/stage1-build && docker push ${REGISTRY}/stage1-build
docker tag stage3-sca  ${REGISTRY}/stage3-sca  && docker push ${REGISTRY}/stage3-sca
docker tag stage9-sbom ${REGISTRY}/stage9-sbom && docker push ${REGISTRY}/stage9-sbom
docker tag stage10-compliance ${REGISTRY}/stage10-compliance && docker push ${REGISTRY}/stage10-compliance

# Run pipeline using registry images
./pipeline.sh --registry ${REGISTRY} --target ./myapp --tag myapp:1.0.0
```

For stage 9 JFrog credentials, create a `.secrets` file (see `stage9-sbom/.secrets.example`):

```
JFROG_USER=your-username
JFROG_TOKEN=your-api-token
```

---

## GitHub Actions

```yaml
jobs:
  stage0:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        stage: [stage0-code, stage0-iac, stage0-pwsh]
    steps:
      - uses: actions/checkout@v4
      - run: docker run --rm -v ${{ github.workspace }}:/workspace ${{ matrix.stage }}

  stage1:
    needs: stage0
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          docker run --rm \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v ${{ github.workspace }}:/workspace \
            -v ${{ github.workspace }}/artifacts:/artifacts \
            stage1-build --tag ${{ github.repository }}:${{ github.sha }} --output /artifacts/stage1
```

---

## Policies

OPA/Conftest policies live in `policies/`. Stage 10 evaluates all JSON artifacts against these rules.

```
policies/
├── vulnerabilities.rego   # No critical CVEs, high < 10
└── sbom.rego              # SBOM must have components and metadata
```

Add custom `.rego` files to enforce additional compliance requirements.

---

## Tool Selection Notes

- **bandit** is used for Python security scanning instead of semgrep. Semgrep adds ~400MB to the image with minimal benefit for Python-only scanning. Semgrep is the better choice if you need multi-language SAST or custom taint-tracking rules.
- **Trivy** covers both SCA (stage 3) and SBOM generation (stage 9), replacing the Grype + Syft combination for simplicity.
- **checkov** is kept in the IaC image despite its size (~500MB) because it provides ~3,000 cloud compliance policies with CIS/SOC2/HIPAA mapping that semgrep cannot replicate.

---

## Sample Files

`samples/` contains intentionally flawed code for testing each scanner:

```
samples/
├── python/       — unused vars, hardcoded passwords, shell=True, pickle
├── terraform/    — open security groups, unencrypted EBS, untyped variables
├── ansible/      — FQCN violations, truthy values, command-instead-of-module
├── docker/       — FROM latest, unpinned packages, missing pipefail
├── powershell/   — plaintext passwords, Invoke-Expression, cmdlet aliases
└── shell/        — unquoted variables, backticks, missing -r on read
```

Test locally:

```bash
./pipeline.sh --target ./samples --stage 0-code,0-iac,0-pwsh
```
