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

- Docker (via Docker Desktop on Windows, OrbStack on macOS, or Docker Engine on Linux)
- bash or PowerShell 5.1+

### Build all stage images

> **Note:** `build-all.sh` / `build-all.ps1` are intended for local testing and bootstrapping. In production, stage images will be built through the pipeline itself, pushed to JFrog Artifactory, and the pipeline will pull from the registry via `--registry` / `-Registry` instead of using local builds.

Place your corporate CA certificate (PEM format) at `certs/corporate-ca.crt`, then:

```bash
# Bash (macOS/Linux)
./build-all.sh

# PowerShell (Windows)
.\build-all.ps1
```

Images are tagged with the `DockerShiftLeft/` prefix by default (e.g. `DockerShiftLeft/stage0-code:latest`). Override with:

```bash
./build-all.sh --prefix myproject
.\build-all.ps1 -Prefix myproject
```

If `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` are set in your environment, they are forwarded as build args automatically.

You can also build individually from the repo root:

```bash
docker build -f stage0-code/Dockerfile -t DockerShiftLeft/stage0-code:latest .
```

> **Note:** All builds must use the repo root as the build context (`.`) so Dockerfiles can access `certs/corporate-ca.crt`.

### Run the full pipeline

```bash
# Bash
./pipeline.sh --target ./myapp --tag myapp:1.0.0

# PowerShell
.\pipeline.ps1 -Target ./myapp -Tag myapp:1.0.0
```

The pipeline stops on the first stage failure by default. Use `--continue` (bash) or `-ContinueOnFail` (PowerShell) to run all stages regardless.

---

## Pipeline Orchestrator

`pipeline.sh` / `pipeline.ps1` orchestrates all stages. Both scripts are equivalent.

### Options

| Flag (bash) | Flag (PowerShell) | Description |
|-------------|-------------------|-------------|
| `--target <path\|url>` | `-Target` | Local path or git URL to scan |
| `--stage <list>` | `-Stage` | Comma-separated stages (default: `all`) |
| `--tag <tag>` | `-Tag` | Image tag for build/scan (default: `app:latest`) |
| `--prefix <prefix>` | `-Prefix` | Image name prefix (default: `DockerShiftLeft`) |
| `--registry <url>` | `-Registry` | Container registry (e.g. `jfrog.io/docker-local`) |
| `--output <dir>` | `-Output` | Artifacts directory (default: `./artifacts`) |
| `--fix` | `-Fix` | Apply auto-fixes (ruff, tflint) |
| `--strict` | `-Strict` | Treat warnings as errors |
| `--fail-on <severity>` | `-FailOn` | Fail stage 3 on severity (e.g. `CRITICAL`) |
| `--skip-sign` | `-SkipSign` | Skip image signing in stage 9 |
| `--keyless` | `-Keyless` | Keyless signing via Sigstore/Fulcio |
| `--key <path>` | `-Key` | Cosign private key for signing |
| `--skip-verify` | `-SkipVerify` | Skip signature verification in stage 10 |
| `--continue` | `-ContinueOnFail` | Continue running stages after a failure |
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

# Use custom image prefix
./pipeline.sh --prefix myproject --stage 0-code

# Run all stages even if one fails
./pipeline.sh --continue

# Dry run to preview
./pipeline.sh --dry-run
```

```powershell
# Scan a local directory (code + IaC only)
# NOTE: In PowerShell, comma-separated stage lists MUST be in double quotes
.\pipeline.ps1 -Target ./myapp -Stage "0-code,0-iac"

# Scan a git repo
.\pipeline.ps1 -Target https://github.com/org/repo.git

# Full pipeline with JFrog registry
.\pipeline.ps1 -Target ./myapp -Tag myapp:1.0.0 -Registry jfrog.io/docker-local -Keyless

# Build, scan, and generate SBOM (no signing)
.\pipeline.ps1 -Stage "1,3,9" -Tag myapp:1.0.0 -SkipSign

# Auto-fix code issues
.\pipeline.ps1 -Stage 0-code -Target ./myapp -Fix

# Use custom image prefix
.\pipeline.ps1 -Prefix myproject -Stage 0-code

# Run all stages even if one fails
.\pipeline.ps1 -ContinueOnFail

# Dry run to preview
.\pipeline.ps1 -DryRun
```

> **PowerShell note:** When passing multiple stages, wrap the value in double quotes (e.g. `-Stage "0-code,0-iac"`). Without quotes, PowerShell interprets the comma as an array separator and only the first value is passed. Single stages like `-Stage 0-code` do not need quotes.

---

## Corporate Network / Proxy

If you're behind a corporate proxy or firewall with TLS interception, two things are needed:

### 1. CA Certificate

All Dockerfiles expect a `corporate-ca.crt` file in the `certs/` directory:

```
certs/
└── corporate-ca.crt    # Your corporate CA bundle (PEM format)
```

The cert file can contain multiple certificates (a full corporate CA bundle). During the Docker build, each certificate is validated with `openssl` and only non-expired certs are appended to the system trust store at `/etc/ssl/certs/ca-certificates.crt`.

The following environment variables are set in all images to ensure tools use the system bundle:

| Variable | Set in | Purpose |
|----------|--------|---------|
| `SSL_CERT_FILE` | All images | OpenSSL / generic TLS |
| `CURL_CA_BUNDLE` | All images | curl |
| `PIP_CERT` | Python images | pip |
| `REQUESTS_CA_BUNDLE` | Python images | Python requests library |

If `certs/corporate-ca.crt` is not present, the build scripts create an empty placeholder so builds succeed without a cert.

### 2. Proxy Environment Variables

Set these in your shell before running `build-all.sh` or the pipeline scripts:

```bash
export HTTP_PROXY=http://proxy.corp.example.com:8080
export HTTPS_PROXY=http://proxy.corp.example.com:8080
export NO_PROXY=localhost,127.0.0.1,.corp.example.com
```

- `build-all.sh` / `build-all.ps1` forward them as `--build-arg` to `docker build`
- `pipeline.sh` / `pipeline.ps1` forward them as `-e` flags to `docker run`

---

## Windows / Cross-Platform Notes

- All shell scripts (`.sh`) and Dockerfiles are forced to LF line endings via `.gitattributes`
- `build-all.ps1` automatically converts CRLF to LF for all shell scripts and Dockerfiles before building, so builds work correctly even if git checks out files with Windows line endings
- Each Dockerfile also runs `sed -i 's/\r$//'` on its entrypoint script as a safety net
- PowerShell scripts (`.ps1`) are compatible with PowerShell 5.1 (Windows built-in) and PowerShell 7+

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
for stage in stage0-code stage0-iac stage0-pwsh stage1-build stage3-sca stage9-sbom stage10-compliance; do
  docker tag DockerShiftLeft/${stage} ${REGISTRY}/${stage}
  docker push ${REGISTRY}/${stage}
done

# Run pipeline using registry images
./pipeline.sh --registry ${REGISTRY} --target ./myapp --tag myapp:1.0.0
```

For stage 9 JFrog credentials, create a `.secrets` file (see `stage9-sbom/.secrets.example`):

```
JFROG_USER=your-username
JFROG_TOKEN=your-api-token
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

- **bandit** is used for Python security scanning instead of semgrep. Semgrep adds ~400MB to the image with minimal benefit for Python-only scanning.
- **Trivy** covers both SCA (stage 3) and SBOM generation (stage 9), replacing the Grype + Syft combination for simplicity.
- **checkov** is kept in the IaC image despite its size (~500MB) because it provides ~3,000 cloud compliance policies with CIS/SOC2/HIPAA mapping.

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

```powershell
.\pipeline.ps1 -Target ./samples -Stage "0-code,0-iac,0-pwsh"
```
