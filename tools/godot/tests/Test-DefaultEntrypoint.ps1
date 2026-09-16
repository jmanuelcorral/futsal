#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Common.ps1')
$local = Get-GodotInstallation
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$project = Join-Path $root 'game'
$runPath = Join-Path $PSScriptRoot ('..\runtime\default-entrypoint-guards-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runPath -Force | Out-Null
$runPath = (Resolve-Path -LiteralPath $runPath).Path
$cases = [ordered]@{
    'micro-default' = 'default host auto-started PLAYING before any driver setup'
    'not-started' = 'default host auto-started PLAYING before any driver setup'
    'no-ticks' = 'untouched default advances ticks, clock and human commands'
    'input-repaired-on-restart' = 'default keyboard D moved authoritative human'
}
$checks = [Collections.Generic.List[object]]::new()
$reports = [ordered]@{}
foreach ($case in $cases.Keys) {
    $path = Join-Path $runPath "$case.json"
    $prefix = Join-Path $runPath $case
    $started = [DateTime]::UtcNow
    $expectedExit = $false
    $failedResult = $null
    try {
        $null = Invoke-GodotProcess -FilePath $local.consolePath -Arguments @(
            '--headless', '--path', $project, '--audio-driver', 'Dummy', '--fixed-fps', '60',
            '--script', (Join-Path $PSScriptRoot 'test_default_entrypoint.gd'), '--',
            '--smoke-test', "--entrypoint-negative=$case", "--report-path=$path"
        ) -WorkingDirectory $project -LogPrefix $prefix -TimeoutSeconds 20 -ExpectedChildExecutable $local.godotPath
    }
    catch {
        if ($_.ToString() -notmatch 'exited 1\.') { throw }
        $expectedExit = $true
        $failedResult = $_.Exception.Data['GodotProcessResult']
    }
    if (-not $expectedExit) { throw "Default-entrypoint guard did not reject $case with exit 1." }
    $output = [pscustomobject]@{
        Stdout = Get-Content -LiteralPath "$prefix.stdout.log" -Raw
        Stderr = Get-Content -LiteralPath "$prefix.stderr.log" -Raw
        ExitCode = 0
    }
    # Exit 1 was required above; engine/script errors remain forbidden in a negative fixture.
    Assert-GodotOutput $output
    $lines = @($output.Stdout -split '\r?\n' | Where-Object { $_.StartsWith('FUTSAL_MATCH_SMOKE ') })
    if ($lines.Count -ne 1 -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path).LastWriteTimeUtc -lt $started) { throw "No fresh negative report for $case." }
    $report = $lines[0].Substring('FUTSAL_MATCH_SMOKE '.Length) | ConvertFrom-Json -AsHashtable -Depth 32
    $disk = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    if (($disk | ConvertTo-Json -Compress -Depth 32) -cne ($report | ConvertTo-Json -Compress -Depth 32) -or
        $report['ok'] -isnot [bool] -or $report['ok'] -or $report['driver_start_calls'] -ne 0 -or
        $report['main_scene'] -ne 'res://match/match.tscn' -or
        $report['scope'] -ne 'playable-preview-runtime-smoke' -or $report['project_version'] -ne '0.5.0-preview' -or
        ($report['input_schema_version'] -isnot [long] -and $report['input_schema_version'] -isnot [int]) -or
        $report['input_schema_version'] -ne 3 -or
        $report['default_entrypoint']['verified'] -ne $false -or
        @($report['failures'] | Where-Object { $_['name'] -eq $cases[$case] -and $_['passed'] -eq $false }).Count -ne 1) {
        throw "The $case fixture did not fail at its intended default-entry guard before any driver start."
    }
    if (-not (Test-GodotReportedProcess $failedResult $report['process_id'])) {
        throw 'The negative fixture PID has no observed original-handle runtime completion.'
    }
    if ($case -ceq 'no-ticks') {
        $before = $report['default_entrypoint']['before']
        $after = $report['default_entrypoint']['after_wait']
        if ($before['phase'] -cne 'PLAYING' -or $after['phase'] -cne 'PLAYING' -or
            $after['tick'] -ne $before['tick'] -or
            $after['seconds_remaining'] -ne $before['seconds_remaining'] -or
            $after['human_sequence'] -ne $before['human_sequence'] -or
            $report['command_rejections'] -isnot [array] -or $report['command_rejections'].Count -ne 0 -or
            $report['integration_errors'] -isnot [array] -or $report['integration_errors'].Count -ne 0) {
            throw 'The no-ticks fixture must isolate stalled progression, not introduce command or integration errors.'
        }
        $checks.Add([ordered]@{ name = 'no-ticks isolates a stalled authority and sampler without hiding errors'; passed = $true })
    }
    $checks.Add([ordered]@{ name = "$case is rejected before all driver starts"; passed = $true })
    $reports[$case] = [ordered]@{
        path = $path; expectedExit = 1; driverStartCalls = 0
        runtimeProcessIds = $failedResult.RuntimeProcessIds; exitWitnesses = $failedResult.ExitWitnesses
    }
}
$result = [ordered]@{
    ok = $true; passed = $checks.Count; total = $checks.Count; checks = $checks.ToArray()
    scope = 'negative in-process default-entrypoint fixtures; NOT source/export gameplay acceptance'
    reports = $reports; runPath = $runPath
}
$result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $runPath 'result.json') -Encoding utf8
Write-Output ('FUTSAL_ENTRYPOINT_GUARD_TESTS ' + ($result | ConvertTo-Json -Compress -Depth 16))
