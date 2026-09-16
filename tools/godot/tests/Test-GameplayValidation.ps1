#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Common.ps1')
. (Join-Path $PSScriptRoot '..\MicroSliceValidation.ps1')
. (Join-Path $PSScriptRoot '..\GameplayValidation.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$directory = Join-Path $root ('tools\godot\runtime\gameplay-helper-' + [guid]::NewGuid().ToString('N'))
$scratch = Join-Path $directory 'fixtures'
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
$checks = [Collections.Generic.List[object]]::new()
$complete = $false
$failure = $null

function Check([string]$Name, [bool]$Passed) {
    $checks.Add([ordered]@{name = $Name; passed = $Passed})
    if (-not $Passed) { throw "FAIL $Name" }
}

function Rejected([string]$Name, [scriptblock]$Action) {
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

function Copy-Fixture($Value) {
    return $Value | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable -Depth 32
}

function Fixture-Output($Report) {
    return [pscustomobject]@{Stdout = 'FUTSAL_FIXTURE_TESTS ' + ($Report | ConvertTo-Json -Compress -Depth 32)}
}

function Assert-HistoricalGameplay04Metadata($Metadata) {
    $godot = $Metadata['godot']
    $preview = $godot['previewValidation']
    $history = @($godot['g1Validation'], $godot['previousPreviewValidation'], $godot['playerControlValidation'])
    if ($godot['projectVersion'] -isnot [string] -or $godot['projectVersion'] -cne '0.4.0-preview' -or
        $godot['inputSchemaVersion'] -ne 3 -or $preview['projectVersion'] -isnot [string] -or
        $preview['projectVersion'] -cne '0.4.0-preview' -or $preview['inputSchemaVersion'] -ne 3 -or
        $preview['currentlyExportedVersion'] -isnot [string] -or $preview['currentlyExportedVersion'] -cne '0.4.0-preview') {
        throw 'Current metadata cannot inherit the old exported version or input schema.'
    }
    foreach ($schema in @($godot['inputSchemaVersion'], $preview['inputSchemaVersion'])) {
        if ($schema -isnot [int] -and $schema -isnot [long]) { throw 'Input schema metadata must be an integer.' }
    }
    foreach ($flag in @('runtimeValidated', 'gpuValidated')) {
        if ($preview[$flag] -isnot [bool] -or -not $preview[$flag]) {
            throw "Current 0.4 evidence requires a real validation flag: $flag"
        }
    }
    foreach ($flag in @('artifactPending', 'humanFeelAccepted', 'artApproved', 'renderedFpsAccepted',
            'diagnosticFixedStepIsFpsEvidence')) {
        if ($preview[$flag] -isnot [bool] -or $preview[$flag]) {
            throw "Automatic evidence cannot grant an unrelated gate or remain a pending artifact: $flag"
        }
    }
    if ($preview['artifactSha256'] -isnot [string] -or $preview['artifactSha256'] -cnotmatch '^[a-f0-9]{64}$' -or
        $preview['artifactSha256'] -cin @($history | ForEach-Object { $_['artifactSha256'] }) -or
        $preview['runtimeEvidence'] -isnot [string] -or
        $preview['runtimeEvidence'] -cnotmatch '^tools\\godot\\runtime\\preview-[^\\]+\\result\.json$' -or
        $preview['runtimeEvidence'] -cin @($history | ForEach-Object { $_['runtimeEvidence'] })) {
        throw 'The current preview needs its own artifact identity and runtime evidence reference, not a historical record.'
    }
}

function New-FixturePng([string]$Path, [int]$Index, [bool]$Uniform = $false, [int]$Width = 1920) {
    Add-Type -AssemblyName System.Drawing
    $image = [Drawing.Bitmap]::new($Width, 1080)
    $graphics = [Drawing.Graphics]::FromImage($image)
    $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(30 + $Index, 70, 110))
    try {
        $graphics.Clear([Drawing.Color]::Black)
        if (-not $Uniform) { $graphics.FillRectangle($brush, 200, 200, 1500, 700) }
        $image.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $brush.Dispose(); $graphics.Dispose(); $image.Dispose() }
}

try {
    $contract = Get-GodotGameplayContract
    Check 'current source tooling uses exact 0.5 schema 3 without rewriting 0.4 evidence' (
        $contract['projectVersion'] -ceq '0.5.0-preview' -and $contract['inputSchemaVersion'] -eq 3)
    Assert-GodotGameplayContractBinding $root $contract
    Check 'all canonical overrides and G01-G32 definitions are bound to the published section' $true
    $planText = [IO.File]::ReadAllText((Join-Path $root $contract['repositoryPlan']))
    $planFixture = Join-Path $scratch 'canonical-plan.md'
    $fixtureContract = Copy-Fixture $contract
    $fixtureContract['repositoryPlan'] = 'canonical-plan.md'
    foreach ($lineEnding in @("`n", "`r`n")) {
        [IO.File]::WriteAllText($planFixture, $planText.Replace("`r`n", "`n").Replace("`n", $lineEnding))
        Assert-GodotGameplayContractBinding $scratch $fixtureContract
        Check "entire canonical section binding normalizes line endings of length $($lineEnding.Length)" $true
    }
    foreach ($change in @(
            @('| `RestartState`: contacto del lanzamiento | `launch_contact_id: int = -1` |', ''),
            @('#### 4.3.7. Input, cámara de córner y guía', '#### 4.3.7. Unreviewed fixture-only change'),
            @('`--fixed-fps 60`', '`--fixed-fps 30`'))) {
        Check "canonical regression target exists: $($change[0])" ($planText.Contains($change[0]))
        [IO.File]::WriteAllText($planFixture, $planText.Replace($change[0], $change[1]))
        Rejected "full section hash rejects non-criterion drift: $($change[0])" {
            Assert-GodotGameplayContractBinding $scratch $fixtureContract
        }
    }
    foreach ($field in @('canonicalSectionSha256', 'acceptanceCriteria', 'acceptanceIds', 'trainingExercises', 'foulTuning')) {
        $badContract = Copy-Fixture $contract
        switch ($field) {
            'canonicalSectionSha256' { $badContract[$field] = '0' * 64 }
            'acceptanceCriteria' { $badContract[$field]['G28'] = 'Incorrectly count penalties as accumulated fouls.' }
            'acceptanceIds' { $badContract[$field][1] = 'G01' }
            'trainingExercises' { $badContract[$field]['PENALTY_6M'] = 9 }
            'foulTuning' { $badContract[$field]['foul_reckless_closing_speed']['initial'] = 8.0 }
        }
        Rejected "contract drift cannot silently change the binding: $field" { Assert-GodotGameplayContractBinding $root $badContract }
    }
    $dependencies = @(Get-GodotGameplayRuntimeDependencies)
    Check 'published contract no longer appears as a missing-contract dependency' (
        $dependencies.Count -eq 0)
    $badContract = Copy-Fixture $contract
    $badContract.canonicalSectionSha256 = '0' * 64
    Check 'changed binding reappears as an explicit dependency rather than being ignored' (
        @(Get-GodotGameplayRuntimeDependencies $badContract).Count -eq 1)
    Check 'canonical overrides preserve longitudinal projection and exclusive kick extension' (
        -not $contract['acceptedRuleOverrides']['penaltyCountsAsAccumulatedFoul'] -and
        $contract['acceptedRuleOverrides']['indirectProjectionChangesAxis'] -ceq 'X' -and
        $contract['acceptedRuleOverrides']['indirectProjectionPreservesAxis'] -ceq 'Z' -and
        ($contract['acceptedRuleOverrides']['extendedPeriodKinds'] -join ',') -ceq '6,7' -and
        $contract['acceptedRuleOverrides']['penaltyStraightLength'] -eq 3.16)
    foreach ($field in @('originalLaunchEpisodeField', 'secondTouchUsesEpisodeIdentityNotTickGrace')) {
        $badContract = Copy-Fixture $contract
        $badContract['acceptedRuleOverrides'][$field] = if ($field -ceq 'originalLaunchEpisodeField') { 'unrelated_contact' } else { $false }
        Rejected "G10 physical episode binding cannot be replaced: $field" { Assert-GodotGameplayContractBinding $root $badContract }
    }
    $tuning = @{foul_challenge_window_ticks = 18; foul_min_closing_speed = 0.8; foul_reckless_closing_speed = 9.5}
    Assert-GodotGameplayFoulTuning $tuning -RequireDefaults
    Check 'declared foul-tuning defaults are exactly eighteen ticks and 0.8/9.5 metres per second' $true
    foreach ($bounds in @(
            @{foul_challenge_window_ticks = 1; foul_min_closing_speed = 0.1; foul_reckless_closing_speed = 2.0},
            @{foul_challenge_window_ticks = 60; foul_min_closing_speed = 4.0; foul_reckless_closing_speed = 20.0})) {
        Assert-GodotGameplayFoulTuning $bounds
        Check ('canonical tuning includes legal bounds: ' + ($bounds | ConvertTo-Json -Compress)) $true
        Rejected ('custom legal tuning is not default evidence: ' + ($bounds | ConvertTo-Json -Compress)) {
            Assert-GodotGameplayFoulTuning $bounds -RequireDefaults
        }
    }
    foreach ($field in $tuning.Keys) {
        foreach ($invalid in @($null, $true, '18', [double]::NaN, [double]::PositiveInfinity)) {
            $badTuning = Copy-Fixture $tuning
            $badTuning[$field] = $invalid
            $label = if ($null -eq $invalid) { 'missing' } else { "$($invalid.GetType().Name):$invalid" }
            Rejected "foul tuning rejects non-numeric or non-finite $field $label" {
                Assert-GodotGameplayFoulTuning $badTuning
            }
        }
    }
    foreach ($change in @(@{foul_challenge_window_ticks = 0}, @{foul_challenge_window_ticks = 61},
            @{foul_challenge_window_ticks = 18.0}, @{foul_min_closing_speed = 0.09}, @{foul_min_closing_speed = 4.01},
            @{foul_reckless_closing_speed = 1.99}, @{foul_reckless_closing_speed = 20.01},
            @{foul_min_closing_speed = 3.0; foul_reckless_closing_speed = 3.0},
            @{foul_min_closing_speed = 4.0; foul_reckless_closing_speed = 3.0})) {
        $badTuning = Copy-Fixture $tuning
        foreach ($key in $change.Keys) { $badTuning[$key] = $change[$key] }
        Rejected ('foul tuning rejects bounds/type/order violation: ' + ($change | ConvertTo-Json -Compress)) {
            Assert-GodotGameplayFoulTuning $badTuning
        }
    }
    $required = Get-GodotGameplayStages $scratch $contract
    foreach ($stage in @('ai-tactics', 'rules', 'gameplay-rules', 'camera', 'gameplay-runtime', 'aim-guide', 'gestures')) {
        Check "native suite remains mandatory even before its file exists: $stage" $required.Contains($stage)
        Check "new native suite cannot omit checks: $stage" (Test-GodotNativeChecksRequired $stage)
        $project = Join-Path $scratch 'game'
        $path = Join-Path $scratch $required[$stage]
        $arguments = @(Get-GodotGameplayNativeArguments $stage $project $path)
        Check "$stage native arguments preserve its actual source, headless path and script" (
            $arguments[0] -ceq '--headless' -and $arguments[1] -ceq '--path' -and $arguments[2] -ceq $project -and
            $arguments[-2] -ceq '--script' -and $arguments[-1] -ceq $path)
        Check "$stage fixed-step scheduling is exclusive to the long pure physical suite" (
            ('--fixed-fps' -cin $arguments) -eq ($stage -ceq 'gameplay-rules') -and
            ($stage -cne 'gameplay-rules' -or $arguments[6] -ceq '60'))
        Check "$stage full-suite runner never aggregates subsets or starts a watchdog probe" (
            @($arguments | Where-Object { $_ -like '--groups*' -or $_ -ceq '--probe-watchdog' }).Count -eq 0)
    }
    Rejected 'a UI suite cannot be relabelled as the accelerated physical suite' {
        Get-GodotGameplayNativeArguments 'gameplay-rules' $project (Join-Path $project 'tests\test_match_gameplay_runtime.gd')
    }
    Rejected 'relative native project paths cannot bypass suite identity' {
        Get-GodotGameplayNativeArguments 'gameplay-rules' 'game' (Join-Path $project 'tests\test_match_gameplay_rules.gd')
    }
    $runnerSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\Test-MicroSlice.ps1'))
    $runnerAst = [Management.Automation.Language.Parser]::ParseInput($runnerSource, [ref]$null, [ref]$null)
    $fixedLiterals = @($runnerAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value -like '--fixed-fps*'
    }, $true))
    $fixedOwners = @($fixedLiterals | ForEach-Object {
        $owner = $_.Parent
        while ($null -ne $owner -and $owner -isnot [Management.Automation.Language.FunctionDefinitionAst]) { $owner = $owner.Parent }
        if ($null -eq $owner) { 'top-level' } else { $owner.Name }
    })
    Check 'runner fixed timing is confined to legacy smoke and stage metadata, not component or visual arguments' (
        $fixedLiterals.Count -eq 2 -and (($fixedOwners | Sort-Object) -join ',') -ceq 'Invoke-Game,Invoke-Stage' -and
        $runnerSource.Contains('Get-GodotGameplayNativeArguments -Stage $name -Project $project -ScriptPath $path') -and
        $runnerSource.Contains("fixedStepWithoutRealtimeSynchronization = '--fixed-fps' -cin `$Arguments"))
    Check 'published gestures cannot disappear behind a conditional file-presence skip' (
        $required['gestures'] -ceq 'game\tests\test_match_gestures.gd' -and $contract['requiredWhenPresent'].Count -eq 0)
    Check 'new visual producer must include its full checks array' (Test-GodotNativeChecksRequired 'visual-native')
    foreach ($stage in @('hud', 'integration', 'development-menu', 'preview-integration', 'player-control')) {
        Check "only documented legacy producer may omit checks: $stage" (-not (Test-GodotNativeChecksRequired $stage))
    }
    $native = @{ok = $true; total = 1; passed = 1; failures = @(); checks = @(@{name = 'fixture'; passed = $true})}
    $parsed = ConvertFrom-GodotStructuredReport (Fixture-Output $native) 'FUTSAL_FIXTURE_TESTS' -RequireChecks
    Assert-GodotGameplayComponentReport $parsed
    Check 'typed component fixture passes shared strict report parser' $true
    $classification = Copy-Fixture $native
    $classification['checks'][0]['name'] = 'synthetic negative classification without submitting an invalid command'
    $classification['expected_refusals'] = 0
    $classification['expected_validation_errors'] = 0
    $classification['errors'] = @()
    $parsed = ConvertFrom-GodotStructuredReport (Fixture-Output $classification) 'FUTSAL_FIXTURE_TESTS' -RequireChecks
    Assert-GodotGameplayComponentReport $parsed
    Check 'negative classification passes with zero diagnostic or refusal allowances' $true
    foreach ($field in @('expected_refusals', 'expected_validation_errors')) {
        $bad = Copy-Fixture $classification
        $bad[$field] = 1
        Rejected "negative assertion polarity cannot create an allowance: $field" { Assert-GodotGameplayComponentReport $bad }
    }
    $bad = Copy-Fixture $classification
    $bad['errors'] = @('Unexpected diagnostic despite a passing negative assertion.')
    Rejected 'passing classification does not hide an unexpected diagnostic' { Assert-GodotGameplayComponentReport $bad }
    foreach ($change in @(@{ok = 'true'}, @{passed = 0}, @{total = 2}, @{failures = @('failure')},
            @{checks = @()}, @{checks = @(@{name = 'fixture'; passed = 'true'})})) {
        $bad = Copy-Fixture $native
        foreach ($key in $change.Keys) { $bad[$key] = $change[$key] }
        Rejected ('invalid native report fixture: ' + ($change | ConvertTo-Json -Compress -Depth 8)) {
            ConvertFrom-GodotStructuredReport (Fixture-Output $bad) 'FUTSAL_FIXTURE_TESTS' -RequireChecks
        }
    }
    $bad = Copy-Fixture $native
    $bad.checks += Copy-Fixture $bad.checks[0]
    $bad.total = 2
    $bad.passed = 2
    Rejected 'repeated check labels cannot count as native coverage' {
        ConvertFrom-GodotStructuredReport (Fixture-Output $bad) 'FUTSAL_FIXTURE_TESTS' -RequireChecks
    }
    [void]$native.Remove('checks')
    $null = ConvertFrom-GodotStructuredReport (Fixture-Output $native) 'FUTSAL_FIXTURE_TESTS'
    Check 'legacy optional checks still preserve the old report shape' $true
    Rejected 'new producer cannot use the legacy optional-check exception' {
        ConvertFrom-GodotStructuredReport (Fixture-Output $native) 'FUTSAL_FIXTURE_TESTS' -RequireChecks
    }
    foreach ($change in @(@{complete = 'true'}, @{failures = $null}, @{errors = @('hidden')},
            @{command_refusals = @('unmapped')}, @{expected_refusals = 1}, @{expected_refusals = '0'},
            @{expected_validation_errors = 1}, @{expected_validation_errors = $false})) {
        $bad = Copy-Fixture $native
        foreach ($key in $change.Keys) { $bad[$key] = $change[$key] }
        Rejected ('component negatives need exact producer accounting: ' + ($change | ConvertTo-Json -Compress)) {
            Assert-GodotGameplayComponentReport $bad
        }
    }
    $restart = @{id = 1; kind = 2; stage = 3; stage_started_tick = 160; placement_end_tick = 160; ready_tick = 160; deadline_tick = 400}
    foreach ($kind in 1..7) {
        $valid = Copy-Fixture $restart
        $valid.kind = $kind
        $valid.deadline_tick = if ($kind -eq 6) { -1 } else { 400 }
        Assert-GodotGameplayReadyRestartTiming $valid 100 160
        Assert-GodotGameplayRestartLaunchWindow $valid 399 $true
        Check "canonical sixty-tick placement and correct ready deadline: restart $kind" $true
    }
    foreach ($change in @(@{id = 0}, @{kind = 8}, @{stage = 0}, @{ready_tick = '160'},
            @{placement_end_tick = 159}, @{ready_tick = 159}, @{stage_started_tick = 161},
            @{deadline_tick = -1}, @{deadline_tick = 401}, @{kind = 6})) {
        $bad = Copy-Fixture $restart
        foreach ($key in $change.Keys) { $bad[$key] = $change[$key] }
        Rejected ('invalid placement or deadline fixture: ' + ($change | ConvertTo-Json -Compress)) {
            Assert-GodotGameplayReadyRestartTiming $bad 100 160
        }
    }
    Rejected 'placement observation cannot precede authoritative READY' { Assert-GodotGameplayReadyRestartTiming $restart 100 159 }
    Rejected 'placement event tick cannot be a numeric string' { Assert-GodotGameplayReadyRestartTiming $restart '100' 160 }
    Rejected 'deadline boundary rejects accepted launch at exactly ready plus 240' {
        Assert-GodotGameplayRestartLaunchWindow $restart 400 $true
    }
    Assert-GodotGameplayRestartLaunchWindow $restart 400 $false
    Check 'non-executable preview at exact expiry is not an accepted launch' $true
    $penalty = Copy-Fixture $restart
    $penalty.kind = 6
    $penalty.deadline_tick = -1
    Assert-GodotGameplayRestartLaunchWindow $penalty 1000 $true
    Check 'penalty remains legally executable without a four-second countdown' $true
    Rejected 'executable must be a native boolean rather than a truthy string' {
        Assert-GodotGameplayRestartLaunchWindow $restart 399 'true'
    }
    Rejected 'negative observation tick is not evidence even for a non-executable query' {
        Assert-GodotGameplayRestartLaunchWindow $restart -1 $false
    }
    $placing = Copy-Fixture $restart
    $placing.stage = 2
    Rejected 'preparation solution cannot execute before READY' { Assert-GodotGameplayRestartLaunchWindow $placing 159 $true }
    foreach ($case in @(
            @{name = 'direct confirmed foul counts'; kind = 3; foul_verdict = 2; counts_as_accumulated_foul = $true; restart = @{kind = 4}},
            @{name = 'sixth reckless foul counts'; kind = 3; foul_verdict = 3; counts_as_accumulated_foul = $true; restart = @{kind = 7}},
            @{name = 'penalty is explicitly exempt'; kind = 3; foul_verdict = 2; counts_as_accumulated_foul = $false; restart = @{kind = 6}},
            @{name = 'indirect expiry never counts'; kind = 2; foul_verdict = 0; counts_as_accumulated_foul = $false; restart = @{kind = 5}},
            @{name = 'clean contact is no foul'; kind = 0; foul_verdict = 1; counts_as_accumulated_foul = $false; restart = @{kind = 0}})) {
        Assert-GodotGameplayAccumulatedFoulDecision $case
        Check "canonical RuleDecision: $($case.name)" $true
        $bad = Copy-Fixture $case
        $bad.counts_as_accumulated_foul = -not $case.counts_as_accumulated_foul
        Rejected "incorrect accumulated counter flag: $($case.name)" { Assert-GodotGameplayAccumulatedFoulDecision $bad }
    }
    Rejected 'accumulation requires an explicit boolean not a missing or coerced flag' {
        Assert-GodotGameplayAccumulatedFoulDecision @{kind = 3; foul_verdict = 2; counts_as_accumulated_foul = 'true'; restart = @{kind = 4}}
    }
    $coverage = @()
    foreach ($mode in $contract['modes']) {
        foreach ($name in $contract['runtimeCaseNames']) {
            $coverage += @{case = "m$mode/$name"; source_script = 'res://match/match.gd'; passed = $true}
        }
    }
    Assert-GodotGameplayCoverage $coverage
    Check 'runtime identities require the real fourteen scenarios independently in both modes' $true
    Rejected 'micro-only scenarios do not prove both-mode runtime coverage' { Assert-GodotGameplayCoverage @($coverage[0..13]) }
    $bad = Copy-Fixture $coverage
    $bad[1] = $bad[0]
    Rejected 'duplicated acceptance case cannot replace another case' { Assert-GodotGameplayCoverage $bad }
    foreach ($change in @(@{case = 'G99'}, @{case = 'm2/live_charged_shot'}, @{source_script = 'res://fixture.gd'},
            @{passed = 'true'}, @{passed = $false})) {
        $bad = Copy-Fixture $coverage
        foreach ($key in $change.Keys) { $bad[0][$key] = $change[$key] }
        Rejected ('invalid gameplay coverage: ' + ($change | ConvertTo-Json -Compress)) { Assert-GodotGameplayCoverage $bad }
    }
    $paths = @()
    foreach ($stage in @('source-headless', 'source-rendered', 'artifact-headless', 'artifact-rendered')) {
        $path = Get-GodotGameplayEvidencePaths $scratch $stage
        Assert-GodotGameplayFreshPaths $path
        $paths += $path
        Check "capture directory is a sibling of the report for $stage" (
            (Split-Path $path.ReportPath -Parent) -ceq (Split-Path $path.CaptureDirectory -Parent))
    }
    Check 'source and artifact cannot share report/capture paths' (
        @($paths.Directory | Sort-Object -Unique).Count -eq 4 -and @($paths.CaptureDirectory | Sort-Object -Unique).Count -eq 4)
    Rejected 'relative run root cannot define owned capture evidence' { Get-GodotGameplayEvidencePaths '.\relative' 'source-rendered' }
    New-Item -ItemType Directory -Path $paths[1].CaptureDirectory -Force | Out-Null
    Rejected 'existing invocation directory cannot be overwritten by a later run' { Assert-GodotGameplayFreshPaths $paths[1] }
    $started = [DateTime]::UtcNow.AddSeconds(-1)
    $captures = @()
    $index = 0
    foreach ($mode in $contract['modes']) {
        foreach ($exercise in $contract['captureExerciseIds']) {
            $png = Join-Path $paths[1].CaptureDirectory "$mode-$exercise.png"
            New-FixturePng $png $index
            $rule = $contract['captureContextRules'][$exercise]
            $selection = if ($rule.Contains('selectedActor')) { $rule['selectedActor'] } else { 0 }
            $event = $null
            if ($rule['acceptedEventRequired']) {
                $event = @{
                    kind = $rule['eventKind']; tick = 10
                    actor_id = $(if ($rule.Contains('eventActor')) { $rule['eventActor'] } else { $selection })
                }
                if ($rule.Contains('launchKind')) { $event['launch_kind'] = $rule['launchKind'] }
                if ($rule.Contains('gestureKind')) { $event['gesture_kind'] = $rule['gestureKind'] }
            }
            $captures += @{
                mode = $mode; exercise = $exercise; path = $png
                sha256 = (Get-FileHash -LiteralPath $png -Algorithm SHA256).Hash.ToLowerInvariant()
                training_exercise = $(if ($null -ne $rule['trainingExercise']) { $rule['trainingExercise'] } else { 0 })
                tick = 10; phase = $rule['phase']; selected_actor_id = $selection
                restart = @{
                    kind = $(if ($rule.Contains('restartKind')) { $rule['restartKind'] } else { 0 })
                    stage = $(if ($rule.Contains('restartStages')) { $rule['restartStages'][0] } else { 0 })
                }
                camera = @{fixture = $true}; input = @{fixture = $true}
                accepted_event = $event
            }
            $index += 1
        }
    }
    Assert-GodotGameplayCaptureCoverage $captures $paths[1].CaptureDirectory $started
    Check 'twenty decoded synthetic PNG fixtures validate file/context coverage only' $true
    Rejected 'nineteen files cannot satisfy twenty capture contexts' {
        Assert-GodotGameplayCaptureCoverage @($captures[0..18]) $paths[1].CaptureDirectory $started
    }
    foreach ($change in @(@{mode = '0'}, @{exercise = 'invented'}, @{tick = '10'}, @{tick = 0},
            @{selected_actor_id = 1}, @{selected_actor_id = 20}, @{phase = ''}, @{phase = 4},
            @{training_exercise = '2'}, @{training_exercise = 3}, @{training_exercise = 12},
            @{restart = @{}}, @{camera = @{}}, @{input = @{}}, @{accepted_event = @{}},
            @{restart = @{kind = 3; stage = 2}}, @{restart = @{kind = 2; stage = 1}},
            @{sha256 = ('0' * 64)}, @{path = (Join-Path $scratch 'outside.png')})) {
        $bad = Copy-Fixture $captures
        foreach ($key in $change.Keys) { $bad[0][$key] = $change[$key] }
        Rejected ('invalid capture context/file fixture: ' + ($change | ConvertTo-Json -Compress)) {
            Assert-GodotGameplayCaptureCoverage $bad $paths[1].CaptureDirectory $started
        }
    }
    $releaseIndex = [array]::IndexOf($contract['captureExerciseIds'], 'keeper-clearance-release')
    foreach ($change in @(@{kind = 2}, @{actor_id = 0}, @{actor_id = '2'}, @{launch_kind = 0},
            @{launch_kind = '2'}, @{tick = 11}, @{tick = 0})) {
        $bad = Copy-Fixture $captures
        foreach ($key in $change.Keys) { $bad[$releaseIndex]['accepted_event'][$key] = $change[$key] }
        Rejected ('keeper release needs the accepted physical throw: ' + ($change | ConvertTo-Json -Compress)) {
            Assert-GodotGameplayCaptureCoverage $bad $paths[1].CaptureDirectory $started
        }
    }
    $bad = Copy-Fixture $captures
    $bad[$releaseIndex]['accepted_event'] = $null
    Rejected 'keeper release cannot omit the accepted event as preparation may' {
        Assert-GodotGameplayCaptureCoverage $bad $paths[1].CaptureDirectory $started
    }
    $bad = Copy-Fixture $captures
    $cutIndex = [array]::IndexOf($contract['captureExerciseIds'], 'cut-left-contact')
    $bad[$cutIndex]['accepted_event']['gesture_kind'] = 2
    Rejected 'pace-change event cannot substitute for a cut contact' {
        Assert-GodotGameplayCaptureCoverage $bad $paths[1].CaptureDirectory $started
    }
    $bad = Copy-Fixture $captures
    $bad[1] = $bad[0]
    Rejected 'duplicate capture identity/file does not count twice' {
        Assert-GodotGameplayCaptureCoverage $bad $paths[1].CaptureDirectory $started
    }
    $bad = Copy-Fixture $captures
    $bad[1].sha256 = $bad[0].sha256
    Rejected 'copied image bytes cannot fabricate a different exercise' {
        Assert-GodotGameplayCaptureCoverage $bad $paths[1].CaptureDirectory $started
    }
    $file = Get-Item -LiteralPath $captures[0].path
    $originalTime = $file.LastWriteTimeUtc
    $file.LastWriteTimeUtc = $started.AddSeconds(-2)
    Rejected 'stale capture fails despite matching bytes and hash' {
        Assert-GodotGameplayCaptureFile $captures[0].path $paths[1].CaptureDirectory $started $captures[0].sha256
    }
    $file.LastWriteTimeUtc = $originalTime
    foreach ($kind in @('uniform', 'wrong-size', 'invalid-png')) {
        $path = Join-Path $paths[1].CaptureDirectory "$kind.png"
        if ($kind -eq 'invalid-png') { [IO.File]::WriteAllBytes($path, [byte[]]::new(2048)) }
        else { New-FixturePng $path 0 ($kind -eq 'uniform') $(if ($kind -eq 'wrong-size') { 1280 } else { 1920 }) }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        Rejected "$kind is not a real varied 1080p PNG" { Assert-GodotGameplayCaptureFile $path $paths[1].CaptureDirectory $started $hash }
    }
    Rejected 'normalized coverage and synthetic images cannot replace a witnessed production report' {
        Read-GodotGameplayRuntimeReport -Result @{ok = $true; coverage = $coverage; captures = $captures} `
            -ReportPath (Join-Path $scratch 'unowned.json') -StartedAt $started -Executable 'C:\unowned.exe' `
            -EditorBinary $true -Headless $true -CaptureDirectory $paths[1].CaptureDirectory
    }
    Check 'exact delivered runtime protocol replaces the former unconditional decoder blocker' (
        @(Get-GodotGameplayRuntimeDependencies).Count -eq 0 -and $contract['runtimeCliFlag'] -ceq '--gameplay-smoke')
    $input = Get-Content -LiteralPath (Join-Path $root 'config\input-schema.json') -Raw | ConvertFrom-Json -AsHashtable
    $dribble = @($input['actions'] | Where-Object { $_['name'] -ceq 'dribble' })
    Check 'schema-3 dribble binding is exactly L/X while legacy actions remain' (
        $input['schemaVersion'] -eq 3 -and $input['actions'].Count -eq 10 -and $dribble.Count -eq 1 -and
        ($dribble[0]['keys'] -join ',') -ceq 'KEY_L' -and $dribble[0]['button'] -ceq 'JOY_BUTTON_X')
    Check 'contextual dribble and confirmed own-restart fine aim preserve separate actions' (
        $dribble[0]['contextualActions']['LIVE'] -ceq 'DRIBBLE' -and
        $dribble[0]['contextualActions']['RESTART_AIM_WITH_SPOT_CHOICE'] -ceq 'CHOOSE_RESTART_SPOT' -and
        $input['restartFineKeyboardAim'] -ceq $contract['fineAimHint'] -and $input['restartFineAimMaxDegreesPerSecond'] -eq 30.0)
    $metadata = Get-Content -LiteralPath (Join-Path $root 'config\toolchain.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 32
    Assert-HistoricalGameplay04Metadata $metadata
    Check 'historical 0.4 metadata remains bound to its own runtime and GPU evidence, not source 0.5' $true
    foreach ($change in @(
            @{projectVersion = '0.3.0-preview'}, @{projectVersion = '0.5.0-preview'},
            @{inputSchemaVersion = 2}, @{inputSchemaVersion = '3'},
            @{currentlyExportedVersion = '0.3.0-preview'},
            @{runtimeValidated = $false}, @{runtimeValidated = 'true'}, @{gpuValidated = $false}, @{gpuValidated = 'true'},
            @{artifactPending = $true}, @{artifactPending = 'false'}, @{humanFeelAccepted = $true},
            @{artApproved = $true}, @{renderedFpsAccepted = $true}, @{diagnosticFixedStepIsFpsEvidence = $true},
            @{artifactSha256 = ''}, @{artifactSha256 = $metadata['godot']['playerControlValidation']['artifactSha256']},
            @{artifactSha256 = $metadata['godot']['previousPreviewValidation']['artifactSha256']},
            @{artifactSha256 = $metadata['godot']['g1Validation']['artifactSha256']},
            @{runtimeEvidence = ''}, @{runtimeEvidence = $metadata['godot']['playerControlValidation']['runtimeEvidence']},
            @{runtimeEvidence = $metadata['godot']['previousPreviewValidation']['runtimeEvidence']},
            @{runtimeEvidence = $metadata['godot']['g1Validation']['runtimeEvidence']})) {
        $mutant = Copy-Fixture $metadata
        foreach ($key in $change.Keys) { $mutant['godot']['previewValidation'][$key] = $change[$key] }
        Rejected ('current metadata rejects stale or conflated evidence: ' + ($change | ConvertTo-Json -Compress)) {
            Assert-HistoricalGameplay04Metadata $mutant
        }
    }
    foreach ($field in @('godot.projectVersion', 'previewValidation.projectVersion', 'currentlyExportedVersion')) {
        foreach ($case in @(
                @{name = 'boolean true'; value = $true}, @{name = 'boolean false'; value = $false},
                @{name = 'single-version array'; value = @('0.4.0-preview')},
                @{name = 'repeated-version array'; value = @('0.4.0-preview', '0.4.0-preview')})) {
            $mutant = Copy-Fixture $metadata
            switch ($field) {
                'godot.projectVersion' { $mutant['godot']['projectVersion'] = $case.value }
                'previewValidation.projectVersion' { $mutant['godot']['previewValidation']['projectVersion'] = $case.value }
                'currentlyExportedVersion' { $mutant['godot']['previewValidation']['currentlyExportedVersion'] = $case.value }
            }
            Rejected "version metadata $field rejects $($case.name) without coercion" {
                Assert-HistoricalGameplay04Metadata $mutant
            }
        }
    }
    Check 'completed 0.3 counts stay in the historical player-control record' (
        $metadata['godot']['playerControlValidation']['historical'] -ceq $true -and
        $metadata['godot']['playerControlValidation']['runnerPassed'] -eq 125 -and
        $metadata['godot']['playerControlValidation']['foundationPassed'] -eq 819 -and
        $metadata['godot']['playerControlValidation']['processPassed'] -eq 72)
    $bootstrap = Get-Content -LiteralPath (Join-Path $root 'game\bootstrap\bootstrap.gd') -Raw
    Check 'diagnostic source declares schema 3 and both native dribble bindings' (
        $bootstrap.Contains('const INPUT_SCHEMA_VERSION: int = 3') -and
        $bootstrap.Contains('const EXPECTED_PROJECT_VERSION: String = "0.5.0-preview"') -and
        $bootstrap.Contains('&"dribble"') -and $bootstrap.Contains('KEY_L') -and $bootstrap.Contains('JOY_BUTTON_X'))
    foreach ($name in @('GameplayValidation.ps1', 'Test-MicroSlice.ps1', 'tests\Test-GameplayValidation.ps1')) {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "..\$name"), [ref]$null, [ref]$errors)
        Check "first-pass gameplay PowerShell parses: $name" ($errors.Count -eq 0)
    }
    $complete = $true
}
catch {
    $failure = $_.Exception.Message
    $checks.Add([ordered]@{name = 'pure gameplay fixture suite completed'; passed = $false; error = $failure})
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse
}
$failed = @($checks | Where-Object { -not $_['passed'] }).Count
$report = [ordered]@{
    ok = $complete -and $failed -eq 0; passed = $checks.Count - $failed; total = $checks.Count; checks = $checks.ToArray()
    scope = 'pure PowerShell synthetic fixtures; NOT native G01-G32/gameplay/capture acceptance'
    nativeValidated = $false; runtimeDecoderReady = $true; error = $failure; evidence = $directory
}
if ($report.ok) {
    $null = ConvertFrom-GodotStructuredReport ([pscustomobject]@{
        Stdout = 'FUTSAL_GAMEPLAY_VALIDATION_TESTS ' + ($report | ConvertTo-Json -Compress -Depth 16)
    }) 'FUTSAL_GAMEPLAY_VALIDATION_TESTS' -RequireChecks
}
$report | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $directory 'result.json') -Encoding utf8
Write-Output ('FUTSAL_GAMEPLAY_VALIDATION_TESTS ' + ($report | ConvertTo-Json -Compress -Depth 16))
exit $(if ($report.ok) { 0 } else { 1 })
