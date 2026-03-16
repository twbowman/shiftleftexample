<#
.SYNOPSIS
    Sample deployment script with PSScriptAnalyzer issues.
#>

# PSScriptAnalyzer: PSAvoidUsingPlainTextForPassword
param(
    [string]$ServerName,
    [string]$Password,
    [string]$environment
)

# PSScriptAnalyzer: PSAvoidUsingWriteHost
Write-Host "Deploying to $ServerName..."

# PSScriptAnalyzer: PSAvoidUsingInvokeExpression
$cmd = "Get-Process -Name notepad"
Invoke-Expression $cmd

# PSScriptAnalyzer: PSAvoidUsingConvertToSecureStringWithPlainText
$securePass = ConvertTo-SecureString $Password -AsPlainText -Force

# PSScriptAnalyzer: PSUseDeclaredVarsMoreThanAssignments
$unusedVariable = "this is never used"

# PSScriptAnalyzer: PSAvoidUsingCmdletAliases
$procs = gps
$items = ls C:\temp

# PSScriptAnalyzer: PSUseShouldProcessForStateChangingFunctions
function Remove-OldLogs {
    param([string]$LogPath)
    Get-ChildItem $LogPath -Filter "*.log" |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        Remove-Item -Force
}

# PSScriptAnalyzer: PSProvideCommentHelp
function Get-DeploymentStatus {
    param([string]$Server)
    return "Running"
}

# Clean function for comparison
<#
.SYNOPSIS
    Gets the application version.
.PARAMETER ConfigPath
    Path to the configuration file.
#>
function Get-AppVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    if (Test-Path $ConfigPath) {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
        return $config.version
    }

    return $null
}
