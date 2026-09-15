#Requires -Version 7.2
[CmdletBinding()]
param(
    [switch]$RunGame,
    [switch]$Diagnostic,
    [switch]$AllowKnownVulkanLayerWarning,
    [ValidateRange(-1, 32)][int]$GpuIndex = -1
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')
$local = Get-GodotInstallation
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
$runtime = Join-Path $PSScriptRoot 'runtime'
$session = 'session-' + [guid]::NewGuid().ToString('N')
$arguments = @('--path', $project, '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan')
if ($Diagnostic) {
    $arguments += 'res://bootstrap/bootstrap.tscn'
}
elseif (-not $RunGame) {
    $arguments += '--editor'
}
else {
    $settings = Get-Content -LiteralPath (Join-Path $project 'project.godot') -Raw
    Assert-GodotProjectConfiguration $settings
}
if ($GpuIndex -ge 0) { $arguments += @('--gpu-index', [string]$GpuIndex) }
$arguments += @('--log-file', (Join-Path $runtime "$session.engine.log"))
$mode = if ($Diagnostic) { 'diagnóstico técnico independiente' } elseif ($RunGame) { 'Laboratorio 5v5 · preview experimental' } else { 'editor' }
Write-Host "Godot $($local.versionOutput) | $mode"
Write-Host "Project: $project"
Write-Host 'Attached process: close its window or press Ctrl+C to stop only this launch.'
$result = Invoke-GodotProcess -FilePath $local.consolePath -Arguments $arguments `
    -WorkingDirectory $project -LogPrefix (Join-Path $runtime $session) -TimeoutSeconds 0
Assert-GodotOutput $result -AllowKnownVulkanLayerWarning:$AllowKnownVulkanLayerWarning
