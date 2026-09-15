#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$uv = Get-Command uv -ErrorAction Stop
$environment = Get-ToolingEnvironment $root
$blenderLocal = Join-Path $root 'tools\blender\local.json'
if (-not (Test-Path -LiteralPath $blenderLocal -PathType Leaf)) {
    throw 'Run .\tools\blender\Install-Blender.ps1 first.'
}
$blender = Get-Content -LiteralPath $blenderLocal -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $blender.blenderPath -PathType Leaf)) {
    throw 'Saved Blender executable is missing; rerun Install-Blender.ps1 with an explicit path.'
}
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'uv.lock') -PathType Leaf)) {
    throw 'Missing reviewed uv.lock. Do not resolve or upgrade dependencies silently.'
}
$result = Invoke-CheckedTool -FilePath $uv.Source -WorkingDirectory $root -Environment $environment `
    -Arguments @('sync', '--project', $PSScriptRoot, '--locked', '--no-build', '--python', '3.12.13') `
    -TimeoutSeconds 900
Write-Host $result.Stderr.Trim()
$python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
$result = Invoke-CheckedTool -FilePath $python -WorkingDirectory $root -Environment $environment `
    -Arguments @((Join-Path $PSScriptRoot 'verify_package.py')) -TimeoutSeconds 30
$package = $result.Stdout | ConvertFrom-Json
Write-Host $result.Stdout.Trim()
$configure = Join-Path $root 'tools\blender\configure_blender.py'
foreach ($mode in @('install', 'verify')) {
    $result = Invoke-CheckedTool -FilePath $blender.blenderPath -WorkingDirectory $root -Environment $environment `
        -Arguments @('--background', '--disable-autoexec', '--python-exit-code', '1', '--python', $configure, '--', $mode) `
        -TimeoutSeconds 120
    Write-Host $result.Stdout.Trim()
}
$addon = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime\addon-install.json') -Raw | ConvertFrom-Json
$local = [ordered]@{
    pythonPath = $python
    pythonVersion = '3.12.13'
    uvPath = $uv.Source
    packageVersion = $package.version
    mcpSdkVersion = $package.mcpSdkVersion
    upstreamCommit = $package.upstreamCommit
    addonPath = $addon.addonPath
    addonSha256 = $addon.addonSha256
    verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
}
$local | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'local.json') -Encoding utf8
$copilotConfig = & (Join-Path $PSScriptRoot 'New-CopilotConfig.ps1')
Write-Host "Copilot session configuration: $copilotConfig"
Write-Host 'Pinned MCP environment, saved Blender addon preferences and actual GLB export verified.'
