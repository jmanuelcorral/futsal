#Requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tools = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $tools 'Common.ps1')
$inventoryPath = Join-Path $tools 'local.json'
$original = [IO.File]::ReadAllBytes($inventoryPath)
$installed = [Text.Encoding]::UTF8.GetString($original).TrimStart([char]0xFEFF) | ConvertFrom-Json
$release = Get-Content -LiteralPath (Join-Path $tools 'release.json') -Raw | ConvertFrom-Json
$runtime = Join-Path $tools 'runtime'
if (Test-Path -LiteralPath (Join-Path $runtime 'test.lock')) {
    throw 'Wait for the running Godot validation before testing installer reuse.'
}
$id = 'installer-reuse-' + [guid]::NewGuid().ToString('N')
$fixture = Join-Path $runtime $id
$backup = Join-Path $fixture 'original-inventory.json'
$reportPath = Join-Path $runtime 'installer-reuse-result.json'
$checks = [Collections.Generic.List[string]]::new()
$shell = (Get-Process -Id $PID).Path
$failure = $null

function Confirm-Check([string]$Name, [bool]$Condition) {
    if (-not $Condition) { throw "Installer regression failed: $Name" }
    $checks.Add($Name)
}

function Invoke-Installer([string]$Stage, [string[]]$Arguments = @(), [System.Collections.IDictionary]$Environment = @{}) {
    return Invoke-GodotProcess -FilePath $shell `
        -Arguments (@('-NoProfile', '-File', (Join-Path $tools 'Install-Godot.ps1')) + $Arguments) `
        -WorkingDirectory $tools -Environment $Environment `
        -LogPrefix (Join-Path $runtime "$id-$Stage") -TimeoutSeconds 300
}

New-Item -ItemType Directory -Path $fixture | Out-Null
[IO.File]::WriteAllBytes($backup, $original)
if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath }
try {
    $aliasDirectory = Join-Path $fixture 'alias con espacios'
    New-Item -ItemType Directory -Path $aliasDirectory | Out-Null
    $aliasPath = Join-Path $aliasDirectory 'godot.exe'
    $wrapper = Join-Path $aliasDirectory 'godot_console.exe'
    Copy-Item -LiteralPath $installed.godotPath -Destination $aliasPath
    Confirm-Check 'no canonical GUI sibling can hide the filename defect' (
        -not (Test-Path -LiteralPath (Join-Path $aliasDirectory $release.editor.executable))
    )

    $null = Invoke-Installer 'explicit' @('-GodotPath', $aliasPath)
    $actual = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    Confirm-Check 'explicit renamed GUI selected' ($actual.godotPath -eq $aliasPath)
    Confirm-Check 'console wrapper matches renamed GUI basename' ($actual.consolePath -eq $wrapper)
    Confirm-Check 'real renamed pair returns official engine version' ($actual.versionOutput -eq $installed.versionOutput)
    $mainHash = (Get-FileHash -LiteralPath $aliasPath -Algorithm SHA512).Hash
    $wrapperHash = (Get-FileHash -LiteralPath $wrapper -Algorithm SHA512).Hash
    Confirm-Check 'renamed GUI retains official bytes' (
        $mainHash -eq (Get-FileHash -LiteralPath $installed.godotPath -Algorithm SHA512).Hash
    )
    Confirm-Check 'renamed wrapper retains official bytes' (
        $wrapperHash -eq (Get-FileHash -LiteralPath $installed.consolePath -Algorithm SHA512).Hash
    )
    $null = Invoke-Installer 'repeat' @('-GodotPath', $aliasPath)
    Confirm-Check 'repeat preserves both verified binaries' (
        $mainHash -eq (Get-FileHash -LiteralPath $aliasPath -Algorithm SHA512).Hash -and
        $wrapperHash -eq (Get-FileHash -LiteralPath $wrapper -Algorithm SHA512).Hash
    )

    # The original bytes are durably backed up before exercising discovery without an inventory.
    Remove-Item -LiteralPath $inventoryPath
    $null = Invoke-Installer 'path' -Environment @{
        LOCALAPPDATA = (Join-Path $fixture 'isolated-local-appdata')
        PATH = $aliasDirectory + [IO.Path]::PathSeparator + $env:PATH
    }
    $discovered = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    Confirm-Check 'PATH discovery selects the renamed official executable' ($discovered.godotPath -eq $aliasPath)
    Confirm-Check 'PATH-discovered pair really executes' (
        $discovered.consolePath -eq $wrapper -and $discovered.versionOutput -eq $installed.versionOutput
    )

    $collisionDirectory = Join-Path $fixture 'unrelated wrapper'
    New-Item -ItemType Directory -Path $collisionDirectory | Out-Null
    $collisionMain = Join-Path $collisionDirectory 'godot.exe'
    $collisionWrapper = Join-Path $collisionDirectory 'godot_console.exe'
    Copy-Item -LiteralPath $installed.godotPath -Destination $collisionMain
    [IO.File]::WriteAllText($collisionWrapper, 'Test-owned unrelated file; never execute or overwrite.')
    $sentinelHash = (Get-FileHash -LiteralPath $collisionWrapper -Algorithm SHA256).Hash
    $refused = $false
    try { $null = Invoke-Installer 'collision' @('-GodotPath', $collisionMain) }
    catch { $refused = $_.ToString().Contains('Existing file differs from the verified release:') }
    Confirm-Check 'unrelated companion is explicitly refused' $refused
    Confirm-Check 'unrelated companion remains byte-identical' (
        (Get-FileHash -LiteralPath $collisionWrapper -Algorithm SHA256).Hash -eq $sentinelHash
    )
    $version = Invoke-GodotProcess -FilePath $installed.consolePath -Arguments @('--version') `
        -WorkingDirectory $tools -LogPrefix (Join-Path $runtime "$id-canonical") -TimeoutSeconds 30
    Confirm-Check 'canonical installation remains executable' ($version.Stdout.Trim() -eq $installed.versionOutput)
}
catch {
    $failure = $_.ToString()
    throw
}
finally {
    [IO.File]::WriteAllBytes($inventoryPath, [IO.File]::ReadAllBytes($backup))
    if ([Convert]::ToHexString([IO.File]::ReadAllBytes($inventoryPath)) -ne [Convert]::ToHexString($original)) {
        throw "Original inventory could not be restored; backup retained at $backup."
    }
    $checks.Add('original machine inventory restored byte-for-byte')
    Remove-Item -LiteralPath $fixture -Recurse
    $summary = [ordered]@{ runId = $id; ok = ($null -eq $failure); passed = $checks.Count; checks = @($checks); failure = $failure }
    $summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding utf8
}
$summary | ConvertTo-Json -Depth 4
