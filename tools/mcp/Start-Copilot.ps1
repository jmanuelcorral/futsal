#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CopilotArguments = @()
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$configPath = & (Join-Path $PSScriptRoot 'New-CopilotConfig.ps1')
$copilot = Get-Command copilot -ErrorAction Stop
Push-Location -LiteralPath $root
try {
    & $copilot.Source --additional-mcp-config "@$configPath" @CopilotArguments
    $result = $LASTEXITCODE
}
finally {
    Pop-Location
}
if ($result -ne 0) { throw "Copilot exited with code $result." }
