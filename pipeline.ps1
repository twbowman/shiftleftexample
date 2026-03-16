<#
.SYNOPSIS
    Run pipeline stages locally via Docker.
.DESCRIPTION
    Orchestrates all or individual pipeline stages against a target repo.
    Each stage runs in its own container with the repo mounted at /workspace.
.PARAMETER Target
    Local path or git URL to scan (default: current directory).
.PARAMETER Stage
    Comma-separated stages to run (default: all).
    Valid: 0-code, 0-iac, 0-pwsh, 1, 3, 9, 10, all
.PARAMETER Tag
    Image tag for stage 1 build (default: app:latest).
.PARAMETER Registry
    Container registry for images (e.g. jfrog.io/docker-local).
.PARAMETER Output
    Artifacts directory (default: ./artifacts).
.PARAMETER Fix
    Pass --fix to stage 0 scripts.
.PARAMETER Strict
    Treat warnings as errors across all stages.
.PARAMETER FailOn
    Pass --fail-on to stage 3 (e.g. CRITICAL).
.PARAMETER SkipSign
    Skip signing in stage 9.
.PARAMETER Keyless
    Use keyless signing in stage 9.
.PARAMETER Key
    Cosign private key path for stage 9.
.PARAMETER SkipVerify
    Skip signature verification in stage 10.
.PARAMETER DryRun
    Show what would run without executing.
.EXAMPLE
    ./pipeline.ps1
    ./pipeline.ps1 -Target ./myapp -Stage 0-code,0-iac
    ./pipeline.ps1 -Target https://github.com/org/repo.git
    ./pipeline.ps1 -Stage 1,3,9 -Tag myapp:1.0.0 -SkipSign
    ./pipeline.ps1 -Registry jfrog.io/docker-local -Keyless
    ./pipeline.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [string]$Target = "",
    [string]$Stage = "all",
    [string]$Tag = "app:latest",
    [string]$Registry = "",
    [string]$Output = "./artifacts",
    [switch]$Fix,
    [switch]$Strict,
    [string]$FailOn = "",
    [switch]$SkipSign,
    [switch]$Keyless,
    [string]$Key = "",
    [switch]$SkipVerify,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Helpers ──────────────────────────────────────────────────────────────────
function Write-Banner {
    param([string]$Text)
    $line = "═" * 60
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor White
    Write-Host "$line" -ForegroundColor Cyan
}

function Get-StageImage {
    param([string]$Name)
    if ($Registry) { return "$Registry/$Name" }
    return $Name
}

function Test-ShouldRun {
    param([string]$StageName)
    if ($Stage -eq "all") { return $true }
    $list = $Stage.Split(",") | ForEach-Object { $_.Trim() }
    return $list -contains $StageName
}

$script:StageResults = @()
$script:ExitCode = 0

function Invoke-Stage {
    param([string]$Name, [string[]]$DockerArgs)

    if ($DryRun) {
        Write-Host "  [dry-run] docker run --rm $($DockerArgs -join ' ')" -ForegroundColor DarkGray
        $script:StageResults += [PSCustomObject]@{ Stage = $Name; Result = "PASS" }
        Write-Host "`n  ✓ $Name PASSED" -ForegroundColor Green
        return
    }

    Write-Host "  ▶  $Name" -ForegroundColor White
    $rc = 0
    try {
        & docker run --rm @DockerArgs 2>&1 | ForEach-Object { Write-Host "  $_" }
        $rc = $LASTEXITCODE
    } catch {
        $rc = 1
    }

    if ($rc -ne 0) {
        $script:StageResults += [PSCustomObject]@{ Stage = $Name; Result = "FAIL" }
        $script:ExitCode = 1
        Write-Host "`n  ✗ $Name FAILED" -ForegroundColor Red
    } else {
        $script:StageResults += [PSCustomObject]@{ Stage = $Name; Result = "PASS" }
        Write-Host "`n  ✓ $Name PASSED" -ForegroundColor Green
    }
}

# ── Resolve Target ───────────────────────────────────────────────────────────
$ClonedDir = ""
$RepoPath = ""

if (-not $Target) {
    $RepoPath = (Get-Location).Path
} elseif ($Target -match '^(https?://|git@|ssh://|git://)') {
    # Git URL — clone to temp dir
    $ClonedDir = Join-Path ([System.IO.Path]::GetTempPath()) "pipeline-$(New-Guid)"
    Write-Host "  ▶  Cloning $Target" -ForegroundColor White
    Write-Host "     → $ClonedDir" -ForegroundColor DarkGray
    try {
        git clone --depth 1 $Target $ClonedDir 2>&1 | ForEach-Object { Write-Host "     $_" }
        if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
        $RepoPath = $ClonedDir
        Write-Host "  ✓  Cloned" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Git clone failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    $RepoPath = (Resolve-Path $Target).Path
}

# Ensure artifacts dir exists and is absolute
New-Item -ItemType Directory -Force -Path $Output | Out-Null
$ArtifactsPath = (Resolve-Path $Output).Path

# Cleanup on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    if ($ClonedDir -and (Test-Path $ClonedDir)) {
        Write-Host "`n  Cleaning up cloned repo: $ClonedDir" -ForegroundColor DarkGray
        Remove-Item -Recurse -Force $ClonedDir
    }
}

# ── Pipeline Start ───────────────────────────────────────────────────────────
$PipelineStart = Get-Date

Write-Banner "Pipeline"
Write-Host "  Target:    $($Target ? $Target : (Get-Location).Path)" -ForegroundColor DarkGray
Write-Host "  Repo:      $RepoPath" -ForegroundColor DarkGray
Write-Host "  Stages:    $Stage" -ForegroundColor DarkGray
Write-Host "  Tag:       $Tag" -ForegroundColor DarkGray
Write-Host "  Artifacts: $ArtifactsPath" -ForegroundColor DarkGray
if ($Registry) { Write-Host "  Registry:  $Registry" -ForegroundColor DarkGray }
if ($DryRun)   { Write-Host "  DRY RUN — no containers will execute" -ForegroundColor Yellow }

# ── Stage 0: Code ────────────────────────────────────────────────────────────
if (Test-ShouldRun "0-code") {
    Write-Banner "Stage 0: Code Quality & Security"
    $args = @("-v", "${RepoPath}:/workspace", (Get-StageImage "stage0-code"), "--path", "/workspace")
    if ($Fix)    { $args += "--fix" }
    if ($Strict) { $args += "--strict" }
    Invoke-Stage "stage0-code" $args
}

# ── Stage 0: IaC ─────────────────────────────────────────────────────────────
if (Test-ShouldRun "0-iac") {
    Write-Banner "Stage 0: IaC Linting & Compliance"
    $args = @("-v", "${RepoPath}:/workspace", (Get-StageImage "stage0-iac"), "--path", "/workspace")
    if ($Fix)    { $args += "--fix" }
    if ($Strict) { $args += "--strict" }
    Invoke-Stage "stage0-iac" $args
}

# ── Stage 0: PowerShell ──────────────────────────────────────────────────────
if (Test-ShouldRun "0-pwsh") {
    Write-Banner "Stage 0: PowerShell Linting"
    $args = @("-v", "${RepoPath}:/workspace", (Get-StageImage "stage0-pwsh"), "--path", "/workspace")
    if ($Strict) { $args += "--strict" }
    Invoke-Stage "stage0-pwsh" $args
}

# ── Stage 1: Build ───────────────────────────────────────────────────────────
if (Test-ShouldRun "1") {
    Write-Banner "Stage 1: Build"
    New-Item -ItemType Directory -Force -Path "$ArtifactsPath/stage1" | Out-Null
    $args = @(
        "-v", "/var/run/docker.sock:/var/run/docker.sock",
        "-v", "${RepoPath}:/workspace",
        "-v", "${ArtifactsPath}:/artifacts",
        (Get-StageImage "stage1-build"),
        "--context", "/workspace", "--tag", $Tag, "--output", "/artifacts/stage1"
    )
    Invoke-Stage "stage1-build" $args
}

# ── Stage 3: SCA ─────────────────────────────────────────────────────────────
if (Test-ShouldRun "3") {
    Write-Banner "Stage 3: Software Composition Analysis"
    New-Item -ItemType Directory -Force -Path "$ArtifactsPath/stage3" | Out-Null
    $args = @(
        "-v", "/var/run/docker.sock:/var/run/docker.sock",
        "-v", "${RepoPath}:/workspace",
        "-v", "${ArtifactsPath}:/artifacts",
        (Get-StageImage "stage3-sca"),
        "--image", $Tag, "--output", "/artifacts/stage3"
    )
    if ($FailOn) { $args += @("--fail-on", $FailOn) }
    Invoke-Stage "stage3-sca" $args
}

# ── Stage 9: SBOM & Sign ─────────────────────────────────────────────────────
if (Test-ShouldRun "9") {
    Write-Banner "Stage 9: SBOM & Signing"
    New-Item -ItemType Directory -Force -Path "$ArtifactsPath/stage9" | Out-Null
    $args = @(
        "-v", "/var/run/docker.sock:/var/run/docker.sock",
        "-v", "${ArtifactsPath}:/artifacts"
    )
    # Mount secrets file if present
    $secretsFile = Join-Path $RepoPath ".secrets"
    if (Test-Path $secretsFile) {
        $args += @("-v", "${secretsFile}:/workspace/.secrets:ro")
    }
    # Mount cosign key if specified
    if ($Key) {
        $keyAbs = (Resolve-Path $Key).Path
        $args += @("-v", "${keyAbs}:/cosign.key:ro")
    }
    $args += @((Get-StageImage "stage9-sbom"), "--image", $Tag, "--output", "/artifacts/stage9")
    if ($Registry)  { $args += @("--registry", $Registry) }
    if ($SkipSign)  { $args += "--skip-sign" }
    if ($Keyless)   { $args += "--keyless" }
    if ($Key)       { $args += @("--key", "/cosign.key") }
    Invoke-Stage "stage9-sbom" $args
}

# ── Stage 10: Compliance ─────────────────────────────────────────────────────
if (Test-ShouldRun "10") {
    Write-Banner "Stage 10: Compliance & Policy"
    New-Item -ItemType Directory -Force -Path "$ArtifactsPath/stage10" | Out-Null
    $args = @(
        "-v", "/var/run/docker.sock:/var/run/docker.sock",
        "-v", "${ArtifactsPath}:/artifacts"
    )
    $policiesDir = Join-Path $RepoPath "policies"
    if (Test-Path $policiesDir) {
        $args += @("-v", "${policiesDir}:/policies")
    }
    $args += @((Get-StageImage "stage10-compliance"), "--artifacts", "/artifacts", "--output", "/artifacts/stage10")
    if ($Tag)        { $args += @("--image", $Tag) }
    if ($SkipVerify) { $args += "--skip-verify" }
    Invoke-Stage "stage10-compliance" $args
}

# ── Pipeline Summary ─────────────────────────────────────────────────────────
$elapsed = ((Get-Date) - $PipelineStart).TotalSeconds

Write-Banner "Pipeline Summary"

$script:StageResults | Format-Table -Property Stage, Result -AutoSize | Out-String | Write-Host

$passed = @($script:StageResults | Where-Object { $_.Result -eq "PASS" }).Count
$failed = @($script:StageResults | Where-Object { $_.Result -eq "FAIL" }).Count

Write-Host "  Passed: $passed | Failed: $failed" -ForegroundColor White
Write-Host "  Total elapsed: $($elapsed.ToString('F1'))s" -ForegroundColor DarkGray

if ($script:ExitCode -ne 0) {
    Write-Host "`n  ✗ PIPELINE FAILED" -ForegroundColor Red
} else {
    Write-Host "`n  ✓ PIPELINE PASSED" -ForegroundColor Green
}

# Cleanup cloned dir
if ($ClonedDir -and (Test-Path $ClonedDir)) {
    Write-Host "`n  Cleaning up cloned repo: $ClonedDir" -ForegroundColor DarkGray
    Remove-Item -Recurse -Force $ClonedDir
}

exit $script:ExitCode
