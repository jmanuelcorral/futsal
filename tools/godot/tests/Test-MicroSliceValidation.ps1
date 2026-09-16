#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Common.ps1')
. (Join-Path $PSScriptRoot '..\MicroSliceValidation.ps1')
$checks = [Collections.Generic.List[object]]::new()
$fixtureSharingRetries = 0
$work = Join-Path $PSScriptRoot ('..\runtime\validation-helper-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$work = (Resolve-Path -LiteralPath $work).Path

function Check([string]$Name, [bool]$Passed) {
    $checks.Add([ordered]@{ name = $Name; passed = $Passed })
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

function ProcessResult([string]$Output = '', [string]$Errors = '', [int]$Code = 0) {
    return [pscustomobject]@{
        Stdout = $Output; Stderr = $Errors; ExitCode = $Code; ProcessId = 42; RuntimeProcessIds = @(42)
    }
}

function ReportOutput($Report, [string]$Prefix = 'FUTSAL_MATCH_SMOKE') {
    return ProcessResult ("$Prefix " + ($Report | ConvertTo-Json -Compress -Depth 64))
}

function PersistGameReport($Report) {
    $json = $Report | ConvertTo-Json -Depth 64
    # Retry only Windows sharing/lock violations in generated fixture files.
    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            [IO.File]::WriteAllText($reportPath, $json, [Text.UTF8Encoding]::new($false))
            break
        }
        catch {
            $cause = $_.Exception
            while ($null -ne $cause.InnerException) { $cause = $cause.InnerException }
            if ($cause -isnot [IO.IOException] -or ($cause.HResult -band 0xffff) -notin @(32, 33) -or $attempt -eq 9) { throw }
            $script:fixtureSharingRetries += 1
            Start-Sleep -Milliseconds 100
        }
    }
    return ReportOutput $Report
}

function FreshGame($Result) {
    return Read-GodotGameReport -Result $Result -ReportPath $reportPath -StartedAt $started `
        -EditorBinary $true -Headless $true -Executable $executable
}

function CopyFixture($Value) {
    return $Value | ConvertTo-Json -Depth 32 | ConvertFrom-Json -AsHashtable -Depth 32
}

function RejectedGame([string]$Name, [scriptblock]$Mutate) {
    $mutant = CopyFixture $game
    & $Mutate $mutant | Out-Null
    $badResult = PersistGameReport $mutant
    Rejected $Name { FreshGame $badResult }
}

function ModeState([int]$Mode = 1, [int]$Tick = 12, [double]$Seconds = 119.8,
    [string]$Phase = 'PLAYING', [bool]$Ai = $true, [int]$Selected = 0) {
    $ids = if ($Mode -eq 1) { @(0..9) } else { @(0..3) }
    $intent = if ($Ai) { $ids } else { @() }
    $aiIds = @($intent | Where-Object { $_ -ne $Selected })
    $actors = @($ids | ForEach-Object {
        $sequence = if ($Tick -eq 0 -or ($_ -ne $Selected -and -not $Ai)) { -1 } else { $Tick }
        @{
            id = $_; team = $_ % 2; role = $(if ($_ -in @(2, 3)) { 1 } else { 0 }); human = $_ -eq $Selected
            sequence = $sequence; position = @([double]$_, 0.0, 0.0); velocity = @(0.0, 0.0, 0.0)
        }
    })
    return @{
        mode = $Mode; actor_count = $ids.Count; physical_actor_ids = $ids; actors = $actors; ai_actor_ids = @($aiIds)
        ai_intent_actor_ids = @($intent); selected_actor_id = $Selected
        ball_owner_id = $Selected
        phase = $Phase; tick = $Tick; seconds_remaining = $Seconds; human_sequence = $actors[$Selected].sequence
        driver_start_calls = 0; score = @(0, 0); ball_position = @(0.0, 0.12, 0.0); ball_velocity = @(0.0, 0.0, 0.0)
    }
}

function AiChange([int]$Mode) {
    $before = ModeState $Mode 12 119.8 'PAUSED'
    $off = CopyFixture $before
    $off.ai_actor_ids = @()
    $off.ai_intent_actor_ids = @()
    $offLater = CopyFixture $off
    $offLater.phase = 'PLAYING'
    $offLater.tick = 48
    $offLater.seconds_remaining = 119.2
    $offLater.actors[0].sequence = 48
    $restarted = ModeState $Mode 12 119.8 'PLAYING' $false
    $onBefore = CopyFixture $restarted
    $onBefore.phase = 'PAUSED'
    $on = CopyFixture $onBefore
    $on.ai_actor_ids = if ($Mode -eq 1) { @(1..9) } else { @(1..3) }
    $on.ai_intent_actor_ids = if ($Mode -eq 1) { @(0..9) } else { @(0..3) }
    $onLater = CopyFixture $on
    $onLater.phase = 'PLAYING'
    $onLater.tick = 36
    $onLater.seconds_remaining = 119.4
    foreach ($actor in $onLater.actors) { $actor.sequence = 36 }
    return @{
        mode = $Mode; route = 'production-dev-menu-signal'; before = $before; off = $off; off_later = $offLater
        restarted_off = $restarted; on_before = $onBefore; on = $on; on_later = $onLater
    }
}

function PlayerControlFixture {
    $policy = Get-GodotPlayerControlNegativeCases
    $refusals = @()
    $labels = @()
    foreach ($name in $policy.Keys) {
        $case = $policy[$name]
        $item = @{code = $case.code; id = $case.ids[0]; message = $case.message}
        $refusals += $item
        $label = CopyFixture $item
        $label['case'] = $name
        $labels += $label
    }
    $events = @()
    foreach ($request in @(@(0, 0, 2, 'off_ball_switch'), @(0, 0, 2, 'pass'), @(0, 2, 0, 'pass'),
            @(1, 0, 8, 'off_ball_switch'), @(1, 4, 6, 'restart_taker'))) {
        $mode, $old, $selected, $reason = $request
        $intent = @()
        if ($mode -eq 0) { $intent = @(0..3) }
        $events += @{
            old_id = $old; selected_actor_id = $selected; target_id = $selected; reason = $reason; mode = $mode
            tick = 12; owner_id = -1; ai_intent_actor_ids = $intent
            ai_actor_ids = @($intent | Where-Object { $_ -ne $selected })
        }
    }
    return @{
        complete = $true; failures = @(); cases_completed = @(1..12 | ForEach-Object { 'F{0:d2}' -f $_ })
        source_script = 'res://match/match.gd'; main_scene = 'res://match/match.tscn'; project_version = '0.5.0-preview'
        input_schema_version = 3; native_events = @{key = 101; joy_button = 31; joy_motion = 31}; mouse_events = 2
        command_refusals = $refusals; expected_command_refusals = $labels
        unexpected_command_refusals = @(); integration_errors = @(); unexpected_integration_errors = @()
        focus_changes = $events; headless = $true; engine = '4.7.2-stable (official)'
        camera_handoff_motion = @{
            start_tick = 5; end_tick = 55; sampled_frames = 50; consecutive = $true; maximum_step = 0.75
            minimum_right_dot = 1.0; ball_visible = $true; end_phase = 1; camera_mode = 'broadcast'
            selected_actor_id = 2; keeper_visible = $true; focus_progress_x = 2.0
        }
    }
}

function FocusEvent([int]$Id, [int]$Kind, [int]$Actor, [int]$Target, [int]$Selected,
    [int]$Owner, [int]$Tick, [string]$Reason) {
    return @{
        id = $Id; kind = $Kind; actor = $Actor; target = $Target; selected_actor_id = $Selected
        ball_owner_id = $Owner; tick = $Tick; reason = $Reason; score = @(0, 0)
    }
}

function SelectFixture($State, [int]$Selected, [int[]]$Intent) {
    $State.selected_actor_id = $Selected
    $State.ai_intent_actor_ids = @($Intent)
    $State.ai_actor_ids = @($Intent | Where-Object { $_ -ne $Selected })
    foreach ($actor in $State.actors) { $actor.human = $actor.id -eq $Selected }
    $State.human_sequence = $State.actors[$Selected].sequence
}

function MotionFixture([string]$Control, $Actor, [int]$Starts, [int]$Axis = 0, [int]$Sign = 1) {
    $proof = @{
        control = $Control; event_class = 'InputEventKey'; device = 0; selected_actor_id = $Actor.id
        driver_start_calls = $Starts; before = (CopyFixture $Actor)
    }
    foreach ($stage in @(@('pressed', 18, 1.0), @('settled', 42, 1.2), @('released', 48, 1.2))) {
        $next = CopyFixture $Actor
        $next.sequence += $stage[1]
        $next.position[$Axis] += $stage[2] * $Sign
        $next.velocity = @(0.0, 0.0, 0.0)
        if ($stage[0] -eq 'pressed') { $next.velocity[$Axis] = 5.8 * $Sign }
        $proof[$stage[0]] = $next
    }
    return $proof
}

function FocusSmokeFixture {
    $cases = @()
    $history = @()
    $policy = Get-GodotFocusSmokeCases
    $starts = 3
    foreach ($name in $policy.Keys) {
        $expected = $policy[$name]
        if ($name -eq 'micro_keeper_manual_return') {
            $before = CopyFixture $cases[-1].received
        }
        else {
            $starts += 1
            $history += FocusEvent 0 4 -1 -1 0 -1 0 'training_start'
            $before = ModeState $expected.mode 6 119.9 'PLAYING' $false $expected.from
            $before.driver_start_calls = $starts
            SelectFixture $before $expected.from $expected.intent
            foreach ($actor in $before.actors) {
                $actor.sequence = if ($actor.id -eq $expected.from) { 5 } elseif ($actor.id -in $before.ai_actor_ids) { 0 } else { -1 }
            }
            $before.human_sequence = $before.actors[$expected.from].sequence
            if ($expected.mode -eq 1) {
                $before.actors[0].position = @(-4.0, 0.0, -3.0)
                $before.actors[4].position = @(2.0, 0.0, -3.0)
                $before.actors[8].position = @(-10.0, 0.0, -3.0)
                $before.ball_position = if ($expected.reason -eq 'pass') { @(-3.45, 0.12, -3.0) } else { @(0.0, 0.12, 8.0) }
            }
            else {
                $before.actors[0].position = @(-12.0, 0.0, 0.0)
                $before.actors[2].position = @(-18.5, 0.0, 0.0)
                $before.ball_position = if ($expected.reason -eq 'keeper_ai') { @(-17.95, 0.12, 0.0) } else { @(-12.55, 0.12, 0.0) }
            }
            $before.ball_owner_id = if ($expected.reason -eq 'keeper_ai') { 2 } elseif ($expected.reason -eq 'pass') { $expected.from } else { -1 }
        }
        $after = CopyFixture $before
        $ticks = if ($expected.reason -eq 'keeper_ai') { 60 } else { 2 }
        $after.tick += $ticks
        $after.seconds_remaining -= $ticks / 60.0
        if ($expected.reason -eq 'keeper_ai') {
            $after.actors[0].sequence += $ticks
            $after.actors[2].sequence += 6
            $after.ball_owner_id = 0
            $after.ball_position = @(-12.55, 0.105, 0.0)
            $after.ball_velocity = @(8.0, 0.0, 0.0)
            $events = @(
                (FocusEvent 2 1 2 0 0 -1 ($before.tick + 20) 'kick')
                (FocusEvent 3 6 0 -1 0 0 $after.tick 'received')
            )
        }
        else {
            $after.actors[$expected.from].sequence += 1
            $after.actors[$expected.to].sequence += 1
            $after.ball_owner_id = -1
            if ($expected.reason -eq 'pass') {
                $sign = [Math]::Sign($after.actors[$expected.to].position[0] - $after.actors[$expected.from].position[0])
                $after.ball_position[0] += 0.15 * $sign
                $after.ball_velocity = @((8.0 * $sign), 0.0, 0.0)
                $events = @(
                    (FocusEvent 2 1 $expected.from $expected.to $expected.to -1 ($before.tick + 1) 'kick')
                    (FocusEvent 3 9 $expected.from $expected.to $expected.to -1 ($before.tick + 1) 'pass')
                )
            }
            else {
                $events = @((FocusEvent 1 9 $expected.from $expected.to $expected.to -1 ($before.tick + 1) 'off_ball_switch'))
                if ($name -eq 'preview_off_ball_directional') {
                    $after.actors[0].position[0] -= 0.01
                    $after.actors[8].position[0] -= 0.01
                    $after.actors[8].velocity = @(-0.466, 0.0, 0.0)
                }
            }
        }
        SelectFixture $after $expected.to $expected.intent
        $case = @{
            case = $name; source_script = 'res://match/match.gd'; input = $expected.input; reason = $expected.reason
            before_selected_actor_id = $expected.from; after_selected_actor_id = $expected.to
            before_ball_owner_id = $before.ball_owner_id; after_ball_owner_id = $after.ball_owner_id
            actor_count = $after.actor_count; ai_intent_actor_ids = @($expected.intent); ai_actor_ids = @($after.ai_actor_ids)
            expected_selected_actor_id = $expected.to; before = $before; after = $after; events = $events; passed = $true
        }
        $history += $events
        if ($expected.reason -eq 'pass') {
            $received = CopyFixture $after
            $flightAndHold = if ($name -eq 'micro_pass_keeper') { 60 } else { 30 }
            $received.tick += $flightAndHold
            $received.seconds_remaining -= $flightAndHold / 60.0
            $received.actors[$expected.to].sequence += $flightAndHold
            foreach ($id in $received.ai_actor_ids) { $received.actors[$id].sequence += 2 }
            $received.human_sequence = $received.actors[$expected.to].sequence
            $received.ball_owner_id = $expected.to
            $received.ball_position = @($received.actors[$expected.to].position)
            $received.ball_position[0] -= 0.55 * $sign
            $received.ball_position[1] = 0.105
            $case.received = $received
            $receiptTick = if ($name -eq 'micro_pass_keeper') { $received.tick - 45 } else { $received.tick }
            $history += FocusEvent 4 6 $expected.to -1 $expected.to $expected.to $receiptTick 'received'
        }
        $cases += $case
    }
    return @{cases = $cases; history = $history; motion = (MotionFixture 'selected field D' $cases[0].after.actors[4] $cases[0].after.driver_start_calls)}
}

try {
    $configuration = @(
        'config/name="Futsal — Laboratorio 5v5"'
        'config/version="0.5.0-preview"'
        'run/main_scene="res://match/match.tscn"'
        'preparation/input_schema_version=3'
    ) -join "`r`n"
    Assert-GodotProjectConfiguration $configuration
    Check 'exact schema-3 gameplay project configuration passes' $true
    foreach ($change in @(
            @('0.5.0-preview', '0.4.0-preview'), @('0.5.0-preview', '0.3.0-preview'),
            @('input_schema_version=3', 'input_schema_version=2'),
            @('Laboratorio 5v5', 'Microdemo G1'), @('match/match.tscn', 'bootstrap/bootstrap.tscn'))) {
        Rejected "old or incorrect production configuration fails: $($change[0]) -> $($change[1])" {
            Assert-GodotProjectConfiguration ($configuration.Replace($change[0], $change[1]))
        }
    }
    foreach ($mode in @(0, 1)) {
        $intent = if ($mode -eq 1) { @(0..9) } else { @(0..3) }
        $state = ModeState $mode 12 119.8 'PLAYING' $true 2
        Assert-GodotModeState $state $mode $intent 'PLAYING' 2
        Check "mode $mode accepts manually selected HOME keeper and latent AI intent" $true
        Rejected "mode $mode keeper selection cannot masquerade as default actor zero" {
            Assert-GodotModeState $state $mode $intent 'PLAYING'
        }
        $off = ModeState $mode 12 119.8 'PLAYING' $false 2
        Assert-GodotModeState $off $mode @() 'PLAYING' 2
        Check "mode $mode all-off intent stays all-off with keeper selected" $true
        $partial = CopyFixture $state
        $partial.ai_intent_actor_ids = @($intent | Where-Object { $_ -ne 0 })
        $partial.ai_actor_ids = @($partial.ai_intent_actor_ids | Where-Object { $_ -ne 2 })
        Assert-GodotModeState $partial $mode $partial.ai_intent_actor_ids 'PLAYING' 2
        Check "mode $mode deselected zero stays disabled when absent from intent" $true
        foreach ($change in @(
                @{selected_actor_id = '2'}, @{selected_actor_id = 1}, @{selected_actor_id = 20},
                @{ai_actor_ids = $intent}, @{ai_intent_actor_ids = @()}, @{ai_intent_actor_ids = @(2, 2)})) {
            $mutant = CopyFixture $state
            foreach ($key in $change.Keys) { $mutant[$key] = $change[$key] }
            Rejected ("selection/intent mismatch mode $mode : " + ($change | ConvertTo-Json -Compress)) {
                Assert-GodotModeState $mutant $mode $intent 'PLAYING' 2
            }
        }
        $mutant = CopyFixture $state
        $mutant.actors[0].human = $true
        Rejected "mode $mode forbids two human-controlled identities" {
            Assert-GodotModeState $mutant $mode $intent 'PLAYING' 2
        }
        $mutant = CopyFixture $state
        $mutant.actors[2].human = $false
        Rejected "mode $mode cannot omit the selected keeper human flag" {
            Assert-GodotModeState $mutant $mode $intent 'PLAYING' 2
        }
    }
    $control = PlayerControlFixture
    Assert-GodotPlayerControlReport $control
    Check 'current F11 includes the native HOME restart-taker focus event without granting possession' $true
    foreach ($version in @('0.4.0-preview', '0.5.0-preview')) {
        $versionedControl = CopyFixture $control
        $versionedControl.project_version = $version
        Assert-GodotPlayerControlReport $versionedControl -ProjectVersion $version
        Check "$version retains its explicit player-control contract" $true
        $mutant = CopyFixture $versionedControl
        [void]$mutant.Remove('camera_handoff_motion')
        Rejected "$version cannot omit the native F12 motion window" {
            Assert-GodotPlayerControlReport $mutant -ProjectVersion $version
        }
        $mutant = CopyFixture $versionedControl
        $mutant.focus_changes = @($mutant.focus_changes | Where-Object { $_.reason -cne 'restart_taker' })
        Rejected "$version cannot omit the restart-taker focus event" {
            Assert-GodotPlayerControlReport $mutant -ProjectVersion $version
        }
    }
    $mutant = CopyFixture $control
    $mutant.focus_changes = @($mutant.focus_changes | Where-Object { $_.reason -cne 'restart_taker' })
    Rejected 'F11 completion alone cannot replace the actual restart-taker event' {
        Assert-GodotPlayerControlReport $mutant
    }
    foreach ($change in @(
            @{owner_id = 6}, @{selected_actor_id = 7; target_id = 7},
            @{old_id = 5}, @{reason = 'Restart_Taker'}, @{reason = $true})) {
        $mutant = CopyFixture $control
        foreach ($key in $change.Keys) { $mutant.focus_changes[4][$key] = $change[$key] }
        Rejected ('native restart-taker evidence preserves exact reason and HOME/free-ball invariants: ' + (
                $change | ConvertTo-Json -Compress)) { Assert-GodotPlayerControlReport $mutant }
    }
    Check 'F12 fixed-like motion has a complete authority window and consecutive per-image observations' $true
    Check 'player-control motion fixture does not invent a checks array absent from its producer' (-not $control.Contains('checks'))
    foreach ($positive in @(
            @{name = 'ordinary scheduling is not physics-frame equality'; frames = 122; end = 55; step = 0.38},
            @{name = 'the final authority tick may overshoot the window'; frames = 123; end = 57; step = 0.38},
            @{name = 'the declared sample cap is inclusive'; frames = 6000; end = 55; step = 0.999999},
            @{name = 'zero translation is a finite valid measurement'; frames = 50; end = 55; step = 0})) {
        $candidate = CopyFixture $control
        $candidate.camera_handoff_motion.sampled_frames = $positive.frames
        $candidate.camera_handoff_motion.end_tick = $positive.end
        $candidate.camera_handoff_motion.maximum_step = $positive.step
        Assert-GodotPlayerControlReport $candidate
        Check "F12 motion accepts $($positive.name)" $true
    }
    $mutant = CopyFixture $control
    [void]$mutant.Remove('camera_handoff_motion')
    Rejected 'F12 label and a green legacy summary cannot replace the new motion observation' {
        Assert-GodotPlayerControlReport $mutant
    }
    foreach ($bad in @(
            @{name = 'null'; value = $null}, @{name = 'boolean'; value = $true},
            @{name = 'string'; value = 'motion'}, @{name = 'array'; value = @($control.camera_handoff_motion)},
            @{name = 'empty dictionary'; value = @{}})) {
        $mutant = CopyFixture $control
        $mutant.camera_handoff_motion = $bad.value
        Rejected "F12 motion rejects a $($bad.name) observation" { Assert-GodotPlayerControlReport $mutant }
    }
    foreach ($field in @('start_tick', 'end_tick', 'sampled_frames', 'consecutive', 'maximum_step',
            'minimum_right_dot', 'ball_visible', 'end_phase', 'camera_mode',
            'selected_actor_id', 'keeper_visible', 'focus_progress_x')) {
        $mutant = CopyFixture $control
        [void]$mutant.camera_handoff_motion.Remove($field)
        Rejected "F12 motion requires the explicit $field field" { Assert-GodotPlayerControlReport $mutant }
    }
    foreach ($field in @('start_tick', 'end_tick', 'sampled_frames')) {
        foreach ($bad in @(
                @{name = 'string'; value = [string]$control.camera_handoff_motion[$field]},
                @{name = 'float'; value = [double]$control.camera_handoff_motion[$field]},
                @{name = 'boolean'; value = $true}, @{name = 'negative'; value = -1},
                @{name = 'null'; value = $null})) {
            $mutant = CopyFixture $control
            $mutant.camera_handoff_motion[$field] = $bad.value
            Rejected "F12 motion rejects $($bad.name) $field" { Assert-GodotPlayerControlReport $mutant }
        }
    }
    foreach ($change in @(
            @{end_tick = 54}, @{end_tick = 5}, @{end_tick = 4},
            @{sampled_frames = 0}, @{sampled_frames = 6001},
            @{consecutive = $false}, @{consecutive = 'true'}, @{consecutive = 1})) {
        $mutant = CopyFixture $control
        foreach ($key in $change.Keys) { $mutant.camera_handoff_motion[$key] = $change[$key] }
        Rejected ('F12 motion rejects an incomplete or nonconsecutive window: ' + ($change | ConvertTo-Json -Compress)) {
            Assert-GodotPlayerControlReport $mutant
        }
    }
    foreach ($bad in @(
            @{name = 'boundary'; value = 1.0}, @{name = 'jump'; value = 1.01}, @{name = 'negative'; value = -0.01},
            @{name = 'string'; value = '0.75'}, @{name = 'boolean'; value = $false}, @{name = 'null'; value = $null},
            @{name = 'NaN'; value = [double]::NaN}, @{name = 'positive infinity'; value = [double]::PositiveInfinity},
            @{name = 'negative infinity'; value = [double]::NegativeInfinity}, @{name = 'array'; value = @(0.75)})) {
        $mutant = CopyFixture $control
        $mutant.camera_handoff_motion.maximum_step = $bad.value
        Rejected "F12 motion rejects a $($bad.name) maximum_step" { Assert-GodotPlayerControlReport $mutant }
    }
    foreach ($field in @('minimum_right_dot', 'focus_progress_x')) {
        foreach ($bad in @($null, $true, '1', [double]::NaN, [double]::PositiveInfinity, @(1.0))) {
            $mutant = CopyFixture $control
            $mutant.camera_handoff_motion[$field] = $bad
            $kind = if ($null -eq $bad) { 'null' } else { $bad.GetType().Name + ':' + [string]$bad }
            Rejected "F12 rejects nonnumeric or nonfinite $field ($kind)" { Assert-GodotPlayerControlReport $mutant }
        }
    }
    foreach ($change in @(
            @{minimum_right_dot = 0.999}, @{minimum_right_dot = 0.5}, @{minimum_right_dot = 1.001},
            @{focus_progress_x = 1.0}, @{focus_progress_x = 0.0}, @{focus_progress_x = -1.0})) {
        $mutant = CopyFixture $control
        foreach ($key in $change.Keys) { $mutant.camera_handoff_motion[$key] = $change[$key] }
        Rejected ('F12 preserves the orientation and focus limits: ' + ($change | ConvertTo-Json -Compress)) {
            Assert-GodotPlayerControlReport $mutant
        }
    }
    foreach ($field in @('ball_visible', 'keeper_visible')) {
        foreach ($bad in @($null, $false, 'true', 1)) {
            $mutant = CopyFixture $control
            $mutant.camera_handoff_motion[$field] = $bad
            $kind = if ($null -eq $bad) { 'null' } else { $bad.GetType().Name + ':' + [string]$bad }
            Rejected "F12 requires observed visibility $field ($kind)" { Assert-GodotPlayerControlReport $mutant }
        }
    }
    foreach ($field in @('end_phase', 'selected_actor_id')) {
        foreach ($bad in @($null, $true, '1', 1.0, 0, 3)) {
            $mutant = CopyFixture $control
            $mutant.camera_handoff_motion[$field] = $bad
            $kind = if ($null -eq $bad) { 'null' } else { $bad.GetType().Name + ':' + [string]$bad }
            Rejected "F12 requires the actual phase and keeper identity $field ($kind)" { Assert-GodotPlayerControlReport $mutant }
        }
    }
    foreach ($bad in @($null, $true, 'Broadcast', 'corner', 'returning')) {
        $mutant = CopyFixture $control
        $mutant.camera_handoff_motion.camera_mode = $bad
        Rejected "F12 requires actual broadcast mode ($bad)" { Assert-GodotPlayerControlReport $mutant }
    }
    $historicalControl = CopyFixture $control
    $historicalControl.project_version = '0.3.0-preview'
    $historicalControl.input_schema_version = 2
    [void]$historicalControl.Remove('camera_handoff_motion')
    $historicalControl.focus_changes = @($historicalControl.focus_changes | Where-Object { $_.reason -cne 'restart_taker' })
    $historicalPolicy = Get-GodotPlayerControlNegativeCases -ProjectVersion '0.3.0-preview'
    for ($index = 0; $index -lt $historicalControl.expected_command_refusals.Count; $index++) {
        $message = $historicalPolicy[$historicalControl.expected_command_refusals[$index].case].message
        $historicalControl.command_refusals[$index].message = $message
        $historicalControl.expected_command_refusals[$index].message = $message
    }
    Assert-GodotPlayerControlReport $historicalControl -ProjectVersion '0.3.0-preview' -InputSchemaVersion 2
    Check 'explicit historical player-control replay preserves the exact old phase and contact refusals' $true
    Check 'explicit 0.3 player-control replay does not invent a later F12 motion observation' (
        -not $historicalControl.Contains('camera_handoff_motion'))
    $mutant = CopyFixture $historicalControl
    $mutant.focus_changes += CopyFixture $control.focus_changes[4]
    Rejected 'explicit 0.3 replay cannot silently adopt the 0.4 restart-taker protocol' {
        Assert-GodotPlayerControlReport $mutant -ProjectVersion '0.3.0-preview' -InputSchemaVersion 2
    }
    Rejected 'historical native player-control evidence is not current 0.4 acceptance' {
        Assert-GodotPlayerControlReport $historicalControl
    }
    foreach ($label in @('F07 pase sin contacto', 'F11 comando tras FINISHED')) {
        $mutant = CopyFixture $control
        $index = [array]::IndexOf(@($mutant.expected_command_refusals | ForEach-Object { $_.case }), $label)
        $mutant.command_refusals[$index].message = $historicalPolicy[$label].message
        $mutant.expected_command_refusals[$index].message = $historicalPolicy[$label].message
        Rejected "old refusal text cannot authorize a new 0.5 result: $label" { Assert-GodotPlayerControlReport $mutant }
    }
    Check 'source-defined player-control report requires behavioral records and exact negatives' $true
    foreach ($change in @(
            @{complete = $false}, @{complete = 'true'}, @{cases_completed = @('F01')},
            @{source_script = 'res://bootstrap/bootstrap.gd'}, @{input_schema_version = '3'}, @{input_schema_version = 2},
            @{integration_errors = @('hidden')}, @{unexpected_command_refusals = @('hidden')},
            @{native_events = @{key = '101'; joy_button = 31; joy_motion = 31}}, @{mouse_events = 0},
            @{focus_changes = @()}, @{command_refusals = @()}, @{expected_command_refusals = @()})) {
        $mutant = CopyFixture $control
        foreach ($key in $change.Keys) { $mutant[$key] = $change[$key] }
        Rejected ('player-control report rejects incomplete/invalid proof: ' + ($change | ConvertTo-Json -Compress -Depth 16)) {
            Assert-GodotPlayerControlReport $mutant
        }
    }
    foreach ($change in @(
            @{selected_actor_id = 1}, @{target_id = 0}, @{owner_id = 2}, @{mode = 99}, @{reason = 'teleport'},
            @{ai_actor_ids = @(0..3)}, @{ai_intent_actor_ids = @(0, 2, 2)})) {
        $mutant = CopyFixture $control
        foreach ($key in $change.Keys) { $mutant.focus_changes[1][$key] = $change[$key] }
        Rejected ('native focus event rejects false transfer: ' + ($change | ConvertTo-Json -Compress)) {
            Assert-GodotPlayerControlReport $mutant
        }
    }
    $mutant = CopyFixture $control
    $mutant.command_refusals[0].message = 'invented matching failure'
    $mutant.expected_command_refusals[0].message = 'invented matching failure'
    Rejected 'player-control actual and expected messages cannot authorize invented failures' { Assert-GodotPlayerControlReport $mutant }
    $mutant = CopyFixture $control
    $mutant.focus_changes = @($mutant.focus_changes | Where-Object { $_.old_id -ne 2 })
    Rejected 'accepted pass to keeper is insufficient without the manual pass back' { Assert-GodotPlayerControlReport $mutant }
    foreach ($count in @(6, 8)) {
        $mutant = CopyFixture $control
        $mutant.command_refusals = @($mutant.command_refusals * 2)[0..($count - 1)]
        $mutant.expected_command_refusals = @($mutant.expected_command_refusals * 2)[0..($count - 1)]
        Rejected "player-control requires seven source-defined negatives, not $count" { Assert-GodotPlayerControlReport $mutant }
    }
    $mutant = CopyFixture $control
    $mutant.command_refusals[5].id = 0
    $mutant.expected_command_refusals[5].id = 0
    Rejected 'reentrant F08 negative must name the actual selected actor eight' { Assert-GodotPlayerControlReport $mutant }
    $mutant = CopyFixture $control
    $mutant.command_refusals[1].code = '44'
    $mutant.expected_command_refusals[1].code = '44'
    Rejected 'matching string error codes do not replace native integer refusals' { Assert-GodotPlayerControlReport $mutant }
    $mutant = CopyFixture $control
    $mutant.command_refusals = @($mutant.command_refusals[1], $mutant.command_refusals[0]) + @($mutant.command_refusals[2..6])
    $mutant.expected_command_refusals = @($mutant.expected_command_refusals[1], $mutant.expected_command_refusals[0]) + @($mutant.expected_command_refusals[2..6])
    Rejected 'matching reordered negatives do not replace native case order' { Assert-GodotPlayerControlReport $mutant }
    $mutant = CopyFixture $control
    $mutant.expected_command_refusals[0].case = 'F03 invented label'
    Rejected 'native negative labels must match the exact source assertions' { Assert-GodotPlayerControlReport $mutant }
    $mutant = CopyFixture $control
    $mutant.cases_completed[11] = 'F01'
    Rejected 'twelve labels cannot hide a missing F12 completion' { Assert-GodotPlayerControlReport $mutant }
    Check 'producer marker is read from a literal native report, not guessed' (
        (Get-GodotNativeReportPrefix 'print("FUTSAL_PRODUCER_TESTS " + JSON.stringify(report))') -ceq 'FUTSAL_PRODUCER_TESTS')
    $methodMarker = "func _test_marker() -> String:`n`treturn `"FUTSAL_CAMERA_FIXTURE_TESTS`"`n"
    Check 'inherited native report may use one literal typed marker method' (
        (Get-GodotNativeReportPrefix $methodMarker) -ceq 'FUTSAL_CAMERA_FIXTURE_TESTS')
    Rejected 'computed marker method is not a reviewed literal protocol' {
        Get-GodotNativeReportPrefix "func _test_marker() -> String:`n`treturn PREFIX + `"TESTS`"`n"
    }
    Rejected 'method and printed report cannot declare different markers' {
        Get-GodotNativeReportPrefix ($methodMarker + 'print("FUTSAL_OTHER_TESTS " + data)')
    }
    Rejected 'missing producer report marker is explicit' { Get-GodotNativeReportPrefix 'extends SceneTree' }
    Rejected 'ambiguous producer report markers fail' {
        Get-GodotNativeReportPrefix 'print("FUTSAL_FIRST_TESTS " + data); print("FUTSAL_SECOND_TESTS " + data)'
    }
    Assert-GodotOutput (ProcessResult)
    Check 'clean output passes' $true
    $ioEscaped = $false
    try { Rejected 'fixture I/O faults must not become accepted negative evidence' { throw [IO.IOException]::new('deliberate fixture I/O failure') } }
    catch [IO.IOException] { $ioEscaped = $true }
    Check 'negative-fixture harness propagates I/O faults instead of counting a false green' $ioEscaped
    $expected = Get-MatchHudExpectedErrors
    $errors = ($expected.Keys | ForEach-Object {
        $line = $_
        1..$expected[$line] | ForEach-Object { $line }
    }) -join "`n"
    Assert-GodotOutput (ProcessResult '' $errors) -ExpectedErrors $expected
    Check 'all source-defined legacy and restart HUD validation messages pass' $true
    $hudCount = [int](($expected.Values | Measure-Object -Sum).Sum)
    $hudFixture = @{
        expected_validation_errors = $hudCount; failures = @(); new_expected_error_counts = Get-MatchHudNewExpectedErrors
        checks = @(Get-MatchHudRequiredCheckNames | ForEach-Object { @{name = $_; passed = $true} })
    }
    Assert-GodotHudReport $hudFixture
    Check 'HUD structured diagnostic accounting uses the exact source policy and integer type' $true
    foreach ($wrongCount in @(0, ($hudCount - 1), ($hudCount + 1), [string]$hudCount, $null, $true)) {
        Rejected "HUD structured report rejects invalid diagnostic count: $wrongCount / $($null -eq $wrongCount)" {
            $badHud = CopyFixture $hudFixture
            $badHud.expected_validation_errors = $wrongCount
            Assert-GodotHudReport $badHud
        }
    }
    Rejected 'HUD structured report cannot conceal a failed assertion' {
        $badHud = CopyFixture $hudFixture
        $badHud.failures = @('hidden')
        Assert-GodotHudReport $badHud
    }
    foreach ($field in @('checks', 'new_expected_error_counts')) {
        Rejected "current HUD cannot omit negative linkage $field" {
            $badHud = CopyFixture $hudFixture
            [void]$badHud.Remove($field)
            Assert-GodotHudReport $badHud
        }
    }
    foreach ($message in $hudFixture.new_expected_error_counts.Keys) {
        foreach ($count in @(0, 1, '6', $null, $true)) {
            Rejected "HUD typed per-message count $message $count / $($null -eq $count)" {
                $badHud = CopyFixture $hudFixture
                $badHud.new_expected_error_counts[$message] = $count
                Assert-GodotHudReport $badHud
            }
        }
    }
    Rejected 'HUD cannot replace a rejected restart assertion with a generic passing label' {
        $badHud = CopyFixture $hudFixture
        $badHud.checks[12].name = 'unrelated passing assertion'
        Assert-GodotHudReport $badHud
    }
    Rejected 'HUD cannot conceal a nonboolean negative assertion' {
        $badHud = CopyFixture $hudFixture
        $badHud.checks[12].passed = 'true'
        Assert-GodotHudReport $badHud
    }
    $restartError = 'ERROR: MatchHUD.present_restart: estado de reanudación incoherente o no válido.'
    $withoutRestart = ($errors -split "`n" | Where-Object { $_ -cne $restartError }) -join "`n"
    foreach ($count in @(0, ($expected[$restartError] - 1), ($expected[$restartError] + 1))) {
        $messages = $withoutRestart + "`n" + ((@($restartError) * $count) -join "`n")
        Rejected "restart diagnostics must exactly match the source list, not $count" {
            Assert-GodotOutput (ProcessResult '' $messages) -ExpectedErrors $expected
        }
    }
    Rejected 'restart diagnostic is an exact sentence, not a broad new allowance' {
        Assert-GodotOutput (ProcessResult '' $errors.Replace('estado de reanudación incoherente', 'otro estado')) -ExpectedErrors $expected
    }
    $selectionError = 'ERROR: MatchHUD.set_selected_actor: se requiere identidad válida y control humano de un actor local.'
    $withoutSelection = ($errors -split "`n" | Where-Object { $_ -cne $selectionError }) -join "`n"
    foreach ($count in @(0, 5, 7)) {
        $messages = $withoutSelection + "`n" + ((@($selectionError) * $count) -join "`n")
        Rejected "selected-actor HUD diagnostics require exactly six, not $count" {
            Assert-GodotOutput (ProcessResult '' $messages) -ExpectedErrors $expected
        }
    }
    Rejected 'selected-actor diagnostic must match the exact source sentence' {
        Assert-GodotOutput (ProcessResult '' $errors.Replace('identidad válida y control humano', 'identidad válida y control IA')) -ExpectedErrors $expected
    }
    Rejected 'missing HUD diagnostic fails' { Assert-GodotOutput (ProcessResult) -ExpectedErrors $expected }
    Rejected 'extra allowed HUD diagnostic fails' {
        Assert-GodotOutput (ProcessResult '' ($errors + "`n" + @($expected.Keys)[0])) -ExpectedErrors $expected
    }
    Rejected 'near-match HUD message fails' {
        Assert-GodotOutput (ProcessResult '' $errors.Replace('entre 0 y 999.', 'entre 0 y 999!')) -ExpectedErrors $expected
    }
    foreach ($line in @('ERROR: unrelated engine failure', 'SCRIPT ERROR: invalid call',
            'WARNING: unrelated renderer warning', 'Parse Error: invalid script')) {
        Rejected "unexpected $($line.Split(':')[0]) is not hidden by expected HUD errors" {
            Assert-GodotOutput (ProcessResult '' ($errors + "`n" + $line)) -ExpectedErrors $expected
        }
    }
    Rejected 'nonzero exit cannot pass on report or messages' { Assert-GodotOutput (ProcessResult '' '' 7) }
    $coreRefusals = ProcessResult "PASS expected refusal: first`nPASS expected refusal: second"
    Assert-GodotSimulationRefusals $coreRefusals @{expected_refusals = 2}
    Check 'core refusal total follows actual native negative assertions' $true
    foreach ($count in @('2', 0, 1, 27)) {
        Rejected "a historical or malformed core refusal count cannot replace native evidence: $count / $($count.GetType().Name)" {
            Assert-GodotSimulationRefusals $coreRefusals @{expected_refusals = $count}
        }
    }
    $developmentWarnings = Get-DevelopmentIntegrationExpectedWarnings
    $warnings = ($developmentWarnings.Keys | ForEach-Object {
        $line = $_
        1..$developmentWarnings[$line] | ForEach-Object { $line }
    }) -join "`n"
    Rejected 'development diagnostics fail without their explicit allowance' { Assert-GodotOutput (ProcessResult '' $warnings) }
    Assert-GodotOutput (ProcessResult '' $warnings) -ExpectedDevelopmentWarnings $developmentWarnings
    Check 'eight exact development diagnostics pass only in their negative suite' $true
    Rejected 'missing development diagnostic fails' {
        Assert-GodotOutput (ProcessResult) -ExpectedDevelopmentWarnings $developmentWarnings
    }
    Rejected 'extra development diagnostic fails' {
        Assert-GodotOutput (ProcessResult '' ($warnings + "`n" + @($developmentWarnings.Keys)[0])) `
            -ExpectedDevelopmentWarnings $developmentWarnings
    }
    Rejected 'near-match development diagnostic fails' {
        Assert-GodotOutput (ProcessResult '' $warnings.Replace('no válido', 'no válido!')) `
            -ExpectedDevelopmentWarnings $developmentWarnings
    }
    foreach ($line in @('ERROR: unrelated failure', 'SCRIPT ERROR: invalid call', 'WARNING: unrelated warning')) {
        Rejected "development allowance cannot hide $line" {
            Assert-GodotOutput (ProcessResult '' ($warnings + "`n" + $line)) -ExpectedDevelopmentWarnings $developmentWarnings
        }
    }
    Rejected 'development allowance cannot whitelist arbitrary engine warnings' {
        Assert-GodotOutput (ProcessResult '' 'WARNING: arbitrary') -ExpectedDevelopmentWarnings @{'WARNING: arbitrary' = 1}
    }
    $previewIntegration = @{
        unexpected_integration_errors = @(); unexpected_command_refusals = @()
        expected_development_errors = @(Get-DevelopmentIntegrationNegativeCases).Count
        error_codes = @(Get-DevelopmentIntegrationNegativeCases | ForEach-Object { $_.code })
        command_refusals = @(); expected_command_refusals = @()
    }
    $refusalCases = @(Get-DevelopmentIntegrationNegativeCases | Where-Object { $null -ne $_.refusal })
    for ($index = 0; $index -lt $refusalCases.Count; $index++) {
        $case = $refusalCases[$index]
        $previewIntegration.command_refusals += @{code = $case.code; id = -1; message = $case.refusal}
        $previewIntegration.expected_command_refusals += @{code = $case.code; id = -1; message = $case.refusal; case = $case.case}
    }
    Assert-PreviewIntegrationReport $previewIntegration
    Check 'preview integration accounts for intentional errors and refusals' $true
    foreach ($change in @(
            @{unexpected_integration_errors = @('hidden')}, @{unexpected_command_refusals = @('hidden')},
            @{expected_development_errors = 0}, @{error_codes = @(31)}, @{command_refusals = @()},
            @{expected_command_refusals = @()})) {
        $mutant = CopyFixture $previewIntegration
        foreach ($key in $change.Keys) { $mutant[$key] = $change[$key] }
        Rejected ('preview integration rejects mismatched accounting: ' + ($change.Keys -join ',')) {
            Assert-PreviewIntegrationReport $mutant
        }
    }
    $mutant = CopyFixture $previewIntegration
    $mutant.command_refusals[0].message = 'different'
    Rejected 'preview integration rejects a different refusal message' { Assert-PreviewIntegrationReport $mutant }
    $mutant.expected_command_refusals[0].message = 'different'
    Rejected 'mutually matching invented refusal messages cannot whitelist themselves' { Assert-PreviewIntegrationReport $mutant }
    Check 'an obsolete selected-zero negative is a producer dependency' (
        -not [string]::IsNullOrEmpty((Get-GodotDevelopmentNegativeDependency 'var invalid_ids: Array[int] = [0]')))
    Check 'unknown-ID negative is compatible with latent selected intent' (
        [string]::IsNullOrEmpty((Get-GodotDevelopmentNegativeDependency 'var invalid_ids: Array[int] = [20]')))
    $mutant = CopyFixture $previewIntegration
    $mutant.expected_command_refusals[1].case = $mutant.expected_command_refusals[0].case
    Rejected 'preview integration rejects duplicate negative identities' { Assert-PreviewIntegrationReport $mutant }
    $mutant = CopyFixture $previewIntegration
    $mutant.expected_command_refusals[2].case = 'IDs inválidos [0]'
    Rejected 'preview negatives cannot relabel legal latent selected intent as invalid' { Assert-PreviewIntegrationReport $mutant }
    foreach ($count in @(5, 7)) {
        $mutant = CopyFixture $previewIntegration
        $mutant.command_refusals = @($mutant.command_refusals * 2)[0..($count - 1)]
        $mutant.expected_command_refusals = @($mutant.expected_command_refusals * 2)[0..($count - 1)]
        Rejected "preview integration requires six exact refusals, not $count" { Assert-PreviewIntegrationReport $mutant }
    }
    $loader = "WARNING: GENERAL - Message Id Number: 0 | Message Id Name: Loader Message`n" +
        "`twindows_read_data_files_in_registry: Registry lookup failed to get layer manifest files.`n" +
        "`tObjects - 1`n`t`tObject[0] - VK_OBJECT_TYPE_INSTANCE, Handle 12345`n" +
        '   at: _debug_messenger_callback (drivers/vulkan/rendering_context_driver_vulkan.cpp:654)'
    Rejected 'known loader warning fails by default' { Assert-GodotOutput (ProcessResult '' $loader) }
    Assert-GodotOutput (ProcessResult '' $loader) -AllowKnownVulkanLayerWarning
    Check 'explicit loader exception matches the complete one-warning block' $true
    Rejected 'loader header does not whitelist another warning' {
        Assert-GodotOutput (ProcessResult '' $loader.Replace('Registry lookup failed', 'Different warning')) -AllowKnownVulkanLayerWarning
    }
    Rejected 'repeated loader warning fails' {
        Assert-GodotOutput (ProcessResult '' ($loader + "`n" + $loader)) -AllowKnownVulkanLayerWarning
    }
    Rejected 'truncated loader warning fails' {
        Assert-GodotOutput (ProcessResult '' ($loader -split "`n")[0]) -AllowKnownVulkanLayerWarning
    }
    $basic = [ordered]@{ ok = $true; passed = 1; total = 1; checks = @(@{ name = 'one'; passed = $true }); failures = @() }
    $null = ConvertFrom-GodotStructuredReport (ReportOutput $basic) 'FUTSAL_MATCH_SMOKE' -RequireChecks
    Check 'consistent dynamic assertion counts pass' $true
    Rejected 'empty stdout report fails' { ConvertFrom-GodotStructuredReport (ProcessResult) 'FUTSAL_MATCH_SMOKE' }
    $line = (ReportOutput $basic).Stdout
    Rejected 'duplicate native reports fail' {
        ConvertFrom-GodotStructuredReport (ProcessResult ($line + "`n" + $line)) 'FUTSAL_MATCH_SMOKE'
    }
    Rejected 'malformed JSON fails' { ConvertFrom-GodotStructuredReport (ProcessResult 'FUTSAL_MATCH_SMOKE {oops') 'FUTSAL_MATCH_SMOKE' }
    foreach ($change in @(@{ok = 'true'}, @{total = 2}, @{passed = 0}, @{failures = @('hidden failure')},
            @{checks = @{name = 'one'; passed = $true}},
            @{checks = @(@{name = 'one'; passed = 'true'})}, @{total = 0; passed = 0; checks = @()})) {
        $mutant = $basic | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable
        foreach ($key in $change.Keys) { $mutant[$key] = $change[$key] }
        Rejected ('inconsistent report fails: ' + ($change | ConvertTo-Json -Compress -Depth 8)) {
            ConvertFrom-GodotStructuredReport (ReportOutput $mutant) 'FUTSAL_MATCH_SMOKE' -RequireChecks
        }
    }
    $mutant = @{ok = $true; passed = 2; total = 2; checks = @(@{name = 'duplicate'; passed = $true}, @{name = 'duplicate'; passed = $true})}
    Rejected 'duplicate check identities fail' { ConvertFrom-GodotStructuredReport (ReportOutput $mutant) 'FUTSAL_MATCH_SMOKE' -RequireChecks }
    $reportPath = Join-Path $work 'current-run.json'
    $executable = Join-Path $work 'verified-engine.exe'
    $started = [DateTime]::UtcNow.AddSeconds(-1)
    $game = [ordered]@{
        ok = $true; passed = 1; total = 1; checks = @(@{name = 'native check'; passed = $true}); failures = @()
        complete = $true; integration_errors = @()
        process_id = 42; report_path = $reportPath; scope = 'playable-preview-runtime-smoke'
        project_name = 'Futsal — Laboratorio 5v5'; project_version = '0.5.0-preview'; engine_version = '4.7.2-stable (official)'
        input_schema_version = 3
        main_scene = 'res://match/match.tscn'; configured_main_scene = 'res://match/match.tscn'
        editor_binary = $true; headless = $true; executable = $executable
        viewport_width = 1920; viewport_height = 1080; physics_engine = 'Jolt Physics'; physics_ticks_per_second = 60
        capture_phase = 'PLAYING'; mode = 1; final_mode = 1; final_actor_count = 10; initial_tick = 12; final_tick = 16
        final_hud_mode = '5v5 experimental · Sin progresión/XP'
        final_hud_selected = "CONTROL · ID 0`nCAMPO LOCAL"
        initial_selected_actor_id = 0; initial_ai_intent_actor_ids = @(0..9)
        initial_ai_actor_ids = @(1..9); loaded_actors = (ModeState).actors; final_state = (ModeState)
        inputs = @('keyboard D', 'keyboard W', 'joypad left X', 'joypad left Y',
            'Esc / Start', 'Start / Esc', 'Esc / Down / Enter restart',
            'development AI mode 1', 'development AI mode 0') | ForEach-Object { @{control = $_} }
        default_entrypoint = @{
            verified = $true
            before = (ModeState 1 0 120.0)
            after_wait = (ModeState 1 12 119.8)
            after_input = (ModeState 1 60 119.0)
        }
        mode_changes = @(
            @{route = 'production-dev-menu-signal'; requested_mode = 0; before = (ModeState 1 36 119.4 'PAUSED'); after = (ModeState 0)}
            @{route = 'production-dev-menu-signal'; requested_mode = 1; before = (ModeState 0 36 119.4 'PAUSED' $false); after = (ModeState 1)}
        )
        ai_changes = @((AiChange 1), (AiChange 0))
        command_rejections = @(); gpu_validated = $false; rendering_method = 'headless'; rendering_driver = 'dummy'
    }
    $focus = FocusSmokeFixture
    $game['focus_changes'] = $focus.cases
    $game['events'] = $focus.history
    $restoreBefore = CopyFixture $focus.cases[-1].after
    $restoreBefore.phase = 'PAUSED'
    $restoreAfter = ModeState 1
    $restoreAfter.driver_start_calls = $restoreBefore.driver_start_calls
    $game['mode_changes'] += @{route = 'production-dev-menu-signal'; requested_mode = 1; before = $restoreBefore; after = $restoreAfter}
    $game['final_state'] = ModeState 1 16 (120.0 - 16.0 / 60.0)
    $game['final_state']['driver_start_calls'] = $restoreBefore.driver_start_calls
    $game['inputs'] += @(
        $focus.motion
        (MotionFixture 'physical arrow Right' (ModeState).actors[0] 1)
        (MotionFixture 'physical arrow Up' (ModeState).actors[0] 1 2 -1)
    )
    $game['inputs'] = @(@{
        control = 'default keyboard D'; event_class = 'InputEventKey'; device = 0; driver_start_calls = 0
        before = @{sequence = 12; position = @(-2.0, 0.0, 0.0); velocity = @(0.0, 0.0, 0.0)}
        pressed = @{sequence = 30; position = @(-1.0, 0.0, 0.0); velocity = @(5.8, 0.0, 0.0)}
        settled = @{sequence = 54; position = @(-0.5, 0.0, 0.0); velocity = @(0.0, 0.0, 0.0)}
        released = @{sequence = 60; position = @(-0.5, 0.0, 0.0); velocity = @(0.0, 0.0, 0.0)}
    }) + @($game['inputs'])
    $result = PersistGameReport $game
    $null = FreshGame $result
    Check 'fresh matching file, stdout, native identity and checks pass' $true
    $withoutFocus = CopyFixture $game
    [void]$withoutFocus.Remove('focus_changes')
    $missingFocusResult = PersistGameReport $withoutFocus
    Rejected 'missing focus evidence cannot promote base evidence to complete gameplay acceptance' {
        Read-GodotGameReport -Result $missingFocusResult -ReportPath $reportPath -StartedAt $started `
            -EditorBinary $true -Headless $true -Executable $executable
    }
    Rejected 'an invented focus payload cannot satisfy the exact producer contract' {
        Assert-GodotFocusChangesReport @{focus_changes = @(@{passed = $true})}
    }
    $mutant = CopyFixture $game
    $mutant.mode_changes[1].before.ai_actor_ids = @(1..3)
    $badResult = PersistGameReport $mutant
    Rejected 'final mode switch must preserve disabled AI from the goal drill' { FreshGame $badResult }
    $null = PersistGameReport $game
    Rejected 'unobserved runtime PID fails' {
        $wrongOwner = ProcessResult $result.Stdout
        $wrongOwner.RuntimeProcessIds = @(999)
        FreshGame $wrongOwner
    }
    (Get-Item -LiteralPath $reportPath).LastWriteTimeUtc = $started.AddSeconds(-10)
    Rejected 'stale on-disk report fails' { FreshGame $result }
    $null = PersistGameReport $game
    [IO.File]::WriteAllText($reportPath, '{}')
    Rejected 'stdout and file disagreement fails' { FreshGame $result }
    foreach ($change in @(
            @{process_id = 999}, @{report_path = (Join-Path $work 'wrong.json')},
            @{main_scene = 'res://bootstrap/bootstrap.tscn'}, @{configured_main_scene = 'res://bootstrap/bootstrap.tscn'},
            @{project_version = '0.0.0-preparation'}, @{project_version = '0.1.0-g1'}, @{project_version = '0.2.0-preview'},
            @{input_schema_version = 1}, @{input_schema_version = 2}, @{input_schema_version = '3'},
            @{project_version = '0.3.0-preview'},
            @{complete = $false}, @{complete = 'true'}, @{integration_errors = @('hidden')}, @{integration_errors = $null},
            @{initial_selected_actor_id = 2}, @{initial_selected_actor_id = '0'}, @{initial_ai_intent_actor_ids = @(1..9)},
            @{initial_tick = 99}, @{final_tick = 99}, @{final_hud_selected = "CONTROL · ID 2`nPORTERO LOCAL"},
            @{project_name = 'Futsal — Microdemo G1'}, @{scope = 'playable-g1-runtime-smoke'},
            @{editor_binary = $false}, @{headless = 'true'},
            @{executable = (Join-Path $work 'other.exe')}, @{capture_phase = 'PAUSED'}, @{final_actor_count = 3},
            @{final_actor_count = 4}, @{mode = 0}, @{final_mode = 0}, @{initial_ai_actor_ids = @(1..3)},
            @{mode = '1'}, @{final_actor_count = '10'}, @{process_id = '42'}, @{final_hud_mode = '1v1 de regresión'},
            @{gpu_validated = $true}, @{viewport_width = 1280}, @{command_rejections = @('refused')},
            @{loaded_actors = @(@{id = 0})}, @{inputs = @()}, @{mode_changes = @()}, @{ai_changes = @()},
            @{final_state = (ModeState 0)})) {
        $mutant = $game | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
        foreach ($key in $change.Keys) { $mutant[$key] = $change[$key] }
        $badResult = PersistGameReport $mutant
        Rejected ('false game evidence fails: ' + ($change | ConvertTo-Json -Compress -Depth 16)) { FreshGame $badResult }
    }
    $mutant = $game | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
    [void]$mutant.Remove('default_entrypoint')
    $badResult = PersistGameReport $mutant
    Rejected 'legacy smoke without untouched-default evidence fails' { FreshGame $badResult }
    foreach ($change in @(
            @{stage = 'before'; field = 'phase'; value = 'READY'},
            @{stage = 'after_wait'; field = 'tick'; value = 0},
            @{stage = 'after_wait'; field = 'seconds_remaining'; value = 120.0},
            @{stage = 'after_wait'; field = 'human_sequence'; value = -1},
            @{stage = 'after_input'; field = 'phase'; value = 'PAUSED'},
            @{stage = 'after_input'; field = 'tick'; value = 12},
            @{stage = 'before'; field = 'mode'; value = 0},
            @{stage = 'after_wait'; field = 'actor_count'; value = 4},
            @{stage = 'before'; field = 'actor_count'; value = '10'},
            @{stage = 'after_input'; field = 'physical_actor_ids'; value = @(0..3)},
            @{stage = 'before'; field = 'ai_actor_ids'; value = @(1..3)},
            @{stage = 'before'; field = 'selected_actor_id'; value = 2},
            @{stage = 'after_wait'; field = 'ai_intent_actor_ids'; value = @(1..9)},
            @{stage = 'before'; field = 'driver_start_calls'; value = 1},
            @{stage = 'after_wait'; field = 'driver_start_calls'; value = 1},
            @{stage = 'after_input'; field = 'driver_start_calls'; value = 1})) {
        $mutant = $game | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
        $mutant['default_entrypoint'][$change.stage][$change.field] = $change.value
        $badResult = PersistGameReport $mutant
        Rejected "default-entry evidence fails: $($change.stage)/$($change.field)" { FreshGame $badResult }
    }
    $mutant = CopyFixture $game
    $mutant['mode_changes'][0]['after'] = ModeState 1
    $badResult = PersistGameReport $mutant
    Rejected 'preview twice cannot masquerade as a micro regression' { FreshGame $badResult }
    $mutant = CopyFixture $game
    $mutant['mode_changes'][1]['after'] = ModeState 0
    $badResult = PersistGameReport $mutant
    Rejected 'micro cannot be the published final preview' { FreshGame $badResult }
    foreach ($change in @(
            @{stage = 'off'; field = 'ai_actor_ids'; value = @(1..9)},
            @{stage = 'off'; field = 'seconds_remaining'; value = 120.0},
            @{stage = 'off'; field = 'physical_actor_ids'; value = @(0..3)},
            @{stage = 'off_later'; field = 'tick'; value = 12},
            @{stage = 'restarted_off'; field = 'ai_actor_ids'; value = @(1..9)},
            @{stage = 'on'; field = 'tick'; value = 0},
            @{stage = 'on_later'; field = 'phase'; value = 'PAUSED'})) {
        $mutant = CopyFixture $game
        $mutant['ai_changes'][0][$change.stage][$change.field] = $change.value
        $badResult = PersistGameReport $mutant
        Rejected "AI evidence fails: $($change.stage)/$($change.field)" { FreshGame $badResult }
    }
    foreach ($modeIndex in @(0, 1)) {
        foreach ($change in @(
                @{stage = 'off'; actor = 1; field = 'sequence'; value = -1},
                @{stage = 'off_later'; actor = 1; field = 'sequence'; value = 99},
                @{stage = 'off_later'; actor = 2; field = 'velocity'; value = @(1.0, 0.0, 0.0)},
                @{stage = 'on_later'; actor = 3; field = 'sequence'; value = -1})) {
            $mutant = CopyFixture $game
            $mutant['ai_changes'][$modeIndex][$change.stage]['actors'][$change.actor][$change.field] = $change.value
            $badResult = PersistGameReport $mutant
            Rejected "native AI commands fail: mode-index $modeIndex/$($change.stage)/$($change.field)" { FreshGame $badResult }
        }
    }
    $mutant = CopyFixture $game
    $mutant['default_entrypoint']['after_wait']['actors'][8]['role'] = 1
    $badResult = PersistGameReport $mutant
    Rejected 'new preview field actors cannot be mislabeled as keepers' { FreshGame $badResult }
    $mutant = $game | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
    $mutant['default_entrypoint']['verified'] = $false
    $badResult = PersistGameReport $mutant
    Rejected 'unverified default cannot be repaired by later successful drills' { FreshGame $badResult }
    foreach ($change in @(
            @{stage = 'pressed'; field = 'position'; value = @(-2.0, 0.0, 0.0)},
            @{stage = 'pressed'; field = 'sequence'; value = 12},
            @{stage = 'released'; field = 'velocity'; value = @(5.8, 0.0, 0.0)},
            @{stage = 'released'; field = 'position'; value = @(1.0, 0.0, 0.0)})) {
        $mutant = $game | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
        $mutant['inputs'][0][$change.stage][$change.field] = $change.value
        $badResult = PersistGameReport $mutant
        Rejected "default physical input evidence fails: $($change.stage)/$($change.field)" { FreshGame $badResult }
    }
    $mutant = $game | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
    $mutant['inputs'][0]['driver_start_calls'] = 1
    $badResult = PersistGameReport $mutant
    Rejected 'movement proven only after a driver start fails' { FreshGame $badResult }
    foreach ($count in @(0, 5, 7)) {
        RejectedGame "runtime focus requires exactly six distinct ordered cases, not $count" {
            param($r)
            $r.focus_changes = if ($count -eq 0) { @() } else { @($r.focus_changes * 2)[0..($count - 1)] }
        }
    }
    RejectedGame 'six repeated case records are not six behaviors' { param($r) $r.focus_changes[1] = $r.focus_changes[0] }
    RejectedGame 'runtime focus order follows actual production execution' {
        param($r)
        $r.focus_changes = @($r.focus_changes[1], $r.focus_changes[0]) + @($r.focus_changes[2..5])
    }
    foreach ($change in @(
            @{passed = $false}, @{passed = 'true'}, @{source_script = 'res://tests/fake_host.gd'},
            @{input = 'helper-switch'}, @{reason = 'pass'}, @{before_selected_actor_id = '0'},
            @{after_selected_actor_id = 8}, @{expected_selected_actor_id = 8}, @{actor_count = 4},
            @{before_ball_owner_id = 0}, @{after_ball_owner_id = 4}, @{ai_intent_actor_ids = $null},
            @{ai_intent_actor_ids = @(0)}, @{ai_actor_ids = @(4)})) {
        RejectedGame ('runtime focus rejects false summaries: ' + ($change | ConvertTo-Json -Compress)) {
            param($r)
            foreach ($key in $change.Keys) { $r.focus_changes[0][$key] = $change[$key] }
        }
    }
    foreach ($change in @(
            @{stage = 'before'; field = 'selected_actor_id'; value = 2},
            @{stage = 'after'; field = 'selected_actor_id'; value = '4'},
            @{stage = 'after'; field = 'tick'; value = '8'},
            @{stage = 'after'; field = 'tick'; value = 6},
            @{stage = 'after'; field = 'seconds_remaining'; value = 120.0},
            @{stage = 'after'; field = 'seconds_remaining'; value = 119.8},
            @{stage = 'before'; field = 'driver_start_calls'; value = 0},
            @{stage = 'after'; field = 'driver_start_calls'; value = 5},
            @{stage = 'after'; field = 'human_sequence'; value = 99},
            @{stage = 'after'; field = 'ai_intent_actor_ids'; value = @(4)},
            @{stage = 'after'; field = 'ai_actor_ids'; value = @(0)},
            @{stage = 'after'; field = 'physical_actor_ids'; value = @(0..3)},
            @{stage = 'after'; field = 'score'; value = @(1, 0)},
            @{stage = 'after'; field = 'ball_owner_id'; value = 4})) {
        RejectedGame "runtime focus rejects false snapshot $($change.stage)/$($change.field)/$($change.value)" {
            param($r)
            $r.focus_changes[0][$change.stage][$change.field] = $change.value
        }
    }
    RejectedGame 'focus must advance the old selected actor command sequence' {
        param($r)
        $r.focus_changes[0].after.actors[0].sequence = $r.focus_changes[0].before.actors[0].sequence
    }
    RejectedGame 'focus must advance the new selected actor command sequence' {
        param($r)
        $r.focus_changes[0].before.actors[4].sequence = $r.focus_changes[0].after.actors[4].sequence
    }
    RejectedGame 'focus cannot regress an unselected actor sequence' {
        param($r)
        $r.focus_changes[0].before.actors[5].sequence = 7
        $r.focus_changes[0].after.actors[5].sequence = 6
    }
    RejectedGame 'all-off intent must prevent unrelated native AI commands after selection' {
        param($r)
        $r.focus_changes[0].after.actors[8].sequence += 1
    }
    RejectedGame 'selection changes the human identity rather than adding another human' {
        param($r)
        $r.focus_changes[0].after.actors[0].human = $true
    }
    RejectedGame 'off-ball selection cannot claim a received human pass' {
        param($r)
        $r.focus_changes[0].received = CopyFixture $r.focus_changes[0].after
    }
    RejectedGame 'off-ball input cannot hide an extra pass event' {
        param($r)
        $r.focus_changes[0].events += CopyFixture $r.focus_changes[0].events[0]
    }
    foreach ($change in @(
            @{kind = 1}, @{actor = 1}, @{target = 8}, @{selected_actor_id = 0}, @{ball_owner_id = 4},
            @{tick = 6}, @{tick = 9}, @{id = '1'}, @{reason = 'pass'}, @{score = @(1, 0)})) {
        RejectedGame ('runtime focus rejects false native events: ' + ($change | ConvertTo-Json -Compress)) {
            param($r)
            foreach ($key in $change.Keys) { $r.focus_changes[0].events[0][$key] = $change[$key] }
        }
    }
    RejectedGame 'case events must exist in the production history' {
        param($r)
        $eventIndex = Find-GodotRecordedEvent $r.events $r.focus_changes[0].events[0]
        $r.events = @(for ($i = 0; $i -lt $r.events.Count; $i++) { if ($i -ne $eventIndex) { $r.events[$i] } })
    }
    RejectedGame 'case event identity must not be ambiguous in production history' {
        param($r)
        $r.events += CopyFixture $r.focus_changes[0].events[0]
    }
    RejectedGame 'global history cannot replace native integer event scores with strings' {
        param($r)
        $eventIndex = Find-GodotRecordedEvent $r.events $r.focus_changes[0].events[0]
        $r.events[$eventIndex].score = @('0', '0')
    }
    RejectedGame 'directional selection must move the new actor immediately' {
        param($r)
        $r.focus_changes[1].after.actors[8].position = $r.focus_changes[1].before.actors[8].position
    }
    RejectedGame 'directional selection must retain the held movement velocity' {
        param($r)
        $r.focus_changes[1].after.actors[8].velocity = @(0.0, 0.0, 0.0)
    }
    foreach ($index in @(2, 3, 4)) {
        RejectedGame "human pass $index requires physical received possession, not only an accepted kick" {
            param($r)
            [void]$r.focus_changes[$index].Remove('received')
        }
        RejectedGame "human pass $index changes focus before the receiver owns the ball" {
            param($r)
            $r.focus_changes[$index].after.ball_owner_id = $r.focus_changes[$index].after.selected_actor_id
            $r.focus_changes[$index].after_ball_owner_id = $r.focus_changes[$index].after.selected_actor_id
        }
    }
    RejectedGame 'human pass and focus must occupy the same accepted-kick frame' {
        param($r)
        $eventIndex = Find-GodotRecordedEvent $r.events $r.focus_changes[2].events[1]
        $r.events[$eventIndex].tick += 1
        $r.focus_changes[2].events[1].tick += 1
    }
    RejectedGame 'human pass must precede its focus event' {
        param($r)
        $r.focus_changes[2].events = @($r.focus_changes[2].events[1], $r.focus_changes[2].events[0])
    }
    RejectedGame 'human pass cannot claim physical flight with a stationary ball' {
        param($r)
        $r.focus_changes[2].after.ball_velocity = @(0.0, 0.0, 0.0)
    }
    RejectedGame 'human pass must actually leave its pre-kick ball position' {
        param($r)
        $r.focus_changes[2].after.ball_position = $r.focus_changes[2].before.ball_position
    }
    RejectedGame 'claimed reception must move the ball toward the selected recipient' {
        param($r)
        $r.focus_changes[2].received.ball_position = $r.focus_changes[2].after.ball_position
    }
    RejectedGame 'pass reception must preserve AI all-off intent' {
        param($r)
        $r.focus_changes[2].received.ai_intent_actor_ids = @(0..9)
        $r.focus_changes[2].received.ai_actor_ids = @(0, 1, 2, 3, 5, 6, 7, 8, 9)
    }
    RejectedGame 'possession at reception needs a real production reception event' {
        param($r)
        $r.events = @($r.events | Where-Object { -not ($_.kind -eq 6 -and $_.actor -eq 4) })
    }
    RejectedGame 'physical reception cannot precede the after-kick snapshot' {
        param($r)
        ($r.events | Where-Object { $_.kind -eq 6 -and $_.actor -eq 4 }).tick = $r.focus_changes[2].after.tick
    }
    RejectedGame 'human pass cannot lose receiver focus during physical flight' {
        param($r)
        $eventIndex = Find-GodotRecordedEvent $r.events $r.focus_changes[2].events[1]
        $r.events = @($r.events[0..$eventIndex]) +
            @((FocusEvent 4 9 4 0 0 -1 ($r.focus_changes[2].after.tick + 1) 'off_ball_switch')) +
            @($r.events[($eventIndex + 1)..($r.events.Count - 1)])
    }
    RejectedGame 'a restart cannot bridge a claimed pass reception' {
        param($r)
        $eventIndex = Find-GodotRecordedEvent $r.events $r.focus_changes[2].events[1]
        $r.events = @($r.events[0..$eventIndex]) + @((FocusEvent 5 4 0 -1 0 -1 0 'training_start')) +
            @($r.events[($eventIndex + 1)..($r.events.Count - 1)])
    }
    RejectedGame 'selected keeper remains latent in intent but cannot stay effective AI' {
        param($r)
        $r.focus_changes[3].after.ai_actor_ids = @(2)
        $r.focus_changes[3].ai_actor_ids = @(2)
    }
    RejectedGame 'keeper manual return must continue the received snapshot without reset' {
        param($r)
        $r.focus_changes[4].before.actors[1].position[0] += 0.1
    }
    RejectedGame 'controlled keeper must retain possession for the actual 45-tick hold' {
        param($r)
        ($r.events | Where-Object { $_.kind -eq 6 -and $_.actor -eq 2 }).tick = $r.focus_changes[3].received.tick
    }
    RejectedGame 'controlled keeper cannot autonomously return before manual A' {
        param($r)
        $eventIndex = Find-GodotRecordedEvent $r.events $r.focus_changes[4].events[0]
        $r.events = @($r.events[0..($eventIndex - 1)]) +
            @((FocusEvent 5 1 2 0 2 -1 ($r.focus_changes[4].before.tick - 1) 'kick')) +
            @($r.events[$eventIndex..($r.events.Count - 1)])
    }
    RejectedGame 'autonomous keeper cannot be mislabeled as a human A press' {
        param($r)
        $r.focus_changes[5].input = 'InputEventJoypadButton:A'
    }
    RejectedGame 'autonomous keeper return cannot transfer human focus' {
        param($r)
        $r.focus_changes[5].after.selected_actor_id = 2
        $r.focus_changes[5].after_selected_actor_id = 2
    }
    RejectedGame 'autonomous keeper proof cannot add a focus event' {
        param($r)
        $r.focus_changes[5].events += CopyFixture $r.focus_changes[0].events[0]
    }
    RejectedGame 'autonomous keeper return requires later physical arrival' {
        param($r)
        $r.focus_changes[5].events[1].tick = $r.focus_changes[5].events[0].tick
    }
    RejectedGame 'autonomous keeper must receive actual AI commands' {
        param($r)
        $r.focus_changes[5].after.actors[2].sequence = $r.focus_changes[5].before.actors[2].sequence
    }
    foreach ($where in @('before-pass', 'after-pass', 'after-reception')) {
        RejectedGame "keeper AI cannot omit real focus events $where from its case payload" {
            param($r)
            $case = $r.focus_changes[5]
            $offset = if ($where -eq 'after-reception') { 1 } else { 0 }
            $eventIndex = Find-GodotRecordedEvent $r.events $case.events[$offset]
            $tick = if ($where -eq 'before-pass') { $case.before.tick + 1 } else { $case.events[$offset].tick }
            if ($where -ne 'before-pass') { $eventIndex += 1 }
            $tail = @()
            if ($eventIndex -lt $r.events.Count) { $tail = @($r.events[$eventIndex..($r.events.Count - 1)]) }
            $r.events = @($r.events[0..($eventIndex - 1)]) + @((FocusEvent 5 9 0 2 2 -1 $tick 'off_ball_switch')) + $tail
        }
    }
    foreach ($controlName in @('selected field D', 'physical arrow Right', 'physical arrow Up')) {
        RejectedGame "mandatory selected/arrow motion proof cannot be missing: $controlName" {
            param($r)
            $r.inputs = @($r.inputs | Where-Object { $_.control -cne $controlName })
        }
        RejectedGame "mandatory selected/arrow motion must stop on release: $controlName" {
            param($r)
            ($r.inputs | Where-Object { $_.control -ceq $controlName }).released.velocity = @(2.0, 0.0, 0.0)
        }
    }
    RejectedGame 'selected-player movement cannot be substituted with an old actor command feed' {
        param($r)
        ($r.inputs | Where-Object { $_.control -ceq 'selected field D' }).selected_actor_id = 0
    }
    RejectedGame 'selected-player movement must continue the switched actor without another setup' {
        param($r)
        ($r.inputs | Where-Object { $_.control -ceq 'selected field D' }).driver_start_calls += 1
    }
    RejectedGame 'the final published preview must follow all keeper cases' {
        param($r)
        $r.final_state.driver_start_calls += 1
    }
    RejectedGame 'the third development-mode restoration is mandatory' {
        param($r)
        $r.mode_changes = @($r.mode_changes[0..1])
    }
    RejectedGame 'final development-mode restoration cannot precede keeper AI completion' {
        param($r)
        $r.mode_changes[2].before.tick = $r.focus_changes[5].after.tick - 1
    }
    $pngPath = Join-Path $work 'invalid.png'
    [IO.File]::WriteAllBytes($pngPath, [byte[]](1, 2, 3))
    Check 'truncated PNG fails' (-not (Test-GodotPng $pngPath))
    Check 'missing PNG fails' (-not (Test-GodotPng (Join-Path $work 'missing.png')))
    # Header fixture only; live captures must also pass the native image/content checks.
    $png = [byte[]]::new(2048)
    [Convert]::FromHexString('89504E470D0A1A0A0000000D494844520000078000000438').CopyTo($png, 0)
    [IO.File]::WriteAllBytes($pngPath, $png)
    Check 'PNG header with native 1920x1080 dimensions passes' (Test-GodotPng $pngPath)
    $png[19] = 0
    [IO.File]::WriteAllBytes($pngPath, $png)
    Check 'wrong PNG width fails' (-not (Test-GodotPng $pngPath))
    $png[19] = 128
    $png[23] = 0
    [IO.File]::WriteAllBytes($pngPath, $png)
    Check 'wrong PNG height fails' (-not (Test-GodotPng $pngPath))
    $png[23] = 56
    [IO.File]::WriteAllBytes($pngPath, $png)
    $rendered = $game | ConvertTo-Json -Depth 16 | ConvertFrom-Json -AsHashtable
    $rendered['headless'] = $false
    $rendered['gpu_validated'] = $true
    $rendered['rendering_method'] = 'forward_plus'
    $rendered['rendering_driver'] = 'vulkan'
    $rendered['gpu_name'] = 'Fixture GPU'
    $rendered['capture_path'] = $pngPath
    $renderResult = PersistGameReport $rendered
    $header = "Vulkan 1.4.329 - Forward+ - Using Device #0: Fixture - Fixture GPU`n"
    $renderResult.Stdout = $header + $renderResult.Stdout
    $null = Read-GodotGameReport -Result $renderResult -ReportPath $reportPath -StartedAt $started `
        -EditorBinary $true -Headless $false -Executable $executable -CapturePath $pngPath
    Check 'rendered-mode report must agree with native startup and fresh PNG header' $true
    Rejected 'GPU name mismatch against native output fails' {
        $wrongGpu = ProcessResult ($renderResult.Stdout.Replace('Fixture - Fixture GPU', 'Different - Other GPU'))
        Read-GodotGameReport -Result $wrongGpu -ReportPath $reportPath -StartedAt $started `
            -EditorBinary $true -Headless $false -Executable $executable -CapturePath $pngPath
    }
    Rejected 'renderer mismatch against native output fails' {
        $wrongRenderer = ProcessResult ($renderResult.Stdout.Replace(' - Forward+ - ', ' - Mobile - '))
        Read-GodotGameReport -Result $wrongRenderer -ReportPath $reportPath -StartedAt $started `
            -EditorBinary $true -Headless $false -Executable $executable -CapturePath $pngPath
    }
    Rejected 'unrequested capture path fails' {
        Read-GodotGameReport -Result $renderResult -ReportPath $reportPath -StartedAt $started `
            -EditorBinary $true -Headless $false -Executable $executable -CapturePath (Join-Path $work 'another.png')
    }
    (Get-Item -LiteralPath $pngPath).LastWriteTimeUtc = $started.AddSeconds(-10)
    Rejected 'stale PNG fails even with fresh JSON' {
        Read-GodotGameReport -Result $renderResult -ReportPath $reportPath -StartedAt $started `
            -EditorBinary $true -Headless $false -Executable $executable -CapturePath $pngPath
    }
    $preset = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\..\game\export_presets.cfg') -Raw
    $excluded = [regex]::Match($preset, '(?m)^exclude_filter="([^"]*)"').Groups[1].Value -split ','
    Check 'export excludes the known provisional integration capture' ('match/validation.png' -in $excluded)
    Check 'export excludes all native test resources' ('tests/*' -in $excluded -and 'tests/**/*' -in $excluded)
    Check 'diagnostic driver remains exportable' (@($excluded | Where-Object { 'diagnostics/match_smoke.gd' -like $_ }).Count -eq 0)
    $root = Join-Path $PSScriptRoot '..\..\..'
    $settings = Get-Content -LiteralPath (Join-Path $root 'game\project.godot') -Raw
    $metadata = Get-Content -LiteralPath (Join-Path $root 'config\toolchain.json') -Raw | ConvertFrom-Json -AsHashtable
    $bootstrap = Get-Content -LiteralPath (Join-Path $root 'game\bootstrap\bootstrap.gd') -Raw
    Check 'source 0.5 diagnostic guards preserve the historical 0.4 toolchain record and schema 3' (
        $metadata['godot']['projectVersion'] -ceq '0.4.0-preview' -and $metadata['godot']['inputSchemaVersion'] -eq 3 -and
        (Get-GodotExpectedProjectIdentity).projectVersion -ceq '0.5.0-preview' -and
        $bootstrap.Contains('const EXPECTED_PROJECT_VERSION: String = "0.5.0-preview"') -and
        $bootstrap.Contains('const INPUT_SCHEMA_VERSION: int = 3'))
    Check 'preview project name is explicit, legacy filename is unchanged' (
        $settings -match '(?m)^config/name="Futsal — Laboratorio 5v5"\r?$' -and
        $metadata['godot']['debugArtifact'] -eq 'build\windows\FutsalG1.exe')
    Check 'G1 and preview evidence have independent versioned records' (
        $metadata['godot']['g1Validation']['historical'] -eq $true -and
        $metadata['godot']['g1Validation']['projectVersion'] -eq '0.1.0-g1' -and
        $metadata['godot']['previewValidation']['projectVersion'] -eq '0.4.0-preview' -and
        $metadata['godot']['previewValidation']['runtimeValidated'] -is [bool])
    Check 'approved 0.2.0 evidence is preserved independently of current preview' (
        $metadata['godot']['previousPreviewValidation']['projectVersion'] -ceq '0.2.0-preview' -and
        $metadata['godot']['previousPreviewValidation']['historical'] -eq $true -and
        $metadata['godot']['previousPreviewValidation']['preservedArtifact'] -ceq 'build\windows\FutsalPreview-0.2.0.exe' -and
        $metadata['godot']['previousPreviewValidation']['artifactSha256'] -ceq 'a728d5f961b80db4a1f0ea56a8547481044f323d017cd3b9fb32522edb132176' -and
        $metadata['godot']['previousPreviewValidation']['artifactBytes'] -eq 103371984)
    Check 'completed 0.3.0 evidence remains historical before any 0.4 export' (
        $metadata['godot']['playerControlValidation']['historical'] -eq $true -and
        $metadata['godot']['playerControlValidation']['projectVersion'] -ceq '0.3.0-preview' -and
        $metadata['godot']['playerControlValidation']['runnerPassed'] -eq 125 -and
        $metadata['godot']['playerControlValidation']['foundationPassed'] -eq 819 -and
        $metadata['godot']['playerControlValidation']['processPassed'] -eq 72 -and
        $metadata['godot']['playerControlValidation']['artifactSha256'] -ceq '6fe42916e7d91309044758439b96c48324ce967d1597f3f24872ff6dbd9192f6')
    $runnerSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\Test-MicroSlice.ps1') -Raw
    Check 'player-control suite and its native marker are mandatory in the runner' (
        $runnerSource.Contains("'player-control' = 'game\tests\test_match_player_control.gd'") -and
        $runnerSource.Contains("'FUTSAL_PLAYER_CONTROL_TESTS'"))
    foreach ($name in @('Common.ps1', 'Start-Godot.ps1', 'Test-Godot.ps1', 'MicroSliceValidation.ps1', 'Test-MicroSlice.ps1',
            'tests\Test-MicroSliceValidation.ps1', 'tests\Test-DefaultEntrypoint.ps1',
            'tests\Test-ArchivedPlayerControlReports.ps1',
            'tests\process_probe.ps1', 'tests\process_encoding_probe.ps1')) {
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "..\$name"), [ref]$null, [ref]$parseErrors)
        Check "owned PowerShell parses: $name" ($parseErrors.Count -eq 0)
    }
    $encodingResult = Invoke-GodotProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'process_encoding_probe.ps1'),
            '-LogPrefix', (Join-Path $work 'legacy-code-page')) `
        -WorkingDirectory $PSScriptRoot -LogPrefix (Join-Path $work 'encoding-probe') -TimeoutSeconds 30
    Assert-GodotOutput $encodingResult
    $encoding = $encodingResult.Stdout | ConvertFrom-Json
    Check 'UTF-8 stdout survives a legacy-code-page caller' ($encoding.parent_code_page -eq 437 -and $encoding.stdout_ok -eq $true)
    Check 'UTF-8 stderr survives a legacy-code-page caller' ($encoding.parent_code_page -eq 437 -and $encoding.stderr_ok -eq $true)
    $report = [ordered]@{
        ok = $true; passed = $checks.Count; total = $checks.Count; checks = $checks.ToArray()
        fixtureSharingRetries = $fixtureSharingRetries
    }
    $result = ReportOutput $report 'FUTSAL_PREVIEW_VALIDATION_TESTS'
    $null = ConvertFrom-GodotStructuredReport $result 'FUTSAL_PREVIEW_VALIDATION_TESTS' -RequireChecks
    Write-Output $result.Stdout
}
catch {
    [Console]::Error.WriteLine("Fixture failure after $($checks.Count) checks: $($_.Exception.Message)")
    throw
}
finally {
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        try {
            if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -ErrorAction Stop }
            break
        }
        catch {
            if ($attempt -eq 3) { throw }
            Start-Sleep -Milliseconds 100
        }
    }
}
