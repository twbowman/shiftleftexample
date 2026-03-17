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

## Debugging & Interactive Testing

## Why Conftest

Conftest is a lightweight single-binary CLI (~30MB) that evaluates structured data (JSON, YAML) against OPA/Rego policies. It's the right fit for stage 10 because the job is to check static pipeline artifacts — vuln reports, SBOMs, metadata — against compliance rules without touching a running system.

Alternatives considered:
- OPA server — designed as a daemon, overkill for a one-shot policy check in a pipeline
- Custom bash/Python validation — brittle, hard to maintain, not declarative
- InSpec — tests runtime state of live infrastructure (SSH into hosts, cloud API checks). Complementary to Conftest but solves a different problem. InSpec would fit as a post-deploy stage ("is the running system compliant?") rather than a pre-deploy artifact gate ("are the pipeline outputs compliant?")

Conftest uses Rego, the same policy language as OPA, so policies are portable if you scale up later. Teams can drop `.rego` files into `policies/` without touching any pipeline code.

## Debugging & Interactive Testing

To drop into the container with a shell for debugging or testing tools directly:

```bash
# Interactive shell with artifacts and policies mounted
docker run --rm -it \
    -v "$(pwd)/artifacts":/artifacts \
    -v "$(pwd)/policies":/policies \
    --entrypoint bash \
    DockerShiftLeft/stage10-compliance:latest

# Once inside, test tools:
cosign version
conftest --version
jq --version

# Test conftest against a specific artifact
conftest test /artifacts/stage3/vuln-report.json --policy /policies
conftest test /artifacts/stage9/sbom.cyclonedx.json --policy /policies

# Inspect artifacts with jq
jq '.Results[].Vulnerabilities | length' /artifacts/stage3/vuln-report.json
jq '.components | length' /artifacts/stage9/sbom.cyclonedx.json

# Verify an image signature manually
cosign verify --certificate-identity-regexp '.*' --certificate-oidc-issuer-regexp '.*' myimage:latest
```
