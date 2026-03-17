# Stage 0: PowerShell Linting

Scans PowerShell scripts (`.ps1`, `.psm1`, `.psd1`) using PSScriptAnalyzer via pwsh.

## Tools

| Tool | Language | Purpose |
|------|----------|---------|
| PSScriptAnalyzer | PowerShell | Linting and best practices |

## Run via Pipeline

```bash
# Bash
./pipeline.sh --stage 0-pwsh
./pipeline.sh --stage 0-pwsh --target ./myapp
./pipeline.sh --stage 0-pwsh --strict
```

```powershell
# PowerShell
.\pipeline.ps1 -Stage 0-pwsh
.\pipeline.ps1 -Stage 0-pwsh -Target ./myapp
.\pipeline.ps1 -Stage 0-pwsh -Strict
```

## Run via Docker

```bash
# Scan current directory
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-pwsh:latest --path /workspace

# Strict mode (include informational severity)
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-pwsh:latest --path /workspace --strict

# Skip PSScriptAnalyzer entirely
docker run --rm -v "$(pwd)":/workspace DockerShiftLeft/stage0-pwsh:latest --path /workspace --skip psscriptanalyzer
```

## Script Options

| Flag | Description |
|------|-------------|
| `-p, --path <dir>` | Root path to scan (default: `.`) |
| `-S, --strict` | Include informational severity (default: Warning and Error only) |
| `-s, --skip <tools>` | Skip psscriptanalyzer |
| `-h, --help` | Show help |

## Behavior

- Finds all `.ps1`, `.psm1`, `.psd1` files recursively
- Default severity: Error and Warning
- Strict mode adds Informational severity
- Exits 0 if no PowerShell files found
- Exit code is non-zero if any issues are found

## Debugging & Interactive Testing

To drop into the container with a shell for debugging or testing tools directly:

```bash
# Interactive shell with your code mounted
docker run --rm -it -v "$(pwd)":/workspace --entrypoint bash DockerShiftLeft/stage0-pwsh:latest

# Launch pwsh interactively
pwsh

# Inside pwsh, test PSScriptAnalyzer:
Import-Module PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path /workspace/myscript.ps1 -Severity Error,Warning
Get-Module PSScriptAnalyzer | Select-Object Version

# Or run from bash directly:
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path /workspace -Recurse -Severity Error,Warning"

# Check versions
pwsh --version
```
