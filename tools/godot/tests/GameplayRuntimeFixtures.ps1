# Synthetic data only. Reuse the existing legacy fixture functions without running that test script.
$fixtureAst = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Test-MicroSliceValidation.ps1'), [ref]$null, [ref]$null)
foreach ($name in @('CopyFixture', 'ModeState', 'AiChange', 'FocusEvent', 'SelectFixture', 'MotionFixture', 'FocusSmokeFixture')) {
    $definition = @($fixtureAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name
    }, $false))
    if ($definition.Count -ne 1) { throw "Legacy fixture definition missing or ambiguous: $name" }
    . ([scriptblock]::Create($definition[0].Extent.Text))
}

function New-GpFixtureRestart([int]$Kind = 0, [int]$Stage = 0, [int]$Taker = 0, $Spot = @(0.0, 0.0, 0.0), [int]$Taken = 65) {
    $restart = @{
        id = -1; kind = 0; stage = 0; awarded_team_id = -1; taker_actor_id = -1
        spot = @($Spot); offence_spot = @($Spot); border = 0; spot_choice = 0; has_spot_choice = $false
        stage_started_tick = -1; placement_end_tick = -1; ready_tick = -1; deadline_tick = -1
        launch_contact_id = -1
        minimum_opponent_distance = 0.0; direct_opponent_goal_allowed = $false; requires_direct_shot = $false; other_actor_touched = $false
    }
    if ($Kind -ne 0) {
        $restart.id = 1; $restart.kind = $Kind; $restart.stage = $Stage
        $restart.awarded_team_id = 0; $restart.taker_actor_id = $Taker
        $restart.stage_started_tick = if ($Stage -eq 2) { 1 } elseif ($Stage -eq 4) { $Taken } else { 61 }
        $restart.placement_end_tick = 61
        if ($Stage -eq 4) { $restart.launch_contact_id = 1 }
        if ($Stage -ge 3) { $restart.ready_tick = 61; $restart.deadline_tick = if ($Kind -eq 6) { -1 } else { 301 } }
        $restart.minimum_opponent_distance = if ($Kind -eq 3) { 0.0 } else { 5.0 }
        $restart.direct_opponent_goal_allowed = $Kind -in @(2, 4, 6, 7)
        $restart.requires_direct_shot = $Kind -in @(6, 7)
        $restart.has_spot_choice = $Kind -eq 7
        if ($Kind -eq 7) { $restart.offence_spot = @(12.0, 0.105, 7.0) }
    }
    return $restart
}

function Add-GpFixtureStateFields($State, [int]$Exercise = 0) {
    $State['training_exercise'] = $Exercise
    $State['human_control_context'] = 1
    $State['selected_can_move'] = $true
    $State['human_allowed_actions'] = @(0, 1, 5, 2)
    $State['accumulated_fouls'] = if ($Exercise -eq 11) { @(0, 6) } else { @(0, 0) }
    $State['period_state'] = 0; $State['extended_restart_id'] = -1; $State['extended_kick_event_id'] = -1
    $State['restart'] = New-GpFixtureRestart
    foreach ($actor in $State.actors) {
        $actor['ball_in_hands'] = $false; $actor['ball_contact_reachable'] = $actor.id -eq $State.ball_owner_id
        $actor['gesture_kind'] = 0; $actor['gesture_started_tick'] = -1; $actor['gesture_duration_ticks'] = 0
        $actor['gesture_direction'] = @(0.0, 0.0, 0.0); $actor['gesture_contact_position'] = @(0.0, 0.0, 0.0)
    }
    Set-GpFixtureContext $State
}

function Set-GpFixtureContext($State) {
    $r = $State.restart
    $State.human_control_context = if ($State.phase -ceq 'PLAYING') { 1 } elseif ($r.stage -eq 3) { 2 } else { 0 }
    $State.selected_can_move = $State.human_control_context -eq 1
    $State.human_allowed_actions = @(0)
    if ($State.phase -ceq 'PLAYING') {
        $actor = $State.actors[$State.selected_actor_id]
        if ($State.ball_owner_id -ne $State.selected_actor_id) { $State.human_allowed_actions = @(0, 3, 4) }
        elseif ($actor.ball_in_hands) { $State.human_allowed_actions = @(0, 6) }
        elseif ($actor.ball_contact_reachable) { $State.human_allowed_actions = @(0, 1, 5, 2) }
    }
    elseif ($r.stage -eq 3) {
        $State.human_allowed_actions = @(0) + @(if ($r.kind -eq 3) { 6 } elseif ($r.kind -eq 7) { 2; 7 } elseif ($r.kind -eq 6) { 2 } else { 1; 2 })
    }
    $State.human_sequence = $State.actors[$State.selected_actor_id].sequence
}

function New-GpFixtureEvent([int]$Id, [int]$Kind, [int]$Tick, $State, [string]$Reason = 'fixture') {
    return @{
        id = $Id; kind = $Kind; tick = $Tick; actor = $State.selected_actor_id; target = -1; reason = $Reason
        selected_actor_id = $State.selected_actor_id; ball_owner_id = $State.ball_owner_id; score = @(0, 0)
        position = @($State.ball_position); velocity = @($State.ball_velocity); contact_point = @(0.0, 0.0, 0.0)
        launch_kind = 0; gesture_kind = 0; contact_id = -1; foul_verdict = 0; shot_charge = 0.0
        restart = CopyFixture $State.restart
    }
}

function New-GpFixtureInput([string]$Label, [int]$Tick, [string]$Class, [int]$Code, $Value) {
    $input = @{case = $Label; tick = $Tick; class = $Class; device = 0}
    switch ($Class) {
        'InputEventKey' { $input.physical_keycode = $Code; $input.pressed = [bool]$Value; $input.echo = $false }
        'InputEventJoypadButton' { $input.button_index = $Code; $input.pressed = [bool]$Value }
        'InputEventJoypadMotion' { $input.axis = $Code; $input.axis_value = [double][single]$Value }
        'InputEventMouseButton' { $input.button_index = 1; $input.pressed = [bool]$Value; $input.position = @(100.0, 100.0) }
        'InputEventMouseMotion' { $input.position = @(100.0, 100.0); $input.relative = @(0.0, 0.0) }
    }
    return $input
}

function New-GpFixturePose($State, [int]$Id, [int]$Variant = 0) {
    $actor = $State.actors[$Id]; $path = "/root/Match/Athletes/Athlete$Id"
    $pose = @{
        actor_id = $Id; path = $path; source_script = 'res://match/presentation/athletes/athlete_view.gd'
        context_valid = $true; context_before_tick = [Math]::Max(0, $State.tick - 1)
        context_tick = $State.tick; context_phase = $(if ($State.phase -ceq 'PLAYING') { 1 } else { 3 })
        render_tick = [double]$State.tick; validation_error = ''
        gesture_kind = $actor.gesture_kind; gesture_weight = $(if ($actor.gesture_kind -eq 0) { 0.0 } else { 1.0 })
        gesture_progress = $(if ($actor.gesture_kind -eq 0) { 0.0 } else { [Math]::Clamp(($State.tick - $actor.gesture_started_tick) / [double]$actor.gesture_duration_ticks, 0.0, 1.0) })
        contact_tick = $actor.gesture_started_tick; gesture_age_ticks = [double]($State.tick - $actor.gesture_started_tick)
        contact_world = @($actor.gesture_contact_position); snapshot_ball = @($State.ball_position); feet = @(); hands = @()
    }
    foreach ($kind in @('feet', 'hands')) {
        for ($side = 0; $side -lt 2; $side++) {
            $x = [double]$actor.position[0] + ($side * 2 - 1) * 0.1
            $y = if ($kind -eq 'hands') { 1.1 } else { 0.04 }
            $origin = @($x, ($actor.position[1] + $y), [double]$actor.position[2])
            if ($actor.gesture_kind -ne 0 -and (($kind -eq 'hands' -and $actor.gesture_kind -eq 5) -or
                ($kind -eq 'feet' -and $actor.gesture_kind -ne 5))) {
                $origin = @(([double]$actor.gesture_contact_position[0] + ($side * 2 - 1) * 0.08),
                    ($actor.gesture_contact_position[1] + $Variant * 0.005), [double]$actor.gesture_contact_position[2])
            }
            if ($actor.ball_in_hands -and $kind -eq 'hands') {
                $origin = @(([double]$State.ball_position[0] + ($side * 2 - 1) * 0.1), [double]$State.ball_position[1], [double]$State.ball_position[2])
            }
            $pose[$kind] += @{
                path = "$path/$kind$side"; visible = $true; origin = $origin
                basis_x = @(1.0, 0.0, 0.0); basis_y = @(0.0, 1.0, 0.0); basis_z = @(0.0, 0.0, 1.0)
            }
        }
    }
    return $pose
}

function New-GpFixtureObservation($State, $Policy, $Inputs, $Events, $Launch = $null, [bool]$Charged = $false) {
    $corner = $State.phase -ceq 'RESTART_PAUSE' -and $State.restart.kind -eq 2
    $position = @(0.0, 18.0, 25.0); $target = @(0.0, 0.0, 0.0)
    $yaw = 0.0; $pitch = -[Math]::Atan2(18, 25)
    if ($corner) {
        $sx = [Math]::Sign($State.restart.spot[0]); $sz = [Math]::Sign($State.restart.spot[2])
        $position = @(([double]$State.restart.spot[0] + $sx * 2.2), 2.9, ([double]$State.restart.spot[2] + $sz * 3.1))
        $target = @(([double]$State.restart.spot[0] - $sx * 2.0), 0.4, ([double]$State.restart.spot[2] - $sz * 1.1))
        $yaw = [Math]::Atan2($sx * 4.2, $sz * 4.2)
        $pitch = -[Math]::Atan2(2.5, [Math]::Sqrt(4.2 * 4.2 * 2))
    }
    $camera = @{
        mode = $(if ($corner) { 'corner' } else { 'broadcast' })
        restart_id = $(if ($corner -or ($null -ne $Launch -and $Policy.index -eq 0)) { 1 } else { -1 })
        taker_actor_id = $(if ($corner -or ($null -ne $Launch -and $Policy.index -eq 0)) { 0 } else { -1 })
        tick = $State.tick; restart_spot = @($State.restart.spot)
        transition_started_tick = $(if ($corner) { 1 } elseif ($null -ne $Launch -and $Policy.index -eq 0) { $Launch.tick } else { -1 })
        transition_ticks_elapsed = 45; transition_complete = $true
        accepted_return_event_id = $(if ($null -ne $Launch -and $Policy.index -eq 0) { $Launch.id } else { -1 })
        position = $position; rotation = @($pitch, $yaw, 0.0); fov = $(if ($corner) { 60.0 } elseif ($State.mode -eq 0) { 46.0 } else { 48.0 })
        look_target = $target; tracked_ball = @($State.ball_position)
        fov_axis = 'vertical'; keep_aspect = 1; near = 0.1; far = 110.0
        input_projection_serial = 0; input_locked = $false; input_right = @(1.0, 0.0, 0.0); input_down = @(0.0, 0.0, 1.0)
    }
    $camera.transition_ticks_elapsed = [Math]::Min(45, [Math]::Max(0, $State.tick - $camera.transition_started_tick))
    $camera.transition_complete = $camera.transition_started_tick -lt 0 -or $camera.transition_ticks_elapsed -eq 45
    if (-not $corner -and -not $camera.transition_complete) { $camera.mode = 'returning' }
    $visible = @(); $axes = Get-GpCameraAxes $camera
    foreach ($actor in $State.actors) {
        if ($actor.team -eq 0 -and $actor.id -ne $State.selected_actor_id -and
            (Test-GpFramedPoint $actor.position $camera $axes) -and
            (Test-GpFramedPoint @($actor.position[0], ($actor.position[1] + 1.75), $actor.position[2]) $camera $axes)) { $visible += $actor.id }
    }
    $showGuide = $State.phase -ceq 'RESTART_PAUSE' -or $Charged
    $target = if ($Policy.index -in @(0, 1, 2, 3)) { 2 } elseif ($Policy.index -in @(5, 6)) { 0 } else { -1 }
    $direction = @(1.0, 0.0, 0.0)
    if ($showGuide -and $target -ge 0) {
        $point = $State.actors[$target].position
        $delta = @(($point[0] - $State.ball_position[0]), 0.0, ($point[2] - $State.ball_position[2]))
        $length = Get-GpLength $delta
        $direction = @(($delta[0] / $length), 0.0, ($delta[2] / $length))
    }
    $guide = @{
        path = '/root/Match/BallView/WorldAimGuide/Arrow'; visible = $showGuide; shaft_visible = $showGuide; head_visible = $showGuide
        mesh_count = 2; same_render_world_as_ball = $true; render_origin = @($State.ball_position[0], ($State.ball_position[1] + 0.035), $State.ball_position[2])
        physical_origin = @($State.ball_position); direction = $direction; launch_velocity = @(($direction[0] * 10), 2.0, ($direction[2] * 10))
        power = $(if ($Charged) { 0.25 } else { 0.0 }); executable = $true; effective_target_actor_id = $target
    }
    if (-not $showGuide) {
        $guide.physical_origin = @(0.0, 0.0, 0.0)
        $guide.launch_velocity = @(0.0, 0.0, 0.0)
        $guide.power = 0.0
        $guide.executable = $false
        $guide.effective_target_actor_id = -1
    }
    $selected = $State.selected_actor_id
    $role = if ($selected -eq 2) { 'PORTERO' } else { 'CAMPO' }
    $caption = if ($State.human_control_context -eq 2) { 'SAQUE PROPIO' } elseif ($State.ball_owner_id -eq $selected) { 'CON BALÓN' } else { 'SIN BALÓN' }
    return @{
        state = CopyFixture $State; mode = $State.mode; exercise = $State.training_exercise; tick = $State.tick; phase = $State.phase
        selected_actor_id = $selected; restart = CopyFixture $State.restart; camera = $camera; visible_home_options = @($visible)
        athlete_presentations = @($State.actors | ForEach-Object { New-GpFixturePose $State $_.id })
        input = @(CopyFixture @($Inputs)); events = @(CopyFixture @($Events)); guide = $guide; render_ball_position = @($State.ball_position)
        interpolation_fraction = 1.0; hud_selected = "CONTROL · ID $selected`n$role LOCAL"; hud_context = $caption
        hud_restart_title = 'Saque de prueba'; hud_restart_clock = '4'; hud_fouls = '0 / 6 predefinido'
    }
}

function New-GpFixtureCaseGroup($Policy, [int]$Starts) {
    $index = $Policy.index; $taker = if ($index -in @(5, 6)) { 2 } else { 0 }
    $state = ModeState $Policy.mode 4 (120.0 - 4.0 / 60.0) 'PLAYING' $false $taker
    Add-GpFixtureStateFields $state $Policy.exercise
    $state.driver_start_calls = $Starts
    $state.actors[0].position = @(-4.0, 0.0, 0.0); $state.actors[2].position = @(-12.0, 0.0, 0.0)
    $state.ball_position = @(-3.45, 0.105, 0.0)
    $spot = @(14.0, 0.105, 0.0)
    if ($index -lt 4) {
        $sx = if ($index -lt 2) { 1 } else { -1 }; $sz = if ($index % 2 -eq 0) { -1 } else { 1 }
        $spot = @(($sx * 19.8), 0.105, ($sz * 9.8))
        $state.actors[0].position = @(($sx * 19.3), 0.0, ($sz * 9.3))
        $state.actors[2].position = @(($sx * 17.7), 0.0, ($sz * 8.7))
    }
    elseif ($index -in @(5, 6)) {
        $spot = @(-18.5, 1.1, 0.0); $state.actors[2].position = @(-18.5, 0.0, 0.0); $state.actors[0].position = @(-12.0, 0.0, 0.0)
    }
    elseif ($index -eq 10) {
        $spot = @(5.0, 0.105, 9.895); $state.actors[0].position = @(4.5, 0.0, 9.895); $state.actors[2].position = @(2.0, 0.0, 9.895)
    }
    elseif ($index -ge 11) {
        if ($index -eq 13) { $spot = @(10.0, 0.105, 0.0) }
        $state.actors[0].position = @(($spot[0] - 0.5), 0.0, $spot[2])
    }
    if ($Policy.kind -ne 0) {
        $state.phase = 'RESTART_PAUSE'; $state.seconds_remaining = 120.0
        $state.restart = New-GpFixtureRestart $Policy.kind 2 $taker $spot
        $state.ball_position = @($spot)
    }
    $state.ball_owner_id = $taker
    $state.actors[$taker].ball_in_hands = $index -in @(5, 6)
    Set-GpFixtureContext $state
    $before = CopyFixture $state
    $events = @()
    $startState = CopyFixture $state; $startState.restart = New-GpFixtureRestart
    $events += New-GpFixtureEvent 0 4 0 $startState 'training_start'
    if ($Policy.kind -ne 0) {
        $placement = New-GpFixtureEvent 1 10 1 $state 'placement'
        $events += $placement
        $state.restart = New-GpFixtureRestart $Policy.kind 3 $taker $spot
        $state.tick = 64; $state.actors[$taker].sequence = 64
        Set-GpFixtureContext $state
        $events += New-GpFixtureEvent 2 10 61 $state 'ready'
    }
    else { $state.tick = if ($index -eq 4) { 16 } else { 6 }; $state.seconds_remaining = 120.0 - $state.tick / 60.0; $state.actors[0].sequence = $state.tick }
    Set-GpFixtureContext $state
    $label = $Policy.label
    $inputs = @(
        (New-GpFixtureInput $label 10 InputEventKey 4194332 $true)
        (New-GpFixtureInput $label 10 InputEventKey 4194332 $false)
        (New-GpFixtureInput $label 10 InputEventMouseMotion 0 $null)
        (New-GpFixtureInput $label 10 InputEventMouseButton 1 $true)
        (New-GpFixtureInput $label 10 InputEventMouseButton 1 $false)
    )
    if ($index -eq 2) {
        $inputs += New-GpFixtureInput $label 4 InputEventJoypadMotion 1 -0.8
        $inputs += New-GpFixtureInput $label 48 InputEventJoypadMotion 1 0.0
    }
    if ($index -eq 4) { $inputs += New-GpFixtureInput $label 4 InputEventKey 75 $true }
    if ($index -eq 5) {
        $inputs += New-GpFixtureInput $label 61 InputEventKey 75 $true
        $inputs += New-GpFixtureInput $label 64 InputEventKey 75 $false
    }
    $ready = New-GpFixtureObservation $state $Policy $inputs $events $null ($index -eq 4)
    $launch = $null; $after = $ready; $completion = $ready
    if ($index -in @(0, 4, 5, 10, 11, 12)) {
        $old = $taker; $pass = $index -in @(0, 5, 10); $target = if ($index -eq 5) { 0 } else { 2 }
        $taken = if ($index -eq 4) { 17 } elseif ($index -eq 12) { 83 } elseif ($index -eq 11) { 74 } else { 65 }
        $origin = @($state.ball_position)
        $velocity = @(10.0, 2.0, 0.0)
        if ($pass) {
            $point = $state.actors[$target].position
            $delta = @(($point[0] - $origin[0]), 0.0, ($point[2] - $origin[2]))
            $length = Get-GpLength $delta
            $velocity = @(($delta[0] * 10 / $length), 2.0, ($delta[2] * 10 / $length))
        }
        if ($index -eq 12) {
            $velocity = @((10.0 * [Math]::Cos(0.06)), 2.0, (10.0 * [Math]::Sin(0.06)))
            $inputs += New-GpFixtureInput $label 64 InputEventJoypadMotion 4 1.0
            $inputs += New-GpFixtureInput $label 64 InputEventJoypadMotion 0 0.8
            $inputs += New-GpFixtureInput $label 73 InputEventJoypadMotion 4 0.0
            $inputs += New-GpFixtureInput $label 73 InputEventJoypadMotion 0 0.0
        }
        $control = if ($index -in @(0, 10)) { 74 } elseif ($index -eq 4) { 75 } else { 1 }
        $class = if ($index -in @(0, 4, 10)) { 'InputEventKey' } else { 'InputEventJoypadButton' }
        if ($index -eq 5) { $control = 0 }
        if ($index -ne 4) {
            $inputs += New-GpFixtureInput $label $(if ($index -in @(11, 12)) { $taken - 10 } else { $taken - 1 }) $class $control $true
        }
        $inputs += New-GpFixtureInput $label ($taken - 1) $class $control $false
        $state.tick = $taken + 1
        $state.seconds_remaining = if ($Policy.kind -eq 0) { 120.0 - $state.tick / 60.0 } else { 120.0 - 1.0 / 60.0 }
        $state.phase = 'PLAYING'
        if ($Policy.kind -ne 0) { $state.restart = New-GpFixtureRestart $Policy.kind 4 $taker $spot $taken }
        $state.ball_owner_id = -1; $state.ball_velocity = $velocity
        $state.ball_position = @(($origin[0] + $velocity[0] / 60.0), ($origin[1] + $velocity[1] / 60.0), ($origin[2] + $velocity[2] / 60.0))
        $state.actors[$old].ball_in_hands = $false; $state.actors[$old].sequence = $taken
        $state.actors[$old].gesture_kind = if ($index -eq 5) { 5 } else { 4 }
        $state.actors[$old].gesture_started_tick = $taken; $state.actors[$old].gesture_duration_ticks = if ($index -eq 5) { 18 } else { 12 }
        $state.actors[$old].gesture_contact_position = @($origin); $state.actors[$old].gesture_direction = @(1.0, 0.0, 0.0)
        if ($pass) { SelectFixture $state $target @() }
        $state.actors[$state.selected_actor_id].sequence = $state.tick
        Set-GpFixtureContext $state
        $launch = New-GpFixtureEvent 3 $(if ($pass) { 1 } else { 2 }) $taken $state $(if ($index -eq 5) { 'throw' } else { 'kick' })
        $launch.position = @($origin); $launch.contact_point = @($origin); $launch.velocity = @($velocity); $launch.contact_id = 1
        $launch.gesture_kind = $state.actors[$old].gesture_kind; $launch.actor = $old
        $launch.launch_kind = if ($index -eq 5) { 2 } elseif ($pass) { 0 } else { 1 }
        $launch.shot_charge = if ($pass) { 0.0 } elseif ($index -eq 4) { 0.25 } else { 9.0 / 48.0 }
        $launch.target = if ($pass) { $target } else { -1 }
        $events += $launch
        if ($pass) { $focus = New-GpFixtureEvent 4 9 $taken $state 'pass'; $focus.actor = $old; $focus.target = $target; $events += $focus }
        if ($Policy.kind -ne 0) { $events += New-GpFixtureEvent $(if ($pass) { 5 } else { 4 }) 10 $taken $state 'taken' }
        $kicked = New-GpFixtureObservation $state $Policy $inputs $events $launch
        $after = if ($index -in @(0, 4, 5)) { $ready } else { $kicked }
        $endState = CopyFixture $state
        $endState.tick += if ($index -eq 0) { 46 } else { 2 }
        $endState.seconds_remaining -= ($endState.tick - $state.tick) / 60.0
        $endState.actors[$endState.selected_actor_id].sequence = $endState.tick
        if ($index -eq 0) { $endState.actors[$old].gesture_kind = 0 }
        Set-GpFixtureContext $endState
        $completion = New-GpFixtureObservation $endState $Policy $inputs $events $launch
        $contactState = $state
        $progressState = CopyFixture $state; $progressState.tick += 2; $progressState.actors[$progressState.selected_actor_id].sequence += 2
        $contactPose = New-GpFixturePose $contactState $old
        $progressPose = New-GpFixturePose $progressState $old 1
    }
    elseif ($index -in @(7, 8, 9)) {
        $sign = if ($index -eq 7) { -1 } else { 1 }
        $direction = if ($index -eq 9) { @(1.0, 0.0, 0.0) } else { @(0.2873479, 0.0, ($sign * 0.9578263)) }
        $controller = ($Policy.mode + $index - 7) % 2 -eq 1
        if ($controller) {
            $inputs += New-GpFixtureInput $label 4 InputEventJoypadMotion $(if ($index -eq 9) { 0 } else { 1 }) $sign
            $inputs += New-GpFixtureInput $label 4 InputEventJoypadButton 2 $true
        }
        else {
            $inputs += New-GpFixtureInput $label 4 InputEventKey $(if ($index -eq 9) { 4194321 } elseif ($index -eq 7) { 4194320 } else { 4194322 }) $true
            $inputs += New-GpFixtureInput $label 4 InputEventKey 76 $true
        }
        $origin = @($state.ball_position); $velocity = @(($direction[0] * 5.0), 0.0, ($direction[2] * 5.0))
        $state.ball_owner_id = -1; $state.ball_velocity = $velocity
        $state.ball_position = @(($origin[0] + $velocity[0] / 60.0), $origin[1], ($origin[2] + $velocity[2] / 60.0))
        $state.actors[0].gesture_kind = if ($index -eq 9) { 2 } else { 1 }
        $state.actors[0].gesture_started_tick = 5; $state.actors[0].gesture_duration_ticks = 18
        $state.actors[0].gesture_direction = $direction; $state.actors[0].gesture_contact_position = $origin
        Set-GpFixtureContext $state
        $launch = New-GpFixtureEvent 1 11 5 $state $(if ($index -eq 9) { 'pace_change' } else { 'cut' })
        $launch.gesture_kind = $state.actors[0].gesture_kind; $launch.contact_id = 1; $launch.position = $origin; $launch.contact_point = $origin
        $events += $launch
        $after = New-GpFixtureObservation $state $Policy $inputs $events
        $endState = CopyFixture $state; $endState.tick += 16; $endState.seconds_remaining -= 16.0 / 60.0
        $endState.actors[0].sequence = $endState.tick; Set-GpFixtureContext $endState
        $inputs += New-GpFixtureInput $label $endState.tick $(if ($controller) { 'InputEventJoypadButton' } else { 'InputEventKey' }) $(if ($controller) { 2 } else { 76 }) $false
        $completion = New-GpFixtureObservation $endState $Policy $inputs $events
        $contactPose = New-GpFixturePose $state 0
        $progressState = CopyFixture $state; $progressState.tick += 2
        $progressPose = New-GpFixturePose $progressState 0 1
    }
    elseif ($index -eq 1) {
        $inputs += New-GpFixtureInput $label 64 InputEventJoypadButton 1 $true
        $inputs += New-GpFixtureInput $label 66 InputEventJoypadButton 1 $false
        $inputs += New-GpFixtureInput $label 66 InputEventKey 4194305 $true
        foreach ($toggle in 1..2) {
            $inputs += New-GpFixtureInput $label 66 InputEventMouseMotion 0 $null
            $inputs += New-GpFixtureInput $label 66 InputEventMouseButton 1 $true
            $inputs += New-GpFixtureInput $label 66 InputEventMouseButton 1 $false
        }
        $state.tick = 76; $state.actors[0].sequence = 76; Set-GpFixtureContext $state
        $completion = New-GpFixtureObservation $state $Policy $inputs $events
    }
    elseif ($index -eq 13) {
        $state.tick = 80; $state.actors[0].sequence = 80; $state.restart.spot_choice = 1; Set-GpFixtureContext $state
        $offence = New-GpFixtureEvent 3 10 65 $state 'spot_changed'
        $offence.restart.spot_choice = 2; $offence.restart.spot = @($offence.restart.offence_spot)
        $events += $offence
        $events += New-GpFixtureEvent 4 10 76 $state 'spot_changed'
        $inputs += New-GpFixtureInput $label 64 InputEventKey 76 $true
        $inputs += New-GpFixtureInput $label 75 InputEventJoypadButton 2 $true
        $inputs += New-GpFixtureInput $label 78 InputEventKey 74 $true
        $after = New-GpFixtureObservation $state $Policy $inputs $events
        $completion = $after
    }
    $records = @()
    $suffixes = if ($index -eq 5) { @('keeper_clearance_ready', 'keeper_clearance_release') } else { @($Policy.name) }
    foreach ($suffix in $suffixes) {
        $id = "m$($Policy.mode)/$suffix"
        $obs = if ($suffix -ceq 'keeper_clearance_release') { CopyFixture $kicked } else { CopyFixture $after }
        if ($Policy.capture) {
            $obs['case'] = $id; $obs['accepted_event'] = @{}
            if ($index -in @(7, 8, 9) -or $suffix -ceq 'keeper_clearance_release') { $obs['accepted_event'] = CopyFixture $launch }
            $obs['capture_status'] = 'not_rendered_headless'; $obs['filename'] = ''
        }
        $record = @{case = $id; source_script = 'res://match/match.gd'; before = CopyFixture $before; after = $obs; passed = $true}
        if ($Policy.capture) { $record['completion'] = CopyFixture $completion }
        $records += $record
    }
    $samples = @(); $focusRecord = $null
    if ($index -eq 5) {
        $samples += @{case = "m$($Policy.mode)/keeper_clearance_ready"; ready_hands = $after.athlete_presentations[2]; render_ball_position = $after.render_ball_position}
    }
    if ($null -ne $launch) {
        $samples += @{case = $label; event_id = $launch.id; accepted_tick = $launch.tick; at_contact = $contactPose}
        if ($index -eq 5) { $samples += @{case = "m$($Policy.mode)/keeper_clearance_release"; event_id = $launch.id; accepted_tick = $launch.tick; at_contact = $contactPose} }
        if ($index -in @(4, 5, 7, 8, 9)) {
            $samples += @{case = "$label/progress"; event_id = $launch.id; at_contact = $contactPose; advanced = $progressPose}
        }
        if ($index -in @(0, 5)) {
            $focusRecord = @{
                case = $label + $(if ($index -eq 5) { '/manual_throw' } else { '/accepted_pass' })
                source_script = 'res://match/match.gd'; input = $(if ($index -eq 5) { 'InputEventJoypadButton:A' } else { 'InputEventKey:J' })
                reason = 'pass'; before = CopyFixture $ready.state; after = CopyFixture $kicked.state
                before_selected_actor_id = $taker; after_selected_actor_id = $launch.target; expected_selected_actor_id = $launch.target
                before_ball_owner_id = $taker; after_ball_owner_id = -1; actor_count = $state.actor_count
                ai_intent_actor_ids = @(); ai_actor_ids = @(); events = @($events | Where-Object { $_.tick -eq $launch.tick }); passed = $true
            }
        }
    }
    return @{records = $records; events = $events; inputs = $inputs; poses = $samples; focus = $focusRecord; end = $completion.state}
}

function New-GpFixtureReport([string]$ReportPath, [bool]$Headless, [bool]$EditorBinary) {
    $defaults = @{
        verified = $true; before = ModeState 1 0 120.0; after_wait = ModeState 1 12 119.8; after_input = ModeState 1 60 119.0
    }
    foreach ($name in @('before', 'after_wait', 'after_input')) { Add-GpFixtureStateFields $defaults[$name] }
    $focus = FocusSmokeFixture
    $modeChanges = @(
        @{route = 'production-dev-menu-signal'; requested_mode = 0; before = ModeState 1 36 119.4 PAUSED; after = ModeState 0}
        @{route = 'production-dev-menu-signal'; requested_mode = 1; before = ModeState 0 36 119.4 PAUSED $false; after = ModeState 1}
    )
    $restoreBefore = CopyFixture $focus.cases[-1].after
    $restoreBefore.phase = 'PAUSED'
    $restored = ModeState 0
    $restored.driver_start_calls = $restoreBefore.driver_start_calls
    $modeChanges += @{route = 'production-dev-menu-signal'; requested_mode = 0; before = $restoreBefore; after = $restored}
    $inputs = @(@{
        control = 'default keyboard D'; event_class = 'InputEventKey'; device = 0; driver_start_calls = 0
        before = @{sequence = 12; position = @(-2.0, 0.0, 0.0); velocity = @(0.0, 0.0, 0.0)}
        pressed = @{sequence = 30; position = @(-1.0, 0.0, 0.0); velocity = @(5.8, 0.0, 0.0)}
        settled = @{sequence = 54; position = @(-0.5, 0.0, 0.0); velocity = @(0.0, 0.0, 0.0)}
        released = @{sequence = 60; position = @(-0.5, 0.0, 0.0); velocity = @(0.0, 0.0, 0.0)}
    })
    $inputs += @('keyboard D', 'keyboard W', 'joypad left X', 'joypad left Y',
        'Esc / Start', 'Start / Esc', 'Esc / Down / Enter restart',
        'development AI mode 1', 'development AI mode 0') | ForEach-Object { @{control = $_} }
    $inputs += @($focus.motion,
        (MotionFixture 'physical arrow Right' $defaults.after_wait.actors[0] 1),
        (MotionFixture 'physical arrow Up' $defaults.after_wait.actors[0] 1 2 -1))
    $policy = Get-GodotGameplayCasePolicy
    $cases = @(); $nativeInputs = @(); $poses = @(); $events = @($focus.history); $focusRecords = @($focus.cases)
    $starts = $restoreBefore.driver_start_calls
    foreach ($id in $policy.Keys) {
        $p = $policy[$id]
        if ($p.index -eq 6) { continue }
        $starts++
        $group = New-GpFixtureCaseGroup $p $starts
        $cases += $group.records; $nativeInputs += $group.inputs; $poses += $group.poses; $events += $group.events
        if ($null -ne $group.focus) { $focusRecords += $group.focus }
        if ($p.index -eq 13) {
            $previous = CopyFixture $group.end; $previous.phase = 'PAUSED'
            $restored = ModeState 1
            $restored.driver_start_calls = $starts
            $modeChanges += @{route = 'production-dev-menu-signal'; requested_mode = 1; before = $previous; after = $restored}
        }
    }
    $final = ModeState 1 16 (120.0 - 16.0 / 60.0)
    Add-GpFixtureStateFields $final
    $final.driver_start_calls = $starts
    $captureDirectory = Join-Path ([IO.Path]::GetDirectoryName($ReportPath)) (
        [IO.Path]::GetFileNameWithoutExtension($ReportPath) + '-gameplay-captures')
    $checks = @(Get-GpRequiredNativeChecks | ForEach-Object { @{name = $_; passed = $true} })
    $report = [ordered]@{
        ok = $true; complete = $true; passed = $checks.Count; total = $checks.Count; checks = $checks; failures = @()
        process_id = 0; executable = ''; report_path = $ReportPath; timestamp_utc = [datetime]::UtcNow.ToString('s')
        scope = 'playable-gameplay-runtime-smoke'; project_name = 'Futsal — Laboratorio 5v5'
        project_version = '0.5.0-preview'; engine_version = '4.7.2-stable (official)'; input_schema_version = 3
        main_scene = 'res://match/match.tscn'; configured_main_scene = 'res://match/match.tscn'
        editor_binary = $EditorBinary; headless = $Headless; display_server = $(if ($Headless) { 'headless' } else { 'Windows' })
        viewport_width = 1920; viewport_height = 1080; physics_engine = 'Jolt Physics'; physics_ticks_per_second = 60
        gpu_validated = -not $Headless; gpu_name = $(if ($Headless) { 'not measured (headless)' } else { 'Synthetic fixture device' })
        gpu_api = $(if ($Headless) { '' } else { '1.3.0' }); frames_drawn = $(if ($Headless) { 0 } else { 200 })
        rendering_method = $(if ($Headless) { 'headless' } else { 'forward_plus' })
        rendering_driver = $(if ($Headless) { 'dummy' } else { 'vulkan' })
        camera_path = '/root/Match/BroadcastCamera'; authority_path = '/root/Match/MatchSimulation'
        hud_path = '/root/Match/MatchHUD'; development_menu_path = '/root/Match/DevelopmentMenu'
        capture_phase = 'PLAYING'; mode = 1; final_mode = 1; final_actor_count = 10; initial_tick = 12; final_tick = 16
        final_hud_mode = '5v5 experimental · Sin progresión/XP'; final_hud_selected = "CONTROL · ID 0`nCAMPO LOCAL"
        initial_selected_actor_id = 0; initial_ai_intent_actor_ids = @(0..9); initial_ai_actor_ids = @(1..9)
        loaded_actors = CopyFixture $defaults.after_wait.actors; final_state = $final
        inputs = $inputs; default_entrypoint = $defaults; mode_changes = $modeChanges; ai_changes = @((AiChange 1), (AiChange 0))
        focus_changes = $focusRecords; events = $events; command_rejections = @(); integration_errors = @()
        driver_start_calls = $starts; wall_seconds = 1.0; watchdog_msec = 120000
        gameplay_driver_script = 'res://diagnostics/gameplay_smoke.gd'
        aim_precision_controls = (Get-GodotGameplayContract)['fineAimHint']; aim_precision_max_degrees_per_second = 30.0
        input_method = 'Input.parse_input_event; physical keys and raw joypad events, device 0'
        gui_input_method = 'Viewport.push_input; local mouse coordinates, device 0'
        limitations = @('SYNTHETIC FIXTURE ONLY: not native gameplay, GPU or art evidence.')
        gameplay = @{
            started = $true; complete = $true; expected_cases = @($policy.Keys); completed_cases = @($policy.Keys)
            cases = $cases; native_inputs = $nativeInputs; athlete_presentations = $poses
            required_png_count = 20; observed_moment_count = 20; saved_png_count = $(if ($Headless) { 0 } else { 20 })
            capture_complete = -not $Headless; capture_directory = $captureDirectory
            capture_manifest_path = Join-Path $captureDirectory 'manifest.json'
        }
    }
    return $report
}

function New-GpFixturePng([string]$Path, [int]$Index, [int]$Width = 1920, [bool]$Uniform = $false) {
    Add-Type -AssemblyName System.Drawing
    $image = [Drawing.Bitmap]::new($Width, 1080)
    $graphics = [Drawing.Graphics]::FromImage($image)
    $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(40 + $Index, 85, 130))
    try {
        $graphics.Clear([Drawing.Color]::Black)
        if (-not $Uniform) { $graphics.FillRectangle($brush, 200, 200, 1500, 700) }
        $image.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $brush.Dispose(); $graphics.Dispose(); $image.Dispose() }
}

function New-GpFixtureManifest($Report, [switch]$CreatePngs) {
    $gameplay = $Report['gameplay']
    $observations = @(); $captures = @(); $index = 0
    foreach ($case in $gameplay['cases']) {
        if (-not $case.Contains('completion')) { continue }
        $observation = $case['after']
        if (-not $Report['headless']) {
            $path = Join-Path $gameplay['capture_directory'] ($case['case'].Replace('/', '-') + '.png')
            if ($CreatePngs) { New-GpFixturePng $path $index }
            $observation['capture_status'] = 'saved'; $observation['filename'] = $path
            $observation['width'] = 1920; $observation['height'] = 1080; $observation['render_valid'] = $true
            $observation['sha256'] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            $captures += CopyFixture $observation
        }
        $observations += CopyFixture $observation
        $index++
    }
    return @{
        schema_version = 1; project_version = $Report['project_version']; driver_script = $Report['gameplay_driver_script']
        main_scene = $Report['main_scene']; process_id = $Report['process_id']; editor_binary = $Report['editor_binary']
        headless = $Report['headless']; report_path = $Report['report_path']; capture_directory = $gameplay['capture_directory']
        required_png_count = 20; saved_png_count = $captures.Count; observations = $observations; captures = $captures
        functional_traversal_complete = $true
    }
}

function Get-GpFixtureStdout($Report, [string]$SerializedReport = ($Report | ConvertTo-Json -Depth 64 -Compress)) {
    $lines = @()
    if (-not $Report['headless']) { $lines += 'Vulkan 1.3.0 - Forward+ - Using Device #0: fixture - ' + $Report['gpu_name'] }
    $lines += @($Report['checks'] | ForEach-Object { 'PASS ' + $_['name'] })
    $lines += 'FUTSAL_GAMEPLAY_SMOKE ' + $SerializedReport
    return ($lines -join "`n") + "`n"
}

function Write-GpFixtureJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 64 -Compress), [Text.UTF8Encoding]::new($false))
}
