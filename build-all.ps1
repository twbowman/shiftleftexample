<#
.SYNOPSIS
    Build all pipeline stage Docker images locally.
.DESCRIPTION
    Builds all stage images using each stage directory as the build context.
    Each stage is expected to have its own certs/ directory with the corporate CA cert.
    Forwards proxy environment variables as build args if set.
.PARAMETER Prefix
    Image name prefix (default: DockerShiftLeft). Images are tagged as prefix/stage:latest.
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

$Images = @(
    "stage0-code",
    "stage0-iac",
    "stage0-pwsh",
    "stage1-build",
    "stage3-sca",
    "stage9-sbom",
    "stage10-compliance"
)

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
    $stageDir = Join-Path $RepoDir $stage

    Write-Host ""
    Write-Host "--- Building $tag (context: $stage/) ---"

    $cmdArgs = New-Object System.Collections.ArrayList
    [void]$cmdArgs.Add("build")
    foreach ($ba in $BuildArgs) { [void]$cmdArgs.Add($ba) }
    [void]$cmdArgs.Add("-t")
    [void]$cmdArgs.Add($tag)
    [void]$cmdArgs.Add($stageDir)

    & docker $cmdArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "==> FAILED to build $tag" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "==> All images built:"
& docker images --filter "reference=$Prefix/*" --format "table {{.Repository}}`t{{.Tag}}`t{{.Size}}"
