#Requires -Version 7.2
[CmdletBinding()]
param([string]$EvidenceDirectory = (Join-Path $PSScriptRoot '..\..\..\.validation\hicks-player-control'))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Common.ps1')
. (Join-Path $PSScriptRoot '..\MicroSliceValidation.ps1')
$directory = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$local = Get-GodotInstallation
$checks = [Collections.Generic.List[object]]::new()
$reports = [ordered]@{}
$hashes = [ordered]@{}
$smoke = $null
$previewSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\..\game\tests\test_match_preview_integration.gd') -Raw

function Check-Archive([string]$Name, [scriptblock]$Action) {
    try {
        & $Action | Out-Null
        $checks.Add([ordered]@{name = $Name; passed = $true})
    }
    catch {
        $checks.Add([ordered]@{name = $Name; passed = $false; error = $_.Exception.Message})
    }
}

$producers = [ordered]@{
    'test_match_preview_integration' = (Get-GodotNativeReportPrefix $previewSource)
    'test_match_player_control' = 'FUTSAL_PLAYER_CONTROL_TESTS'
    'match-smoke' = 'FUTSAL_MATCH_SMOKE'
}
foreach ($stem in $producers.Keys) {
    foreach ($extension in @('json', 'log')) {
        $path = Join-Path $directory "$stem.$extension"
        $hashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    $reportPath = Join-Path $directory "$stem.json"
    $fromFile = Get-Content -LiteralPath $reportPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable -Depth 64
    $reports[$stem] = [ordered]@{declaredPassed = $fromFile['passed']; declaredTotal = $fromFile['total']; accepted = $false}
    $result = [pscustomobject]@{
        Stdout = [IO.File]::ReadAllText((Join-Path $directory "$stem.log"))
        Stderr = ''; ExitCode = 0; ProcessId = 0; RuntimeProcessIds = @()
    }
    if ($stem -eq 'match-smoke') { $smoke = $fromFile }
    Check-Archive "$stem original JSON/log production reader" {
        $warnings = if ($stem -eq 'test_match_preview_integration') { Get-DevelopmentIntegrationExpectedWarnings } else { @{} }
        Assert-GodotOutput $result -ExpectedDevelopmentWarnings $warnings
        if ($stem -eq 'match-smoke') {
            # Historical context tests the reader, never live PID ownership, freshness or native exit.
            $result.ProcessId = $fromFile['process_id']
            $result.RuntimeProcessIds = @($fromFile['process_id'])
            $historicalStart = [DateTime]::SpecifyKind([DateTime]$fromFile['timestamp_utc'], [DateTimeKind]::Utc)
            $null = Read-GodotGameReport -Result $result -ReportPath $reportPath -StartedAt $historicalStart `
                -EditorBinary $true -Headless $true -Executable $local.godotPath -ProjectVersion '0.3.0-preview' -InputSchemaVersion 2
        }
        else {
            $parsed = ConvertFrom-GodotStructuredReport $result $producers[$stem]
            if (($parsed | ConvertTo-Json -Compress -Depth 64) -cne ($fromFile | ConvertTo-Json -Compress -Depth 64)) {
                throw 'Original JSON and raw native log disagree.'
            }
            if ($stem -eq 'test_match_preview_integration') { Assert-PreviewIntegrationReport $parsed }
            else { Assert-GodotPlayerControlReport $parsed -ProjectVersion '0.3.0-preview' -InputSchemaVersion 2 }
        }
        $reports[$stem]['accepted'] = $true
    }
}
Check-Archive 'original smoke untouched-default subcontract only' { Assert-GodotDefaultEntrypoint $smoke }
Check-Archive 'original smoke mode and AI subcontract only' { Assert-GodotPreviewTransitions $smoke }
Check-Archive 'original smoke six focus behaviors subcontract only' { Assert-GodotFocusChangesReport $smoke }
Check-Archive 'all original producer JSON and logs remain byte-identical' {
    foreach ($path in $hashes.Keys) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $hashes[$path]) {
            throw "Original evidence changed during read-only replay: $path"
        }
    }
}
$duplicates = @($smoke['checks'] | Group-Object -Property { $_['name'] } |
    Where-Object Count -gt 1 | ForEach-Object { [ordered]@{name = $_.Name; count = $_.Count} })
$failed = @($checks | Where-Object { -not $_['passed'] }).Count
$summary = [ordered]@{
    scope = 'offline archived producer-report consumers; NOT a new native run or source/export/GPU acceptance'
    ok = $failed -eq 0; passed = $checks.Count - $failed; total = $checks.Count
    checks = $checks.ToArray(); evidenceDirectory = $directory; reports = $reports
    smokeDuplicateCheckNames = $duplicates; originalSha256 = $hashes
    nativeExitObserved = $false; recordedNativeExitCode = 0; liveProcessOwnershipObserved = $false
    runtimeValidated = $false; gpuValidated = $false
}
Write-Output ('FUTSAL_ARCHIVED_REPORT_CONSUMERS ' + ($summary | ConvertTo-Json -Compress -Depth 32))
exit $(if ($failed -eq 0) { 0 } else { 1 })
