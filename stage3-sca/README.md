# Stage 3: Software Composition Analysis

Scans container images and repositories for known vulnerabilities using Trivy.

## Run via Pipeline

```bash
# Bash
./pipeline.sh --stage 3
./pipeline.sh --stage 3 --tag myapp:1.0.0
./pipeline.sh --stage 3 --fail-on CRITICAL
```

```powershell
# PowerShell
.\pipeline.ps1 -Stage 3
.\pipeline.ps1 -Stage 3 -Tag myapp:1.0.0
.\pipeline.ps1 -Stage 3 -FailOn CRITICAL
```

## Usage

### Native (requires trivy)

```bash
# Scan an image
./scan.sh --image myapp:1.0.0 --output ./artifacts/stage3

# Scan an image tarball from Stage 1
./scan.sh --image ./artifacts/stage1/myapp_1.0.0.tar --output ./artifacts/stage3

# Scan a repo/filesystem for dependency vulnerabilities
./scan.sh --repo /path/to/project --output ./artifacts/stage3

# Fail pipeline on critical vulnerabilities
./scan.sh --image myapp:1.0.0 --fail-on CRITICAL --output ./artifacts/stage3

# Scan both image and repo
./scan.sh --image myapp:1.0.0 --repo /workspace --output ./artifacts/stage3
```

### Docker

```bash
# Build the stage3 image
docker build -t stage3-sca ./stage3-sca

# Scan an image (mount Docker socket for image access)
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)/artifacts":/artifacts \
    stage3-sca \
    --image myapp:1.0.0 \
    --output /artifacts/stage3

# Scan from Stage 1 tarball
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)/artifacts":/artifacts \
    stage3-sca \
    --image /artifacts/stage1/myapp_1.0.0.tar \
    --output /artifacts/stage3

# Scan repo filesystem
docker run --rm \
    -v "$(pwd)":/workspace \
    -v "$(pwd)/artifacts":/artifacts \
    stage3-sca \
    --repo /workspace \
    --output /artifacts/stage3
```

## Options

| Flag | Description |
|------|-------------|
| `-i, --image <tag>` | Image to scan (tag or tarball path) |
| `-r, --repo <path>` | Git repo or filesystem path to scan |
| `-o, --output <dir>` | Output directory for reports |
| `-s, --severity <levels>` | Severity filter (default: `HIGH,CRITICAL`) |
| `--fail-on <severity>` | Exit non-zero if vulnerabilities found at this level |
| `--ignore-unfixed` | Ignore vulnerabilities without available fixes |

## Artifacts

```
<output>/
├── vuln-report.json     # Image vulnerability report (JSON)
├── repo-scan.json       # Repo dependency scan report (JSON)
└── scan-metadata.json   # Scan metadata for downstream stages
```

These reports feed into Stage 9 (SBOM) and Stage 10 (compliance policy evaluation).

## Why Trivy over Syft + Grype

Trivy handles both vulnerability scanning (Stage 3) and SBOM generation (Stage 9) in a single tool, replacing the Syft + Grype combination. This means one binary to install, one vulnerability database to update, and consistent results across stages. Grype and Syft are solid tools, but maintaining two separate binaries with their own update cycles adds complexity without meaningful coverage gains for our use case.
