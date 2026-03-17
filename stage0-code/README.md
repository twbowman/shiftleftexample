# Stage 0: Code Quality & Security

Scans Python, Dockerfile, and Shell scripts for lint, formatting, and security issues. Also runs gitleaks for secrets detection.

## Tools

| Tool | Language | Purpose |
|------|----------|---------|
| ruff | Python | Linting and formatting |
| bandit | Python | Security analysis |
| hadolint | Dockerfile | Dockerfile best practices |
| shellcheck | Shell | Shell script analysis |
| gitleaks | All | Secrets detection |

## Run via Pipeline

```bash
# Bash
./pipeline.sh --stage 0-code
./pipeline.sh --stage 0-code --target ./myapp
./pipeline.sh --stage 0-code --fix
```

```powershell
# PowerShell
.\pipeline.ps1 -Stage 0-code
.\pipeline.ps1 -Stage 0-code -Target ./myapp
.\pipeline.ps1 -Stage 0-code -Fix
```

## Run via Docker

```bash
# Scan current directory
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-code:latest --path /workspace

# Auto-fix issues
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-code:latest --path /workspace --fix

# Strict mode (warnings become errors)
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-code:latest --path /workspace --strict

# Skip specific tools
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-code:latest --path /workspace --skip gitleaks,bandit
```

## Script Options

| Flag | Description |
|------|-------------|
| `-p, --path <dir>` | Root path to scan (default: `.`) |
| `-f, --fix` | Apply auto-fixes (ruff lint + ruff format) |
| `-s, --skip <tools>` | Comma-separated tools to skip |
| `-S, --strict` | Treat warnings as errors |
| `-h, --help` | Show help |

Valid skip values: `ruff`, `bandit`, `hadolint`, `shellcheck`, `gitleaks`

## Behavior

- Without `--fix`: ruff format runs with `--check --diff` (reports only, no changes)
- With `--fix`: ruff format actually reformats files, ruff lint applies auto-fixes
- hadolint scans each Dockerfile individually
- shellcheck auto-detects shell type from shebang; skips unsupported shells (zsh, fish)
- gitleaks runs in `--no-git` mode (scans files, not git history)
- Exit code is non-zero if any tool fails
