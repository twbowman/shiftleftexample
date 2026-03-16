<#
.SYNOPSIS
    Build all pipeline stage Docker images locally.
.DESCRIPTION
    Builds all stage images using the repo root as the build context.
    Requires certs/corporate-ca.crt to be present.
    Forwards proxy environment variables as build args if set.
.EXAMPLE
    ./build-all.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Prefix = "shiftleft"
$CertDir = "certs"
$CertFile = "corporate-ca.crt"

$Images = @(
    "stage0-code"
    "stage0-iac"
    "stage0-pwsh"
    "stage1-build"
    "stage3-sca"
    "stage9-sbom"
    "stage10-compliance"
)

# ── Check for corporate CA cert ─────────────────────────────────────────────
$CertPath = Join-Path $RepoDir "$CertDir/$CertFile"
Write-Host "==> Checking for $CertDir/$CertFile..."
$CertPlaceholder = $false
if (-not (Test-Path $CertPath)) {
    Write-Host "==> NOTE: $CertDir/$CertFile not found — building without corporate CA cert." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path (Join-Path $RepoDir $CertDir) | Out-Null
    New-Item -ItemType File -Force -Path $CertPath | Out-Null
    $CertPlaceholder = $true
} else {
    Write-Host "==> Found $CertDir/$CertFile"
}

# ── Proxy build args (forwarded if set in environment) ───────────────────────
$BuildArgs = @()
foreach ($var in @("HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy")) {
    $val = [System.Environment]::GetEnvironmentVariable($var)
    if ($val) {
        $BuildArgs += @("--build-arg", "${var}=${val}")
        Write-Host "==> Forwarding $var to builds"
    }
}

Write-Host "==> Building $($Images.Count) images..."

foreach ($stage in $Images) {
    $tag = "${Prefix}/${stage}:latest"
    $dockerfile = Join-Path $RepoDir "$stage/Dockerfile"
    Write-Host ""
    Write-Host "--- Building $tag (context: repo root, dockerfile: $stage/Dockerfile) ---"
    & docker build @BuildArgs -f $dockerfile -t $tag $RepoDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "==> FAILED to build $tag" -ForegroundColor Red
        if ($CertPlaceholder) { Remove-Item -Force $CertPath }
        exit 1
    }
}

Write-Host ""
Write-Host "==> All images built:"
& docker images --filter "reference=${Prefix}/*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

# ── Clean up placeholder cert if we created one ──────────────────────────────
if ($CertPlaceholder) {
    Remove-Item -Force $CertPath
}
