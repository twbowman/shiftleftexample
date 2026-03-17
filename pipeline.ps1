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
    Image tag for stage 1 build (default: <target-name>:latest).
.PARAMETER Prefix
    Image name prefix (e.g. shiftleft -> shiftleft/stage0-code).
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
.PARAMETER ContinueOnFail
    Continue running remaining stages even if one fails (default: stop on first failure).
.PARAMETER DryRun
    Show what would run without executing.
.EXAMPLE
    ./pipeline.ps1
    ./pipeline.ps1 -Target ./myapp -Stage 0-code,0-iac
    ./pipeline.ps1 -Target https://github.com/org/repo.git
    ./pipeline.ps1 -Stage 1,3,9 -Tag myapp:1.0.0 -SkipSign
    ./pipeline.ps1 -Registry jfrog.io/docker-local -Keyless
    ./pipeline.ps1 -Prefix shiftleft -Stage 0-code
    ./pipeline.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [string]$Target = "",
    [string]$Stage = "all",
    [string]$Tag = "",
    [string]$Prefix = "DockerShiftLeft",
    [string]$Registry = "",
    [string]$Output = "./artifacts",
    [switch]$Fix,
    [switch]$Strict,
    [string]$FailOn = "",
    [Alias("NoSign")][switch]$SkipSign,
    [switch]$Keyless,
    [string]$Key = "",
    [Alias("NoVerify")][switch]$SkipVerify,
    [switch]$ContinueOnFail,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Helpers
function Write-Banner {
    param([string]$Text)
    $line = "=" * 60
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor White
    Write-Host $line -ForegroundColor Cyan
}

function Get-StageImage {
    param([string]$Name)
    if ($Prefix) { $Name = "$Prefix/$Name" }
    if ($Registry) { return "$Registry/$Name" }
    return $Name
}

function Test-ShouldRun {
    param([string]$StageName)
    if ($Stage -eq "all") { return $true }
    $list = $Stage.Split(",") | ForEach-Object { $_.Trim() }
    return ($list -contains $StageName)
}

$script:StageResults = @()
$script:ExitCode = 0

function Invoke-Stage {
    param([string]$Name, [string[]]$DockerArgs)

    if ($DryRun) {
        Write-Host "  [dry-run] docker run --rm $($DockerArgs -join ' ')" -ForegroundColor DarkGray
        $script:StageResults += [PSCustomObject]@{ Stage = $Name; Result = "PASS" }
        Write-Host ""
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        return
    }

    Write-Host "  >> $Name" -ForegroundColor White
    $logFile = Join-Path $ArtifactsPath "$Name.log"
    $rc = 0
    try {
        $runArgs = New-Object System.Collections.ArrayList
        [void]$runArgs.Add("run")
        [void]$runArgs.Add("--rm")
        foreach ($a in $DockerArgs) { [void]$runArgs.Add($a) }
        $output = & docker $runArgs 2>&1
        $rc = $LASTEXITCODE
        # Write to console and log file
        $logLines = New-Object System.Collections.ArrayList
        foreach ($line in $output) {
            $text = "$line"
            Write-Host "  $text"
            [void]$logLines.Add($text)
        }
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($logFile, $logLines.ToArray(), $utf8NoBom)
        Write-Host ""
        Write-Host "  Log saved to: $logFile" -ForegroundColor DarkGray
    } catch {
        $rc = 1
    }

    if ($rc -ne 0) {
        $script:StageResults += [PSCustomObject]@{ Stage = $Name; Result = "FAIL" }
        $script:ExitCode = 1
        Write-Host ""
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if (-not $ContinueOnFail) {
            Write-Host ""
            Write-Host "  Aborting pipeline - stage failed. Use -ContinueOnFail to run all stages." -ForegroundColor Red
            Show-Summary
            exit $script:ExitCode
        }
    } else {
        $script:StageResults += [PSCustomObject]@{ Stage = $Name; Result = "PASS" }
        Write-Host ""
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    }
}

# Resolve Target
$ClonedDir = ""
$RepoPath = ""

if (-not $Target) {
    $RepoPath = (Get-Location).Path
} elseif ($Target -match '^(https?://|git@|ssh://|git://)') {
    $ClonedDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pipeline-" + [guid]::NewGuid().ToString())
    Write-Host "  >> Cloning $Target" -ForegroundColor White
    Write-Host "     -> $ClonedDir" -ForegroundColor DarkGray
    try {
        git clone --depth 1 $Target $ClonedDir 2>&1 | ForEach-Object { Write-Host "     $_" }
        if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
        $RepoPath = $ClonedDir
        Write-Host "  [OK] Cloned" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] Git clone failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    $RepoPath = (Resolve-Path $Target).Path
}

# Ensure artifacts dir exists and is absolute
New-Item -ItemType Directory -Force -Path $Output | Out-Null

# Derive tag from target name if not explicitly provided
if (-not $Tag) {
    if ($Target -match '^(https?://|git@|ssh://|git://)') {
        # Extract repo name from URL (strip .git suffix)
        $repoName = ($Target -split '/')[-1] -replace '\.git$', ''
    } else {
        $repoName = Split-Path -Leaf $RepoPath
    }
    $Tag = "${repoName}:latest"
}
$ArtifactsPath = (Resolve-Path $Output).Path

# Cleanup on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    if ($ClonedDir -and (Test-Path $ClonedDir)) {
        Write-Host ""
        Write-Host "  Cleaning up cloned repo: $ClonedDir" -ForegroundColor DarkGray
        Remove-Item -Recurse -Force $ClonedDir
    }
}

# Proxy env flags for docker run
$ProxyEnv = @()
foreach ($var in @("HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy")) {
    $val = [System.Environment]::GetEnvironmentVariable($var)
    if ($val) { $ProxyEnv += @("-e", "${var}=${val}") }
}
if ($ProxyEnv.Count -gt 0) {
    Write-Host "  Proxy: forwarding $([int]($ProxyEnv.Count / 2)) env vars into containers" -ForegroundColor DarkGray
}

# Pipeline Start
$PipelineStart = Get-Date

Write-Banner "Pipeline"
if ($Target) { $targetDisplay = $Target } else { $targetDisplay = (Get-Location).Path }
Write-Host "  Target:    $targetDisplay" -ForegroundColor DarkGray
Write-Host "  Repo:      $RepoPath" -ForegroundColor DarkGray
Write-Host "  Stages:    $Stage" -ForegroundColor DarkGray
Write-Host "  Tag:       $Tag" -ForegroundColor DarkGray
if ($Prefix)   { Write-Host "  Prefix:    $Prefix" -ForegroundColor DarkGray }
Write-Host "  Artifacts: $ArtifactsPath" -ForegroundColor DarkGray
if ($Registry) { Write-Host "  Registry:  $Registry" -ForegroundColor DarkGray }
if ($DryRun)   { Write-Host "  DRY RUN - no containers will execute" -ForegroundColor Yellow }

# Stage 0: Code
if (Test-ShouldRun "0-code") {
    Write-Banner "Stage 0: Code Quality & Security"
    $dockerArgs = @($ProxyEnv) + @("-v", "${RepoPath}:/workspace", (Get-StageImage "stage0-code"), "--path", "/workspace")
    if ($Fix)    { $dockerArgs += "--fix" }
    if ($Strict) { $dockerArgs += "--strict" }
    Invoke-Stage "stage0-code" $dockerArgs
}

# Stage 0: IaC
if (Test-ShouldRun "0-iac") {
    Write-Banner "Stage 0: IaC Linting & Compliance"
    $dockerArgs = @($ProxyEnv) + @("-v", "${RepoPath}:/workspace", (Get-StageImage "stage0-iac"), "--path", "/workspace")
    if ($Fix)    { $dockerArgs += "--fix" }
    if ($Strict) { $dockerArgs += "--strict" }
    Invoke-Stage "stage0-iac" $dockerArgs
}

# Stage 0: PowerShell
if (Test-ShouldRun "0-pwsh") {
    Write-Banner "Stage 0: PowerShell Linting"
    $dockerArgs = @($ProxyEnv) + @("-v", "${RepoPath}:/workspace", (Get-StageImage "stage0-pwsh"), "--path", "/workspace")
    if ($Strict) { $dockerArgs += "--strict" }
    Invoke-Stage "stage0-pwsh" $dockerArgs
}

# Stage 1: Build
if (Test-ShouldRun "1") {
    Write-Banner "Stage 1: Build"
    New-Item -ItemType Directory -Force -Path (Join-Path $ArtifactsPath "stage1") | Out-Null
    $dockerArgs = @($ProxyEnv) + @(
        "-v", "/var/run/docker.sock:/var/run/docker.sock",
        "-v", "${RepoPath}:/workspace",
        "-v", "${ArtifactsPath}:/artifacts",
        (Get-StageImage "stage1-build"),
        "--context", "/workspace", "--tag", $Tag, "--output", "/artifacts/stage1"
    )
    Invoke-Stage "stage1-build" $dockerArgs
}

# Stage 3: SCA
if (Test-ShouldRun "3") {
    Write-Banner "Stage 3: Software Composition Analysis"
    New-Item -ItemType Directory -Force -Path (Join-Path $ArtifactsPath "stage3") | Out-Null
    $dockerArgs = @($ProxyEnv) + @(
        "-v", "/var/run/docker.sock:/var/run/docker.sock",
        "-v", "${RepoPath}:/workspace",
        "-v", "${ArtifactsPath}:/artifacts",
        (Get-StageImage "stage3-sca"),
        "--image", $Tag, "--output", "/artifacts/stage3"
    )
    if ($FailOn) { $dockerArgs += @("--fail-on", $FailOn) }
    Invoke-Stage "stage3-sca" $dockerArgs
}

# Stage 9: SBOM & Sign
if (Test-ShouldRun "9") {
    Write-Banner "Stage 9: SBOM & Signing"
    New-Item -ItemType Directory -Force -Path (Join-Path $ArtifactsPath "stage9") | Out-Null
    $dockerArgs = @($ProxyEnv) + @(
        "-v", "/var/run/docker.sock:/var/run/docker.sock",
        "-v", "${ArtifactsPath}:/artifacts"
    )
    $secretsFile = Join-Path $RepoPath ".secrets"
    if (Test-Path $secretsFile) {
        $dockerArgs += @("-v", "${secretsFile}:/workspace/.secrets:ro")
    }
    $effectiveSkipSign = [bool]$SkipSign
    if ($Key) {
        if (Test-Path $Key) {
            $keyAbs = (Resolve-Path $Key).Path
            $dockerArgs += @("-v", "${keyAbs}:/cosign.key:ro")
        } else {
            Write-Host "  WARNING: Cosign key not found: $Key - skipping signing" -ForegroundColor Yellow
            $effectiveSkipSign = $true
        }
    } elseif (-not $Keyless -and -not $SkipSign) {
        Write-Host "  WARNING: No cosign key or -Keyless specified - skipping signing" -ForegroundColor Yellow
        $effectiveSkipSign = $true
    }
    $dockerArgs += @((Get-StageImage "stage9-sbom"), "--image", $Tag, "--output", "/artifacts/stage9")
    if ($Registry)  { $dockerArgs += @("--registry", $Registry) }
    if ($effectiveSkipSign) { $dockerArgs += "--skip-sign" }
    if ($Keyless)   { $dockerArgs += "--keyless" }
    if ($Key -and (Test-Path $Key)) { $dockerArgs += @("--key", "/cosign.key") }
    Invoke-Stage "stage9-sbom" $dockerArgs
}

# Stage 10: Compliance
if (Test-ShouldRun "10") {
    Write-Banner "Stage 10: Compliance & Policy"
    New-Item -ItemType Directory -Force -Path (Join-Path $ArtifactsPath "stage10") | Out-Null
    $dockerArgs = @($ProxyEnv) + @(
        "-v", "/var/run/docker.sock:/var/run/docker.sock",
        "-v", "${ArtifactsPath}:/artifacts"
    )
    $policiesDir = Join-Path $RepoPath "policies"
    if (Test-Path $policiesDir) {
        $dockerArgs += @("-v", "${policiesDir}:/policies")
    }
    $dockerArgs += @((Get-StageImage "stage10-compliance"), "--artifacts", "/artifacts", "--output", "/artifacts/stage10")
    if ($Tag)        { $dockerArgs += @("--image", $Tag) }
    if ($SkipVerify) { $dockerArgs += "--skip-verify" }
    Invoke-Stage "stage10-compliance" $dockerArgs
}

# Pipeline Summary
function Show-Summary {
    $elapsed = ((Get-Date) - $PipelineStart).TotalSeconds

    Write-Banner "Pipeline Summary"

    $script:StageResults | Format-Table -Property Stage, Result -AutoSize | Out-String | Write-Host

    $passed = @($script:StageResults | Where-Object { $_.Result -eq "PASS" }).Count
    $failed = @($script:StageResults | Where-Object { $_.Result -eq "FAIL" }).Count

    Write-Host "  Passed: $passed | Failed: $failed" -ForegroundColor White
    Write-Host "  Total elapsed: $($elapsed.ToString('F1'))s" -ForegroundColor DarkGray

    if ($script:ExitCode -ne 0) {
        Write-Host ""
        Write-Host "  [FAIL] PIPELINE FAILED" -ForegroundColor Red
    } else {
        Write-Host ""
        Write-Host "  [PASS] PIPELINE PASSED" -ForegroundColor Green
    }
}

Show-Summary

# Cleanup cloned dir
if ($ClonedDir -and (Test-Path $ClonedDir)) {
    Write-Host ""
    Write-Host "  Cleaning up cloned repo: $ClonedDir" -ForegroundColor DarkGray
    Remove-Item -Recurse -Force $ClonedDir
}

exit $script:ExitCode
