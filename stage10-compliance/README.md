# Stage 10: Compliance & Policy Enforcement

Evaluates pipeline artifacts against security policies. Verifies image signatures, checks vulnerability thresholds, validates SBOM completeness, and runs custom OPA/Conftest policies.

## Checks Performed

1. **Signature Verification** — Verifies the image was signed with cosign
2. **Vulnerability Compliance** — Checks vuln-report.json against thresholds (no critical, high < 10)
3. **SBOM Completeness** — Validates SBOM exists, is valid JSON, has components and metadata
4. **Conftest Policies** — Runs custom .rego policies against all JSON artifacts

## Run via Pipeline

```bash
# Bash
./pipeline.sh --stage 10
./pipeline.sh --stage 10 --skip-verify
```

```powershell
# PowerShell
.\pipeline.ps1 -Stage 10
.\pipeline.ps1 -Stage 10 -SkipVerify
```

## Usage

### Native

```bash
# Basic compliance check
./comply.sh --artifacts ./artifacts --policy ./policies

# With image signature verification
./comply.sh --image jfrog.io/repo/myapp:1.0.0 --artifacts ./artifacts

# Skip signature verification (for unsigned images)
./comply.sh --artifacts ./artifacts --skip-verify

# Output compliance report
./comply.sh --artifacts ./artifacts --output ./artifacts/stage10
```

### Docker

```bash
# Build the stage10 image
docker build -t stage10-compliance ./stage10-compliance

# Run compliance checks
docker run --rm \
    -v "$(pwd)/artifacts":/artifacts \
    -v "$(pwd)/policies":/policies \
    stage10-compliance \
    --artifacts /artifacts \
    --policy /policies \
    --output /artifacts/stage10

# With signature verification (needs Docker socket for cosign)
docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$(pwd)/artifacts":/artifacts \
    stage10-compliance \
    --image jfrog.io/repo/myapp:1.0.0 \
    --artifacts /artifacts
```

## Options

| Flag | Description |
|------|-------------|
| `-i, --image <tag>` | Image to verify signature |
| `-a, --artifacts <dir>` | Artifacts directory from previous stages (required) |
| `-p, --policy <dir>` | Policy directory with .rego files (default: `./policies`) |
| `-o, --output <dir>` | Output directory for compliance report |
| `--skip-verify` | Skip image signature verification |

## Expected Artifacts Structure

```
artifacts/
├── stage3/
│   └── vuln-report.json      # From Stage 3 (Trivy scan)
└── stage9/
    ├── sbom.cyclonedx.json   # From Stage 9 (SBOM)
    └── sbom-metadata.json    # From Stage 9 (metadata)
```

## Writing Policies

Create `.rego` files in your policy directory:

```rego
# policies/vulnerabilities.rego
package main

deny[msg] {
    input.Results[_].Vulnerabilities[_].Severity == "CRITICAL"
    msg := "Critical vulnerabilities are not allowed"
}
```

```rego
# policies/sbom.rego
package main

deny[msg] {
    count(input.components) == 0
    msg := "SBOM must contain at least one component"
}
```

## Output

```
artifacts/stage10/
└── compliance-report.json
```

```json
{
    "image": "jfrog.io/repo/myapp:1.0.0",
    "checks_passed": 5,
    "checks_failed": 0,
    "checks_skipped": 1,
    "compliant": true,
    "timestamp": "2024-01-15T12:00:00Z"
}
```
