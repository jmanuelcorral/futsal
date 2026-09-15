#Requires -Version 7.2
[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [string]$BlendFile,
    [ValidateRange(10, 300)][int]$StartupTimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    throw 'Run .\tools\mcp\Install-Mcp.ps1 before starting Blender MCP.'
}
$arguments = @('-u', (Join-Path $PSScriptRoot 'start_blender.py'), '--startup-timeout', "$StartupTimeoutSeconds")
if ($SmokeTest) { $arguments += '--smoke-test' }
if ($BlendFile) { $arguments += @('--blend-file', (Resolve-Path -LiteralPath $BlendFile).Path) }
& $python @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Blender MCP launcher failed with exit code $LASTEXITCODE."
}
