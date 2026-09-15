#Requires -Version 7.2
[CmdletBinding()]
param([switch]$TraceTimings)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$nativeTraceClock = [Diagnostics.Stopwatch]::StartNew()
$nativeTraceLastMilliseconds = 0L
$nativeTraceLastCpuMilliseconds = 0.0
$nativeTraceSpans = @{}
$nativeTraceProcess = if ($TraceTimings) { [Diagnostics.Process]::GetCurrentProcess() } else { $null }
if ($TraceTimings) { Write-Host "NATIVE_FIXTURE_TIMING_START pid=$PID utc=$([DateTime]::UtcNow.ToString('o'))" }

function Write-NativeFixtureBoundary([string]$Boundary, [string]$Phase, [string]$Detail = '') {
    if (-not $TraceTimings) { return }
    $nativeTraceProcess.Refresh()
    $record = [ordered]@{
        boundary = $Boundary; phase = $Phase; detail = $Detail
        processId = $nativeTraceProcess.Id
        processStartTimeUtcTicks = $nativeTraceProcess.StartTime.ToUniversalTime().Ticks
        originalSelfHandle = $nativeTraceProcess.SafeHandle.DangerousGetHandle().ToInt64()
        stopwatchTicks = [Diagnostics.Stopwatch]::GetTimestamp()
        stopwatchFrequency = [Diagnostics.Stopwatch]::Frequency
        wallMilliseconds = $nativeTraceClock.ElapsedMilliseconds
        cpuMilliseconds = $nativeTraceProcess.TotalProcessorTime.TotalMilliseconds
    }
    [Console]::WriteLine('NATIVE_FIXTURE_BOUNDARY ' + ($record | ConvertTo-Json -Compress))
    [Console]::Out.Flush()
}

Write-NativeFixtureBoundary 'begin' 'import/Common'
. (Join-Path $PSScriptRoot '..\Common.ps1')
Write-NativeFixtureBoundary 'end' 'import/Common'
Write-NativeFixtureBoundary 'begin' 'import/MicroSliceValidation'
. (Join-Path $PSScriptRoot '..\MicroSliceValidation.ps1')
Write-NativeFixtureBoundary 'end' 'import/MicroSliceValidation'
Write-NativeFixtureBoundary 'begin' 'import/GameplayValidation'
. (Join-Path $PSScriptRoot '..\GameplayValidation.ps1')
Write-NativeFixtureBoundary 'end' 'import/GameplayValidation'
Write-NativeFixtureBoundary 'begin' 'import/GameplayRuntimeFixtures'
. (Join-Path $PSScriptRoot 'GameplayRuntimeFixtures.ps1')
Write-NativeFixtureBoundary 'end' 'import/GameplayRuntimeFixtures'
Write-NativeFixtureBoundary 'begin' 'initialize-suite'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$directory = Join-Path $root ('tools\godot\runtime\gameplay-native-helper-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$checks = [Collections.Generic.List[object]]::new()
$complete = $false
$failure = $null
$sources = @{}
$diagnostics = @{}
$fixtures = @{}
# Independent case list: do not derive fixture coverage from the reader or report.expected_cases.
$cameraCaseIds = @(
    'broadcast-framing/0', 'broadcast-framing/1'
    'corner/0/2', 'corner/0/3', 'corner/0/4', 'corner/0/5'
    'corner/1/2', 'corner/1/3', 'corner/1/4', 'corner/1/5'
    'expiry-reset/0', 'expiry-reset/1', 'legacy-counterexample'
    'lifecycle/0', 'lifecycle/1', 'opponent/0', 'opponent/1'
    'trace/0/2/1', 'trace/0/2/2', 'trace/0/3/1', 'trace/0/3/2'
    'trace/0/4/1', 'trace/0/4/2', 'trace/0/5/1', 'trace/0/5/2'
    'trace/1/2/1', 'trace/1/2/2', 'trace/1/3/1', 'trace/1/3/2'
    'trace/1/4/1', 'trace/1/4/2', 'trace/1/5/1', 'trace/1/5/2'
) | Sort-Object -CaseSensitive

function Add-NativeFixtureTiming([string]$Phase, [long]$Started) {
    $milliseconds = ([Diagnostics.Stopwatch]::GetTimestamp() - $Started) * 1000.0 / [Diagnostics.Stopwatch]::Frequency
    if (-not $nativeTraceSpans.Contains($Phase)) {
        $nativeTraceSpans[$Phase] = @{calls = 0; milliseconds = 0.0; maximumMilliseconds = 0.0}
    }
    $span = $nativeTraceSpans[$Phase]
    $span.calls++
    $span.milliseconds += $milliseconds
    $span.maximumMilliseconds = [Math]::Max($span.maximumMilliseconds, $milliseconds)
    Write-NativeFixtureBoundary 'end' $Phase
}

function Get-NativeFixtureTimingSummary {
    return @($nativeTraceSpans.GetEnumerator() | Sort-Object Name | ForEach-Object {
        [ordered]@{
            phase = $_.Key; calls = $_.Value.calls
            milliseconds = [Math]::Round($_.Value.milliseconds, 3)
            maximumMilliseconds = [Math]::Round($_.Value.maximumMilliseconds, 3)
        }
    })
}

function Check([string]$Name, [bool]$Passed) {
    $checks.Add(@{name = $Name; passed = $Passed})
    if ($TraceTimings) {
        $elapsed = $nativeTraceClock.ElapsedMilliseconds
        $nativeTraceProcess.Refresh()
        $cpu = $nativeTraceProcess.TotalProcessorTime.TotalMilliseconds
        Write-Host ("NATIVE_FIXTURE_TIMING {0} {1}ms +{2}ms cpu+{3}ms {4}" -f $checks.Count, $elapsed,
            ($elapsed - $script:nativeTraceLastMilliseconds),
            [Math]::Round($cpu - $script:nativeTraceLastCpuMilliseconds, 3), $Name)
        $script:nativeTraceLastMilliseconds = $elapsed
        $script:nativeTraceLastCpuMilliseconds = $cpu
        if ($checks.Count % 25 -eq 0) {
            Write-Host ('NATIVE_FIXTURE_PROFILE ' + ((Get-NativeFixtureTimingSummary) | ConvertTo-Json -Compress -Depth 5))
        }
    }
    if (-not $Passed) { throw "FAIL $Name" }
}

function Rejected([string]$Name, [scriptblock]$Action) {
    Write-NativeFixtureBoundary 'begin' 'negative-case' $Name
    $rejected = $false
    try { & $Action | Out-Null }
    catch {
        $cause = $_.Exception
        while ($null -ne $cause.InnerException) { $cause = $cause.InnerException }
        if ($cause -is [IO.IOException]) { throw }
        $rejected = $true
    }
    Check $Name $rejected
}

function Add-NativeFixtureCheck($Report, [string]$Name, [bool]$Negative = $false) {
    $Report['checks'] += @{name = $Name; passed = $true; negative = $Negative}
    $Report['total'] = $Report['checks'].Count
    $Report['passed'] = $Report['total']
}

function New-NativeFixture {
    return @{
        ok = $true; complete = $true; passed = 0; total = 0; checks = @(); failures = @()
        engine = '4.7.2-stable (official)'; headless = $true; process_id = $PID
        physics = 'Jolt Physics'; physics_hz = 60; wall_seconds = 1.0
    }
}

function New-NativeResult($Report, [string]$Stage) {
    Write-NativeFixtureBoundary 'begin' "encode-payload/$Stage"
    # Literal producer transport: the host inheritance chain prints failures,
    # not successful checks; its report still serializes every individual check.
    $lines = if ($Stage -cin @('camera', 'gameplay-runtime')) { @() } else {
        @($Report['checks'] | ForEach-Object { 'PASS ' + $_['name'] })
    }
    $lines += (Get-GodotNativeReportPrefix $sources[$Stage]) + ' ' + ($Report | ConvertTo-Json -Depth 48 -Compress)
    $errors = @()
    foreach ($kind in @('aimGuideErrors', 'developmentWarnings')) {
        foreach ($message in $diagnostics[$Stage][$kind].Keys) {
            for ($index = 0; $index -lt $diagnostics[$Stage][$kind][$message]; $index++) {
                $errors += $message
                $errors += '   at: push_error (core/variant/variant_utility.cpp:1024)'
            }
        }
    }
    $encoded = [pscustomobject]@{Stdout = $lines -join "`n"; Stderr = $errors -join "`n"; ExitCode = 0}
    Write-NativeFixtureBoundary 'end' "encode-payload/$Stage"
    return $encoded
}

function Read-NativeFixture([string]$Stage, $Report = $null, $Result = $null) {
    if ($null -eq $Report) { $Report = $fixtures[$Stage] }
    if ($null -eq $Result) {
        Write-NativeFixtureBoundary 'begin' "encode/$Stage"
        if ($TraceTimings) { $nativeEncodeStarted = [Diagnostics.Stopwatch]::GetTimestamp() }
        try { $Result = New-NativeResult $Report $Stage }
        finally { if ($TraceTimings) { Add-NativeFixtureTiming "encode/$Stage" $nativeEncodeStarted } }
    }
    Write-NativeFixtureBoundary 'begin' "decode/$Stage"
    if ($TraceTimings) { $nativeDecodeStarted = [Diagnostics.Stopwatch]::GetTimestamp() }
    try { return Read-GodotGameplayNativeReport $Result $Stage $sources[$Stage] $diagnostics[$Stage] }
    finally { if ($TraceTimings) { Add-NativeFixtureTiming "decode/$Stage" $nativeDecodeStarted } }
}

function Reject-Native([string]$Stage, [string]$Name, [scriptblock]$Mutate) {
    Write-NativeFixtureBoundary 'begin' "clone/$Stage" $Name
    if ($TraceTimings) { $nativeCloneStarted = [Diagnostics.Stopwatch]::GetTimestamp() }
    try { $report = CopyFixture $fixtures[$Stage] }
    finally { if ($TraceTimings) { Add-NativeFixtureTiming "clone/$Stage" $nativeCloneStarted } }
    Write-NativeFixtureBoundary 'begin' "mutate/$Stage" $Name
    & $Mutate $report | Out-Null
    Write-NativeFixtureBoundary 'end' "mutate/$Stage" $Name
    Rejected "$Stage $Name" { Read-NativeFixture $Stage $report }
}

function New-NativeHostFixture([string]$Stage) {
    $report = New-NativeFixture
    $report['expected_cases'] = if ($Stage -ceq 'camera') { @($cameraCaseIds) } else { @(Get-GodotNativeHostCases $Stage) }
    $report['completed_cases'] = @($report['expected_cases'])
    $report['main_scene'] = 'res://match/match.tscn'
    $report['native_events'] = @{key = 100; joy_button = 50; joy_motion = 40}
    $report['mouse_events'] = 8
    $report['expected_development_errors'] = $(if ($Stage -ceq 'camera') { 0 } else { 1 })
    foreach ($field in @('unexpected_integration_errors', 'unexpected_command_refusals', 'command_refusals',
            'expected_command_refusals', 'camera_samples', 'transition_samples', 'athlete_presentations')) { $report[$field] = @() }
    $report['trace_coverage'] = @{}
    foreach ($case in $report['expected_cases']) { Add-NativeFixtureCheck $report ("recorrido finito, caso único: " + $case) }
    foreach ($name in @('G01 default intacto antes de resets: FREE_PLAY, 0/10/9',
            'G25 D física mueve el default antes de un drill', 'G25 liberación física frena el default',
            'suite completa, ningún caso perdido por aborto asíncrono', 'diagnósticos exactos hasta la finalización',
            'identificadores de comprobación únicos hasta la finalización')) {
        Add-NativeFixtureCheck $report $name
    }
    if ($Stage -ceq 'camera') { Add-NativeFixtureCheck $report 'contraejemplo rechazado fue ejercitado por cámaras nativas' }
    return $report
}

function Add-HomeDribbleFixture($Report) {
    # Independent literal matrix and assertions. Never obtain these from the
    # consumer's G02 catalogue or copy a green native report into the fixture.
    $rows = @(
        @{name = 'G02 HOME forbidden dribble pace outside carry exclusion'; family = 'forbidden'; ball = '(17.45, 0.12, 0.0)'},
        @{name = 'G02 HOME forbidden dribble neutral pace outside carry exclusion'; family = 'forbidden'; ball = '(17.45, 0.12, 0.0)'},
        @{name = 'G02 HOME forbidden dribble pace inside carry exclusion'; family = 'forbidden'; ball = '(19.05, 0.12, 0.0)'},
        @{name = 'G02 HOME forbidden dribble cut from negative side outside exclusion'; family = 'forbidden'; ball = '(16.9, 0.12, -1.45)'},
        @{name = 'G02 HOME forbidden dribble cut from positive side outside exclusion'; family = 'forbidden'; ball = '(16.9, 0.12, 1.45)'},
        @{name = 'G02 HOME cut with inherited velocity side=-1.0'; family = 'inertia'; ball = '(16.9, 0.12, -1.55)'},
        @{name = 'G02 HOME cut with inherited velocity side=1.0'; family = 'inertia'; ball = '(16.9, 0.12, 1.55)'},
        @{name = 'G02 HOME dribble turns goalward before contact side=-1.0'; family = 'execution'; ball = '(17.45, 0.12, -1.75)'},
        @{name = 'G02 HOME dribble turns goalward before contact side=1.0'; family = 'execution'; ball = '(17.45, 0.12, 1.75)'},
        @{name = 'G02 legal unselected HOME dribble retreat inside exclusion'; family = 'legal'; ball = '(17.95, 0.12, 0.0)'},
        @{name = 'G02 legal unselected HOME dribble advance beside goal mouth'; family = 'legal'; ball = '(17.45, 0.12, 2.4)'},
        @{name = 'G02 legal unselected HOME dribble negative cut inside exclusion'; family = 'legal'; ball = '(19.05, 0.12, 0.0)'},
        @{name = 'G02 legal unselected HOME dribble positive cut inside exclusion'; family = 'legal'; ball = '(19.05, 0.12, 0.0)'},
        @{name = 'G02 legal physical dribble goal selected field pace'; family = 'goal'; ball = '(17.45, 0.12, 0.0)'; actor = 0; velocity = '(7.8, 0.0, 0.0)'},
        @{name = 'G02 legal physical dribble goal AWAY pace at opposite end'; family = 'goal'; ball = '(-17.45, 0.12, 0.0)'; actor = 1; velocity = '(-7.8, 0.0, 0.0)'},
        @{name = 'G02 legal physical dribble goal selected HOME keeper pace'; family = 'goal'; ball = '(17.45, 0.12, 0.0)'; actor = 2; velocity = '(7.8, 0.0, 0.0)'},
        @{name = 'G02 legal physical dribble goal selected field cut from negative side'; family = 'goal'; ball = '(16.9, 0.12, -1.45)'; actor = 0; velocity = '(4.8, 0.0, 0.3)'},
        @{name = 'G02 legal physical dribble goal selected field cut from positive side'; family = 'goal'; ball = '(16.9, 0.12, 1.45)'; actor = 0; velocity = '(4.8, 0.0, -0.3)'},
        @{name = 'G02 mirrored HOME dribble after a public corner and reception'; family = 'mirror'; ball = '(-19.85, 0.12, -9.85)'},
        @{name = 'G02 accidental HOME body deflection remains a goal'; family = 'accidental'; ball = '(18.4, 0.4, 0.0)'}
    )
    $familyChecks = @{
        forbidden = @(
            'public fixture owns the reachable ball with HOME unselected and AI off'
            'initial dribble refusal preserves state, sequence and events'
            'refusal never releases an impulse or consumes gesture recovery'
            'same rejected sequence can queue a legal dribble on the next tick'
            'retry produces one real cut rather than a stale forbidden impulse'
            'no stale goalward impulse scores after the safe retry'
        )
        inertia = @(
            'public lateral movement builds actual cut inertia'
            'nominal cut misses but observed body inertia aims through the mouth'
            'inertial cut refusal is atomic'
            'no cut impulse is hidden behind its nominal lateral direction'
        )
        execution = @(
            'current physical forward ray misses the goal before the queued turn'
            'safe current impulse is accepted before the native turn'
            'execution revalidates the new heading before release and recovery'
            'deferred refusal prevents a goal without rewriting physics or score'
            'execution refusal leaves recovery available to the next safe cut'
            'new lateral intent releases the ball physically'
        )
        legal = @(
            'legal fixture still has the unselected HOME owner'
            'non-finishing dribble is accepted rather than blanket banned'
            'accepted gesture carries its real contact and directional impulse'
            'ball physically travels in the legal direction without focus or teleport'
        )
        goal = @(
            'legal finisher owns the ball with no AI or goalkeeper in its path'
            'selected HOME or AWAY retains the threatening dribble'
            'legal finish comes from the actual dribble impulse'
            'native complete-ball crossing proves the threatened goal is reachable'
        )
        mirror = @(
            'mirrored corner enters live play with a real pass to the carrier'
            'public switch restores selection before the receiver owns the ball'
            'received carrier can face the mirrored attacking goal'
            'public mirrored fixture is outside exclusion with HOME unselected'
            'mirrored refusal preserves physical state and sequence'
            'mirrored unselected carrier receives no dribble impulse'
            'actual human selection unlocks the same mirrored carrier'
            'same rejected dribble is legal for the newly selected HOME actor'
            'human mirrored dribble releases actual negative-X velocity'
            'negative-end native dribble goal belongs to mirrored HOME'
        )
        accidental = @(
            'real uncommanded body collision precedes the complete-ball crossing'
            'physical accidental HOME goal is not erased by finishing policy'
        )
    }
    $refusals = @{
        forbidden = 'goal-directed physical dribble'
        inertia = 'inertia makes the real cut a finish'
        execution = 'changed physical heading at execution'
        mirror = 'HOME finish toward the mirrored negative end'
    }
    foreach ($mode in @(0, 1)) {
        $carrier = if ($mode -eq 0) { 2 } else { 4 }
        foreach ($row in $rows) {
            $exercise = if ($row.family -ceq 'mirror') { 4 } else { 0 }
            $scope = "$($row.name); mode=$mode; exercise=$exercise"
            $scenario = @{
                name = $scope; mode = $mode; exercise = $exercise; start_error = 0
                ball = $row.ball; velocity = '(0.0, 0.0, 0.0)'
            }
            Add-NativeFixtureCheck $Report "$scope/production start"
            foreach ($check in $familyChecks[$row.family]) { Add-NativeFixtureCheck $Report "$scope/$check" }
            if ($refusals.Contains($row.family)) {
                $label = $refusals[$row.family]
                $record = @{
                    scope = $scope; actor_id = $carrier; code = 4; message = 'Allied dribble cannot intentionally finish'
                    matched = $true
                    expected = @{name = "$scope/$label"; actor_id = $carrier; code = 4; message = 'Allied dribble cannot intentionally finish'}
                }
                $Report['negative_cases'] += $record
                # Deferred execution is witnessed by the existing revalidation
                # assertion, not _reject_command's synchronous return check.
                if ($row.family -cne 'execution') { Add-NativeFixtureCheck $Report "$scope/expected refusal $label" }
            }
            if ($row.family -ceq 'goal') {
                $scenario['native_dribble_goal'] = @{actor_id = $row.actor; dribble_tick = 10; goal_tick = 31; velocity = $row.velocity}
                if ($row.actor -eq 2) {
                    Add-NativeFixtureCheck $Report "$scope/public off-ball switch selects the keeper, not an origin flag"
                    Add-NativeFixtureCheck $Report "$scope/keeper becomes the actual current human"
                }
            }
            if ($row.family -ceq 'mirror') {
                $scenario['native_dribble_goal'] = @{actor_id = $carrier; dribble_tick = 130; goal_tick = 154; velocity = '(-7.8, 0.0, 0.0)'}
            }
            if ($row.family -ceq 'accidental') {
                $scenario['velocity'] = '(-31.0, 0.0, 0.0)'
                $scenario['native_deflection_goal'] = @{actor_id = $carrier; contact_tick = 10; goal_tick = 18}
            }
            $Report['scenarios'] += $scenario
        }
    }
}

try {
    Write-NativeFixtureBoundary 'begin' 'load-source-contracts'
    $stages = Get-GodotGameplayStages $root
    foreach ($stage in @('ai-tactics', 'rules', 'gameplay-rules', 'camera', 'gameplay-runtime', 'aim-guide')) {
        Write-NativeFixtureBoundary 'begin' "load-source/$stage"
        $sources[$stage] = [IO.File]::ReadAllText((Join-Path $root $stages[$stage]))
        $diagnostics[$stage] = Get-GodotGameplayNativeDiagnostics $stage $root
        Write-NativeFixtureBoundary 'end' "load-source/$stage"
    }
    Assert-GodotHudDiagnosticSource ([IO.File]::ReadAllText((Join-Path $root 'game\tests\test_match_hud.gd'))) `
        ([IO.File]::ReadAllText((Join-Path $root 'game\match\presentation\hud\match_hud.gd')))
    Check 'new HUD restart policy is bound to its actual source matrix and constant' $true
    Check 'aim diagnostics derive from the actual invalid-input list, not total assertions' (
        @($diagnostics['aim-guide'].aimGuideErrors.Values)[0] -eq (Get-GodotAimGuideNegativeCases).Count)
    $lookupReport = @{checks = @(@{name = 'Exact lookup'; passed = $true})}
    Assert-GodotNativeCheck $lookupReport 'Exact lookup'
    Check 'native check lookup accepts the actual exact-name boolean assertion' $true
    $lookupReport['checks'][0]['passed'] = $false
    Rejected 'native check lookup reobserves a changed status on the same report object' {
        Assert-GodotNativeCheck $lookupReport 'Exact lookup'
    }
    $lookupReport['checks'][0]['passed'] = 'true'
    Rejected 'native check lookup cannot coerce a nonempty string into passed=true' {
        Assert-GodotNativeCheck $lookupReport 'Exact lookup'
    }
    $lookupReport['checks'][0]['passed'] = $true
    $lookupReport['checks'][0]['name'] = 'exact lookup'
    Rejected 'native check lookup remains case-sensitive after an in-place rename' {
        Assert-GodotNativeCheck $lookupReport 'Exact lookup'
    }
    Assert-GodotNativeCheck $lookupReport 'exact lookup'
    Check 'native check lookup observes the current renamed identity without a stale index' $true
    $lookupReport['checks'] += @{name = 'exact lookup'; passed = $true}
    Rejected 'native check lookup detects a duplicate added after a successful lookup' {
        Assert-GodotNativeCheck $lookupReport 'exact lookup'
    }
    Check 'only the declared native invalid-exercise path permits its exact warning' (
        $diagnostics['gameplay-runtime'].developmentWarnings.Count -eq 1 -and
        $diagnostics['camera'].developmentWarnings.Count -eq 0)
    Rejected 'changing a guide invalid-input identity requires an explicit policy review' {
        Get-GodotAimGuideExpectedErrors $sources['aim-guide'].Replace('"speed_mismatch"', '"unreviewed"') `
            ([IO.File]::ReadAllText((Join-Path $root 'game\match\presentation\aim\world_aim_guide.gd')))
    }
    Write-NativeFixtureBoundary 'begin' 'build-fixture/ai-tactics'
    $report = New-NativeFixture
    $report['scope'] = 'playing-and-restart-ai-policy-with-caller-filter'
    $report['production_entrypoint'] = 'MatchAI.decide'
    $report['authority_guard_tested'] = $false
    $report['policy_decisions'] = 1
    $report['observed_refusals'] = 0
    $report['command_refusals'] = @()
    $expected = [int][regex]::Match($sources['ai-tactics'], 'const EXPECTED_CHECKS: int = ([0-9]+)').Groups[1].Value
    $negatives = [int][regex]::Match($sources['ai-tactics'], 'const EXPECTED_NEGATIVE_CASES: int = ([0-9]+)').Groups[1].Value
    for ($index = 0; $index -lt $expected - 5; $index++) {
        Add-NativeFixtureCheck $report "synthetic AI classification $index" ($index -lt $negatives)
    }
    foreach ($name in @('native_headless_jolt_sixty_hz_environment', 'production_caller_reports_zero_unexpected_command_refusals',
            'report_semantic_check_names_are_unique', 'report_negative_case_count_matches_contract', 'report_semantic_case_count_matches_contract')) {
        Add-NativeFixtureCheck $report $name
    }
    $report['expected_checks'] = $expected; $report['negative_cases'] = $negatives; $report['expected_negative_cases'] = $negatives
    foreach ($field in @('expected_errors', 'expected_warnings', 'expected_refusals')) { $report[$field] = 0 }
    $fixtures['ai-tactics'] = $report

    Write-NativeFixtureBoundary 'begin' 'build-fixture/rules'
    $report = New-NativeFixture
    $report['scope'] = 'pure-match-rules-contract'; $report['physical_episode_collection_tested'] = $false
    $report['groups'] = @()
    foreach ($field in @('expected_errors', 'expected_warnings', 'expected_refusals', 'negative_cases')) { $report[$field] = 0 }
    Add-NativeFixtureCheck $report 'native_headless_environment'
    # Independent reviewed matrix: never generate the fixture with the reader's own name regex.
    $ruleGroups = [ordered]@{
        crossings = @(14, 7); boundaries = @(31, 4); direct_goals = @(30, 11); fouls = @(28, 8)
        foul_tuning_addendum = @(13, 8); spots = @(22, 4); expiry = @(26, 18)
        second_touch_and_extension = @(28, 24); g10_episode_identity = @(44, 20)
        placement_and_guards = @(55, 18); corner_orientations = @(8, 0); copies = @(4, 0)
    }
    foreach ($name in $ruleGroups.Keys) {
        $count = $ruleGroups[$name][0]; $negative = $ruleGroups[$name][1]
        $report['groups'] += @{name = $name; actual = $count; expected = $count; actual_negatives = $negative; expected_negatives = $negative}
        for ($index = 0; $index -lt $count; $index++) { Add-NativeFixtureCheck $report ($name + "_synthetic_$index") ($index -lt $negative) }
        Add-NativeFixtureCheck $report ($name + '_exact_case_count')
        Add-NativeFixtureCheck $report ($name + '_exact_negative_count')
        $report['negative_cases'] += $negative
    }
    Add-NativeFixtureCheck $report 'semantic_names_are_unique'
    $report['expected_checks'] = $report['total']; $report['expected_negative_cases'] = $report['negative_cases']
    $fixtures['rules'] = $report
    Check 'independent rules fixture covers twelve groups, 329 checks and 122 classifications including G10' (
        $report['groups'].Count -eq 12 -and $report['total'] -eq 329 -and $report['negative_cases'] -eq 122 -and
        $ruleGroups.Contains('g10_episode_identity'))

    Write-NativeFixtureBoundary 'begin' 'build-fixture/aim-guide'
    $report = New-NativeFixture
    foreach ($case in Get-GodotAimGuideNegativeCases) { Add-NativeFixtureCheck $report "invalid $case hides every stale arrow" }
    Add-NativeFixtureCheck $report 'aim guide suite reached completion'
    $message = @($diagnostics['aim-guide'].aimGuideErrors.Keys)[0]
    $report['expected_validation_errors'] = $diagnostics['aim-guide'].aimGuideErrors[$message]
    $report['new_expected_error_counts'] = @{($message.Substring(7)) = $report['expected_validation_errors']}
    $fixtures['aim-guide'] = $report

    Write-NativeFixtureBoundary 'begin' 'build-fixture/gameplay-rules'
    $report = New-NativeFixture
    $report['scenarios'] = @(); $report['negative_cases'] = @(); $report['duplicate_names'] = $false
    $report['unexpected_refusals'] = @(); $report['pending_refusals'] = @()
    $report['selected_groups'] = @(
        'foul_tuning', 'catalogue', 'finishing_guards', 'touch_and_query', 'boundaries_and_mirror',
        'expiry_and_choices', 'opponent_ready', 'hand_ownership', 'direct_goals', 'release_episode_continuity',
        'separate_touches', 'dribbles', 'physical_fouls', 'seventh_foul', 'extensions', 'extended_expiry', 'world_isolation'
    )
    $report['diagnostics'] = @(); $report['pending_step_budget'] = 0
    $report['requested_physics_steps'] = 100; $report['physics_steps'] = 103
    $report['watchdog_failure'] = ''; $report['watchdog_probe'] = $false
    $refusalPolicy = Get-GodotGameplayAuthorityRefusalPolicy
    foreach ($mode in @(0, 1)) {
        foreach ($label in @($refusalPolicy.Keys) + @('out-of-domain configuration')) {
            $scope = "synthetic $label; mode=$mode; exercise=0"
            if ($label -ceq 'out-of-domain configuration') {
                $scope = "G28 rejected foul tuning foul_min_closing_speed below minimum; mode=$mode"
                $rule = @{code = 31; message = 'foul_min_closing_speed must be finite and within [0.1, 4]'; assertion = 'production start refuses invalid tuning without changing the active world'}
            }
            else { $rule = $refusalPolicy[$label] }
            $actor = if ($label -in @('unknown exercise', 'unordered thresholds', 'out-of-domain configuration')) { -1 } else { 0 }
            $record = @{scope = $scope; actor_id = $actor; code = $rule.code; message = $rule.message; matched = $true}
            $record['expected'] = @{name = "$scope/$label"; actor_id = $actor; code = $rule.code; message = $rule.message}
            $report['negative_cases'] += $record
            $assertion = if ($rule.Contains('assertion')) { $rule.assertion } else { 'expected refusal ' + $label }
            Add-NativeFixtureCheck $report ($scope + '/' + $assertion)
        }
        foreach ($exercise in 0..11) {
            $name = "G01/G08/G30/G32 catalogue; mode=$mode; exercise=$exercise"
            $report['scenarios'] += @{name = $name; mode = $mode; exercise = $exercise; start_error = 0; ball = '(0, 0.1, 0)'; velocity = '(0, 0, 0)'}
            Add-NativeFixtureCheck $report "$name/production start"
        }
        foreach ($label in @('ordinary', 'gentle', 'expired', 'clean', 'late', 'reckless', 'penalty', 'historical', 'late_window')) {
            $name = "G20/G21/G28 physical $label; mode=$mode; exercise=0"
            $report['scenarios'] += @{name = $name; mode = $mode; exercise = 0; start_error = 0; ball = '(0, 0.1, 0)'; velocity = '(0, 0, 0)'}
            Add-NativeFixtureCheck $report "$name/production start"
            Add-NativeFixtureCheck $report "$name/ACTOR_ACTOR evidence comes from a real kinematic collision"
        }
        $episodeCases = Get-GodotGameplayEpisodeCases
        foreach ($prefix in $episodeCases.Keys) {
            $rule = $episodeCases[$prefix]
            $name = "$prefix; mode=$mode; exercise=$($rule.exercise)"
            $scenario = @{name = $name; mode = $mode; exercise = $rule.exercise; start_error = 0;
                ball = '(0, 0.1, 0)'; velocity = '(0, 0, 0)'; launch_contact_id = 700}
            if ($rule.secondContact) {
                $scenario['native_second_contact'] = @{contact_id = 705; tick = 90; actor_id = 0; surface = 'athlete'}
            }
            $report['scenarios'] += $scenario
            Add-NativeFixtureCheck $report "$name/production start"
            foreach ($check in $rule.checks) { Add-NativeFixtureCheck $report "$name/$check" }
        }
    }
    Add-HomeDribbleFixture $report
    $report['expected_refusals'] = $report['negative_cases'].Count
    Add-NativeFixtureCheck $report 'completion/every refusal matches an exact actor/code/message expectation'
    $fixtures['gameplay-rules'] = $report

    Write-NativeFixtureBoundary 'begin' 'build-fixture/camera'
    $report = New-NativeHostFixture 'camera'
    Check 'independent camera matrix has exactly 33 cases, two broadcast cases, sixteen traces and the counterexample' (
        $cameraCaseIds.Count -eq 33 -and @($cameraCaseIds | Where-Object { $_ -like 'trace/*' }).Count -eq 16 -and
        (@(Get-GodotNativeHostCases 'camera') -join "`n") -ceq ($cameraCaseIds -join "`n") -and
        'legacy-counterexample' -cin $cameraCaseIds)
    foreach ($mode in @(0, 1)) {
        $caseId = "broadcast-framing/$mode"
        $height = if ($mode -eq 0) { 17.0 } else { 18.0 }
        $distance = if ($mode -eq 0) { 23.0 } else { 25.0 }
        foreach ($end in @(-1.0, 1.0)) {
            foreach ($side in @(-1.0, 1.0)) {
                foreach ($selected in @(0, 2)) {
                    $camera = @{
                        mode = 'broadcast'; tick = 4; fov = 60.0
                        position = @(0.0, ($height * 3.0), ($distance * 3.0))
                        rotation = @((-[Math]::Atan2($height, $distance)), 0.0, 0.0)
                        look_target = @(0.0, 0.0, 0.0); tracked_ball = @(($end * 19.85), 0.105, ($side * 8.0))
                    }
                    $report['camera_samples'] += @{
                        case = $caseId; end = $end; side = $side; selected_actor_id = $selected
                        tested_points = $(if ($mode -eq 0) { 16 } else { 88 }); outside_count = 0; camera = $camera
                    }
                    $label = "$caseId extremo=$([int]$end) banda=$([int]$side) foco=$selected"
                    Add-NativeFixtureCheck $report "$label conserva la orientación fija usada para calcular el encuadre"
                    Add-NativeFixtureCheck $report "$label no recorta extremos de atletas ni esfera del balón"
                }
            }
        }
        Add-NativeFixtureCheck $report "$caseId no modifica actores ni estado del partido real"
    }
    $samples = [Collections.Generic.List[object]]::new()
    foreach ($id in @($report['expected_cases'] | Where-Object { $_.StartsWith('trace/') })) {
        $mode = [int]$id.Split('/')[1]
        $report['trace_coverage'][$id] = @{entry_ticks = @(0..60); return_ticks = @(0..46); receiver_id = 2;
            ready_actor_ids = $(if ($mode -eq 0) { @(0..3) } else { @(0..9) })}
        foreach ($direction in @('entry', 'return')) {
            $last = if ($direction -ceq 'entry') { 60 } else { 46 }
            foreach ($elapsed in 0..$last) {
                $camera = @{position = @(0.0, 0.0, 10.0); rotation = @(0.0, 0.0, 0.0); fov = 60.0;
                    look_target = @(0.0, 0.0, 0.0); tracked_ball = @(0.0, 0.0, 0.0);
                    tick = $elapsed + $(if ($direction -ceq 'entry') { 0 } else { 61 })}
                $samples.Add(@{case = $id; direction = $direction; elapsed = $elapsed; camera = $camera; ball = @(0.0, 0.0, 0.0);
                    screen = @(0.5, 0.5); behind = $false; sphere_in_frame = $true; travel = 0.0; turn_radians = 0.0; blockers = @()})
            }
        }
    }
    $report['transition_samples'] = $samples.ToArray()
    $fixtures['camera'] = $report

    Write-NativeFixtureBoundary 'begin' 'build-fixture/gameplay-runtime'
    $report = New-NativeHostFixture 'gameplay-runtime'
    Add-NativeFixtureCheck $report 'diagnóstico exacto de negativa: G30 ejercicio fuera de catálogo'
    foreach ($mode in @(0, 1)) {
        foreach ($pair in @(@('secuencia repetida', 31, 'Sequence must increase per actor within [0, 2147483647]'),
                @('pase prohibido en READY', 4, 'Launch refused: launch_rule'))) {
            $label = "G09/G22 m$mode sexta acumulada: $($pair[0])"
            $report['command_refusals'] += @{id = 0; code = $pair[1]; message = $pair[2]}
            $report['expected_command_refusals'] += @{id = 0; code = $pair[1]; message = $pair[2]; case = $label}
            Add-NativeFixtureCheck $report $label
        }
        Add-NativeFixtureCheck $report "G09/G22 m$mode sexta acumulada: rechazo real de autoridad: aviso producido por la ruta real es visible"
        Add-NativeFixtureCheck $report "G09/G22 m$mode sexta acumulada: mostrar el rechazo no pausa ni renueva cuatro segundos"
    }
    $policy = Get-GodotGameplayCasePolicy
    $group = New-GpFixtureCaseGroup $policy['m0/dribble_left_contact'] 1
    $progress = @($group.poses | Where-Object { $_.Contains('advanced') })[0]
    $contact = CopyFixture $progress.at_contact
    $advanced = CopyFixture $progress.advanced
    $report['athlete_presentations'] = @(@{case = 'synthetic native gesture'; event_id = 1; accepted_tick = $contact.contact_tick; at_contact = $contact; advanced = $advanced})
    $fixtures['gameplay-runtime'] = $report

    Write-NativeFixtureBoundary 'end' 'build-fixtures'
    foreach ($stage in $fixtures.Keys) {
        Write-NativeFixtureBoundary 'begin' "stage/$stage"
        $parsed = Read-NativeFixture $stage
        Check "$stage complete source-shaped synthetic report passes its production consumer" ($parsed['total'] -eq $fixtures[$stage]['total'])
        foreach ($field in @('ok', 'passed', 'total')) {
            Reject-Native $stage "rejects nonnative $field" { param($r) $r[$field] = [string]$r[$field] }
        }
        Reject-Native $stage 'requires an explicit empty failure list' { param($r) [void]$r.Remove('failures') }
        Reject-Native $stage 'requires actual individual checks rather than aggregate totals' { param($r) [void]$r.Remove('checks') }
        Reject-Native $stage 'does not count a duplicate assertion twice' {
            param($r) $r['checks'] += CopyFixture $r['checks'][0]; $r['total']++; $r['passed']++
        }
        $raw = New-NativeResult $fixtures[$stage] $stage
        $raw.Stderr += "`nWARNING: Jolt job limit reached"
        Rejected "$stage arbitrary Jolt warning is still a native failure" { Read-NativeFixture $stage -Result $raw }
        $raw = New-NativeResult $fixtures[$stage] $stage
        if ($stage -cin @('camera', 'gameplay-runtime')) {
            Check "$stage fixture reflects native structured-only successes, not invented PASS lines" (
                $raw.Stdout -notmatch '(?m)^(?:PASS|FAIL) ')
            $raw.Stdout = "FAIL failure concealed by a green summary`n" + $raw.Stdout
            Rejected "$stage green JSON cannot hide a printed native failure" { Read-NativeFixture $stage -Result $raw }
            $raw = New-NativeResult $fixtures[$stage] $stage
            $raw.Stdout = "PASS invented parallel assertion protocol`n" + $raw.Stdout
            Rejected "$stage does not replace its native structured transport with synthetic PASS output" {
                Read-NativeFixture $stage -Result $raw
            }
        }
        else {
            $raw.Stdout = $raw.Stdout -replace '(?m)^PASS [^\r\n]+\r?\n', ''
            Rejected "$stage JSON checks cannot replace absent native printed assertions" { Read-NativeFixture $stage -Result $raw }
        }
        $raw = New-NativeResult $fixtures[$stage] $stage
        $raw.ExitCode = 1
        Rejected "$stage report cannot conceal nonzero native exit" { Read-NativeFixture $stage -Result $raw }
    }
    foreach ($stage in @('ai-tactics', 'rules')) {
        Reject-Native $stage 'negative classifications do not authorize API refusals' { param($r) $r['expected_refusals'] = $r['negative_cases'] }
        Reject-Native $stage 'negative counts must agree with individual polarity records' { param($r) $r['checks'][1]['negative'] = -not $r['checks'][1]['negative'] }
        Reject-Native $stage 'classification flags must be actual booleans' { param($r) $r['checks'][1]['negative'] = 'true' }
    }
    Reject-Native 'rules' 'reported group counts cannot hide a missing group' { param($r) $r['groups'] = @($r['groups'] | Select-Object -Skip 1) }
    Reject-Native 'rules' 'a negative-count label cannot stand in for actual group assertions' { param($r) $r['groups'][0]['actual_negatives']-- }
    Reject-Native 'rules' 'digit-bearing G10 group cannot disappear behind self-consistent totals' {
        param($r)
        $r['groups'] = @($r['groups'] | Where-Object { $_['name'] -cne 'g10_episode_identity' })
        $r['checks'] = @($r['checks'] | Where-Object { -not $_['name'].StartsWith('g10_episode_identity_', [StringComparison]::Ordinal) })
        $r['total'] = $r['passed'] = $r['expected_checks'] = $r['checks'].Count
        $r['negative_cases'] = $r['expected_negative_cases'] = @($r['checks'] | Where-Object { $_['negative'] }).Count
    }
    Reject-Native 'ai-tactics' 'observed AI refusals must remain zero' { param($r) $r['observed_refusals'] = 1 }
    Reject-Native 'ai-tactics' 'policy-only evidence cannot claim to test the authority finishing guard' { param($r) $r['authority_guard_tested'] = $true }
    foreach ($stage in @('aim-guide', 'gameplay-runtime')) {
        $raw = New-NativeResult $fixtures[$stage] $stage
        $raw.Stderr = ''
        Rejected "$stage missing declared raw diagnostic cannot be replaced by its report count" { Read-NativeFixture $stage -Result $raw }
        $raw = New-NativeResult $fixtures[$stage] $stage
        $raw.Stderr += "`n" + @($raw.Stderr -split "`n")[0]
        Rejected "$stage extra expected-looking diagnostic still fails" { Read-NativeFixture $stage -Result $raw }
        $raw = New-NativeResult $fixtures[$stage] $stage
        $raw.Stderr += "`nSCRIPT ERROR: unrelated failure"
        Rejected "$stage strict diagnostic allowance never hides an unrelated script fault" { Read-NativeFixture $stage -Result $raw }
    }
    Reject-Native 'aim-guide' 'requires each source-defined actual rejection assertion' { param($r) $r['checks'][0]['name'] = 'unrelated success' }
    Reject-Native 'aim-guide' 'expected error count must be an integer' { param($r) $r['expected_validation_errors'] = '15' }
    Reject-Native 'aim-guide' 'count dictionary cannot silently add another allowed message' {
        param($r) $r['new_expected_error_counts']['unrelated'] = 1
    }
    $raw = New-NativeResult $fixtures['aim-guide'] 'aim-guide'
    Rejected 'guide diagnostics remain prohibited without their explicit source-bound family' { Assert-GodotOutput $raw }
    Rejected 'guide errors cannot be smuggled through the independent HUD allowance' {
        Assert-GodotOutput $raw -ExpectedErrors $diagnostics['aim-guide'].aimGuideErrors
    }
    $wrong = @{ 'ERROR: WorldAimGuide.present: unreviewed failure' = 15 }
    Rejected 'guide diagnostic family rejects alternative sentences even with the right count' { Assert-GodotOutput $raw -ExpectedAimGuideErrors $wrong }
    foreach ($stage in @('camera', 'gameplay-runtime')) {
        Reject-Native $stage 'must complete the last source-defined scenario' { param($r) $r['completed_cases'] = @($r['completed_cases'] | Select-Object -SkipLast 1) }
        Reject-Native $stage 'requires the shared final uniqueness assertion despite consistent totals' {
            param($r)
            $r['checks'] = @($r['checks'] | Where-Object { $_['name'] -cne 'identificadores de comprobación únicos hasta la finalización' })
            $r['total'] = $r['passed'] = $r['checks'].Count
        }
        Reject-Native $stage 'requires the real default before any reset' {
            param($r) $r['checks'] | Where-Object { $_['name'].StartsWith('G01 default') } | ForEach-Object { $_['name'] = 'default after a reset' }
        }
    }
    Reject-Native 'gameplay-runtime' 'expected refusal labels cannot invent a different actual message' { param($r) $r['expected_command_refusals'][0]['message'] = 'invented' }
    Reject-Native 'gameplay-runtime' 'missing authority refusal is not accepted as a clean run' { param($r) $r['command_refusals'] = @() }
    $sourceCodes = @([regex]::Matches($sources['gameplay-runtime'],
        '(?m)^\t_command_negative_code = (ERR_[A-Z_]+)\r?$') | ForEach-Object { $_.Groups[1].Value })
    Check 'current source predeclares one sequence refusal and one unauthorized launch per mode, not new ERROR allowances' (
        ($sourceCodes -join ',') -ceq 'ERR_INVALID_PARAMETER,ERR_UNAUTHORIZED' -and
        $sources['gameplay-runtime'].Contains('_refusals[-1]["message"] == "Launch refused: launch_rule"') -and
        $sources['gameplay-runtime'].Contains('for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:'))
    $raw = New-NativeResult $fixtures['gameplay-runtime'] 'gameplay-runtime'
    Check 'source-shaped fixture accounts for two unauthorized signals plus two sequence signals with no stderr ERROR' (
        @($fixtures['gameplay-runtime']['command_refusals'] | Where-Object { $_['code'] -eq 4 }).Count -eq 2 -and
        @($fixtures['gameplay-runtime']['command_refusals'] | Where-Object { $_['code'] -eq 31 }).Count -eq 2 -and
        $raw.Stderr -notmatch '(?m)^ERROR:')
    foreach ($field in @('command_refusals', 'expected_command_refusals')) {
        Reject-Native 'gameplay-runtime' "cannot omit one source-defined unauthorized signal from $field" {
            param($r) $r[$field] = @($r[$field] | Select-Object -SkipLast 1)
        }
        Reject-Native 'gameplay-runtime' "cannot duplicate an unauthorized signal in $field" {
            param($r) $r[$field] += CopyFixture $r[$field][1]
        }
    }
    Reject-Native 'gameplay-runtime' 'unauthorized refusal actor cannot change in both actual and labelled records' {
        param($r)
        $r['command_refusals'][1]['id'] = 2
        $r['expected_command_refusals'][1]['id'] = 2
    }
    Reject-Native 'gameplay-runtime' 'unauthorized refusal code must be a native integer' {
        param($r) $r['command_refusals'][1]['code'] = '4'
    }
    Reject-Native 'gameplay-runtime' 'two mutually agreeing invented refusal messages do not replace the source contract' {
        param($r)
        $r['command_refusals'][1]['message'] = 'Launch refused: unrelated'
        $r['expected_command_refusals'][1]['message'] = 'Launch refused: unrelated'
    }
    Reject-Native 'gameplay-runtime' 'an unauthorized signal cannot be relabelled into the other mode' {
        param($r) $r['expected_command_refusals'][3]['case'] = $r['expected_command_refusals'][1]['case']
    }
    foreach ($suffix in @('rechazo real de autoridad: aviso producido por la ruta real es visible',
            'mostrar el rechazo no pausa ni renueva cuatro segundos')) {
        Reject-Native 'gameplay-runtime' "requires actual READY feedback evidence: $suffix" {
            param($r)
            $missing = "G09/G22 m0 sexta acumulada: $suffix"
            $r['checks'] = @($r['checks'] | Where-Object { $_['name'] -cne $missing })
            $r['passed'] = $r['total'] = $r['checks'].Count
        }
    }
    foreach ($prefix in @('ERROR', 'WARNING')) {
        $raw = New-NativeResult $fixtures['gameplay-runtime'] 'gameplay-runtime'
        $raw.Stderr += "`n${prefix}: Launch refused: launch_rule`n${prefix}: Launch refused: launch_rule"
        Rejected "two intended authority signals never authorize two stderr $prefix diagnostics" { Read-NativeFixture 'gameplay-runtime' -Result $raw }
    }
    $expanded = CopyFixture $fixtures['gameplay-runtime']
    Add-NativeFixtureCheck $expanded 'synthetic additional review assertion'
    $parsed = Read-NativeFixture 'gameplay-runtime' $expanded
    Check 'native host review can add a unique structured assertion without freezing a producer total' (
        $parsed['total'] -eq $fixtures['gameplay-runtime']['total'] + 1)
    $expanded['checks'][-1]['passed'] = $false
    Rejected 'an additional structured native assertion cannot fail behind green aggregate totals' {
        Read-NativeFixture 'gameplay-runtime' $expanded
    }
    Reject-Native 'gameplay-runtime' 'accepted gesture requires subsequent host context and pose progress' {
        param($r) $r['athlete_presentations'][0]['advanced'] = CopyFixture $r['athlete_presentations'][0]['at_contact']
    }
    Check 'runtime fixture retains 41 own cases and does not invent the camera-only counterexample' (
        $fixtures['gameplay-runtime']['expected_cases'].Count -eq 41 -and
        'legacy-counterexample' -cnotin $fixtures['gameplay-runtime']['expected_cases'] -and
        @($fixtures['gameplay-runtime']['checks'] | Where-Object {
            $_['name'] -ceq 'contraejemplo rechazado fue ejercitado por cámaras nativas'
        }).Count -eq 0)
    Reject-Native 'gameplay-runtime' 'an inherited red counterexample check is never filtered out as inapplicable' {
        param($r)
        $r['checks'] += @{name = 'contraejemplo rechazado fue ejercitado por cámaras nativas'; passed = $false; negative = $false}
        $r['total']++
    }
    Reject-Native 'camera' 'cannot opt out of the required legacy counterexample in its reported matrix' {
        param($r)
        foreach ($field in @('expected_cases', 'completed_cases')) {
            $r[$field] = @($r[$field] | Where-Object { $_ -cne 'legacy-counterexample' })
        }
    }
    Reject-Native 'camera' 'requires the actual counterexample finalization assertion' {
        param($r)
        $r['checks'] = @($r['checks'] | Where-Object { $_['name'] -cne 'contraejemplo rechazado fue ejercitado por cámaras nativas' })
        $r['total'] = $r['passed'] = $r['checks'].Count
    }
    Reject-Native 'camera' 'the old self-consistent 31-case matrix cannot replace the new broadcast regressions' {
        param($r)
        foreach ($field in @('expected_cases', 'completed_cases')) {
            $r[$field] = @($r[$field] | Where-Object { -not $_.StartsWith('broadcast-framing/', [StringComparison]::Ordinal) })
        }
        $r['camera_samples'] = @()
        $r['checks'] = @($r['checks'] | Where-Object { -not $_['name'].Contains('broadcast-framing/', [StringComparison]::Ordinal) })
        $r['total'] = $r['passed'] = $r['checks'].Count
    }
    Reject-Native 'camera' 'eight broadcast observations cannot stand in for both modes' {
        param($r) $r['camera_samples'] = @($r['camera_samples'] | Where-Object { $_['case'] -ceq 'broadcast-framing/0' })
    }
    Reject-Native 'camera' 'duplicate broadcast row cannot hide a missing end/side/focus combination' {
        param($r) $r['camera_samples'][1] = CopyFixture $r['camera_samples'][0]
    }
    foreach ($field in @('case', 'end', 'side', 'selected_actor_id', 'tested_points', 'outside_count', 'camera')) {
        Reject-Native 'camera' "broadcast observation cannot omit $field" { param($r) [void]$r['camera_samples'][0].Remove($field) }
    }
    foreach ($pair in @(@('case', 'broadcast-framing/2'), @('end', 0.0), @('end', '-1'), @('side', $true),
            @('selected_actor_id', 1), @('selected_actor_id', '0'), @('tested_points', 8), @('tested_points', '16'),
            @('outside_count', 1), @('outside_count', '0'))) {
        Reject-Native 'camera' "broadcast matrix rejects altered identity/count/type: $($pair[0])=$($pair[1])" {
            param($r) $r['camera_samples'][0][$pair[0]] = $pair[1]
        }
    }
    Reject-Native 'camera' 'preview cannot reduce all-ten-athlete bounds to selected-only micro coverage' {
        param($r) $r['camera_samples'][8]['tested_points'] = 16
    }
    foreach ($suffix in @('conserva la orientación fija usada para calcular el encuadre',
            'no recorta extremos de atletas ni esfera del balón', 'no modifica actores ni estado del partido real')) {
        Reject-Native 'camera' "broadcast native assertion cannot disappear behind a green outside count: $suffix" {
            param($r)
            $r['checks'] = @($r['checks'] | Where-Object {
                -not ($_.name.StartsWith('broadcast-framing/0', [StringComparison]::Ordinal) -and $_.name.EndsWith($suffix, [StringComparison]::Ordinal))
            })
            $r['total'] = $r['passed'] = $r['checks'].Count
        }
    }
    foreach ($field in @('position', 'rotation', 'look_target', 'tracked_ball', 'mode', 'tick', 'fov')) {
        Reject-Native 'camera' "broadcast camera cannot omit its actual $field" { param($r) [void]$r['camera_samples'][0]['camera'].Remove($field) }
    }
    Reject-Native 'camera' 'broadcast tracker must retain the ball at the declared end and side' {
        param($r) $r['camera_samples'][0]['camera']['tracked_ball'][0] *= -1.0
    }
    Reject-Native 'camera' 'broadcast framing cannot become a corner context while keeping green booleans' {
        param($r) $r['camera_samples'][0]['camera']['mode'] = 'corner'
    }
    Reject-Native 'camera' 'coherent camera metadata cannot rotate the fixed broadcast basis' {
        param($r)
        $camera = $r['camera_samples'][0]['camera']
        $camera['rotation'][1] = 0.2
        $back = (Get-GpCameraAxes $camera).back
        $camera['look_target'] = @(($camera['position'][0] - $back[0] * 80.0),
            ($camera['position'][1] - $back[1] * 80.0), ($camera['position'][2] - $back[2] * 80.0))
    }
    Reject-Native 'camera' 'zero outside count cannot conceal a known ball outside the actual frustum' {
        param($r)
        $camera = $r['camera_samples'][0]['camera']
        $camera['position'][0] += 10000.0; $camera['look_target'][0] += 10000.0
    }
    Reject-Native 'camera' 'every intermediate native camera tick is mandatory' { param($r) $r['transition_samples'] = @($r['transition_samples'] | Select-Object -Skip 1) }
    Reject-Native 'camera' 'duplicate sample cannot conceal missing camera time' { param($r) $r['transition_samples'][1] = CopyFixture $r['transition_samples'][0] }
    Reject-Native 'camera' 'camera depth and pixels cannot contradict a claimed visible sphere' { param($r) $r['transition_samples'][0]['camera']['rotation'][1] = [Math]::PI }
    foreach ($field in @('look_target', 'tracked_ball')) {
        Reject-Native 'camera' "cannot omit source-defined $field at an intermediate tick" {
            param($r) [void]$r['transition_samples'][31]['camera'].Remove($field)
        }
        Reject-Native 'camera' "$field is a numeric array, not a serialized Vector3 string" {
            param($r) $r['transition_samples'][31]['camera'][$field] = '(0, 0, 0)'
        }
        Reject-Native 'camera' "$field components cannot be booleans" {
            param($r) $r['transition_samples'][31]['camera'][$field][0] = $true
        }
        Reject-Native 'camera' "$field components cannot be numeric strings" {
            param($r) $r['transition_samples'][31]['camera'][$field][0] = '0'
        }
    }
    Reject-Native 'camera' 'tracked ball cannot change independently of the recorded native ball at tick 31' {
        param($r) $r['transition_samples'][31]['camera']['tracked_ball'][0] = 1.0
    }
    Reject-Native 'camera' 'look target cannot disagree with the actual production rotation at tick 31' {
        param($r) $r['transition_samples'][31]['camera']['look_target'][0] = 1.0
    }
    Reject-Native 'camera' 'coherent look metadata cannot turn a ball behind the camera into a visible one' {
        param($r)
        $camera = $r['transition_samples'][31]['camera']
        $camera['rotation'][1] = [Math]::PI
        $camera['look_target'] = @(0.0, 0.0, 20.0)
    }
    Reject-Native 'camera' 'the tick-31 counterexample cannot be omitted from both samples and declared coverage' {
        param($r)
        $id = 'trace/1/2/1'
        $r['transition_samples'] = @($r['transition_samples'] | Where-Object {
            -not ($_['case'] -ceq $id -and $_['direction'] -ceq 'entry' -and $_['elapsed'] -eq 31)
        })
        $r['trace_coverage'][$id]['entry_ticks'] = @($r['trace_coverage'][$id]['entry_ticks'] | Where-Object { $_ -ne 31 })
    }
    $expanded = CopyFixture $fixtures['camera']
    $expanded['transition_samples'][31]['camera']['synthetic_additive_observation'] = 'not a schema replacement'
    $parsed = Read-NativeFixture 'camera' $expanded
    Check 'native camera decoding preserves additive fields without freezing the dictionary key set' (
        $parsed['transition_samples'][31]['camera']['synthetic_additive_observation'] -ceq 'not a schema replacement')
    Reject-Native 'camera' 'native normalized coordinates cannot be fabricated independently of pose' { param($r) $r['transition_samples'][0]['screen'][0] += 0.02 }
    Reject-Native 'camera' 'pixel coordinates cannot replace the source-defined normalized camera observation' {
        param($r) $r['transition_samples'][0]['screen'] = @(960.0, 540.0)
    }
    Reject-Native 'camera' 'a visible center cannot conceal a clipped full ball volume' {
        param($r)
        $sample = $r['transition_samples'][0]
        $sample['ball'][1] = 4.35
        $sample['camera']['tracked_ball'][1] = 4.35
        $sample['screen'][1] = 0.5 - 4.35 / (2.0 * [Math]::Tan([Math]::PI / 6.0) * 10.0)
    }
    Reject-Native 'camera' 'native camera collision blockers must really be absent' { param($r) $r['transition_samples'][0]['blockers'] = @('court wall') }
    foreach ($field in @('complete', 'selected_groups', 'diagnostics', 'pending_step_budget',
            'requested_physics_steps', 'physics_steps', 'watchdog_failure', 'watchdog_probe')) {
        Reject-Native 'gameplay-rules' "full physical completion cannot omit $field" { param($r) [void]$r.Remove($field) }
    }
    foreach ($pair in @(@('complete', $false), @('complete', 'true'),
            @('pending_step_budget', 1), @('pending_step_budget', '0'),
            @('requested_physics_steps', 0), @('requested_physics_steps', '100'),
            @('physics_steps', 99), @('physics_steps', '103'),
            @('watchdog_failure', 'No awaited-step progress'), @('watchdog_failure', $false),
            @('watchdog_probe', $true), @('watchdog_probe', 'false'))) {
        Reject-Native 'gameplay-rules' "rejects incomplete/stalled physical evidence: $($pair[0])=$($pair[1])" {
            param($r) $r[$pair[0]] = $pair[1]
        }
    }
    Reject-Native 'gameplay-rules' 'partial selector is not a full run even with coherent passing totals' {
        param($r)
        $r['selected_groups'] = @($r['selected_groups'] | Where-Object { $_ -cne 'hand_ownership' })
        $r['passed'] = $r['total'] = $r['checks'].Count
    }
    Reject-Native 'gameplay-rules' 'seventeen entries cannot sum a duplicate group to hide an omitted one' {
        param($r) $r['selected_groups'][7] = $r['selected_groups'][6]
    }
    Reject-Native 'gameplay-rules' 'unknown selector identity cannot stand in for a required group' {
        param($r) $r['selected_groups'][7] = 'invented_group'
    }
    Reject-Native 'gameplay-rules' 'physical diagnostics cannot be discarded despite green counters' {
        param($r) $r['diagnostics'] = @(@{scope = 'uncompleted scenario'})
    }
    $reordered = CopyFixture $fixtures['gameplay-rules']
    [array]::Reverse($reordered['selected_groups'])
    $parsed = Read-NativeFixture 'gameplay-rules' $reordered
    Check 'full selector order does not change distinct coverage of the fixed production group schedule' (
        $parsed['selected_groups'].Count -eq 17)
    $g02Names = @($fixtures['gameplay-rules']['scenarios'] | Where-Object { $_['name'].StartsWith('G02 ', [StringComparison]::Ordinal) } |
        ForEach-Object { $_['name'] })
    $g02Negatives = @($fixtures['gameplay-rules']['negative_cases'] | Where-Object {
        $_['message'] -ceq 'Allied dribble cannot intentionally finish'
    })
    Check 'independent G02 fixture covers forty new scenarios, not just an enlarged finishing-group count' (
        $g02Names.Count -eq 40 -and @($g02Names | Sort-Object -Unique).Count -eq 40)
    Check 'independent G02 negatives cover acceptance, inertia, execution and mirrored end with 10/4/4/2 observations' (
        $g02Negatives.Count -eq 20 -and
        @($g02Negatives | Where-Object { $_['expected']['name'].EndsWith('/goal-directed physical dribble', [StringComparison]::Ordinal) }).Count -eq 10 -and
        @($g02Negatives | Where-Object { $_['expected']['name'].EndsWith('/inertia makes the real cut a finish', [StringComparison]::Ordinal) }).Count -eq 4 -and
        @($g02Negatives | Where-Object { $_['expected']['name'].EndsWith('/changed physical heading at execution', [StringComparison]::Ordinal) }).Count -eq 4 -and
        @($g02Negatives | Where-Object { $_['expected']['name'].EndsWith('/HOME finish toward the mirrored negative end', [StringComparison]::Ordinal) }).Count -eq 2)
    # Avoid $Name: Reject-Native has that parameter, and PowerShell resolves
    # these scriptblocks dynamically through the helper's invocation scope.
    foreach ($g02ScenarioName in $g02Names) {
        Reject-Native 'gameplay-rules' "cannot omit the actual G02 scenario while retaining green checks: $g02ScenarioName" {
            param($r) $r['scenarios'] = @($r['scenarios'] | Where-Object { $_['name'] -cne $g02ScenarioName })
        }
    }
    foreach ($negative in $g02Negatives) {
        $identity = $negative['expected']['name']
        Reject-Native 'gameplay-rules' "self-consistent refusal totals cannot omit G02 observation: $identity" {
            param($r)
            $r['negative_cases'] = @($r['negative_cases'] | Where-Object { $_['expected']['name'] -cne $identity })
            $r['expected_refusals'] = $r['negative_cases'].Count
        }
    }
    foreach ($mode in @(0, 1)) {
        $scope = "G02 HOME forbidden dribble pace outside carry exclusion; mode=$mode; exercise=0"
        foreach ($change in @(@{actor_id = 0}, @{actor_id = 1}, @{code = '4'}, @{message = 'Launch refused: allied_shot_forbidden'})) {
            Reject-Native 'gameplay-rules' ("G02 exact carrier/code/message for mode $mode cannot be replaced: " + ($change | ConvertTo-Json -Compress)) {
                param($r)
                $record = @($r['negative_cases'] | Where-Object { $_['scope'] -ceq $scope })[0]
                foreach ($key in $change.Keys) { $record[$key] = $change[$key]; $record['expected'][$key] = $change[$key] }
            }
        }
        foreach ($ball in @('(19.05, 0.12, 0.0)', '(16.9, 0.12, 0.0)', '(17.45, NaN, 0.0)', $true)) {
            Reject-Native 'gameplay-rules' "G02 outside-exclusion case must retain its actual ball origin m${mode}: $ball" {
                param($r)
                $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $scope })[0]
                $scenario['ball'] = $ball
            }
        }
    }
    Reject-Native 'gameplay-rules' 'a reviewed G02 message cannot authorize a different physical scenario' {
        param($r)
        $record = @($r['negative_cases'] | Where-Object { $_['message'] -ceq 'Allied dribble cannot intentionally finish' })[0]
        $record['scope'] = 'G02 unreviewed shortcut; mode=0; exercise=0'
        $record['expected']['name'] = $record['scope'] + '/goal-directed physical dribble'
        Add-NativeFixtureCheck $r ($record['scope'] + '/expected refusal goal-directed physical dribble')
    }
    Reject-Native 'gameplay-rules' 'execution refusal cannot be relabelled as a synchronous acceptance refusal' {
        param($r)
        $record = @($r['negative_cases'] | Where-Object {
            $_['expected']['name'].EndsWith('/changed physical heading at execution', [StringComparison]::Ordinal)
        })[0]
        $record['expected']['name'] = $record['scope'] + '/goal-directed physical dribble'
        Add-NativeFixtureCheck $r ($record['scope'] + '/expected refusal goal-directed physical dribble')
    }
    $semanticChecks = @(
        'initial dribble refusal preserves state, sequence and events'
        'nominal cut misses but observed body inertia aims through the mouth'
        'safe current impulse is accepted before the native turn'
        'execution revalidates the new heading before release and recovery'
        'non-finishing dribble is accepted rather than blanket banned'
        'keeper becomes the actual current human'
        'native complete-ball crossing proves the threatened goal is reachable'
        'same rejected dribble is legal for the newly selected HOME actor'
        'physical accidental HOME goal is not erased by finishing policy'
    )
    foreach ($suffix in $semanticChecks) {
        Reject-Native 'gameplay-rules' "G02 green totals cannot replace its native semantic assertion: $suffix" {
            param($r)
            $r['checks'] = @($r['checks'] | Where-Object { -not $_['name'].EndsWith('/' + $suffix, [StringComparison]::Ordinal) })
            $r['total'] = $r['passed'] = $r['checks'].Count
        }
    }
    $goalNames = @($fixtures['gameplay-rules']['scenarios'] | Where-Object { $_.Contains('native_dribble_goal') } | ForEach-Object { $_['name'] })
    Check 'independent G02 goal evidence includes twelve commanded goals and two uncommanded deflections' (
        $goalNames.Count -eq 12 -and @($fixtures['gameplay-rules']['scenarios'] | Where-Object { $_.Contains('native_deflection_goal') }).Count -eq 2)
    foreach ($g02GoalScenarioName in $goalNames) {
        Reject-Native 'gameplay-rules' "named G02 success alone cannot replace native dribble-to-goal data: $g02GoalScenarioName" {
            param($r)
            $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $g02GoalScenarioName })[0]
            [void]$scenario.Remove('native_dribble_goal')
        }
    }
    $goalName = 'G02 legal physical dribble goal selected field pace; mode=0; exercise=0'
    foreach ($change in @(
            @{actor_id = 1}, @{actor_id = '0'}, @{dribble_tick = 0}, @{dribble_tick = '10'},
            @{goal_tick = 10}, @{goal_tick = 9}, @{goal_tick = '31'}, @{goal_tick = $true},
            @{velocity = '(0.0, 0.0, 0.0)'}, @{velocity = '(-7.8, 0.0, 0.0)'},
            @{velocity = '(NaN, 0.0, 0.0)'}, @{velocity = '(1e999, 0.0, 0.0)'},
            @{velocity = @(7.8, 0.0, 0.0)})) {
        Reject-Native 'gameplay-rules' ('G02 goal observation rejects fabricated identity/time/impulse: ' + ($change | ConvertTo-Json -Compress)) {
            param($r)
            $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $goalName })[0]
            foreach ($key in $change.Keys) { $scenario['native_dribble_goal'][$key] = $change[$key] }
        }
    }
    foreach ($mode in @(0, 1)) {
        $g02DeflectionName = "G02 accidental HOME body deflection remains a goal; mode=$mode; exercise=0"
        Reject-Native 'gameplay-rules' "G02 accidental goal must include native contact data in mode $mode" {
            param($r)
            $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $g02DeflectionName })[0]
            [void]$scenario.Remove('native_deflection_goal')
        }
        foreach ($change in @(@{actor_id = 0}, @{contact_tick = '10'}, @{goal_tick = 10}, @{goal_tick = '18'})) {
            Reject-Native 'gameplay-rules' ("G02 deflection has a real uncommanded HOME contact before goal m${mode}: " + ($change | ConvertTo-Json -Compress)) {
                param($r)
                $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $g02DeflectionName })[0]
                foreach ($key in $change.Keys) { $scenario['native_deflection_goal'][$key] = $change[$key] }
            }
        }
        Reject-Native 'gameplay-rules' "G02 accidental goal cannot omit its real incoming ball velocity m$mode" {
            param($r)
            $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $g02DeflectionName })[0]
            $scenario['velocity'] = '(0.0, 0.0, 0.0)'
        }
    }
    foreach ($method in @('_home_dribble_finishing', '_home_dribble_revalidation', '_legal_home_dribbles',
            '_legal_dribble_goals', '_mirrored_home_dribble', '_accidental_home_goal')) {
        $savedSource = $sources['gameplay-rules']
        try {
            $sources['gameplay-rules'] = $savedSource.Replace("await $method(mode)", 'pass # omitted fixture-only traversal')
            Rejected "a full group label cannot hide missing native source traversal $method" { Read-NativeFixture 'gameplay-rules' }
        }
        finally { $sources['gameplay-rules'] = $savedSource }
    }
    $subset = CopyFixture $fixtures['gameplay-rules']
    $subset['selected_groups'] = @('finishing_guards', 'dribbles')
    $subset['scenarios'] = @($subset['scenarios'] | Where-Object { $_['name'].StartsWith('G02 ', [StringComparison]::Ordinal) })
    $subset['negative_cases'] = @($subset['negative_cases'] | Where-Object { $_['scope'].StartsWith('G02 ', [StringComparison]::Ordinal) })
    $subset['checks'] = @($subset['checks'] | Where-Object { $_['name'].StartsWith('G02 ', [StringComparison]::Ordinal) })
    $subset['expected_refusals'] = $subset['negative_cases'].Count
    $subset['passed'] = $subset['total'] = $subset['checks'].Count
    Rejected 'focused finishing/dribble evidence with internally consistent counts remains a subset, never full acceptance' {
        Read-NativeFixture 'gameplay-rules' $subset
    }
    $expanded = CopyFixture $fixtures['gameplay-rules']
    Add-NativeFixtureCheck $expanded 'synthetic extra physical review check'
    $parsed = Read-NativeFixture 'gameplay-rules' $expanded
    Check 'full physical assertion total remains record-derived after the G02 extension, not frozen to 1224 or 1522' (
        $parsed['total'] -eq $fixtures['gameplay-rules']['total'] + 1)
    Reject-Native 'gameplay-rules' 'catalogue must cover both physical modes' { param($r) $r['scenarios'] = @($r['scenarios'] | Where-Object { $_['mode'] -eq 0 }) }
    Reject-Native 'gameplay-rules' 'physical native setup must actually return OK' { param($r) $r['scenarios'][0]['start_error'] = 31 }
    Reject-Native 'gameplay-rules' 'a refusal count cannot replace actual observations' { param($r) $r['negative_cases'] = @() }
    Reject-Native 'gameplay-rules' 'authority diagnostic expectation is compared to the actual code' { param($r) $r['negative_cases'][0]['code'] = 31 }
    Reject-Native 'gameplay-rules' 'native refusal match is a boolean, not a label' { param($r) $r['negative_cases'][0]['matched'] = 'true' }
    Reject-Native 'gameplay-rules' 'unknown refusal classes remain prohibited' {
        param($r) $r['negative_cases'][0]['expected']['name'] = $r['negative_cases'][0]['scope'] + '/unknown'
    }
    Reject-Native 'gameplay-rules' 'a pending deferred refusal prevents completion' { param($r) $r['pending_refusals'] = @(@{name = 'not observed'}) }
    Reject-Native 'gameplay-rules' 'linked refusal assertion cannot be replaced by a generic success' { param($r) $r['checks'][0]['name'] = 'unrelated success' }
    foreach ($prefix in (Get-GodotGameplayEpisodeCases).Keys) {
        Check "G10 scenario prefix is read from the actual producer: $prefix" (
            $sources['gameplay-rules'].Contains('_start("' + $prefix + '"'))
        foreach ($check in (Get-GodotGameplayEpisodeCases)[$prefix].checks) {
            Check "G10 episode assertion is present in the actual producer: $check" (
                $sources['gameplay-rules'].Contains('_check("' + $check + '"'))
        }
    }
    $continuityName = 'G10 original hands release remains continuous until real shape separation; mode=0; exercise=6'
    $secondName = 'G10 separate original-taker touch; mode=0; exercise=1'
    foreach ($episodeName in @($continuityName, $secondName)) {
        Reject-Native 'gameplay-rules' "cannot omit required physical episode scenario: $episodeName" {
            param($r) $r['scenarios'] = @($r['scenarios'] | Where-Object { $_['name'] -cne $episodeName })
        }
        foreach ($value in @('700', $true, -1)) {
            Reject-Native 'gameplay-rules' "original episode is a nonnegative native ID for $episodeName, not $value" {
                param($r)
                $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $episodeName })[0]
                $scenario['launch_contact_id'] = $value
            }
        }
    }
    foreach ($field in @('launch_contact_id', 'native_second_contact')) {
        Reject-Native 'gameplay-rules' "second-touch evidence cannot omit $field" {
            param($r)
            $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $secondName })[0]
            [void]$scenario.Remove($field)
        }
    }
    foreach ($field in @('contact_id', 'actor_id', 'tick', 'surface')) {
        Reject-Native 'gameplay-rules' "actual second contact cannot omit $field or infer it from another field" {
            param($r)
            $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $secondName })[0]
            [void]$scenario['native_second_contact'].Remove($field)
        }
    }
    foreach ($value in @('705', $true, -1, 700)) {
        Reject-Native 'gameplay-rules' "second episode requires a distinct native identity, not $value" {
            param($r)
            $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $secondName })[0]
            $scenario['native_second_contact']['contact_id'] = $value
        }
    }
    foreach ($pair in @(@('actor_id', 4), @('actor_id', 2), @('tick', '90'), @('surface', 'post'))) {
        Reject-Native 'gameplay-rules' "second touching actor/time/surface follows the actual case: $($pair[0])=$($pair[1])" {
            param($r)
            $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $secondName })[0]
            $scenario['native_second_contact'][$pair[0]] = $pair[1]
        }
    }
    Reject-Native 'gameplay-rules' 'continuous release cannot substitute a fabricated second-touch observation' {
        param($r)
        $scenario = @($r['scenarios'] | Where-Object { $_['name'] -ceq $continuityName })[0]
        $scenario['native_second_contact'] = @{contact_id = 705; tick = 90; actor_id = 2; surface = 'athlete'}
    }
    Reject-Native 'gameplay-rules' 'physical episode IDs alone do not replace the native no-time-grace assertion' {
        param($r)
        $missing = $continuityName + '/continuous physical release beyond t plus one is not a second touch'
        $r['checks'] = @($r['checks'] | Where-Object { $_['name'] -cne $missing })
        $r['passed'] = $r['total'] = $r['checks'].Count
    }
    $episodes = CopyFixture $fixtures['gameplay-rules']
    $second = @($episodes['scenarios'] | Where-Object { $_['name'] -ceq $secondName })[0]
    $second['native_second_contact']['contact_id'] = 12
    $parsed = Read-NativeFixture 'gameplay-rules' $episodes
    Check 'physical episode identities are compared for equality, never inferred or ordered by clock ticks' (
        @($parsed['scenarios'] | Where-Object { $_['name'] -ceq $secondName })[0]['native_second_contact']['contact_id'] -eq 12)
    foreach ($file in @('..\Common.ps1', '..\MicroSliceValidation.ps1', '..\GameplayValidation.ps1',
            '..\GameplayNativeValidation.ps1', '..\Test-MicroSlice.ps1', 'Test-GameplayNativeValidation.ps1')) {
        Write-NativeFixtureBoundary 'begin' 'parse-source' $file
        $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file), [ref]$null, [ref]$errors)
        Check "native consumer PowerShell syntax: $file" ($errors.Count -eq 0)
    }
    $complete = $true
}
catch { $failure = $_.ToString(); Write-Output $_.ScriptStackTrace }
Write-NativeFixtureBoundary 'begin' 'finalize-report'
$result = @{
    ok = $complete; passed = @($checks | Where-Object { $_.passed }).Count; total = $checks.Count; checks = $checks.ToArray()
    scope = 'PowerShell source-shaped synthetic native-report fixtures only; no Godot launched'
    nativeValidated = $false; evidence = $directory; error = $failure
}
if ($TraceTimings) {
    $nativeTraceProcess.Refresh()
    $result['timingProfile'] = Get-NativeFixtureTimingSummary
    $result['timingWallMilliseconds'] = $nativeTraceClock.ElapsedMilliseconds
    $result['timingCpuMilliseconds'] = $nativeTraceProcess.TotalProcessorTime.TotalMilliseconds
    Write-Host ('NATIVE_FIXTURE_PROFILE ' + ($result['timingProfile'] | ConvertTo-Json -Compress -Depth 5))
}
Write-NativeFixtureBoundary 'begin' 'write-result-file'
$result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $directory 'result.json') -Encoding utf8
Write-NativeFixtureBoundary 'end' 'write-result-file'
Write-NativeFixtureBoundary 'begin' 'write-result-stdout'
Write-Output ('FUTSAL_GAMEPLAY_NATIVE_VALIDATION_TESTS ' + ($result | ConvertTo-Json -Compress -Depth 16))
Write-NativeFixtureBoundary 'end' 'write-result-stdout'
Write-NativeFixtureBoundary 'begin' 'process-exit'
if ($TraceTimings) { $nativeTraceProcess.Dispose() }
exit $(if ($complete) { 0 } else { 1 })
