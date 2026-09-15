#Requires -Version 7.2
[CmdletBinding()]
param([switch]$TraceTimings)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot '..\Common.ps1')
. (Join-Path $PSScriptRoot '..\MicroSliceValidation.ps1')
. (Join-Path $PSScriptRoot '..\GameplayValidation.ps1')
. (Join-Path $PSScriptRoot 'GameplayRuntimeFixtures.ps1')
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$directory = Join-Path $root ('tools\godot\runtime\gameplay-runtime-helper-' + [guid]::NewGuid().ToString('N'))
$scratch = Join-Path $directory 'fixtures'
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$checks = [Collections.Generic.List[object]]::new()
$complete = $false
$failure = $null
$shell = [Environment]::ProcessPath
$fixtures = @{}
$clock = [Diagnostics.Stopwatch]::StartNew()
$lastCheckMilliseconds = 0L
$runtimeTraceSpans = @{}

function Add-RuntimeFixtureTiming([string]$Phase, [long]$Started) {
    $milliseconds = ([Diagnostics.Stopwatch]::GetTimestamp() - $Started) * 1000.0 / [Diagnostics.Stopwatch]::Frequency
    if (-not $runtimeTraceSpans.Contains($Phase)) {
        $runtimeTraceSpans[$Phase] = @{calls = 0; milliseconds = 0.0; maximumMilliseconds = 0.0}
    }
    $span = $runtimeTraceSpans[$Phase]
    $span.calls++
    $span.milliseconds += $milliseconds
    $span.maximumMilliseconds = [Math]::Max($span.maximumMilliseconds, $milliseconds)
}

function Get-RuntimeFixtureTimingSummary {
    return @($runtimeTraceSpans.GetEnumerator() | Sort-Object Name | ForEach-Object {
        [ordered]@{
            phase = $_.Key; calls = $_.Value.calls
            milliseconds = [Math]::Round($_.Value.milliseconds, 3)
            maximumMilliseconds = [Math]::Round($_.Value.maximumMilliseconds, 3)
        }
    })
}

function Check([string]$Name, [bool]$Passed) {
    $checks.Add([ordered]@{name = $Name; passed = $Passed})
    if ($TraceTimings) {
        $elapsed = $clock.ElapsedMilliseconds
        Write-Host ("FIXTURE_TIMING {0} {1}ms +{2}ms {3}" -f $checks.Count, $elapsed,
            ($elapsed - $script:lastCheckMilliseconds), $Name)
        $script:lastCheckMilliseconds = $elapsed
        if ($checks.Count % 25 -eq 0) {
            Write-Host ('RUNTIME_FIXTURE_PROFILE ' + ((Get-RuntimeFixtureTimingSummary) | ConvertTo-Json -Compress -Depth 5))
        }
    }
    if (-not $Passed) { throw "FAIL $Name" }
}

function Rejected([string]$Name, [scriptblock]$Action, [string]$Because = '') {
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        $cause = $_.Exception
        while ($null -ne $cause.InnerException) { $cause = $cause.InnerException }
        if ($cause -is [IO.IOException]) { throw }
        if ($Because -and -not $_.Exception.Message.Contains($Because, [StringComparison]::Ordinal)) { throw }
        $rejected = $true
    }
    Check $Name $rejected
}

function Read-Fixture($Fixture, $Result = $null) {
    if ($null -eq $Result) { $Result = $Fixture.result }
    if ($TraceTimings) { $runtimeDecodeStarted = [Diagnostics.Stopwatch]::GetTimestamp() }
    try {
        return Read-GodotGameplayRuntimeReport -Result $Result -ReportPath $Fixture.path -StartedAt $Fixture.started `
            -Executable $shell -Headless $Fixture.report['headless'] -EditorBinary $Fixture.report['editor_binary'] `
            -CaptureDirectory $Fixture.report['gameplay']['capture_directory']
    }
    finally { if ($TraceTimings) { Add-RuntimeFixtureTiming 'decode' $runtimeDecodeStarted } }
}

function Copy-Result($Original) {
    $result = [pscustomobject]@{}
    foreach ($property in $Original.PSObject.Properties) { $result | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
    return $result
}

function Reject-Report([string]$Name, [scriptblock]$Mutate, [string]$FixtureName = 'source-headless') {
    $fixture = $fixtures[$FixtureName]
    if ($TraceTimings) { $runtimePrepareStarted = [Diagnostics.Stopwatch]::GetTimestamp() }
    try {
        # Immutable serialized fixture seeds, not cached validation results. Decode
        # fresh objects for every mutation with the original CopyFixture depth/types.
        $report = $fixture.reportSeed | ConvertFrom-Json -AsHashtable -Depth 32
        $manifest = $fixture.manifestSeed | ConvertFrom-Json -AsHashtable -Depth 32
        $result = Copy-Result $fixture.result
        & $Mutate $report $manifest $result | Out-Null
        $serializedReport = $report | ConvertTo-Json -Depth 64 -Compress
        [IO.File]::WriteAllText($fixture.path, $serializedReport, [Text.UTF8Encoding]::new($false))
        Write-GpFixtureJson $fixture.report['gameplay']['capture_manifest_path'] $manifest
        $result.Stdout = Get-GpFixtureStdout $report $serializedReport
    }
    finally { if ($TraceTimings) { Add-RuntimeFixtureTiming 'prepare-mutation' $runtimePrepareStarted } }
    Rejected $Name { Read-Fixture $fixture $result }
    if ($TraceTimings) { $runtimeRestoreStarted = [Diagnostics.Stopwatch]::GetTimestamp() }
    try {
        [IO.File]::WriteAllText($fixture.path, $fixture.restoreReport, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($fixture.report['gameplay']['capture_manifest_path'],
            $fixture.restoreManifest, [Text.UTF8Encoding]::new($false))
    }
    finally { if ($TraceTimings) { Add-RuntimeFixtureTiming 'restore-mutation' $runtimeRestoreStarted } }
}

function Reject-Case([string]$Name, [string]$Id, [scriptblock]$Mutate, [string]$Because = '') {
    $case = CopyFixture @($fixtures['source-headless'].report['gameplay']['cases'] | Where-Object { $_['case'] -ceq $Id })[0]
    & $Mutate $case | Out-Null
    Rejected $Name { Assert-GpCase $case $policy[$Id] '/root/Match' } $Because
}

function Reject-Output([string]$Name, [scriptblock]$Mutate) {
    $fixture = $fixtures['source-headless']
    $result = Copy-Result $fixture.result
    & $Mutate $result | Out-Null
    Rejected $Name { Read-Fixture $fixture $result }
}

try {
    Check 'actual runtime decoder is visible without executing a helper or a native stage' (
        $null -ne (Get-Command Read-GodotGameplayRuntimeReport -ErrorAction SilentlyContinue))
    $policy = Get-GodotGameplayCasePolicy
    Check 'runtime scenarios are exactly twenty-eight with twenty captured moments, not sixty-four fabricated G flags' (
        $policy.Count -eq 28 -and @($policy.Values | Where-Object { $_.capture }).Count -eq 20)
    $installation = @{consolePath = Join-Path $scratch 'engine console.exe'; godotPath = Join-Path $scratch 'engine.exe'}
    $project = Join-Path $scratch 'game project'
    $artifact = Join-Path $scratch 'standalone\game.exe'
    $stageNames = @('source-headless', 'source-rendered', 'artifact-headless', 'artifact-rendered')
    foreach ($stage in $stageNames) {
        $paths = Get-GodotGameplayEvidencePaths $directory $stage
        $invocation = Get-GodotGameplayInvocation $paths $stage $installation $project $artifact
        $args = $invocation.Arguments
        Check "$stage runner uses exact opt-in gameplay flags and owned report path" (
            $args[-3] -ceq '--' -and $args[-2] -ceq '--gameplay-smoke' -and $args[-1] -ceq "--report-path=$($paths.ReportPath)" -and
            @($args | Where-Object { $_ -like '--capture-path*' -or $_ -ceq '--smoke-test' }).Count -eq 0)
        $headless = $stage.EndsWith('-headless')
        $exported = $stage.StartsWith('artifact-')
        Check "$stage runner native ownership and binary kind remain distinct" (
            $invocation.Headless -eq $headless -and $invocation.EditorBinary -ne $exported -and
            $invocation.Executable -ceq $(if ($exported) { $artifact } else { $installation.consolePath }) -and
            $invocation.NativeExecutable -ceq $(if ($exported) { $artifact } else { $installation.godotPath }) -and
            $invocation.ExpectedChild -ceq $(if ($exported) { '' } else { $installation.godotPath }))
        Check "$stage standalone never loads source through --path" (
            ($exported -and '--path' -cnotin $args -and $invocation.WorkingDirectory -ceq [IO.Path]::GetDirectoryName($artifact)) -or
            (-not $exported -and '--path' -cin $args -and $project -cin $args -and $invocation.WorkingDirectory -ceq $project))
        Check "$stage headless versus Vulkan viewport flags follow the actual route" (
            ($headless -and '--headless' -cin $args -and '--windowed' -cnotin $args -and 'vulkan' -cnotin $args) -or
            (-not $headless -and '--headless' -cnotin $args -and '--windowed' -cin $args -and
                '1920x1080' -cin $args -and 'forward_plus' -cin $args -and 'vulkan' -cin $args))
        $fixed = [array]::IndexOf($args, '--fixed-fps')
        Check "$stage reproduces diagnostic input at fixed 60 without guessing a GPU or claiming FPS" (
            '--gpu-index' -cnotin $args -and @($args | Where-Object { $_ -ceq '--fixed-fps' }).Count -eq 1 -and
            $fixed -ge 0 -and $fixed -lt $args.Count - 3 -and $args[$fixed + 1] -ceq '60')
        $selectedGpu = Get-GodotGameplayInvocation $paths $stage $installation $project $artifact -GpuIndex 2
        Check "$stage explicit GPU override is rendered-only" (
            ($headless -and '--gpu-index' -cnotin $selectedGpu.Arguments) -or
            (-not $headless -and '--gpu-index' -cin $selectedGpu.Arguments -and '2' -cin $selectedGpu.Arguments))
    }
    $runner = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\Test-MicroSlice.ps1'))
    $runnerAst = [Management.Automation.Language.Parser]::ParseInput($runner, [ref]$null, [ref]$null)
    $legacy = $runnerAst.Find({
        param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-Game'
    }, $false)
    $builder = [Collections.Generic.List[string]]::new()
    $stoppedBeforeLaunch = $false
    foreach ($statement in $legacy.Body.EndBlock.Statements) {
        if ($statement -is [Management.Automation.Language.AssignmentStatementAst] -and
            $statement.Left.Extent.Text -ceq '$stageStart') { $stoppedBeforeLaunch = $true; break }
        $builder.Add($statement.Extent.Text)
    }
    Check 'legacy argument test isolates the actual builder strictly before process launch' $stoppedBeforeLaunch
    foreach ($stage in $stageNames) {
        $legacyArgs = & {
            param($Source, [bool]$Headless, [bool]$Exported)
            $runPath = $directory; $Name = "legacy-$stage"; $GpuIndex = -1
            function Add-Check([string]$Name, [bool]$Passed) { if (-not $Passed) { throw "FAIL $Name" } }
            . ([scriptblock]::Create($Source))
            return ,$arguments
        } ($builder -join "`n") $stage.EndsWith('-headless') $stage.StartsWith('artifact-')
        $fixed = [array]::IndexOf($legacyArgs, '--fixed-fps')
        Check "$stage legacy production smoke uses the same fixed-60 diagnostic schedule" (
            @($legacyArgs | Where-Object { $_ -ceq '--fixed-fps' }).Count -eq 1 -and
            $fixed -ge 0 -and $legacyArgs[$fixed + 1] -ceq '60' -and
            $fixed -lt [array]::IndexOf($legacyArgs, '--') -and '--smoke-test' -cin $legacyArgs -and
            '--gameplay-smoke' -cnotin $legacyArgs)
        Check "$stage legacy standalone still cannot fall back to a source project" (
            ('--path' -cin $legacyArgs) -ne $stage.StartsWith('artifact-') -and
            ('--headless' -cin $legacyArgs) -eq $stage.EndsWith('-headless'))
    }
    $normalLauncher = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\Start-Godot.ps1'))
    Check 'normal launcher remains real-time and does not inject either opt-in smoke driver' (
        $normalLauncher -notmatch '--fixed-fps|--gameplay-smoke|--smoke-test' -and
        $runner.Contains('renderedFpsEvidence = $false'))
    $sourceOnly = @($runnerAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses.Count -eq 1 -and
        $node.Clauses[0].Item1.Extent.Text -ceq '$Scope -eq ''GameplayRuntime'''
    }, $true))
    Check 'smallest runtime scope contains an actual source-headless invocation outside excluded component loops' (
        $sourceOnly.Count -eq 1 -and $sourceOnly[0].Extent.Text.Contains("Invoke-GameplayRuntime 'source-headless' `$true `$false") -and
        $sourceOnly[0].Parent -is [Management.Automation.Language.StatementBlockAst] -and
        $sourceOnly[0].Parent.Parent -is [Management.Automation.Language.TryStatementAst])
    foreach ($stage in $stageNames) {
        Check "All still includes real gameplay process route $stage" ($runner.Contains("Invoke-GameplayRuntime '$stage'"))
    }
    foreach ($headless in @($true, $false)) {
        foreach ($editor in @($true, $false)) {
            $name = $(if ($editor) { 'source' } else { 'artifact' }) + $(if ($headless) { '-headless' } else { '-rendered' })
            $path = Join-Path $scratch "$name.json"
            $started = [datetime]::UtcNow
            $report = New-GpFixtureReport $path $headless $editor
            New-Item -ItemType Directory -Path $report['gameplay']['capture_directory'] | Out-Null
            $manifest = New-GpFixtureManifest $report -CreatePngs
            Write-GpFixtureJson $path $report
            Write-GpFixtureJson $report['gameplay']['capture_manifest_path'] $manifest
            $result = Invoke-GodotProcess -FilePath $shell -WorkingDirectory $root -LogPrefix (Join-Path $directory $name) `
                -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-GameplayFixtureChild.ps1'), '-ReportPath', $path)
            $report = [IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable -Depth 64
            $manifest = [IO.File]::ReadAllText($report['gameplay']['capture_manifest_path']) | ConvertFrom-Json -AsHashtable -Depth 64
            $fixture = @{
                path = $path; started = $started; report = $report; manifest = $manifest; result = $result
                reportSeed = $report | ConvertTo-Json -Depth 32
                manifestSeed = $manifest | ConvertTo-Json -Depth 32
                restoreReport = $report | ConvertTo-Json -Depth 64 -Compress
                restoreManifest = $manifest | ConvertTo-Json -Depth 64 -Compress
            }
            $fixtures[$name] = $fixture
            Check "$name reuses identical serialized fixture bytes without changing printed assertions or protocol" (
                (Get-GpFixtureStdout $report) -ceq (Get-GpFixtureStdout $report $fixture.restoreReport))
            $seedReport = $fixture.reportSeed | ConvertFrom-Json -AsHashtable -Depth 32
            $seedManifest = $fixture.manifestSeed | ConvertFrom-Json -AsHashtable -Depth 32
            Check "$name immutable seeds retain the existing independent deep-copy values and types" (
                ($seedReport | ConvertTo-Json -Depth 64 -Compress) -ceq ((CopyFixture $report) | ConvertTo-Json -Depth 64 -Compress) -and
                ($seedManifest | ConvertTo-Json -Depth 64 -Compress) -ceq ((CopyFixture $manifest) | ConvertTo-Json -Depth 64 -Compress))
            $seedReport['checks'][0]['passed'] = $false
            $seedManifest['observations'][0]['state']['selected_actor_id'] = 9
            $freshSeedReport = $fixture.reportSeed | ConvertFrom-Json -AsHashtable -Depth 32
            $freshSeedManifest = $fixture.manifestSeed | ConvertFrom-Json -AsHashtable -Depth 32
            Check "$name mutations cannot contaminate original or later report and manifest clones" (
                $report['checks'][0]['passed'] -and $freshSeedReport['checks'][0]['passed'] -and
                $manifest['observations'][0]['state']['selected_actor_id'] -ne 9 -and
                $freshSeedManifest['observations'][0]['state']['selected_actor_id'] -eq
                    $manifest['observations'][0]['state']['selected_actor_id'])
            Check "$name synthetic protocol has a real owned PowerShell exit witness" (Test-GodotProcessCompletion $result)
            $parsed = Read-Fixture $fixture
            Check "$name full decoder accepts the synthetic 28-case protocol with retained legacy evidence" ($parsed['gameplay']['cases'].Count -eq 28)
            Check "$name keeps all thirty real-shaped mouse-motion records rather than dropping an unknown class" (
                @($parsed['gameplay']['native_inputs'] | Where-Object { $_['class'] -ceq 'InputEventMouseMotion' }).Count -eq 30 -and
                $parsed['gameplay']['cases'][0]['after']['input'][2]['relative'].Count -eq 2)
            Check "$name manifest accounts for rendered-only synthetic PNGs" (
                $parsed['gameplay']['saved_png_count'] -eq $(if ($headless) { 0 } else { 20 }))
        }
    }
    $heldInputs = $fixtures['source-headless'].report['gameplay']['cases'][2]['after']['input']
    $heldAxis = @(Find-GpInput $heldInputs InputEventJoypadMotion axis_value (-0.8))
    Check 'held-direction fixture preserves Godot float32 rounding instead of assuming exact negative decimal equality' (
        $heldAxis.Count -eq 1 -and $heldAxis[0]['axis_value'] -ne (-0.8))
    foreach ($field in @('ok', 'complete', 'editor_binary', 'headless')) {
        Reject-Report "native boolean cannot be a string: $field" { param($r) $r[$field] = 'true' }
    }
    foreach ($field in @('process_id', 'input_schema_version', 'driver_start_calls', 'frames_drawn', 'viewport_width')) {
        Reject-Report "native integer cannot be a string: $field" { param($r) $r[$field] = [string]$r[$field] }
    }
    foreach ($pair in @(@('project_version', '0.3.0-preview'), @('main_scene', 'res://bootstrap/bootstrap.tscn'),
            @('configured_main_scene', 'res://bootstrap/bootstrap.tscn'), @('input_schema_version', 2),
            @('scope', 'playable-preview-runtime-smoke'), @('gameplay_driver_script', 'res://diagnostics/match_smoke.gd'),
            @('gui_input_method', 'Input.parse_input_event; physical keys and raw joypad events, device 0'),
            @('gui_input_method', 'direct exercise_requested signal'), @('gui_input_method', $true),
            @('input_method', 'Viewport.push_input; local mouse coordinates, device 0'),
            @('complete', $false), @('gpu_validated', $true), @('watchdog_msec', 0), @('frames_drawn', 1),
            @('aim_precision_max_degrees_per_second', 90.0), @('process_id', 1),
            @('authority_path', '/root/Fake/Simulation'), @('camera_path', '/root/Other/BroadcastCamera'))) {
        Reject-Report "false runtime identity is rejected: $($pair[0])=$($pair[1])" { param($r) $r[$pair[0]] = $pair[1] }
    }
    Reject-Report 'native GUI dispatch method cannot be silently omitted' { param($r) [void]$r.Remove('gui_input_method') }
    Reject-Report 'native key/joy dispatch method cannot be silently omitted' { param($r) [void]$r.Remove('input_method') }
    Reject-Report 'native key/joy dispatch method cannot be a coerced boolean' { param($r) $r['input_method'] = $true }
    foreach ($value in @('windows', 'headless', 'X11', $true)) {
        Reject-Report "rendered backend must retain the actual Windows display identity: $value" {
            param($r) $r['display_server'] = $value
        } 'source-rendered'
    }
    Reject-Report 'headless API metadata must be an empty string, not a false boolean' { param($r) $r['gpu_api'] = $false }
    foreach ($field in @('command_rejections', 'integration_errors', 'failures')) {
        Reject-Report "normal runtime cannot omit the empty $field array" { param($r) [void]$r.Remove($field) }
        Reject-Report "normal runtime cannot hide a nonempty $field array" { param($r) $r[$field] = @('unexpected') }
    }
    Reject-Report 'legacy single-image shortcut cannot satisfy the gameplay protocol' { param($r) $r['capture_path'] = $r['report_path'] + '.png' }
    Reject-Report 'report timestamp must be a native string' { param($r) $r['timestamp_utc'] = 42 }
    Reject-Report 'stale runtime timestamp cannot be refreshed by rewriting the file' { param($r) $r['timestamp_utc'] = '2000-01-01T00:00:00' }
    Reject-Report 'future runtime timestamp is rejected' { param($r) $r['timestamp_utc'] = [datetime]::UtcNow.AddHours(1).ToString('s') }
    Reject-Report 'duplicate native check identity is rejected even when every boolean is true' {
        param($r) $r['checks'][1]['name'] = $r['checks'][0]['name']
    }
    Reject-Report 'missing mandatory native pure-preview assertion fails despite consistent totals' {
        param($r)
        $r['checks'] = @($r['checks'] | Where-Object { $_['name'] -cne 'm0/live_charged_shot repeated preview reads neither resample nor mutate authority' })
        $r['passed'] = $r['checks'].Count; $r['total'] = $r['checks'].Count
    }
    Reject-Report 'native output/report assertion totals must agree' { param($r) $r['total']++ }
    foreach ($label in @('m0/corner_pos_x_neg_z', 'm1/keeper_clearance')) {
        foreach ($suffix in @('Apply emits exactly one native exercise request',
                'Apply confirms the requested production exercise', 'Apply closes the development modal',
                'explicit Apply reaches the actual catalog authority')) {
            Reject-Report "native Apply assertion remains mandatory despite consistent totals: $label $suffix" {
                param($r)
                $r['checks'] = @($r['checks'] | Where-Object { $_['name'] -cne "$label $suffix" })
                $r['passed'] = $r['total'] = $r['checks'].Count
            }
        }
    }
    foreach ($suffix in @('keeper_clearance actual forbidden foot input is visible beside the persistent fine-aim hint',
            'keeper_clearance after refusal own READY shows actual persistent fine-aim instructions',
            'accumulated_spot_choice native forbidden pass has visible contextual feedback')) {
        Reject-Report "actual READY feedback remains mandatory despite consistent totals: $suffix" {
            param($r)
            $missing = "m0/$suffix"
            $r['checks'] = @($r['checks'] | Where-Object { $_['name'] -cne $missing })
            $r['passed'] = $r['total'] = $r['checks'].Count
        }
    }
    Reject-Report 'native-suite unauthorized signals cannot be imported into the clean smoke protocol' {
        param($r)
        $r['command_rejections'] = @(
            @{actor = 0; code = 4; message = 'Launch refused: launch_rule'}
            @{actor = 0; code = 4; message = 'Launch refused: launch_rule'}
        )
        $r['expected_command_rejections'] = CopyFixture $r['command_rejections']
    }
    Reject-Output 'two intended native-suite signals never authorize two runtime stderr ERROR lines' {
        param($r) $r.Stderr += "`nERROR: Launch refused: launch_rule`nERROR: Launch refused: launch_rule"
    }
    $fixture = $fixtures['source-headless']
    $expanded = CopyFixture $fixture.report
    $expanded['checks'] += @{name = 'synthetic additional READY review assertion'; passed = $true}
    $expanded['passed'] = $expanded['total'] = $expanded['checks'].Count
    $expandedResult = Copy-Result $fixture.result
    $expandedResult.Stdout = Get-GpFixtureStdout $expanded
    try {
        Write-GpFixtureJson $fixture.path $expanded
        $parsed = Read-Fixture $fixture $expandedResult
        Check 'runtime review can add a unique printed assertion without freezing a producer total' (
            $parsed['total'] -eq $fixture.report['total'] + 1)
        $expandedResult.Stdout = $expandedResult.Stdout.Replace("PASS synthetic additional READY review assertion`n", '')
        Rejected 'an additional runtime assertion cannot exist only in the JSON' { Read-Fixture $fixture $expandedResult }
    }
    finally { Write-GpFixtureJson $fixture.path $fixture.report }
    foreach ($field in @('cases', 'native_inputs', 'athlete_presentations', 'completed_cases', 'expected_cases')) {
        Reject-Report "nested gameplay cannot omit actual $field" { param($r) [void]$r['gameplay'].Remove($field) }
    }
    Reject-Report 'terminal gameplay traversal must really complete' { param($r) $r['gameplay']['complete'] = $false }
    Reject-Report 'duplicate case hides a missing physical scenario and fails' {
        param($r) $r['gameplay']['cases'][1] = CopyFixture $r['gameplay']['cases'][0]
    }
    Reject-Report 'uncompleted last scenario fails rather than treating twenty images as enough' {
        param($r) $r['gameplay']['completed_cases'] = @($r['gameplay']['completed_cases'][0..26])
    }
    Reject-Report 'headless cannot claim saved PNGs or visual completion' {
        param($r) $r['gameplay']['saved_png_count'] = 20; $r['gameplay']['capture_complete'] = $true
    }
    Reject-Report 'headless cannot fabricate image dimensions even in a matching manifest' {
        param($r, $m) $r['gameplay']['cases'][0]['after']['width'] = 1920; $m['observations'][0]['width'] = 1920
    }
    foreach ($field in @('before', 'after_wait', 'after_input')) {
        Reject-Report "untouched default cannot be started by the driver: $field" {
            param($r) $r['default_entrypoint'][$field]['driver_start_calls'] = 1
        }
    }
    Reject-Report 'untouched default still needs all ten real physical bodies' {
        param($r) $r['default_entrypoint']['before']['physical_actor_ids'] = @(0..3)
    }
    Reject-Report 'default intent cannot omit latent selected zero' {
        param($r) $r['default_entrypoint']['after_wait']['ai_intent_actor_ids'] = @(1..9)
    }
    Reject-Report 'loaded actors must be the actual untouched snapshot actors' { param($r) $r['loaded_actors'][0]['position'][0] += 2.0 }
    Reject-Report 'native exercise input cannot be replaced by automatic metadata' {
        param($r) $r['gameplay']['native_inputs'] = @()
    }
    Reject-Report 'a local event not present in native global history fails' {
        param($r) $r['events'] = @($r['events'][0..($r['events'].Count - 2)])
    }
    Reject-Report 'additional restart focus evidence is mandatory' { param($r) $r['focus_changes'] = @($r['focus_changes'][0..5]) }
    Reject-Report 'restart focus evidence must name the actual receiver' { param($r) $r['focus_changes'][6]['expected_selected_actor_id'] = 0 }
    Reject-Report 'keeper throw focus cannot pretend to be an autonomous AI return' { param($r) $r['focus_changes'][7]['reason'] = 'keeper_ai' }
    Reject-Report 'public catalog start counter cannot skip hidden resets' { param($r) $r['gameplay']['cases'][0]['before']['driver_start_calls'] += 2 }
    foreach ($field in @('process_id', 'headless', 'main_scene', 'functional_traversal_complete', 'saved_png_count')) {
        Reject-Report "capture manifest identity/completion cannot disagree: $field" {
            param($r, $m)
            $m[$field] = switch ($field) {
                'process_id' { 1 }; 'headless' { $false }; 'main_scene' { 'res://bootstrap/bootstrap.tscn' }
                'functional_traversal_complete' { $false }; 'saved_png_count' { 1 }
            }
        }
    }
    Reject-Report 'missing manifest observation is not silently skipped' { param($r, $m) $m['observations'] = @($m['observations'][0..18]) }
    Reject-Report 'manifest snapshot must be the actual captured case, not a similar frame' {
        param($r, $m) $m['observations'][0]['state']['ball_position'][0] += 1.0
    }
    Reject-Report 'capture directory must remain tied to this report basename' {
        param($r) $r['gameplay']['capture_directory'] = Join-Path $scratch 'other-run'
    }
    Reject-Report 'manifest path cannot escape the owned capture directory' {
        param($r) $r['gameplay']['capture_manifest_path'] = Join-Path $scratch 'other-manifest.json'
    }
    foreach ($field in @('ExitWitnesses', 'RuntimeProcessIds')) {
        Reject-Output "empty ownership $field cannot yield a green runtime" { param($r) $r.$field = @() }
    }
    Reject-Output 'ownership start-identity mismatch fails without querying or killing that PID' { param($r) $r.ProcessStartTimeUtcTicks++ }
    Reject-Output 'fabricated JSON exit witness is never an owned native handle witness' {
        param($r) $r.ExitWitnesses = @(@{ProcessId = $r.ProcessId; ExitCode = 0; StartTimeUtcTicks = $r.ProcessStartTimeUtcTicks})
    }
    Reject-Output 'nonzero exit cannot be hidden behind a passing report' { param($r) $r.ExitCode = 7 }
    Reject-Output 'extra runtime marker is not a second successful traversal' { param($r) $r.Stdout += 'FUTSAL_GAMEPLAY_SMOKE {}' }
    Reject-Output 'printed assertions must not be omitted while report booleans remain true' {
        param($r) $r.Stdout = [regex]::Replace($r.Stdout, '(?m)^PASS [^\r\n]+\r?\n', '', 1)
    }
    foreach ($diagnostic in @('ERROR: unexpected gameplay diagnostic', 'SCRIPT ERROR: unexpected script fault',
            'SHADER ERROR: unexpected shader fault', 'WARNING: Jolt job limit reached', 'WARNING: arbitrary loader warning')) {
        Reject-Output "unexpected native diagnostic fails: $($diagnostic.Split(':')[0]) $($diagnostic.Split(':')[1].Trim())" {
            param($r) $r.Stderr = $diagnostic
        }
    }
    $corner = 'm0/corner_pos_x_neg_z'
    $cut = 'm0/dribble_left_contact'
    foreach ($change in @(@('passed', 'true'), @('passed', $false), @('source_script', 'res://tests/fake.gd'))) {
        Reject-Case "case bool/source cannot masquerade as real evidence: $($change[0])=$($change[1])" $corner {
            param($c) $c[$change[0]] = $change[1]
        }
    }
    Reject-Case 'actual captured case requires its post-input completion' $corner { param($c) [void]$c.Remove('completion') }
    Reject-Case 'controlled scenario cannot silently enable AI intent' $corner { param($c) $c['after']['state']['ai_intent_actor_ids'] = @(0..3) }
    Reject-Case 'effective AI cannot run the selected actor' $corner { param($c) $c['after']['state']['ai_actor_ids'] = @(0) }
    Reject-Case 'scenario selection cannot disagree with the HUD and snapshot' $corner { param($c) $c['after']['selected_actor_id'] = 2 }
    Reject-Case 'case cannot start from an already-ready fabricated setup' $corner { param($c) $c['before']['restart']['stage'] = 3 }
    Reject-Case 'restart cannot omit its source-defined original launch episode field' $corner {
        param($c) [void]$c['before']['restart'].Remove('launch_contact_id')
    } 'restart.launch_contact_id'
    Reject-Case 'preparation cannot invent an earlier launch contact' $corner {
        param($c) $c['before']['restart']['launch_contact_id'] = 1
    } 'launch contact identity'
    Reject-Case 'launch contact identity must be an integer rather than a numeric string' $corner {
        param($c) $c['after']['restart']['launch_contact_id'] = '-1'; $c['after']['state']['restart']['launch_contact_id'] = '-1'
    }
    Reject-Case 'accepted restart launch must retain its own physical contact ID' $corner {
        param($c) $c['completion']['events'][3]['restart']['launch_contact_id']++
    } 'original contact episode'
    Reject-Case 'subsequent restart snapshot cannot silently replace the original launch episode' $corner {
        param($c) $c['completion']['state']['restart']['launch_contact_id']++; $c['completion']['restart']['launch_contact_id']++
    } 'original contact episode'
    Reject-Case 'preparation clock cannot count as effective playing seconds' $corner {
        param($c) $c['after']['state']['seconds_remaining'] -= 1.0
    } 'Gameplay clock disagrees'
    Reject-Case 'restart deadline cannot be extended while preparing' $corner {
        param($c) $c['after']['state']['restart']['deadline_tick']++; $c['after']['restart']['deadline_tick']++
    } 'Restart deadline'
    Reject-Case 'ready taker cannot move during own restart aiming' $corner { param($c) $c['after']['state']['selected_can_move'] = $true }
    Reject-Case 'ready corner cannot invent dribble controls' $corner { param($c) $c['after']['state']['human_allowed_actions'] += 5 }
    Reject-Case 'ready corner camera cannot use another authoritative tick' $corner { param($c) $c['after']['camera']['tick']++ }
    Reject-Case 'camera depth/orientation must actually frame the ball, taker and passing options' $corner {
        param($c) $c['after']['camera']['rotation'][1] += [Math]::PI
    }
    foreach ($field in @('look_target', 'tracked_ball')) {
        Reject-Case "camera observation must retain source-defined $field" $corner {
            param($c) [void]$c['after']['camera'].Remove($field)
        }
        Reject-Case "camera $field must contain three numeric components" $corner {
            param($c) $c['after']['camera'][$field] = @(0.0, 0.0)
        }
        Reject-Case "camera $field cannot contain a numeric string" $corner {
            param($c) $c['after']['camera'][$field][0] = '0'
        }
        Reject-Case "camera $field must remain finite" $corner {
            param($c) $c['after']['camera'][$field][0] = [double]::NaN
        }
    }
    Reject-Case 'camera tracked ball must be the observed BallView position, not an unrelated point' $corner {
        param($c) $c['after']['camera']['tracked_ball'][0] += 1.0
    } 'camera tracked ball / observed ball'
    Reject-Case 'camera look target must generate the reported orientation' $corner {
        param($c) $c['after']['camera']['look_target'][0] += 1.0
    } 'camera look target / actual rotation'
    Reject-Case 'camera cannot look at its own eye' $corner {
        param($c) $c['after']['camera']['look_target'] = @($c['after']['camera']['position'])
    } 'look target coincides'
    $expandedCase = CopyFixture $fixtures['source-headless'].report['gameplay']['cases'][0]
    $expandedCase['after']['camera']['synthetic_additive_observation'] = 'not a schema replacement'
    Assert-GpCase $expandedCase $policy[$corner] '/root/Match'
    Check 'runtime camera decoder accepts additional fields without weakening the observed tracking contract' $true
    $flight = $fixtures['source-headless'].report['gameplay']['cases'][4]['completion']
    $tracking = CopyFixture $flight['camera']
    $renderBall = @(0..2 | ForEach-Object {
        $flight['state']['ball_position'][$_] - $flight['state']['ball_velocity'][$_] / 120.0
    })
    $tracking['tracked_ball'] = $renderBall
    Assert-GpCameraTracking $tracking $renderBall
    Check 'camera tracking uses the actual interpolated render point rather than forcing the physical snapshot point' (
        (Get-GodotVectorDistanceSquared $renderBall $flight['state']['ball_position']) -gt 0.0001)
    Rejected 'an interpolated tracking point cannot be relabelled as a different physical observation' {
        Assert-GpCameraTracking $tracking $flight['state']['ball_position']
    } 'camera tracked ball / observed ball'
    Reject-Case 'visible HOME options cannot be fabricated independently of real camera projection' $corner {
        param($c) $c['after']['visible_home_options'] = @()
    } 'Geometrically visible'
    Reject-Case 'camera cannot return before the accepted corner pass' $corner {
        param($c) $c['completion']['camera']['accepted_return_event_id'] = -1
    } 'Corner camera returned'
    Reject-Case 'guide direction cannot oppose its effective launch velocity' $corner {
        param($c) $c['after']['guide']['direction'] = @($c['after']['guide']['direction'] | ForEach-Object { -$_ })
    } 'Guide direction'
    Reject-Case 'guide must share the actual BallView render world' $corner { param($c) $c['after']['guide']['same_render_world_as_ball'] = $false }
    Reject-Case 'guide cannot claim the opposing keeper as an effective HOME receiver' $corner {
        param($c) $c['after']['guide']['effective_target_actor_id'] = 3
    }
    Reject-Case 'guide render origin cannot move independently of the interpolated ball' $corner {
        param($c) $c['after']['guide']['render_origin'][0] += 0.2
    }
    Reject-Case 'actual input device must be native device zero' $corner { param($c) $c['after']['input'][0]['device'] = 1 }
    Reject-Case 'float tolerance never accepts a numeric-string stick observation' 'm0/corner_neg_x_neg_z' {
        param($c)
        $axis = @($c['after']['input'] | Where-Object { $_['class'] -ceq 'InputEventJoypadMotion' -and $_['axis_value'] -lt 0 })[0]
        $axis['axis_value'] = '-0.800000011920929'
    } 'finite bounded'
    Reject-Case 'float32 rounding tolerance does not accept a different held stick value' 'm0/corner_neg_x_neg_z' {
        param($c)
        foreach ($moment in @('after', 'completion')) {
            $axis = @($c[$moment]['input'] | Where-Object { $_['class'] -ceq 'InputEventJoypadMotion' -and $_['axis_value'] -lt 0 })[0]
            $axis['axis_value'] = -0.79
        }
    } 'Missing production input'
    Reject-Case 'exercise cannot be applied by a metadata-only event class' $corner { param($c) $c['after']['input'][3]['class'] = 'ApplyExercise' }
    foreach ($field in @('position', 'relative')) {
        Reject-Case "native mouse motion cannot omit its $field vector" $corner {
            param($c) [void]$c['after']['input'][2].Remove($field)
        } "two-component $field"
        foreach ($value in @('vector metadata', @(0.0), @(0.0, 0.0, 0.0))) {
            $shape = if ($value -is [string]) { 'string' } else { "array length $(@($value).Count)" }
            Reject-Case "native mouse motion requires exactly two $field components: $shape" $corner {
                param($c) $c['after']['input'][2][$field] = $value
            } "two-component $field"
        }
        foreach ($value in @($null, $true, '0', [double]::NaN, [double]::PositiveInfinity)) {
            Reject-Case "native mouse motion rejects nonnumeric/nonfinite $field component: $value" $corner {
                param($c) $c['after']['input'][2][$field][0] = $value
            } 'finite bounded'
        }
    }
    Reject-Case 'native mouse motion cannot use another input device' $corner {
        param($c) $c['after']['input'][2]['device'] = 1
    } 'input device'
    Reject-Case 'native mouse motion cannot use a nonlocal viewport position' $corner {
        param($c) $c['after']['input'][2]['position'][0] = 1921.0
    } 'mouse motion x'
    Reject-Case 'Apply cannot silently discard its motion while retaining both mouse edges' $corner {
        param($c) $c['after']['input'] = @($c['after']['input'] | Where-Object { $_['class'] -cne 'InputEventMouseMotion' })
    } 'recorded local mouse motion'
    Reject-Case 'Apply motion must target the same local point as its button press' $corner {
        param($c) $c['after']['input'][2]['position'][0]++
    } 'Apply motion/press position'
    $applyObservation = CopyFixture $fixtures['source-headless'].report['gameplay']['cases'][2]['after']
    $appliedInputs = @(Get-GpAppliedInputs $applyObservation)
    Check 'pre-dispatch Apply release retains the old clock while following gameplay inputs use the reset authority' (
        $applyObservation['input'][4]['tick'] -gt $applyObservation['input'][5]['tick'] -and
        $appliedInputs.Count -eq $applyObservation['input'].Count - 5 -and $appliedInputs[0]['tick'] -eq 4)
    $emptyApplied = CopyFixture $applyObservation
    $emptyApplied['input'] = @($emptyApplied['input'][0..4])
    Check 'Apply without later actions returns a genuinely empty input list' (@(Get-GpAppliedInputs $emptyApplied).Count -eq 0)
    Reject-Case 'Apply release cannot invent a post-reset timestamp before dispatch' $corner {
        param($c) $c['after']['input'][4]['tick'] = 0
    } 'pre-reset clock'
    Reject-Case 'Apply click must release over its actual pressed position' $corner {
        param($c) $c['after']['input'][4]['position'][0]++
    } 'Apply press/release position'
    Reject-Case 'preparation input cannot rewind before Apply' $corner {
        param($c) $c['after']['input'][0]['tick'] = 11
    } 'preparation input rewinds'
    Reject-Case 'input tick cannot occur after its observation' 'm0/live_charged_shot' {
        param($c) $c['after']['input'][5]['tick'] = 9000
    } 'after its observed authority'
    Reject-Case 'later input cannot use the Apply boundary to conceal another rewind' 'm0/live_charged_shot' {
        param($c) $c['completion']['input'][6]['tick'] = 3
    } 'Native gameplay input rewinds'
    Reject-Case 'input press must remain a native bool' $corner { param($c) $c['after']['input'][0]['pressed'] = 'true' }
    Reject-Case 'every athlete needs current authoritative full-snapshot context' $corner {
        param($c) $c['after']['athlete_presentations'][1]['context_tick']--
    }
    Reject-Case 'athlete presentation cannot borrow another actor identity' $corner {
        param($c) $c['after']['athlete_presentations'][1]['actor_id'] = 2
    }
    Reject-Case 'athlete ball context cannot be replaced by a guessed local anchor' $corner {
        param($c) $c['after']['athlete_presentations'][0]['snapshot_ball'][0] += 1.0
    }
    Reject-Case 'athlete view cannot report stale validation errors as a valid pose' $corner {
        param($c) $c['after']['athlete_presentations'][0]['validation_error'] = 'context_ball'
    }
    Reject-Case 'visible limb matrices must be finite and nondegenerate' $corner {
        param($c) $c['after']['athlete_presentations'][0]['feet'][0]['basis_x'] = @(0.0, 0.0, 0.0)
    }
    Reject-Case 'body limb must remain attached to its real actor' $corner {
        param($c) $c['after']['athlete_presentations'][0]['feet'][0]['origin'][0] += 50.0
    }
    Reject-Case 'NaN camera vectors cannot be repaired by report booleans' $corner { param($c) $c['after']['camera']['position'][0] = [double]::NaN }
    Reject-Case 'actual charge cannot be fabricated without a held interval' 'm0/live_charged_shot' {
        param($c)
        foreach ($i in $c['completion']['input']) {
            if ($i['class'] -ceq 'InputEventKey' -and $i['physical_keycode'] -eq 75 -and -not $i['pressed']) { $i['tick'] = 4 }
        }
    } 'Shot charge/release'
    Reject-Case 'live shot cannot retain a stale visible world guide after release' 'm0/live_charged_shot' {
        param($c) $c['completion']['guide']['visible'] = $true
    }
    foreach ($field in @('physical_origin', 'launch_velocity', 'power', 'executable', 'effective_target_actor_id')) {
        Reject-Case "hidden guide must clear its stale $field metadata" 'm0/live_charged_shot' {
            param($c)
            $c['completion']['guide'][$field] = switch ($field) {
                'physical_origin' { ,@(1.0, 0.0, 0.0) }
                'launch_velocity' { ,@(1.0, 0.0, 0.0) }
                'power' { 0.25 }
                'executable' { $true }
                'effective_target_actor_id' { 2 }
            }
        } 'Hidden guide retained'
    }
    Reject-Case 'keeper release cannot be represented as a foot pass' 'm0/keeper_clearance_release' {
        param($c) $c['after']['accepted_event']['launch_kind'] = 0
    }
    Reject-Case 'prepared keeper hands must surround the actual rendered ball' 'm0/keeper_clearance_ready' {
        param($c) $c['after']['athlete_presentations'][2]['hands'][0]['origin'][0] += 0.5
    } 'Keeper hands'
    Reject-Case 'keeper wrong K routing must be evidenced before A throws' 'm0/keeper_clearance_ready' {
        param($c) $c['after']['input'] = @($c['after']['input'] | Where-Object { -not ($_.Contains('physical_keycode') -and $_['physical_keycode'] -eq 75) })
    } 'Missing production input'
    Reject-Case 'cut-left cannot claim right-facing physical gesture data' $cut {
        param($c) $c['after']['state']['actors'][0]['gesture_direction'][2] *= -1
    } 'wrong physical cut side'
    Reject-Case 'dribble must physically move the authority ball' $cut {
        param($c) $c['after']['state']['ball_position'] = @($c['before']['ball_position'])
        $c['after']['athlete_presentations'] | ForEach-Object { $_['snapshot_ball'] = @($c['before']['ball_position']) }
    }
    Reject-Case 'dribble contact cannot point to an unrelated physical location' $cut {
        param($c) $c['after']['state']['actors'][0]['gesture_contact_position'][0] += 10.0
    } 'dribble authoritative contact'
    Reject-Case 'dribble must keep authoritative human command sequences advancing' $cut {
        param($c)
        $c['after']['state']['actors'][0]['sequence'] = $c['before']['actors'][0]['sequence']
        $c['after']['state']['human_sequence'] = $c['before']['human_sequence']
    } 'stopped advancing'
    Reject-Case 'retained dribble needs its full no-repeat observation window' $cut {
        param($c) $c['completion']['state']['tick'] = $c['after']['tick']
    }
    Reject-Case 'penalty cannot invent an ordinary restart deadline' 'm0/penalty_fine_aim' {
        param($c) $c['after']['events'][3]['restart']['deadline_tick'] = 301
    } 'Restart deadline'
    Reject-Case 'penalty fine input requires the real LT axis, not a different trigger' 'm0/penalty_fine_aim' {
        param($c)
        foreach ($i in $c['after']['input']) { if ($i['class'] -ceq 'InputEventJoypadMotion' -and $i['axis'] -eq 4) { $i['axis'] = 5 } }
    } 'Penalty lacks'
    Reject-Case 'accumulated free kick must retain seeded sixth-count HUD provenance' 'm0/accumulated_spot_choice' {
        param($c) $c['after']['hud_fouls'] = '0 / 6'
    }
    Reject-Report 'pose progression cannot substitute the same frozen limb transforms' {
        param($r)
        $sample = @($r['gameplay']['athlete_presentations'] | Where-Object { $_['case'] -ceq 'm0/live_charged_shot/progress' })[0]
        $sample['advanced'] = CopyFixture $sample['at_contact']
    }
    Reject-Report 'each captured contact requires its actual actor pose sample' {
        param($r) $r['gameplay']['athlete_presentations'] = @($r['gameplay']['athlete_presentations'][1..31])
    }
    Reject-Report 'rendered protocol must prove actual drawn frames' { param($r) $r['frames_drawn'] = 0 } 'source-rendered'
    Reject-Report 'rendered PNG checksum must match actual file bytes' {
        param($r, $m)
        $r['gameplay']['cases'][0]['after']['sha256'] = '0' * 64
        $m['observations'][0]['sha256'] = '0' * 64; $m['captures'][0]['sha256'] = '0' * 64
    } 'source-rendered'
    Reject-Report 'rendered case image path cannot refer to another run' {
        param($r, $m)
        $outside = Join-Path $scratch 'unowned.png'
        $r['gameplay']['cases'][0]['after']['filename'] = $outside
        $m['observations'][0]['filename'] = $outside; $m['captures'][0]['filename'] = $outside
    } 'artifact-rendered'
    $rendered = $fixtures['source-rendered']
    $png = $rendered.manifest['captures'][0]['filename']
    foreach ($variant in @('wrong resolution', 'uniform pixels', 'repeated PNG')) {
        try {
            if ($variant -eq 'repeated PNG') { Copy-Item -LiteralPath $rendered.manifest['captures'][1]['filename'] -Destination $png -Force }
            else { New-GpFixturePng $png 0 $(if ($variant -eq 'wrong resolution') { 1280 } else { 1920 }) ($variant -eq 'uniform pixels') }
            Reject-Report "actual rendered file fails despite internally matching metadata: $variant" {
                param($r, $m)
                $hash = (Get-FileHash -LiteralPath $png -Algorithm SHA256).Hash.ToLowerInvariant()
                $r['gameplay']['cases'][0]['after']['sha256'] = $hash
                $m['observations'][0]['sha256'] = $hash; $m['captures'][0]['sha256'] = $hash
            } 'source-rendered'
        }
        finally { New-GpFixturePng $png 0 }
    }
    try {
        (Get-Item -LiteralPath $png).LastWriteTimeUtc = $rendered.started.AddMinutes(-5)
        Rejected 'old PNG cannot be reused as fresh current-run evidence' { Read-Fixture $rendered }
    }
    finally { (Get-Item -LiteralPath $png).LastWriteTimeUtc = [datetime]::UtcNow }
    try {
        (Get-Item -LiteralPath $png).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(5)
        Rejected 'future-dated PNG cannot manufacture freshness' { Read-Fixture $rendered }
    }
    finally { (Get-Item -LiteralPath $png).LastWriteTimeUtc = [datetime]::UtcNow }
    $extra = Join-Path $rendered.report['gameplay']['capture_directory'] 'unexpected.json'
    try {
        [IO.File]::WriteAllText($extra, '{}')
        Rejected 'extra artifacts are not silently included in the twenty-PNG evidence directory' { Read-Fixture $rendered }
    }
    finally { Remove-Item -LiteralPath $extra }
    $missing = Join-Path $scratch 'held-png.png'
    try {
        Move-Item -LiteralPath $png -Destination $missing
        Rejected 'missing actual PNG prevents rendered acceptance' { Read-Fixture $rendered }
    }
    finally { Move-Item -LiteralPath $missing -Destination $png }
    Rejected 'real owned nonzero PowerShell child is rejected by the production process wrapper' {
        Invoke-GodotProcess -FilePath $shell -WorkingDirectory $root -LogPrefix (Join-Path $directory 'nonzero') -Arguments @('-NoProfile', '-Command', 'exit 7')
    } 'exited 7'
    Rejected 'real owned timed-out child is cleaned up rather than accepted as completed gameplay' {
        Invoke-GodotProcess -FilePath $shell -WorkingDirectory $root -LogPrefix (Join-Path $directory 'timeout') `
            -Arguments @('-NoProfile', '-Command', 'Start-Sleep -Seconds 20') -TimeoutSeconds 1
    } 'Timed out'
    $null = Read-Fixture $rendered
    Check 'negative fixtures leave the valid owned rendered report usable' $true
    foreach ($fixtureName in $stageNames) {
        $fixture = $fixtures[$fixtureName]
        Check "$fixtureName negative mutations restore the exact original serialized report and manifest" (
            [IO.File]::ReadAllText($fixture.path) -ceq $fixture.restoreReport -and
            [IO.File]::ReadAllText($fixture.report['gameplay']['capture_manifest_path']) -ceq $fixture.restoreManifest)
    }
    $complete = $true
}
catch {
    $failure = $_.Exception.Message + ' | ' + $_.ScriptStackTrace
    $checks.Add([ordered]@{name = 'runtime fixture suite completed'; passed = $false; error = $failure})
}
finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse }
}
$failed = @($checks | Where-Object { -not $_['passed'] }).Count
$report = [ordered]@{
    ok = $complete -and $failed -eq 0; passed = $checks.Count - $failed; total = $checks.Count; checks = $checks.ToArray()
    scope = 'PowerShell synthetic protocol/PNG fixtures with owned PowerShell children; NOT native gameplay/GPU acceptance'
    nativeValidated = $false; evidence = $directory; error = $failure
}
if ($TraceTimings) {
    $report['timingProfile'] = @(Get-RuntimeFixtureTimingSummary)
    $report['timingWallMilliseconds'] = $clock.ElapsedMilliseconds
    Write-Host ('RUNTIME_FIXTURE_PROFILE ' + ($report['timingProfile'] | ConvertTo-Json -Compress -Depth 5))
}
if ($report.ok) {
    $null = ConvertFrom-GodotStructuredReport ([pscustomobject]@{
        Stdout = 'FUTSAL_GAMEPLAY_RUNTIME_VALIDATION_TESTS ' + ($report | ConvertTo-Json -Compress -Depth 16)
    }) 'FUTSAL_GAMEPLAY_RUNTIME_VALIDATION_TESTS' -RequireChecks
}
Write-GpFixtureJson (Join-Path $directory 'result.json') $report
Write-Output ('FUTSAL_GAMEPLAY_RUNTIME_VALIDATION_TESTS ' + ($report | ConvertTo-Json -Compress -Depth 16))
exit $(if ($report.ok) { 0 } else { 1 })
