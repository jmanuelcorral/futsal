#Requires -Version 7.2
[CmdletBinding()]
param(
    [switch]$ExistingSession,
    [ValidateRange(10, 300)][int]$StartupTimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'Run .\tools\mcp\Install-Mcp.ps1 first.'
}
if ($ExistingSession) {
    $arguments = @('-u', (Join-Path $PSScriptRoot 'smoke_test.py'))
    $timeout = 150
} else {
    $arguments = @('-u', (Join-Path $PSScriptRoot 'start_blender.py'), '--smoke-test',
        '--startup-timeout', "$StartupTimeoutSeconds")
    $timeout = $StartupTimeoutSeconds + 150
}
$result = Invoke-CheckedTool -FilePath $python -Arguments $arguments -WorkingDirectory $root `
    -Environment (Get-ToolingEnvironment $root) -TimeoutSeconds $timeout
Write-Output $result.Stdout.Trim()
if ($result.Stderr.Trim()) { Write-Host $result.Stderr.Trim() }
