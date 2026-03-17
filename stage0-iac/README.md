# Stage 0: IaC Linting & Compliance

Scans Terraform and Ansible infrastructure-as-code for lint, security, and compliance issues.

## Tools

| Tool | Language | Purpose |
|------|----------|---------|
| tflint | Terraform | Linting and best practices |
| checkov | Terraform/Ansible | Security and compliance (~3,000 policies) |
| ansible-lint | Ansible | Ansible best practices |

## Run via Pipeline

```bash
# Bash
./pipeline.sh --stage 0-iac
./pipeline.sh --stage 0-iac --target ./myapp
./pipeline.sh --stage 0-iac --fix
```

```powershell
# PowerShell
.\pipeline.ps1 -Stage 0-iac
.\pipeline.ps1 -Stage 0-iac -Target ./myapp
.\pipeline.ps1 -Stage 0-iac -Fix
```

## Run via Docker

```bash
# Scan current directory
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-iac:latest --path /workspace

# Auto-fix issues (tflint)
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-iac:latest --path /workspace --fix

# Strict mode
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-iac:latest --path /workspace --strict

# Skip specific tools
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-iac:latest --path /workspace --skip checkov
```

## Script Options

| Flag | Description |
|------|-------------|
| `-p, --path <dir>` | Root path to scan (default: `.`) |
| `-f, --fix` | Apply auto-fixes (tflint) |
| `-s, --skip <tools>` | Comma-separated tools to skip |
| `-S, --strict` | Treat warnings as errors |
| `-h, --help` | Show help |

Valid skip values: `tflint`, `checkov`, `ansible-lint`

## Behavior

- Terraform: scans each directory containing `.tf` files separately
- Ansible: detected heuristically via `ansible.cfg`, `playbooks/`, `roles/`, etc.
- checkov runs in `--soft-fail` mode by default (findings don't fail the stage); use `--strict` to enforce
- Exit code is non-zero if any tool fails
