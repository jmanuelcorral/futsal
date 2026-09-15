#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$localPath = Join-Path $PSScriptRoot 'local.json'
if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
    throw 'Run .\tools\mcp\Install-Mcp.ps1 first.'
}
$local = Get-Content -LiteralPath $localPath -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $local.pythonPath -PathType Leaf)) {
    throw 'The saved MCP interpreter is missing. Rerun Install-Mcp.ps1 after moving the checkout.'
}
$project = Get-Content -LiteralPath (Join-Path $root '.mcp.json') -Raw | ConvertFrom-Json -AsHashtable
if (-not $project.mcpServers.Contains('blender')) {
    throw 'The shared .mcp.json is missing its reviewed blender entry.'
}
$configPath = Join-Path $PSScriptRoot 'copilot.local.json'
$config = if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -AsHashtable
} else {
    @{ mcpServers = @{} }
}
if (-not $config.Contains('mcpServers')) { $config.mcpServers = @{} }
$server = $project.mcpServers.blender
$server.command = $local.pythonPath
$server.args = @('-u', (Join-Path $PSScriptRoot 'server.py'))
$config.mcpServers.blender = $server
$config | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $configPath -Encoding utf8
Write-Output $configPath
