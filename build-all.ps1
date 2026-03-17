<#
.SYNOPSIS
    Build all pipeline stage Docker images locally.
.DESCRIPTION
    Builds all stage images using the repo root as the build context.
    Forwards proxy environment variables as build args if set.
    Creates an empty placeholder cert if certs/corporate-ca.crt is not present.
.PARAMETER Prefix
    Image name prefix (default: shiftleft). Images are tagged as prefix/stage:latest.
.EXAMPLE
    ./build-all.ps1
    ./build-all.ps1 -Prefix myproject
#>

[CmdletBinding()]
param(
    [string]$Prefix = "DockerShiftLeft"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CertDir = "certs"
$CertFile = "corporate-ca.crt"

$Images = @(
    "stage0-code",
    "stage0-iac",
    "stage0-pwsh",
    "stage1-build",
    "stage3-sca",
    "stage9-sbom",
    "stage10-compliance"
)

# Check for corporate CA cert
$CertPath = Join-Path $RepoDir (Join-Path $CertDir $CertFile)
Write-Host "==> Checking for $CertDir\$CertFile..."
$CertPlaceholder = $false
if (-not (Test-Path $CertPath)) {
    Write-Host "==> NOTE: $CertDir\$CertFile not found - building without corporate CA cert." -ForegroundColor Yellow
    $certDirPath = Join-Path $RepoDir $CertDir
    if (-not (Test-Path $certDirPath)) {
        New-Item -ItemType Directory -Force -Path $certDirPath | Out-Null
    }
    New-Item -ItemType File -Force -Path $CertPath | Out-Null
    $CertPlaceholder = $true
} else {
    Write-Host "==> Found $CertDir\$CertFile"
}

# Proxy build args (forwarded if set in environment)
$BuildArgs = New-Object System.Collections.ArrayList
foreach ($var in @("HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy")) {
    $val = [System.Environment]::GetEnvironmentVariable($var)
    if ($val) {
        [void]$BuildArgs.Add("--build-arg")
        [void]$BuildArgs.Add("${var}=${val}")
        Write-Host "==> Forwarding $var to builds"
    }
}

Write-Host "==> Building $($Images.Count) images..."

# Fix Windows CRLF line endings for files that will run inside Linux containers
Write-Host "==> Converting line endings to LF for Linux compatibility..."
$filesToFix = @()
$filesToFix += Get-ChildItem -Path $RepoDir -Recurse -Filter "*.sh"
$filesToFix += Get-ChildItem -Path $RepoDir -Recurse -Filter "*.bash"
$filesToFix += Get-ChildItem -Path $RepoDir -Recurse -Filter "*.zsh"
$filesToFix += Get-ChildItem -Path $RepoDir -Recurse -Filter "Dockerfile"
$filesToFix += Get-ChildItem -Path $RepoDir -Recurse -Filter "*.yml"
$filesToFix += Get-ChildItem -Path $RepoDir -Recurse -Filter "*.yaml"
$filesToFix += Get-ChildItem -Path $RepoDir -Recurse -Filter "*.cfg"
$filesToFix += Get-ChildItem -Path $RepoDir -Recurse -Filter "*.rego"
foreach ($f in $filesToFix) {
    if ($f.PSIsContainer) { continue }
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasCR = $false
    foreach ($b in $bytes) { if ($b -eq 13) { $hasCR = $true; break } }
    if ($hasCR) {
        $content = [System.IO.File]::ReadAllText($f.FullName)
        $content = $content -replace "`r`n", "`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($f.FullName, $content, $utf8NoBom)
        Write-Host "     Fixed: $($f.FullName)" -ForegroundColor DarkGray
    }
}

Write-Host "==> Building $($Images.Count) images..."

foreach ($stage in $Images) {
    $tag = "$Prefix/${stage}:latest"
    $dockerfile = Join-Path $RepoDir (Join-Path $stage "Dockerfile")
    Write-Host ""
    Write-Host "--- Building $tag (context: repo root, dockerfile: $stage\Dockerfile) ---"

    $cmdArgs = New-Object System.Collections.ArrayList
    [void]$cmdArgs.Add("build")
    foreach ($ba in $BuildArgs) { [void]$cmdArgs.Add($ba) }
    [void]$cmdArgs.Add("-f")
    [void]$cmdArgs.Add($dockerfile)
    [void]$cmdArgs.Add("-t")
    [void]$cmdArgs.Add($tag)
    [void]$cmdArgs.Add($RepoDir)

    & docker $cmdArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "==> FAILED to build $tag" -ForegroundColor Red
        if ($CertPlaceholder) { Remove-Item -Force $CertPath }
        exit 1
    }
}

Write-Host ""
Write-Host "==> All images built:"
& docker images --filter "reference=$Prefix/*" --format "table {{.Repository}}`t{{.Tag}}`t{{.Size}}"

# Clean up placeholder cert if we created one
if ($CertPlaceholder) {
    Remove-Item -Force $CertPath
}
