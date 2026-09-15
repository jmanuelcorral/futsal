#Requires -Version 7.2
Set-StrictMode -Version Latest

function Get-GodotGameplayCasePolicy {
    $policy = [ordered]@{}
    $names = (Get-GodotGameplayContract)['runtimeCaseNames']
    $exercises = @(2, 3, 4, 5, 0, 6, 6, 7, 7, 8, 1, 9, 10, 11)
    $kinds = @(2, 2, 2, 2, 0, 3, 3, 0, 0, 0, 1, 4, 6, 7)
    foreach ($mode in @(0, 1)) {
        for ($index = 0; $index -lt $names.Count; $index++) {
            $id = "m$mode/$($names[$index])"
            $label = if ($index -in @(5, 6)) { "m$mode/keeper_clearance" } else { $id }
            $policy[$id] = @{mode = $mode; index = $index; exercise = $exercises[$index]; kind = $kinds[$index];
                capture = $index -lt 10; label = $label; name = $names[$index]}
        }
    }
    return $policy
}

function Get-GpRequiredNativeChecks {
    $names = @(
        'default host auto-started PLAYING before any driver setup'
        'default entrypoint passed before allowing any driver setup'
        'default input proof ran without driver start or host restart'
        'G31 all 28 finite gameplay cases and 20 required observation moments completed'
        'G31 rendered run saves exactly 20 PNGs; headless claims none'
        'gameplay captures derive only from this report; no legacy --capture-path'
        'gameplay final view restores FREE_PLAY, selected 0, ten actors and nine AI'
        'gameplay finalization never substitutes a 21st PNG for a required moment'
        'all planned smoke phases completed'
        'no production rejection through finalization'
        'no production integration error through finalization'
        'requested gameplay extension completed'
        "gameplay manifest is written into this run's isolated directory"
        'gameplay manifest bytes persisted without an I/O error'
    )
    $policy = Get-GodotGameplayCasePolicy
    foreach ($id in $policy.Keys) {
        $names += "G31 finite unique gameplay case: $id"
        # Keeper ready/release share one Apply, not two synthetic exercise requests.
        if ($policy[$id].index -eq 6) { continue }
        foreach ($suffix in @('Apply emits exactly one native exercise request',
                'Apply confirms the requested production exercise', 'Apply closes the development modal',
                'explicit Apply reaches the actual catalog authority')) {
            $names += "$($policy[$id].label) $suffix"
        }
    }
    foreach ($mode in @(0, 1)) {
        $names += "m$mode/live_charged_shot repeated preview reads neither resample nor mutate authority"
        $names += "m$mode/corner_neg_x_neg_z held controller direction survives the real camera blend"
        $names += "m$mode/corner_pos_x_pos_z F1 and guide toggle freeze restart, charge and camera"
        $names += "m$mode/corner_pos_x_pos_z explicit resume does not replay the cancelled shot"
        $names += "m$mode/keeper_clearance actual forbidden foot input is visible beside the persistent fine-aim hint"
        $names += "m$mode/keeper_clearance after refusal own READY shows actual persistent fine-aim instructions"
        $names += "m$mode/accumulated_spot_choice native forbidden pass has visible contextual feedback"
    }
    return $names
}

function Assert-GpInteger($Value, [string]$Name, [long]$Minimum = -1, [long]$Maximum = [long]::MaxValue) {
    if (-not (Test-GodotGameplayInteger $Value) -or $Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "Gameplay requires a valid integer $Name."
    }
}

function Assert-GpNumber($Value, [string]$Name, [double]$Minimum = -1.0e9, [double]$Maximum = 1.0e9) {
    if (-not (Test-GodotGameplayFiniteNumber $Value) -or $Value -lt $Minimum -or $Value -gt $Maximum) {
        throw "Gameplay requires a finite bounded $Name."
    }
}

function Assert-GpBoolean($Value, [string]$Name, $Expected = $null) {
    if ($Value -isnot [bool] -or ($Expected -is [bool] -and $Value -ne $Expected)) { throw "Invalid gameplay boolean $Name." }
}

function Assert-GpEqual($Left, $Right, [string]$Name) {
    if (($Left | ConvertTo-Json -Depth 64 -Compress) -cne ($Right | ConvertTo-Json -Depth 64 -Compress)) {
        throw "Gameplay evidence disagrees across $Name."
    }
}

function Get-GpDot($Left, $Right) {
    return [double]($Left[0] * $Right[0] + $Left[1] * $Right[1] + $Left[2] * $Right[2])
}

function Get-GpLength($Vector) {
    Assert-GodotFiniteVector $Vector 'gameplay vector'
    return [Math]::Sqrt((Get-GpDot $Vector $Vector))
}

function Assert-GpNear($Left, $Right, [double]$Tolerance, [string]$Name) {
    if ((Get-GodotVectorDistanceSquared $Left $Right) -gt $Tolerance * $Tolerance) { throw "Gameplay vector mismatch: $Name." }
}

function Assert-GpRestart($Restart) {
    if ($Restart -isnot [Collections.IDictionary]) { throw 'Gameplay omitted the canonical restart state.' }
    foreach ($field in @('id', 'awarded_team_id', 'taker_actor_id', 'stage_started_tick', 'placement_end_tick', 'ready_tick', 'deadline_tick', 'launch_contact_id')) {
        Assert-GpInteger $Restart[$field] "restart.$field"
    }
    Assert-GpInteger $Restart['kind'] 'restart.kind' 0 7
    Assert-GpInteger $Restart['stage'] 'restart.stage' 0 4
    Assert-GpInteger $Restart['border'] 'restart.border' 0 4
    Assert-GpInteger $Restart['spot_choice'] 'restart.spot_choice' 0 2
    foreach ($field in @('has_spot_choice', 'direct_opponent_goal_allowed', 'requires_direct_shot', 'other_actor_touched')) {
        Assert-GpBoolean $Restart[$field] "restart.$field"
    }
    foreach ($field in @('spot', 'offence_spot')) { Assert-GodotFiniteVector $Restart[$field] "restart.$field" }
    Assert-GpNumber $Restart['minimum_opponent_distance'] 'restart distance' 0 10
    if (($Restart['stage'] -lt 4 -and $Restart['launch_contact_id'] -ne -1) -or
        ($Restart['stage'] -eq 4 -and $Restart['launch_contact_id'] -lt 0)) {
        throw 'Restart launch contact identity contradicts its actual preparation/execution stage.'
    }
    if ($Restart['kind'] -eq 0) {
        if ($Restart['stage'] -ne 0 -or $Restart['id'] -ne -1 -or $Restart['taker_actor_id'] -ne -1 -or
            $Restart['awarded_team_id'] -ne -1 -or $Restart['ready_tick'] -ne -1 -or $Restart['deadline_tick'] -ne -1) {
            throw 'NONE restart cannot pretend to be an active set piece.'
        }
    }
    else {
        if ($Restart['id'] -lt 0 -or $Restart['stage'] -lt 1 -or $Restart['awarded_team_id'] -notin @(0, 1) -or
            $Restart['taker_actor_id'] -lt 0) { throw 'Active restart identity is invalid.' }
        if ($Restart['stage'] -ge 3) {
            if ($Restart['ready_tick'] -lt 60 -or $Restart['placement_end_tick'] -gt $Restart['ready_tick'] -or
                ($Restart['stage'] -eq 3 -and $Restart['stage_started_tick'] -ne $Restart['ready_tick'])) {
                throw 'A restart became READY before authoritative placement.'
            }
            $deadline = if ($Restart['kind'] -eq 6) { -1 } else { $Restart['ready_tick'] + 240 }
            if ($Restart['deadline_tick'] -ne $deadline) { throw 'Restart deadline was renewed or confused with the penalty exemption.' }
        }
        if ($Restart['has_spot_choice'] -and $Restart['kind'] -ne 7) { throw 'Only the accumulated kick offers this spot choice.' }
    }
}

function Assert-GpState($State, [int]$Mode, [int]$Exercise, [switch]$AllowDefaultAi) {
    if ($State -isnot [Collections.IDictionary] -or $State['phase'] -cnotin @('PLAYING', 'RESTART_PAUSE')) {
        throw 'Gameplay case requires a live or actually preparing authority snapshot.'
    }
    $ids = if ($Mode -eq 0) { @(0..3) } else { @(0..9) }
    foreach ($field in @('selected_actor_id', 'training_exercise', 'human_sequence', 'driver_start_calls', 'ball_owner_id')) {
        Assert-GpInteger $State[$field] $field
    }
    foreach ($field in @('actors', 'physical_actor_ids', 'ai_intent_actor_ids', 'ai_actor_ids', 'human_allowed_actions', 'accumulated_fouls')) {
        if ($State[$field] -isnot [Collections.IList]) { throw "Gameplay state requires array $field." }
    }
    [int[]]$intent = @()
    if ($AllowDefaultAi) { $intent = $ids }
    Assert-GodotModeState $State $Mode $intent $State['phase'] $State['selected_actor_id']
    if ($State['training_exercise'] -ne $Exercise -or $State['seconds_remaining'] -gt 120.000001 -or
        $State['ball_owner_id'] -notin (@(-1) + $ids) -or
        $State['human_sequence'] -ne $State['actors'][$State['selected_actor_id']]['sequence']) {
        throw 'Gameplay exercise, possession, clock or selected sequence disagrees with its authority.'
    }
    Assert-GodotIntegerList $State['score'] @(0, 0) 'Controlled gameplay exercise score'
    Assert-GpInteger $State['period_state'] 'period state' 0 0
    Assert-GpInteger $State['extended_restart_id'] 'extension restart' -1 -1
    Assert-GpInteger $State['extended_kick_event_id'] 'extension kick' -1 -1
    $fouls = if ($Exercise -eq 11) { @(0, 6) } else { @(0, 0) }
    Assert-GodotIntegerList $State['accumulated_fouls'] $fouls 'Catalog foul counters'
    Assert-GpRestart $State['restart']
    Assert-GpBoolean $State['selected_can_move'] 'selected_can_move'
    $context = if ($State['phase'] -ceq 'PLAYING') { 1 } elseif ($State['restart']['stage'] -eq 3) { 2 } else { 0 }
    Assert-GpInteger $State['human_control_context'] 'control context' $context $context
    if ($State['selected_can_move'] -ne ($context -eq 1)) { throw 'Prepared taker movement or live controls disagree with authority.' }
    $actions = [Collections.Generic.HashSet[int]]::new()
    foreach ($action in $State['human_allowed_actions']) {
        Assert-GpInteger $action 'allowed action' 0 7
        if (-not $actions.Add($action)) { throw 'Duplicate allowed gameplay action.' }
    }
    if (-not $actions.Contains(0)) { throw 'A valid actor always retains the canonical NONE action.' }
    if ($State['phase'] -ceq 'RESTART_PAUSE') {
        $restart = $State['restart']
        if ($restart['stage'] -notin @(1, 2, 3) -or $restart['awarded_team_id'] -ne 0 -or
            $restart['taker_actor_id'] -ne $State['selected_actor_id']) { throw 'Own restart selection is not the actual taker.' }
        if ($restart['stage'] -eq 3) {
            $expectedActions = @(0, 1, 2)
            if ($restart['kind'] -eq 3) { $expectedActions = @(0, 6) }
            elseif ($restart['kind'] -in @(6, 7)) {
                $expectedActions = @(0, 2)
                if ($restart['has_spot_choice']) { $expectedActions += 7 }
            }
            Assert-GodotIntegerList $State['human_allowed_actions'] $expectedActions 'Actual ready-taker actions'
            if ($State['tick'] -lt $restart['ready_tick'] -or
                ($restart['deadline_tick'] -ge 0 -and $State['tick'] -ge $restart['deadline_tick'])) {
                throw 'READY snapshot lies outside its actual execution window.'
            }
        }
        else { Assert-GodotIntegerList $State['human_allowed_actions'] @(0) 'Placement disables action edges' }
    }
    else {
        $owner = $State['ball_owner_id'] -eq $State['selected_actor_id']
        $selectedActor = $State['actors'][$State['selected_actor_id']]
        $allowed = if ($owner) {
            if ($selectedActor['ball_in_hands']) { @(0, 6) } elseif ($selectedActor['ball_contact_reachable']) { @(0, 1, 2, 5) } else { @(0) }
        } else { @(0, 3, 4) }
        if (@($State['human_allowed_actions'] | Where-Object { $_ -notin $allowed }).Count -ne 0 -or
            (-not $owner -and -not $actions.Contains(4))) {
            throw 'Live action context contradicts physical possession or selected HOME control.'
        }
    }
    foreach ($actor in $State['actors']) {
        foreach ($field in @('id', 'team', 'role', 'gesture_kind', 'gesture_started_tick', 'gesture_duration_ticks')) {
            Assert-GpInteger $actor[$field] "actor.$field"
        }
        Assert-GpInteger $actor['gesture_kind'] 'actor gesture' 0 5
        Assert-GpInteger $actor['gesture_duration_ticks'] 'gesture duration' 0 600
        foreach ($field in @('ball_in_hands', 'ball_contact_reachable')) { Assert-GpBoolean $actor[$field] "actor.$field" }
        foreach ($field in @('gesture_direction', 'gesture_contact_position')) { Assert-GodotFiniteVector $actor[$field] "actor.$field" }
        if ($actor['ball_in_hands'] -and ($actor['role'] -ne 1 -or $State['ball_owner_id'] -ne $actor['id'])) {
            throw 'Only the actual possessing goalkeeper can hold the ball.'
        }
    }
}

function Assert-GpEvent($Event) {
    if ($Event -isnot [Collections.IDictionary]) { throw 'Malformed gameplay event.' }
    foreach ($field in @('id', 'tick', 'actor', 'target', 'selected_actor_id', 'ball_owner_id', 'contact_id')) {
        Assert-GpInteger $Event[$field] "event.$field"
    }
    Assert-GpInteger $Event['kind'] 'event.kind' 0 12
    Assert-GpInteger $Event['launch_kind'] 'event.launch_kind' 0 2
    Assert-GpInteger $Event['gesture_kind'] 'event.gesture_kind' 0 5
    Assert-GpInteger $Event['foul_verdict'] 'event.foul_verdict' 0 3
    Assert-GpNumber $Event['shot_charge'] 'event.shot_charge' 0 1
    if ($Event['reason'] -isnot [string]) { throw 'Event reason is not a native string.' }
    foreach ($field in @('position', 'velocity', 'contact_point')) { Assert-GodotFiniteVector $Event[$field] "event.$field" }
    Assert-GodotIntegerList $Event['score'] @(0, 0) 'Controlled gameplay event score'
    Assert-GpRestart $Event['restart']
}

function Assert-GpInput($NativeInput, [string]$Label) {
    if ($NativeInput -isnot [Collections.IDictionary] -or $NativeInput['case'] -cne $Label) { throw 'Native input is detached from its actual exercise.' }
    Assert-GpInteger $NativeInput['device'] 'input device' 0 0
    Assert-GpInteger $NativeInput['tick'] 'input tick' 0
    switch -CaseSensitive ($NativeInput['class']) {
        'InputEventKey' {
            Assert-GpInteger $NativeInput['physical_keycode'] 'physical key' 1 8388607
            Assert-GpBoolean $NativeInput['pressed'] 'key pressed'
            Assert-GpBoolean $NativeInput['echo'] 'key echo' $false
        }
        'InputEventJoypadButton' {
            Assert-GpInteger $NativeInput['button_index'] 'joy button' 0 20
            Assert-GpBoolean $NativeInput['pressed'] 'joy pressed'
        }
        'InputEventJoypadMotion' {
            Assert-GpInteger $NativeInput['axis'] 'joy axis' 0 5
            Assert-GpNumber $NativeInput['axis_value'] 'joy axis value' -1 1
        }
        'InputEventMouseButton' {
            Assert-GpInteger $NativeInput['button_index'] 'mouse button' 1 1
            Assert-GpBoolean $NativeInput['pressed'] 'mouse pressed'
            if ($NativeInput['position'] -isnot [Collections.IList] -or $NativeInput['position'].Count -ne 2) { throw 'Native GUI click omitted its position.' }
            Assert-GpNumber $NativeInput['position'][0] 'mouse x' 0 1920
            Assert-GpNumber $NativeInput['position'][1] 'mouse y' 0 1080
        }
        'InputEventMouseMotion' {
            foreach ($field in @('position', 'relative')) {
                if ($NativeInput[$field] -isnot [Collections.IList] -or $NativeInput[$field].Count -ne 2) {
                    throw "Native GUI motion requires a two-component $field vector."
                }
            }
            Assert-GpNumber $NativeInput['position'][0] 'mouse motion x' 0 1920
            Assert-GpNumber $NativeInput['position'][1] 'mouse motion y' 0 1080
            Assert-GpNumber $NativeInput['relative'][0] 'mouse relative x' -1920 1920
            Assert-GpNumber $NativeInput['relative'][1] 'mouse relative y' -1080 1080
        }
        default { throw 'Gameplay inputs must be actual key, joypad or GUI mouse events.' }
    }
}

function Find-GpInput($Inputs, [string]$Class, [string]$Field, $Value, $Pressed = $null) {
    return @($Inputs | Where-Object {
        $_['class'] -ceq $Class -and
            $(if ($Value -is [double] -or $Value -is [single]) {
                (Test-GodotGameplayFiniteNumber $_[$Field]) -and [Math]::Abs($_[$Field] - $Value) -lt 0.00001
            } else { $_[$Field] -ceq $Value }) -and
            ($Pressed -isnot [bool] -or $_['pressed'] -ceq $Pressed)
    })
}

function Assert-GpInputAction($Inputs, [string]$Class, [string]$Field, $Value, $Pressed = $null) {
    if (@(Find-GpInput $Inputs $Class $Field $Value $Pressed).Count -eq 0) { throw "Missing production input $Class/$Field=$Value." }
}

function Get-GpAppliedInputs($Observation) {
    $inputs = $Observation['input']
    $apply = -1
    for ($index = 0; $index -lt $inputs.Count; $index++) {
        if ($inputs[$index]['class'] -ceq 'InputEventMouseButton' -and $inputs[$index]['pressed']) { $apply = $index; break }
    }
    if ($apply -lt 0 -or $apply + 1 -ge $inputs.Count) { throw 'No actual Apply mouse input establishes the exercise clock.' }
    if ($apply -eq 0 -or $inputs[$apply - 1]['class'] -cne 'InputEventMouseMotion') {
        throw 'Actual Apply requires its recorded local mouse motion before the paired button edges.'
    }
    $motion = $inputs[$apply - 1]
    $press = $inputs[$apply]
    $release = $inputs[$apply + 1]
    if ($release['class'] -cne 'InputEventMouseButton' -or $release['pressed'] -or $release['button_index'] -ne 1) {
        throw 'Actual Apply requires its paired mouse release.'
    }
    Assert-GpEqual $motion['position'] $press['position'] 'Apply motion/press position'
    Assert-GpEqual $release['position'] $press['position'] 'Apply press/release position'
    if ($motion['tick'] -ne $press['tick'] -or $release['tick'] -ne $press['tick']) {
        throw 'Synchronous Apply motion/edges must retain the same pre-reset clock.'
    }
    $lastTick = -1
    for ($index = 0; $index -le $apply + 1; $index++) {
        if ($inputs[$index]['tick'] -lt $lastTick) { throw 'Native preparation input rewinds before Apply.' }
        $lastTick = $inputs[$index]['tick']
    }
    # The driver records each edge before dispatch; the release resets the authority during dispatch.
    $lastTick = -1
    $result = [Collections.Generic.List[object]]::new()
    for ($index = $apply + 2; $index -lt $inputs.Count; $index++) {
        $item = $inputs[$index]
        if ($item['tick'] -lt $lastTick -or $item['tick'] -gt $Observation['tick']) {
            throw 'Native gameplay input rewinds or occurs after its observed authority snapshot.'
        }
        $lastTick = $item['tick']
        $result.Add($item)
    }
    return $result.ToArray()
}

function Assert-GpLaunchInput($Observation, $Event, [string]$Class, [int]$Code) {
    $field = if ($Class -ceq 'InputEventKey') { 'physical_keycode' } else { 'button_index' }
    $inputs = @(Get-GpAppliedInputs $Observation)
    $pressed = @(Find-GpInput $inputs $Class $field $Code $true)
    $released = @(Find-GpInput $inputs $Class $field $Code $false)
    if ($pressed.Count -ne 1 -or $released.Count -ne 1 -or $released[0]['tick'] -lt $pressed[0]['tick'] -or
        $Event['tick'] -le $pressed[0]['tick']) { throw 'Accepted launch lacks its single native press/release edge and subsequent authority tick.' }
    if ($Event['kind'] -eq 2) {
        $chargedTicks = $released[0]['tick'] - $pressed[0]['tick']
        if ($Event['tick'] -le $released[0]['tick'] -or $chargedTicks -le 0 -or
            [Math]::Abs($Event['shot_charge'] - [Math]::Min(1.0, $chargedTicks / 48.0)) -gt 1.0 / 48.0 + 0.0001) {
            throw 'Shot charge/release does not follow the actual 0.8-second held-input interval.'
        }
    }
    elseif ($Event['tick'] -gt $released[0]['tick'] + 1) { throw 'Pass was delayed beyond the native edge instead of the next accepted tick.' }
}

function Get-GpCameraAxes($Camera) {
    $pitch = [double]$Camera['rotation'][0]
    $yaw = [double]$Camera['rotation'][1]
    $cp = [Math]::Cos($pitch); $sp = [Math]::Sin($pitch)
    $cy = [Math]::Cos($yaw); $sy = [Math]::Sin($yaw)
    return @{
        right = @($cy, 0.0, -$sy)
        up = @(($sy * $sp), $cp, ($cy * $sp))
        back = @(($sy * $cp), -$sp, ($cy * $cp))
    }
}

function Assert-GpCameraTracking($Camera, $Ball) {
    if ($Camera -isnot [Collections.IDictionary]) { throw 'Missing actual camera tracking evidence.' }
    foreach ($field in @('position', 'rotation', 'look_target', 'tracked_ball')) {
        Assert-GodotFiniteVector $Camera[$field] "camera.$field"
    }
    Assert-GpNear $Camera['tracked_ball'] $Ball 0.0001 'camera tracked ball / observed ball'
    $toward = @(($Camera['look_target'][0] - $Camera['position'][0]),
        ($Camera['look_target'][1] - $Camera['position'][1]), ($Camera['look_target'][2] - $Camera['position'][2]))
    $length = Get-GpLength $toward
    if ($length -lt 0.000001) { throw 'Camera look target coincides with its eye.' }
    $back = @((-$toward[0] / $length), (-$toward[1] / $length), (-$toward[2] / $length))
    Assert-GpNear $back (Get-GpCameraAxes $Camera).back 0.0001 'camera look target / actual rotation'
}

function Test-GpFramedPoint($Point, $Camera, $Axes) {
    $delta = @(($Point[0] - $Camera['position'][0]), ($Point[1] - $Camera['position'][1]), ($Point[2] - $Camera['position'][2]))
    $depth = -(Get-GpDot $delta $Axes.back)
    if ($depth -le $Camera['near'] -or $depth -ge $Camera['far']) { return $false }
    $halfHeight = $depth * [Math]::Tan([Math]::PI * $Camera['fov'] / 360.0)
    $x = 0.5 + (Get-GpDot $delta $Axes.right) / (2.0 * $halfHeight * 1920.0 / 1080.0)
    $y = 0.5 - (Get-GpDot $delta $Axes.up) / (2.0 * $halfHeight)
    return $x -gt 0.03 -and $x -lt 0.97 -and $y -gt 0.12 -and $y -lt 0.86
}

function Assert-GpCamera($Camera, $State, $VisibleOptions) {
    if ($Camera -isnot [Collections.IDictionary]) { throw 'Missing real camera evidence.' }
    foreach ($field in @('tick', 'restart_id', 'taker_actor_id', 'transition_started_tick', 'accepted_return_event_id', 'input_projection_serial')) {
        Assert-GpInteger $Camera[$field] "camera.$field"
    }
    Assert-GpInteger $Camera['tick'] 'camera authority tick' 0
    Assert-GpInteger $Camera['input_projection_serial'] 'camera input serial' 0
    Assert-GpInteger $Camera['transition_ticks_elapsed'] 'camera transition age' 0 45
    Assert-GpInteger $Camera['keep_aspect'] 'camera keep height' 1 1
    foreach ($field in @('position', 'rotation', 'restart_spot', 'input_right', 'input_down')) { Assert-GodotFiniteVector $Camera[$field] "camera.$field" }
    Assert-GpBoolean $Camera['transition_complete'] 'camera transition complete'
    Assert-GpBoolean $Camera['input_locked'] 'camera input locked'
    Assert-GpNumber $Camera['fov'] 'camera fov' 35 66
    Assert-GpNumber $Camera['near'] 'camera near plane' 0.01 1
    Assert-GpNumber $Camera['far'] 'camera far plane' 50 150
    if ($Camera['tick'] -ne $State['tick'] -or $Camera['fov_axis'] -cne 'vertical' -or
        [Math]::Abs($Camera['rotation'][2]) -gt 0.001 -or $Camera['mode'] -cnotin @('corner', 'returning', 'broadcast')) {
        throw 'Camera context tick, projection, roll or mode disagrees with the actual host.'
    }
    $elapsed = [Math]::Min(45, [Math]::Max(0, $Camera['tick'] - $Camera['transition_started_tick']))
    $transitioning = $Camera['transition_started_tick'] -ge 0 -and $elapsed -lt 45
    if ($Camera['transition_ticks_elapsed'] -ne $elapsed -or $Camera['transition_complete'] -ne (-not $transitioning)) {
        throw 'Camera transition age was fabricated or uses a separate rendering clock.'
    }
    if ($Camera['mode'] -ceq 'broadcast' -and ($transitioning -or
        [Math]::Abs($Camera['fov'] - $(if ($State['mode'] -eq 0) { 46.0 } else { 48.0 })) -gt 0.001)) {
        throw 'Broadcast projection is not the actual stable mode-specific camera.'
    }
    if ($Camera['mode'] -ceq 'returning' -and -not $transitioning) { throw 'Camera reports a completed transition as still returning.' }
    foreach ($axis in @('input_right', 'input_down')) {
        if ([Math]::Abs((Get-GpLength $Camera[$axis]) - 1.0) -gt 0.001 -or [Math]::Abs($Camera[$axis][1]) -gt 0.001) {
            throw 'Camera input projection is not a finite planar unit direction.'
        }
    }
    if ([Math]::Abs((Get-GpDot $Camera['input_right'] $Camera['input_down'])) -gt 0.001) { throw 'Camera input projection axes disagree.' }
    $axes = Get-GpCameraAxes $Camera
    $visible = @()
    foreach ($actor in $State['actors']) {
        if ($actor['team'] -ne 0 -or $actor['id'] -eq $State['selected_actor_id']) { continue }
        $top = @($actor['position'][0], ($actor['position'][1] + 1.75), $actor['position'][2])
        if ((Test-GpFramedPoint $actor['position'] $Camera $axes) -and (Test-GpFramedPoint $top $Camera $axes)) { $visible += $actor['id'] }
    }
    if ($VisibleOptions -isnot [Collections.IList]) { throw 'Missing measured HOME visibility IDs.' }
    Assert-GodotIntegerList $VisibleOptions $visible 'Geometrically visible complete HOME options'
    if ($State['restart']['kind'] -eq 2 -and $State['phase'] -ceq 'RESTART_PAUSE') {
        $restart = $State['restart']
        if ($Camera['mode'] -cne 'corner' -or $Camera['restart_id'] -ne $restart['id'] -or
            $Camera['taker_actor_id'] -ne $State['selected_actor_id'] -or $visible.Count -eq 0) {
            throw 'Own corner framing is detached from its restart, taker or real passing options.'
        }
        Assert-GpNear $Camera['restart_spot'] $restart['spot'] 0.0001 'corner camera spot'
        if ($restart['stage'] -eq 3) {
            if (-not $Camera['transition_complete'] -or $Camera['transition_ticks_elapsed'] -ne 45 -or
                [Math]::Abs($Camera['fov'] - 60.0) -gt 0.001) { throw 'READY corner camera has not reached its authoritative pose.' }
            $x = $restart['spot'][0]; $z = $restart['spot'][2]
            $eye = @([Math]::Clamp($x + [Math]::Sign($x) * 2.2, -23.2, 23.2), 2.9,
                [Math]::Clamp($z + [Math]::Sign($z) * 3.1, -13.2, 13.2))
            Assert-GpNear $Camera['position'] $eye 0.001 'actual corner orientation'
            $taker = $State['actors'][$State['selected_actor_id']]['position']
            foreach ($point in @($State['ball_position'], $taker, @($taker[0], ($taker[1] + 1.75), $taker[2]))) {
                if (-not (Test-GpFramedPoint $point $Camera $axes)) { throw 'Corner ball or complete taker is behind/outside the real camera.' }
            }
        }
    }
}

function Assert-GpPose($Pose, [string]$HostPath, $State = $null) {
    if ($Pose -isnot [Collections.IDictionary]) { throw 'Missing actual athlete presentation.' }
    Assert-GpInteger $Pose['actor_id'] 'presentation actor' 0 9
    $path = "$HostPath/Athletes/Athlete$($Pose['actor_id'])"
    if ($Pose['path'] -cne $path -or $Pose['source_script'] -cne 'res://match/presentation/athletes/athlete_view.gd' -or
        $Pose['validation_error'] -cne '') { throw 'Athlete presentation is not the actual valid host component.' }
    Assert-GpBoolean $Pose['context_valid'] 'athlete context valid' $true
    foreach ($field in @('context_before_tick', 'context_tick', 'contact_tick')) { Assert-GpInteger $Pose[$field] "pose.$field" }
    Assert-GpInteger $Pose['context_phase'] 'pose phase' 0 5
    Assert-GpInteger $Pose['gesture_kind'] 'pose gesture' 0 5
    Assert-GpNumber $Pose['render_tick'] 'render tick' 0
    Assert-GpNumber $Pose['gesture_age_ticks'] 'gesture age' -1
    Assert-GpNumber $Pose['gesture_weight'] 'gesture_weight' 0 1
    Assert-GpNumber $Pose['gesture_progress'] 'gesture_progress' -1 1
    foreach ($field in @('contact_world', 'snapshot_ball')) { Assert-GodotFiniteVector $Pose[$field] "pose.$field" }
    if ($Pose['context_before_tick'] -lt 0 -or $Pose['context_before_tick'] -gt $Pose['context_tick'] -or
        $Pose['context_tick'] - $Pose['context_before_tick'] -gt 1 -or
        $Pose['render_tick'] -lt $Pose['context_before_tick'] - 0.0001 -or
        $Pose['render_tick'] -gt $Pose['context_tick'] + 0.0001 -or
        [Math]::Abs($Pose['gesture_age_ticks'] - ($Pose['render_tick'] - $Pose['contact_tick'])) -gt 0.0001) {
        throw 'Athlete presentation uses stale/fabricated full-snapshot or gesture timing.'
    }
    if ($null -ne $State) {
        $phase = if ($State['phase'] -ceq 'PLAYING') { 1 } else { 3 }
        if ($Pose['actor_id'] -ge $State['actors'].Count -or $Pose['context_tick'] -ne $State['tick'] -or
            $Pose['context_phase'] -ne $phase) { throw 'Athlete view context is not the observed host snapshot.' }
        Assert-GpNear $Pose['snapshot_ball'] $State['ball_position'] 0.000001 'athlete full-snapshot ball'
    }
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($kind in @('feet', 'hands')) {
        if ($Pose[$kind] -isnot [Collections.IList] -or $Pose[$kind].Count -ne 2) { throw 'Require both real feet and both real hands.' }
        foreach ($mesh in $Pose[$kind]) {
            if ($mesh -isnot [Collections.IDictionary] -or $mesh['path'] -isnot [string] -or
                -not $mesh['path'].StartsWith($path + '/', [StringComparison]::Ordinal) -or -not $paths.Add($mesh['path'])) {
                throw 'Limb transforms must come from distinct descendants of the actual athlete.'
            }
            Assert-GpBoolean $mesh['visible'] 'limb visible' $true
            foreach ($field in @('origin', 'basis_x', 'basis_y', 'basis_z')) { Assert-GodotFiniteVector $mesh[$field] "limb.$field" }
            $x = $mesh['basis_x']; $y = $mesh['basis_y']; $z = $mesh['basis_z']
            $cross = @(($y[1] * $z[2] - $y[2] * $z[1]), ($y[2] * $z[0] - $y[0] * $z[2]), ($y[0] * $z[1] - $y[1] * $z[0]))
            if ([Math]::Abs((Get-GpDot $x $cross)) -lt 1e-9) { throw 'Degenerate limb transform is not a rendered body pose.' }
            if ($null -ne $State -and
                (Get-GodotVectorDistanceSquared $mesh['origin'] $State['actors'][$Pose['actor_id']]['position']) -gt 16) {
                throw 'Limb origin is detached from its physical actor.'
            }
        }
    }
}

function Assert-GpContactPose($Pose, $Event, [string]$HostPath) {
    Assert-GpPose $Pose $HostPath
    if ($Pose['actor_id'] -ne $Event['actor'] -or $Pose['contact_tick'] -ne $Event['tick'] -or
        $Pose['gesture_kind'] -ne $Event['gesture_kind'] -or $Pose['gesture_weight'] -le 0 -or
        $Pose['render_tick'] -lt $Event['tick'] - 1.0) { throw 'Accepted contact does not drive the actual actor gesture and render tick.' }
    Assert-GpNear $Pose['contact_world'] $Event['contact_point'] 0.0001 'accepted physical/rendered contact'
    $limbs = if ($Event['gesture_kind'] -eq 5) { $Pose['hands'] } else { $Pose['feet'] }
    if (@($limbs | Where-Object { (Get-GodotVectorDistanceSquared $_['origin'] $Event['contact_point']) -le 0.25 }).Count -eq 0) {
        throw 'No acting limb is near the claimed physical contact.'
    }
}

function Assert-GpObservation($Observation, $Policy, [string]$HostPath) {
    if ($Observation -isnot [Collections.IDictionary]) { throw 'Gameplay case omitted its observed host state.' }
    $state = $Observation['state']
    Assert-GpState $state $Policy.mode $Policy.exercise
    foreach ($field in @('mode', 'exercise', 'tick', 'selected_actor_id')) { Assert-GpInteger $Observation[$field] "observation.$field" 0 }
    if ($Observation['mode'] -ne $state['mode'] -or $Observation['exercise'] -ne $state['training_exercise'] -or
        $Observation['tick'] -ne $state['tick'] -or $Observation['phase'] -cne $state['phase'] -or
        $Observation['selected_actor_id'] -ne $state['selected_actor_id']) { throw 'Observation summaries disagree with actual snapshot state.' }
    Assert-GpEqual $Observation['restart'] $state['restart'] 'observation/restart'
    foreach ($field in @('input', 'events', 'athlete_presentations')) {
        if ($Observation[$field] -isnot [Collections.IList]) { throw "Observation requires array $field." }
    }
    foreach ($input in $Observation['input']) { Assert-GpInput $input $Policy.label }
    $null = @(Get-GpAppliedInputs $Observation)
    foreach ($event in $Observation['events']) { Assert-GpEvent $event }
    Assert-GpCamera $Observation['camera'] $state $Observation['visible_home_options']
    Assert-GpNumber $Observation['interpolation_fraction'] 'interpolation fraction' 0 1
    Assert-GodotFiniteVector $Observation['render_ball_position'] 'actual BallView origin'
    $tolerance = (Get-GpLength $state['ball_velocity']) / 60.0 + 0.05
    Assert-GpNear $Observation['render_ball_position'] $state['ball_position'] $tolerance 'interpolated/physical ball'
    Assert-GpCameraTracking $Observation['camera'] $Observation['render_ball_position']
    if ($Observation['athlete_presentations'].Count -ne $state['actors'].Count) { throw 'Not every actual body has its host-rendered presentation.' }
    for ($index = 0; $index -lt $state['actors'].Count; $index++) {
        $pose = $Observation['athlete_presentations'][$index]
        if ($pose['actor_id'] -ne $index) { throw 'Duplicated or missing athlete presentation identity.' }
        Assert-GpPose $pose $HostPath $state
    }
    $selected = $state['selected_actor_id']
    $role = if ($selected -eq 2) { 'PORTERO' } else { 'CAMPO' }
    if ($Observation['hud_selected'] -cne "CONTROL · ID $selected`n$role LOCAL") { throw 'Visible HUD selection is not the actual selected actor.' }
    $caption = if ($state['human_control_context'] -eq 2) { 'SAQUE PROPIO' } elseif ($state['human_control_context'] -eq 0) {
        'CONTROLES EN ESPERA'
    } elseif ($state['ball_owner_id'] -eq $selected) { 'CON BALÓN' } else { 'SIN BALÓN' }
    if ($Observation['hud_context'] -isnot [string] -or -not $Observation['hud_context'].StartsWith($caption, [StringComparison]::Ordinal)) {
        throw 'HUD control context is detached from authority.'
    }
    foreach ($field in @('hud_restart_title', 'hud_restart_clock', 'hud_fouls')) {
        if ($Observation[$field] -isnot [string]) { throw "Missing native HUD $field." }
    }
    $guide = $Observation['guide']
    if ($guide -isnot [Collections.IDictionary] -or $guide['path'] -cne "$HostPath/BallView/WorldAimGuide/Arrow") {
        throw 'Guide is not the real host arrow.'
    }
    foreach ($field in @('visible', 'shaft_visible', 'head_visible', 'same_render_world_as_ball', 'executable')) {
        Assert-GpBoolean $guide[$field] "guide.$field"
    }
    Assert-GpInteger $guide['mesh_count'] 'guide mesh count' 2 2
    Assert-GpInteger $guide['effective_target_actor_id'] 'guide receiver' -1 9
    Assert-GpNumber $guide['power'] 'guide power' 0 1
    foreach ($field in @('render_origin', 'physical_origin', 'direction', 'launch_velocity')) { Assert-GodotFiniteVector $guide[$field] "guide.$field" }
    if ($guide['visible']) {
        if (-not $guide['shaft_visible'] -or -not $guide['head_visible'] -or -not $guide['same_render_world_as_ball'] -or
            [Math]::Abs((Get-GpLength $guide['direction']) - 1.0) -gt 0.001 -or [Math]::Abs($guide['direction'][1]) -gt 0.001) {
            throw 'Visible guide has no valid world meshes or planar direction.'
        }
        $ball = $Observation['render_ball_position']
        Assert-GpNear $guide['render_origin'] @($ball[0], ($ball[1] + 0.035), $ball[2]) 0.0001 'guide/real rendered ball'
        Assert-GpNear $guide['physical_origin'] $state['ball_position'] 0.04 'guide/authoritative ball'
        $velocity = @($guide['launch_velocity'][0], 0.0, $guide['launch_velocity'][2])
        $speed = Get-GpLength $velocity
        if ($speed -le 0.5 -or (Get-GpDot $guide['direction'] $velocity) / $speed -lt 0.999) {
            throw 'Guide direction and actual launch velocity disagree.'
        }
        if ($guide['effective_target_actor_id'] -ne -1 -and
            ($guide['effective_target_actor_id'] -ge $state['actor_count'] -or
                $guide['effective_target_actor_id'] % 2 -ne 0 -or $guide['effective_target_actor_id'] -eq $selected)) {
            throw 'Guide fabricated an invalid effective HOME receiver.'
        }
    }
    else {
        if ($guide['shaft_visible'] -or $guide['head_visible']) { throw 'Hidden guide left orphaned visible arrow meshes.' }
        if ($guide['executable'] -or $guide['effective_target_actor_id'] -ne -1 -or $guide['power'] -ne 0.0 -or
            (Get-GpLength $guide['physical_origin']) -ne 0.0 -or (Get-GpLength $guide['launch_velocity']) -ne 0.0) {
            throw 'Hidden guide retained cleared launch metadata.'
        }
    }
}

function Assert-GpPrefix($Prefix, $All, [string]$Name) {
    if ($Prefix -isnot [Collections.IList] -or $All -isnot [Collections.IList] -or $Prefix.Count -gt $All.Count) {
        throw "Incomplete gameplay $Name sequence."
    }
    for ($index = 0; $index -lt $Prefix.Count; $index++) { Assert-GpEqual $Prefix[$index] $All[$index] "${Name}[$index]" }
}

function Get-GpSessionEvents($Observation) {
    $events = $Observation['events']
    $start = -1
    for ($index = 0; $index -lt $events.Count; $index++) {
        if ($events[$index]['kind'] -eq 4 -and $events[$index]['reason'] -ceq 'training_start') { $start = $index }
    }
    if ($start -lt 0) { throw 'Production exercise has no actual catalog start event.' }
    $session = @($events[$start..($events.Count - 1)])
    $lastId = -1
    $lastTick = -1
    foreach ($event in $session) {
        if ($event['id'] -le $lastId -or $event['tick'] -lt $lastTick -or $event['tick'] -gt $Observation['tick'] -or $event['kind'] -eq 8) {
            throw 'Gameplay session event identities/ticks are impossible or out of order.'
        }
        $lastId = $event['id']; $lastTick = $event['tick']
    }
    return $session
}

function Assert-GpProgress($Before, $Observation) {
    $after = $Observation['state']
    if ($Before['driver_start_calls'] -ne $after['driver_start_calls'] -or $after['tick'] -lt $Before['tick']) {
        throw 'Gameplay case was replaced/reset instead of advancing its real authority.'
    }
    $events = @(Get-GpSessionEvents $Observation)
    $window = @($events | Where-Object { $_['tick'] -gt $Before['tick'] })
    $ticks = $after['tick'] - $Before['tick']
    $elapsed = if ($Before['phase'] -ceq 'PLAYING') { $ticks / 60.0 } else { 0.0 }
    $taken = @($window | Where-Object { $_['kind'] -eq 10 -and $_['reason'] -ceq 'taken' })
    if ($Before['phase'] -ceq 'RESTART_PAUSE' -and $after['phase'] -ceq 'PLAYING') {
        if ($taken.Count -ne 1) { throw 'Restart became live without one accepted taking event.' }
        $elapsed = ($after['tick'] - $taken[0]['tick']) / 60.0
    }
    if ([Math]::Abs($Before['seconds_remaining'] - $after['seconds_remaining'] - $elapsed) -gt 0.00001) {
        throw 'Gameplay clock disagrees with effective PLAYING time and frozen restart preparation.'
    }
    $active = [Collections.Generic.HashSet[int]]::new()
    [void]$active.Add($Before['selected_actor_id'])
    foreach ($event in $window | Where-Object { $_['kind'] -eq 9 }) { [void]$active.Add($event['target']) }
    if (-not $active.Contains($after['selected_actor_id'])) { throw 'Selection changed without an actual focus event.' }
    foreach ($actor in $after['actors']) {
        $old = $Before['actors'][$actor['id']]['sequence']
        if ($actor['sequence'] -lt $old -or (-not $active.Contains($actor['id']) -and $actor['sequence'] -ne $old)) {
            throw 'An actor replayed/reset input or gained AI commands while all intent remained off.'
        }
    }
    if ($ticks -gt 0 -and $Before['phase'] -ceq 'PLAYING' -and $after['phase'] -ceq 'PLAYING' -and
        $after['human_sequence'] -le $Before['actors'][$after['selected_actor_id']]['sequence']) {
        throw 'Live controlled input stopped advancing its authoritative sequence.'
    }
}

function Get-GpLaunch($Observation, $Before, [int]$Kind, [int]$LaunchKind) {
    $events = @(Get-GpSessionEvents $Observation)
    $launches = @($events | Where-Object { $_['kind'] -in @(1, 2) })
    if ($launches.Count -ne 1) { throw 'Scenario requires exactly one accepted physical launch.' }
    $event = $launches[0]
    $actor = $Before['selected_actor_id']
    $gesture = if ($LaunchKind -eq 2) { 5 } else { 4 }
    $reason = if ($LaunchKind -eq 2) { 'throw' } else { 'kick' }
    if ($event['kind'] -ne $Kind -or $event['launch_kind'] -ne $LaunchKind -or
        $event['gesture_kind'] -ne $gesture -or $event['actor'] -ne $actor -or $event['reason'] -cne $reason -or
        $event['tick'] -le $Before['tick'] -or $event['ball_owner_id'] -ne -1 -or $event['contact_id'] -lt 0 -or
        $Observation['state']['actors'][$actor]['sequence'] -le $Before['actors'][$actor]['sequence'] -or
        (Get-GpLength $event['velocity']) -le 0.5 -or (Get-GpLength $event['velocity']) -gt 60) {
        throw 'Accepted launch kind, physical actor/contact, velocity or frame is impossible.'
    }
    Assert-GpNear $event['position'] $event['contact_point'] 0.04 'kick origin/contact'
    $focus = @($events | Where-Object { $_['kind'] -eq 9 -and $_['tick'] -ge $event['tick'] })
    if ($Kind -eq 1) {
        if ($event['target'] -lt 0 -or $event['target'] -ge $Before['actor_count'] -or $event['target'] % 2 -ne 0 -or
            $event['target'] -eq $actor -or $event['selected_actor_id'] -ne $event['target'] -or
            $Observation['selected_actor_id'] -ne $event['target'] -or $focus.Count -ne 1 -or
            $focus[0]['actor'] -ne $actor -or $focus[0]['target'] -ne $event['target'] -or
            $focus[0]['reason'] -cne 'pass' -or $focus[0]['tick'] -ne $event['tick'] -or $focus[0]['id'] -le $event['id'] -or
            $event['shot_charge'] -ne 0.0) {
            throw 'Accepted restart pass did not transfer focus atomically to its effective HOME receiver.'
        }
        $receiver = $Before['actors'][$event['target']]['position']
        $toward = @(($receiver[0] - $event['position'][0]), 0.0, ($receiver[2] - $event['position'][2]))
        $velocity = @($event['velocity'][0], 0.0, $event['velocity'][2])
        if ((Get-GpLength $toward) -lt 0.001 -or
            (Get-GpDot $toward $velocity) / ((Get-GpLength $toward) * (Get-GpLength $velocity)) -lt 0.94) {
            throw 'Accepted pass velocity points away from its claimed effective receiver.'
        }
    }
    elseif ($event['target'] -ne -1 -or $event['selected_actor_id'] -ne $actor -or $event['shot_charge'] -le 0.1 -or
        $Observation['selected_actor_id'] -ne $actor -or $focus.Count -ne 0) { throw 'A shot fabricated a focus transfer.' }
    if ($Before['restart']['kind'] -ne 0) {
        $taken = @($events | Where-Object { $_['kind'] -eq 10 -and $_['reason'] -ceq 'taken' })
        if ($taken.Count -ne 1 -or $taken[0]['tick'] -ne $event['tick'] -or
            $taken[0]['id'] -le $event['id'] -or ($Kind -eq 1 -and $taken[0]['id'] -le $focus[0]['id']) -or
            $event['restart']['stage'] -ne 4 -or $event['restart']['id'] -ne $Before['restart']['id']) {
            throw 'Taking a restart must preserve identity and emit launch, focus when applicable, then taken.'
        }
        foreach ($state in @($event['restart'], $taken[0]['restart'], $Observation['state']['restart']) +
                @($focus | ForEach-Object { $_['restart'] })) {
            if ($state['id'] -ne $Before['restart']['id'] -or $state['launch_contact_id'] -ne $event['contact_id']) {
                throw 'Launch, focus, taken and the subsequent snapshot must retain the actual original contact episode.'
            }
        }
        Assert-GodotGameplayRestartLaunchWindow @{
            kind = $event['restart']['kind']; stage = 3; ready_tick = $event['restart']['ready_tick']
            deadline_tick = $event['restart']['deadline_tick']
        } $event['tick'] $true
    }
    return $event
}

function Assert-GpOwnedFile([string]$Path, [datetime]$StartedAt, [long]$MaximumBytes) {
        if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw 'Runtime evidence requires an absolute current-run path.' }
        $file = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($file.PSIsContainer -or $file.Length -le 0 -or $file.Length -gt $MaximumBytes -or
            $file.LastWriteTimeUtc -lt $StartedAt.ToUniversalTime() -or $file.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddSeconds(1)) {
            throw 'Runtime report/manifest is stale, future-dated, empty or exceeds its bounded I/O budget.'
        }
        $ancestor = $file
        while ($null -ne $ancestor) {
            if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Runtime evidence cannot traverse a reparse point.' }
            $ancestor = if ($ancestor -is [IO.FileInfo]) { $ancestor.Directory } else { $ancestor.Parent }
        }
    }

function Assert-GpPath($Actual, [string]$Expected, [string]$Name) {
        if ($Actual -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($Actual) -or
            -not [IO.Path]::GetFullPath($Actual).Equals([IO.Path]::GetFullPath($Expected), [StringComparison]::OrdinalIgnoreCase)) {
            throw "Gameplay $Name escaped or disagrees with the current invocation path."
        }
    }

function Assert-GpPoseSamples($Samples, $Cases, $Policy, [string]$HostPath) {
        if ($Samples -isnot [Collections.IList]) { throw 'Missing host athlete progression evidence.' }
        $wanted = [ordered]@{}
        foreach ($id in $Policy.Keys) {
            $p = $Policy[$id]
            if ($p.index -eq 5) { $wanted[$id] = @{kind = 'hands'; id = $id}; continue }
            if ($p.index -in @(1, 2, 3, 13)) { continue }
            $wanted[$id] = @{kind = 'contact'; id = $id}
            if ($p.index -eq 6) { $wanted[$p.label] = @{kind = 'contact'; id = $id} }
            if ($p.index -in @(4, 6, 7, 8, 9)) { $wanted[$p.label + '/progress'] = @{kind = 'progress'; id = $id} }
        }
        if ($Samples.Count -ne $wanted.Count) { throw 'Missing/duplicated source-defined contact, keeper-hand or pose-progression samples.' }
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($sample in $Samples) {
            if ($sample -isnot [Collections.IDictionary] -or $sample['case'] -cnotin $wanted.Keys -or -not $seen.Add($sample['case'])) {
                throw 'Athlete progression sample has an unknown or duplicate scenario identity.'
            }
            $request = $wanted[$sample['case']]
            $case = $Cases[$request.id]
            $p = $Policy[$request.id]
            if ($request.kind -ceq 'hands') {
                Assert-GpEqual $sample['ready_hands'] $case['after']['athlete_presentations'][2] 'keeper prepared hand pose'
                Assert-GpEqual $sample['render_ball_position'] $case['after']['render_ball_position'] 'keeper prepared BallView anchor'
                continue
            }
            $end = if ($case.Contains('completion')) { $case['completion'] } else { $case['after'] }
            $events = @(Get-GpSessionEvents $end)
            $contacts = @($events | Where-Object { $_['kind'] -in @(1, 2, 11) })
            if ($contacts.Count -ne 1) { throw 'Pose sample lacks its unique actual launch/dribble event.' }
            $event = $contacts[0]
            Assert-GpInteger $sample['event_id'] 'pose event id' 1
            if ($sample['event_id'] -ne $event['id']) { throw 'Pose sample names another physical event.' }
            Assert-GpContactPose $sample['at_contact'] $event $HostPath
            if ($sample['at_contact']['context_tick'] -gt $end['tick']) { throw 'Contact pose comes from after scenario completion.' }
            if ($request.kind -ceq 'progress') {
                $first = $sample['at_contact']; $next = $sample['advanced']
                Assert-GpContactPose $next $event $HostPath
                if ($next['context_tick'] -le $first['context_tick'] -or $next['render_tick'] -le $first['render_tick'] -or
                    $next['gesture_progress'] -le $first['gesture_progress'] -or $next['context_tick'] -gt $end['tick'] -or
                    (($first['feet'] | ConvertTo-Json -Depth 16 -Compress) -ceq ($next['feet'] | ConvertTo-Json -Depth 16 -Compress) -and
                        ($first['hands'] | ConvertTo-Json -Depth 16 -Compress) -ceq ($next['hands'] | ConvertTo-Json -Depth 16 -Compress))) {
                    throw 'Host limb transforms/gesture progression stalled, rewound or use another snapshot.'
                }
            }
            else {
                Assert-GpInteger $sample['accepted_tick'] 'pose accepted tick' 0
                if ($sample['accepted_tick'] -ne $event['tick']) { throw 'Pose/contact tick disagrees with the actual accepted event.' }
                if ($p.index -in @(6, 7, 8, 9) -and $sample['case'] -ceq $request.id) {
                    Assert-GpEqual $sample['at_contact'] $case['after']['athlete_presentations'][$event['actor']] 'captured actor/contact pose'
                }
            }
        }
    }

function Assert-GpRestartFocus($Report, $Cases) {
        for ($index = 6; $index -lt 10; $index++) {
            $focus = $Report['focus_changes'][$index]
            $mode = [int][Math]::Floor(($index - 6) / 2)
            $keeper = ($index - 6) % 2 -eq 1
            $id = if ($keeper) { "m$mode/keeper_clearance_ready" } else { "m$mode/corner_pos_x_neg_z" }
            $case = $Cases[$id]
            Assert-GpBoolean $focus['passed'] 'restart focus passed' $true
            if ($focus['source_script'] -cne 'res://match/match.gd' -or $focus['reason'] -cne 'pass' -or $focus.Contains('received') -or
                $focus['input'] -cne $(if ($keeper) { 'InputEventJoypadButton:A' } else { 'InputEventKey:J' })) {
                throw 'Restart focus record is not the actual production pass/throw input.'
            }
            Assert-GpEqual $focus['before'] $case['after']['state'] 'pre-kick focus/captured preparation'
            Assert-GpState $focus['after'] $mode $(if ($keeper) { 6 } else { 2 })
            foreach ($field in @('before_selected_actor_id', 'after_selected_actor_id', 'expected_selected_actor_id',
                    'before_ball_owner_id', 'after_ball_owner_id', 'actor_count')) { Assert-GpInteger $focus[$field] "focus.$field" }
            $old = $focus['before']['selected_actor_id']; $selected = $focus['after']['selected_actor_id']
            if ($focus['before_selected_actor_id'] -ne $old -or $focus['after_selected_actor_id'] -ne $selected -or
                $focus['expected_selected_actor_id'] -ne $selected -or $focus['before_ball_owner_id'] -ne $old -or
                $focus['after_ball_owner_id'] -ne -1 -or $focus['after']['ball_owner_id'] -ne -1 -or
                $focus['actor_count'] -ne $focus['after']['actor_count'] -or
                $focus['events'] -isnot [Collections.IList] -or $focus['events'].Count -ne 3) {
                throw 'Restart focus summary or ordered launch/focus/taken evidence is inconsistent.'
            }
            Assert-GodotIntegerList $focus['ai_intent_actor_ids'] @() 'Restart pass intent remains off'
            Assert-GodotIntegerList $focus['ai_actor_ids'] @() 'Restart pass does not re-enable AI'
            $full = @(Get-GpSessionEvents $case['completion'])
            $window = @($full | Where-Object { $_['tick'] -gt $focus['before']['tick'] -and $_['tick'] -le $focus['after']['tick'] })
            Assert-GpEqual $focus['events'] $window 'complete restart focus event window'
            $observation = @{
                state = $focus['after']; tick = $focus['after']['tick']; selected_actor_id = $selected
                events = @($full | Where-Object { $_['tick'] -le $focus['after']['tick'] })
            }
            Assert-GpProgress $focus['before'] $observation
            $null = Get-GpLaunch $observation $focus['before'] 1 $(if ($keeper) { 2 } else { 0 })
        }
    }

function Read-GodotGameplayRuntimeReport {
        param([Parameter(Mandatory)]$Result, [Parameter(Mandatory)][string]$ReportPath,
            [Parameter(Mandatory)][datetime]$StartedAt, [Parameter(Mandatory)][string]$Executable,
            [Parameter(Mandatory)][bool]$EditorBinary, [Parameter(Mandatory)][bool]$Headless,
            [Parameter(Mandatory)][string]$CaptureDirectory, [switch]$AllowKnownVulkanLayerWarning)
        if (-not (Test-GodotProcessCompletion $Result)) { throw 'Gameplay requires actual original-handle completion witnesses.' }
        Assert-GodotOutput $Result -AllowKnownVulkanLayerWarning:($AllowKnownVulkanLayerWarning -and -not $Headless)
        Assert-GpOwnedFile $ReportPath $StartedAt 33554432
        $expectedDirectory = Join-Path ([IO.Path]::GetDirectoryName($ReportPath)) (
            [IO.Path]::GetFileNameWithoutExtension($ReportPath) + '-gameplay-captures')
        Assert-GpPath $CaptureDirectory $expectedDirectory 'requested capture directory'
        $report = Read-GodotBaseGameReport -Result $Result -ReportPath $ReportPath -StartedAt $StartedAt `
            -Executable $Executable -EditorBinary $EditorBinary -Headless $Headless -RuntimeProtocol Gameplay
        if (-not (Test-GodotReportedProcess $Result $report['process_id'])) { throw 'Gameplay report PID is not witnessed as an actually owned exited process.' }
        foreach ($field in @('viewport_width', 'viewport_height', 'physics_ticks_per_second', 'driver_start_calls', 'frames_drawn', 'watchdog_msec')) {
            Assert-GpInteger $report[$field] "runtime.$field" 0
        }
        if ($report['display_server'] -isnot [string] -or
            $report['display_server'] -cne $(if ($Headless) { 'headless' } else { 'Windows' }) -or
            $report['gpu_api'] -isnot [string] -or
            ($Headless -and ($report['frames_drawn'] -ne 0 -or $report['gpu_name'] -cne 'not measured (headless)' -or $report['gpu_api'] -cne '')) -or
            (-not $Headless -and ($report['frames_drawn'] -le 0 -or $report['gpu_api'] -isnot [string] -or
                [string]::IsNullOrWhiteSpace($report['gpu_api'])))) {
            throw 'Rendering metadata fabricates a display/GPU or omits actually drawn frames.'
        }
        if ($report['watchdog_msec'] -ne 120000 -or $report['driver_start_calls'] -lt 1 -or
            $report['gameplay_driver_script'] -cne 'res://diagnostics/gameplay_smoke.gd' -or
            $report['input_method'] -isnot [string] -or
            $report['input_method'] -cne 'Input.parse_input_event; physical keys and raw joypad events, device 0' -or
            $report['gui_input_method'] -isnot [string] -or
            $report['gui_input_method'] -cne 'Viewport.push_input; local mouse coordinates, device 0' -or
            $report['aim_precision_controls'] -cne (Get-GodotGameplayContract)['fineAimHint']) {
            throw 'Gameplay driver, watchdog, native GUI dispatch or confirmed own-restart input protocol changed.'
        }
        Assert-GpNumber $report['aim_precision_max_degrees_per_second'] 'fine-aim rate' 29.99999 30.00001
        Assert-GpNumber $report['wall_seconds'] 'runtime wall time' 0.000001 121
        foreach ($field in @('failures', 'command_rejections', 'integration_errors')) {
            if ($report[$field] -isnot [Collections.IList] -or $report[$field].Count -ne 0) { throw "Gameplay requires explicit empty $field." }
        }
        # PowerShell 7.5 may coerce ISO JSON strings to DateTime; inspect the original JSON token.
        $document = [Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText($ReportPath, [Text.UTF8Encoding]::new($false, $true)))
        try { $timestampText = $document.RootElement.GetProperty('timestamp_utc').GetString() }
        finally { $document.Dispose() }
        $timestamp = [datetime]::MinValue
        if ($timestampText -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z?$' -or
            -not [datetime]::TryParse($timestampText,
            [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$timestamp) -or $timestamp -lt $StartedAt.ToUniversalTime().AddSeconds(-2) -or $timestamp -gt [datetime]::UtcNow.AddSeconds(1)) {
            throw 'Gameplay timestamp is not from this current invocation.'
        }
        $printed = @([regex]::Matches($Result.Stdout.Replace("`r`n", "`n"), '(?m)^PASS ([^\n]+)$'))
        if ($printed.Count -ne $report['checks'].Count -or [regex]::Matches($Result.Stdout, '(?m)^FUTSAL_[A-Z0-9_]+ ').Count -ne 1) {
            throw 'Actual printed checks/marker do not match one complete gameplay report.'
        }
        for ($index = 0; $index -lt $printed.Count; $index++) {
            if ($printed[$index].Groups[1].Value -cne $report['checks'][$index]['name']) { throw 'Printed native assertions differ from reported check identities.' }
        }
        $checkNames = @($report['checks'] | ForEach-Object { $_['name'] })
        foreach ($name in Get-GpRequiredNativeChecks) {
            if ($name -cnotin $checkNames) { throw "Mandatory actual native runtime assertion missing: $name" }
        }
        foreach ($name in @('before', 'after_wait', 'after_input')) { Assert-GpState $report['default_entrypoint'][$name] 1 0 -AllowDefaultAi }
        Assert-GpState $report['final_state'] 1 0 -AllowDefaultAi
        Assert-GpEqual $report['loaded_actors'] $report['default_entrypoint']['after_wait']['actors'] 'untouched loaded actors'
        Assert-GodotFocusChangesReport $report -Gameplay
        $authority = $report['authority_path']
        if ($authority -isnot [string] -or -not $authority.StartsWith('/root/', [StringComparison]::Ordinal) -or $authority.LastIndexOf('/') -le 6) {
            throw 'Gameplay authority has no actual main-scene ownership path.'
        }
        $hostPath = $authority.Substring(0, $authority.LastIndexOf('/'))
        if ($report['camera_path'] -cne "$hostPath/BroadcastCamera") { throw 'Main does not own the reported active camera.' }
        foreach ($field in @('hud_path', 'development_menu_path')) {
            if ($report[$field] -isnot [string] -or -not $report[$field].StartsWith($hostPath + '/', [StringComparison]::Ordinal)) {
                throw 'HUD/development ownership is detached from the real main.'
            }
        }
        $gameplay = $report['gameplay']
        if ($gameplay -isnot [Collections.IDictionary]) { throw 'Missing actual nested gameplay report.' }
        foreach ($field in @('started', 'complete')) { Assert-GpBoolean $gameplay[$field] "gameplay.$field" $true }
        Assert-GpBoolean $gameplay['capture_complete'] 'gameplay.capture_complete' (-not $Headless)
        foreach ($field in @('cases', 'native_inputs', 'athlete_presentations', 'expected_cases', 'completed_cases')) {
            if ($gameplay[$field] -isnot [Collections.IList]) { throw "Gameplay omitted typed $field evidence." }
        }
        $policy = Get-GodotGameplayCasePolicy
        $ids = @($policy.Keys)
        Assert-GpEqual $gameplay['expected_cases'] $ids 'source-defined expected cases'
        Assert-GpEqual $gameplay['completed_cases'] $ids 'source-defined completed cases'
        if ($gameplay['cases'].Count -ne $ids.Count) { throw 'Require all 28 actual cases, not fabricated G01-G32 pass flags.' }
        $cases = [ordered]@{}
        $historyCursor = Find-GodotRecordedEvent $report['events'] $report['focus_changes'][5]['events'][-1]
        $lastLabel = ''; $lastStarts = $report['focus_changes'][5]['after']['driver_start_calls']
        $lastEventStart = $historyCursor
        foreach ($id in $ids) {
            $case = $gameplay['cases'][$cases.Count]
            if ($case['case'] -cne $id) { throw 'Gameplay case missing, duplicated or out of actual production order.' }
            $p = $policy[$id]
            Assert-GpCase $case $p $hostPath
            if ($p.label -ceq $lastLabel) {
                if ($case['before']['driver_start_calls'] -ne $lastStarts) { throw 'Ready/release keeper observations changed sessions.' }
            }
            elseif ($case['before']['driver_start_calls'] -ne $lastStarts + 1) { throw 'A new catalog exercise did not use exactly one public start after the default proof.' }
            $globalInputs = @($gameplay['native_inputs'] | Where-Object { $_['case'] -ceq $p.label })
            Assert-GpPrefix $case['after']['input'] $globalInputs 'global native input'
            $end = if ($case.Contains('completion')) { $case['completion'] } else { $case['after'] }
            Assert-GpPrefix $end['input'] $globalInputs 'complete global native input'
            $local = $end['events']
            $found = -1
            $searchStart = if ($p.label -ceq $lastLabel) { $lastEventStart } else { $historyCursor }
            for ($position = $searchStart; $position -le $report['events'].Count - $local.Count; $position++) {
                if (-not (Test-GodotSameEvent $local[0] $report['events'][$position])) { continue }
                $matches = $true
                for ($offset = 0; $offset -lt $local.Count; $offset++) {
                    if (($local[$offset] | ConvertTo-Json -Depth 32 -Compress) -cne
                        ($report['events'][$position + $offset] | ConvertTo-Json -Depth 32 -Compress)) { $matches = $false; break }
                }
                if ($matches) { $found = $position; break }
            }
            if ($found -lt 0) { throw 'Gameplay case invented or omitted actual production events.' }
            $lastEventStart = $found
            $historyCursor = $found + $local.Count
            $lastLabel = $p.label; $lastStarts = $case['before']['driver_start_calls']
            $cases[$id] = $case
        }
        $labels = @($policy.Values | ForEach-Object { $_.label }) + @('', 'final_preview_restoration')
        foreach ($input in $gameplay['native_inputs']) {
            if ($input['case'] -cnotin $labels) { throw 'Global native input names an unknown scenario.' }
            Assert-GpInput $input $input['case']
        }
        Assert-GpRestartFocus $report $cases
        Assert-GpPoseSamples $gameplay['athlete_presentations'] $cases $policy $hostPath
        if ($report['driver_start_calls'] -ne $lastStarts -or $report['final_state']['driver_start_calls'] -ne $lastStarts -or
            $report['mode_changes'][4]['before']['driver_start_calls'] -ne $lastStarts) {
            throw 'Final default preview restoration is detached from the completed gameplay traversal.'
        }
        Assert-GpInteger $gameplay['required_png_count'] 'required PNG count' 20 20
        Assert-GpInteger $gameplay['observed_moment_count'] 'actual observation count' 20 20
        $saved = if ($Headless) { 0 } else { 20 }
        Assert-GpInteger $gameplay['saved_png_count'] 'actual saved PNG count' $saved $saved
        Assert-GpPath $gameplay['capture_directory'] $CaptureDirectory 'capture directory'
        $manifestPath = Join-Path $CaptureDirectory 'manifest.json'
        Assert-GpPath $gameplay['capture_manifest_path'] $manifestPath 'capture manifest'
        Assert-GpOwnedFile $manifestPath $StartedAt 33554432
        $manifest = [IO.File]::ReadAllText($manifestPath, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -AsHashtable -Depth 64
        foreach ($field in @('schema_version', 'process_id', 'required_png_count', 'saved_png_count')) { Assert-GpInteger $manifest[$field] "manifest.$field" 0 }
        if ($manifest['schema_version'] -ne 1 -or $manifest['process_id'] -ne $report['process_id'] -or
            $manifest['project_version'] -cne '0.4.0-preview' -or $manifest['driver_script'] -cne 'res://diagnostics/gameplay_smoke.gd' -or
            $manifest['main_scene'] -cne 'res://match/match.tscn' -or $manifest['required_png_count'] -ne 20 -or $manifest['saved_png_count'] -ne $saved) {
            throw 'Manifest identity does not belong to the actual source/artifact invocation.'
        }
        Assert-GpBoolean $manifest['headless'] 'manifest headless' $Headless
        Assert-GpBoolean $manifest['editor_binary'] 'manifest binary kind' $EditorBinary
        Assert-GpBoolean $manifest['functional_traversal_complete'] 'manifest traversal complete' $true
        Assert-GpPath $manifest['report_path'] $ReportPath 'manifest report'
        Assert-GpPath $manifest['capture_directory'] $CaptureDirectory 'manifest directory'
        if ($manifest['observations'] -isnot [Collections.IList] -or $manifest['observations'].Count -ne 20 -or
            $manifest['captures'] -isnot [Collections.IList] -or $manifest['captures'].Count -ne $saved) { throw 'Manifest omitted actual observation or PNG records.' }
        $captureIds = @($ids | Where-Object { $policy[$_].capture })
        $hashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        for ($index = 0; $index -lt $captureIds.Count; $index++) {
            $id = $captureIds[$index]
            $observation = $manifest['observations'][$index]
            Assert-GpEqual $observation $cases[$id]['after'] 'manifest/captured host observation'
            if ($observation['case'] -cne $id -or $observation['accepted_event'] -isnot [Collections.IDictionary]) {
                throw 'Capture case or accepted-event shape is not the real producer observation.'
            }
            if ($policy[$id].index -notin @(6, 7, 8, 9) -and $observation['accepted_event'].Count -ne 0) {
                throw 'Preparation/charge image invented an accepted contact event.'
            }
            if ($Headless) {
                if ($observation['capture_status'] -cne 'not_rendered_headless' -or $observation['filename'] -cne '') {
                    throw 'Headless runtime cannot fabricate a saved image or visual acceptance.'
                }
                foreach ($field in @('width', 'height', 'render_valid', 'sha256')) {
                    if ($observation.Contains($field)) { throw 'Headless observation contains invented PNG metadata.' }
                }
            }
            else {
                Assert-GpEqual $manifest['captures'][$index] $observation 'saved/observed PNG metadata'
                Assert-GpBoolean $observation['render_valid'] 'rendered capture valid' $true
                Assert-GpInteger $observation['width'] 'PNG width' 1920 1920
                Assert-GpInteger $observation['height'] 'PNG height' 1080 1080
                $path = Join-Path $CaptureDirectory ($id.Replace('/', '-') + '.png')
                Assert-GpPath $observation['filename'] $path 'actual capture filename'
                if ($observation['capture_status'] -cne 'saved' -or $observation['sha256'] -isnot [string] -or
                    -not $hashes.Add($observation['sha256'])) { throw 'A repeated or unsaved image cannot represent another gameplay moment.' }
                Assert-GodotGameplayCaptureFile $path $CaptureDirectory $StartedAt $observation['sha256']
            }
        }
        $files = @(Get-ChildItem -LiteralPath $CaptureDirectory -Force -File -Recurse)
        if ($files.Count -ne 1 + $saved -or @(Get-ChildItem -LiteralPath $CaptureDirectory -Force -Directory).Count -ne 0) {
            throw 'Capture directory contains extra, copied or nested evidence outside the exact manifest.'
        }
        return $report
    }

function Assert-GpCase($Case, $Policy, [string]$HostPath) {
    if ($Case -isnot [Collections.IDictionary] -or $Case['source_script'] -cne 'res://match/match.gd') {
        throw 'Gameplay cases must use the actual main host, not a fixture factory.'
    }
    Assert-GpBoolean $Case['passed'] 'case passed' $true
    Assert-GpState $Case['before'] $Policy.mode $Policy.exercise
    if ($Case['before']['driver_start_calls'] -lt 1 -or $Case['before']['restart']['kind'] -ne $Policy.kind) {
        throw 'Case did not enter its declared production catalog exercise.'
    }
    if ($Policy.kind -ne 0 -and ($Case['before']['phase'] -cne 'RESTART_PAUSE' -or
        $Case['before']['restart']['stage'] -notin @(1, 2))) { throw 'Set-piece fixture jumped directly into READY.' }
    Assert-GpObservation $Case['after'] $Policy $HostPath
    Assert-GpProgress $Case['before'] $Case['after']
    $after = $Case['after']
    $end = $after
    if ($Policy.capture) {
        if (-not $Case.Contains('completion')) { throw 'Captured case lacks its post-input completion observation.' }
        $end = $Case['completion']
        Assert-GpObservation $end $Policy $HostPath
        Assert-GpProgress $after['state'] $end
        Assert-GpPrefix $after['input'] $end['input'] 'case input'
        Assert-GpPrefix $after['events'] $end['events'] 'case event'
    }
    elseif ($Case.Contains('completion')) { throw 'Unexpected non-capture case shape.' }
    Assert-GpInputAction $after['input'] 'InputEventKey' 'physical_keycode' 4194332 $true
    $clicks = @(Find-GpInput $after['input'] 'InputEventMouseButton' 'button_index' 1)
    if ($clicks.Count -lt 2 -or -not $clicks[0]['pressed'] -or $clicks[1]['pressed']) {
        throw 'Exercise was not explicitly applied through native production GUI input.'
    }
    Assert-GpEqual $clicks[0]['position'] $clicks[1]['position'] 'Apply press/release position'
    $events = @(Get-GpSessionEvents $end)
    if ($Policy.kind -ne 0) {
        $placement = @($events | Where-Object { $_['kind'] -eq 10 -and $_['reason'] -ceq 'placement' })
        $ready = @($events | Where-Object { $_['kind'] -eq 10 -and $_['reason'] -ceq 'ready' })
        if ($placement.Count -ne 1 -or $ready.Count -ne 1 -or $ready[0]['tick'] - $placement[0]['tick'] -lt 60 -or
            $ready[0]['restart']['ready_tick'] -ne $ready[0]['tick'] -or
            $ready[0]['restart']['placement_end_tick'] -ne $placement[0]['tick'] + 60 -or
            $ready[0]['restart']['id'] -ne $Case['before']['restart']['id']) {
            throw 'Case lacks actual localized placement and authoritative READY timing.'
        }
    }
    $index = $Policy.index
    if ($index -lt 4) {
        if ($after['phase'] -cne 'RESTART_PAUSE' -or $after['restart']['kind'] -ne 2 -or $after['restart']['stage'] -ne 3 -or
            -not $after['guide']['visible'] -or -not $after['guide']['executable']) { throw 'Corner image is not an actually prepared own restart.' }
        $sx = if ($index -lt 2) { 1 } else { -1 }; $sz = if ($index % 2 -eq 0) { -1 } else { 1 }
        if ($after['restart']['spot'][0] * $sx -lt 19 -or $after['restart']['spot'][2] * $sz -lt 9) {
            throw 'Corner identity uses the wrong physical orientation.'
        }
        if ($index -eq 0) {
            Assert-GpInputAction @(Get-GpAppliedInputs $end) 'InputEventKey' 'physical_keycode' 74 $true
            $launch = Get-GpLaunch $end $after['state'] 1 0
            if ($end['camera']['mode'] -cne 'broadcast' -or
                $end['camera']['accepted_return_event_id'] -ne $launch['id'] -or
                $end['camera']['transition_started_tick'] -ne $launch['tick'] -or
                $end['tick'] - $launch['tick'] -lt 45) { throw 'Corner camera returned without the actual accepted kick or before transition completion.' }
        }
        else {
            if ($end['phase'] -cne 'RESTART_PAUSE' -or $end['restart']['deadline_tick'] -ne $after['restart']['deadline_tick'] -or
                @($events | Where-Object { $_['kind'] -in @(1, 2) }).Count -ne 0) { throw 'Prepared corner replayed a launch or renewed its clock.' }
            if ($index -eq 1) {
                Assert-GpInputAction $end['input'] 'InputEventJoypadButton' 'button_index' 1 $true
                Assert-GpInputAction $end['input'] 'InputEventJoypadButton' 'button_index' 1 $false
                Assert-GpInputAction $end['input'] 'InputEventKey' 'physical_keycode' 4194305 $true
                if (@(Find-GpInput $end['input'] 'InputEventMouseButton' 'button_index' 1 $true).Count -lt 3) {
                    throw 'F1 guide toggle did not traverse the actual GUI controls.'
                }
            }
            if ($index -eq 2) {
                # Bare -0.8 in PowerShell argument mode is a string, bypassing the existing float tolerance.
                Assert-GpInputAction $after['input'] 'InputEventJoypadMotion' 'axis_value' (-0.8)
                Assert-GpInputAction $after['input'] 'InputEventJoypadMotion' 'axis_value' 0.0
            }
        }
    }
    elseif ($index -eq 4) {
        if ($after['phase'] -cne 'PLAYING' -or $after['selected_actor_id'] -ne 0 -or
            -not $after['guide']['visible'] -or $after['guide']['power'] -le 0.1 -or $after['guide']['effective_target_actor_id'] -ne -1) {
            throw 'Live-shot moment contains no actual own charged guide.'
        }
        Assert-GpInputAction @(Get-GpAppliedInputs $after) 'InputEventKey' 'physical_keycode' 75 $true
        Assert-GpInputAction @(Get-GpAppliedInputs $end) 'InputEventKey' 'physical_keycode' 75 $false
        $launch = Get-GpLaunch $end $after['state'] 2 1
        $horizontal = @($launch['velocity'][0], 0.0, $launch['velocity'][2])
        if ((Get-GpDot $after['guide']['direction'] $horizontal) / (Get-GpLength $horizontal) -lt 0.999 -or
            $launch['shot_charge'] + 0.0001 -lt $after['guide']['power'] -or
            $launch['shot_charge'] - $after['guide']['power'] -gt ($launch['tick'] - $after['tick']) / 48.0 + 0.0001 -or
            $end['guide']['visible']) { throw 'Live release changed aim/charge impossibly or retained a stale guide.' }
    }
    elseif ($index -in @(5, 6)) {
        if ($index -eq 5) {
            if ($after['phase'] -cne 'RESTART_PAUSE' -or $after['selected_actor_id'] -ne 2 -or
                $after['state']['ball_owner_id'] -ne 2 -or -not $after['state']['actors'][2]['ball_in_hands'] -or
                $after['state']['ball_position'][1] -le 0.5 -or -not $after['guide']['visible']) {
                throw 'Prepared clearance is not a real ball in the selected goalkeeper hands.'
            }
            $pose = $after['athlete_presentations'][2]
            Assert-GpInputAction @(Get-GpAppliedInputs $after) 'InputEventKey' 'physical_keycode' 75 $true
            Assert-GpInputAction @(Get-GpAppliedInputs $after) 'InputEventKey' 'physical_keycode' 75 $false
            if (@($events | Where-Object { $_['kind'] -eq 2 }).Count -ne 0) { throw 'Keeper wrong-K input became a foot shot.' }
            foreach ($hand in $pose['hands']) {
                $distance = [Math]::Sqrt((Get-GodotVectorDistanceSquared $hand['origin'] $after['render_ball_position']))
                if ($distance -lt 0.063 -or $distance -gt 0.165) { throw 'Keeper hands do not surround the actual rendered ball.' }
            }
        }
        else {
            $launch = Get-GpLaunch $after $Case['before'] 1 2
            Assert-GpEqual $after['accepted_event'] $launch 'keeper release/accepted event'
            if ($after['phase'] -cne 'PLAYING' -or $after['state']['actors'][2]['ball_in_hands']) {
                throw 'Keeper release did not actually free the physical ball.'
            }
            Assert-GpInputAction $after['input'] 'InputEventJoypadButton' 'button_index' 0 $true
            Assert-GpContactPose $after['athlete_presentations'][2] $launch $HostPath
        }
    }
    elseif ($index -in @(7, 8, 9)) {
        $dribbles = @($events | Where-Object { $_['kind'] -eq 11 })
        $gesture = if ($index -eq 9) { 2 } else { 1 }
        if ($dribbles.Count -ne 1 -or $dribbles[0]['actor'] -ne 0 -or $dribbles[0]['gesture_kind'] -ne $gesture -or
            $dribbles[0]['contact_id'] -lt 0 -or $dribbles[0]['selected_actor_id'] -ne 0 -or
            $after['selected_actor_id'] -ne 0 -or $end['selected_actor_id'] -ne 0 -or
            $dribbles[0]['reason'] -cne $(if ($index -eq 9) { 'pace_change' } else { 'cut' }) -or
            $dribbles[0]['target'] -ne -1 -or $dribbles[0]['ball_owner_id'] -ne -1 -or
            @($events | Where-Object { $_['kind'] -in @(1, 2, 9) }).Count -ne 0) { throw 'Dribble contact was forged, replayed or changed focus.' }
        $event = $dribbles[0]; $actor = $after['state']['actors'][0]
        if ($actor['gesture_kind'] -ne $gesture -or $actor['gesture_started_tick'] -ne $event['tick'] -or
            $actor['gesture_duration_ticks'] -le 0 -or $after['tick'] -ge $event['tick'] + $actor['gesture_duration_ticks'] -or
            (Get-GodotVectorDistanceSquared $Case['before']['ball_position'] $after['state']['ball_position']) -le 0.0001 -or
            (Get-GpLength $after['state']['ball_velocity']) -le 0.5 -or $end['tick'] - $after['tick'] -lt 16) {
            throw 'Dribble lacks physical ball motion, finite gesture recovery or retained-button observation.'
        }
        Assert-GpEqual $after['accepted_event'] $event 'dribble captured/accepted event'
        Assert-GpNear $actor['gesture_contact_position'] $event['contact_point'] 0.0001 'dribble authoritative contact'
        Assert-GpNear $event['position'] $event['contact_point'] 0.04 'dribble physical origin'
        Assert-GpContactPose $after['athlete_presentations'][0] $event $HostPath
        $sign = if ($index -eq 7) { -1 } else { 1 }
        $axis = if ($index -eq 9) { 0 } else { 2 }
        if ($actor['gesture_direction'][$axis] * $sign -lt 0.5 -or $event['velocity'][$axis] * $sign -le 0) {
            throw 'Dribble uses the wrong physical cut side or pace direction.'
        }
        $controller = ($Policy.mode + $index - 7) % 2 -eq 1
        if ($controller) {
            Assert-GpInputAction $after['input'] 'InputEventJoypadButton' 'button_index' 2 $true
            Assert-GpInputAction $end['input'] 'InputEventJoypadButton' 'button_index' 2 $false
            $motion = @(Find-GpInput $after['input'] 'InputEventJoypadMotion' 'axis' $(if ($index -eq 9) { 0 } else { 1 }))
            if (@($motion | Where-Object { $_['axis_value'] -eq $sign }).Count -eq 0) { throw 'Missing actual directional dribble stick input.' }
        }
        else {
            Assert-GpInputAction $after['input'] 'InputEventKey' 'physical_keycode' 76 $true
            Assert-GpInputAction $end['input'] 'InputEventKey' 'physical_keycode' 76 $false
            $key = if ($index -eq 9) { 4194321 } elseif ($index -eq 7) { 4194320 } else { 4194322 }
            Assert-GpInputAction $after['input'] 'InputEventKey' 'physical_keycode' $key $true
        }
    }
    elseif ($index -in @(10, 11, 12)) {
        $kind = if ($index -eq 10) { 1 } else { 2 }
        $launchKind = if ($index -eq 10) { 0 } else { 1 }
        $launch = Get-GpLaunch $after $Case['before'] $kind $launchKind
        if ($index -eq 10) {
            if ([Math]::Abs($Case['before']['restart']['spot'][2]) -le 9.5) { throw 'Kick-in used the former centre reset.' }
            Assert-GpInputAction $after['input'] 'InputEventKey' 'physical_keycode' 74 $true
        }
        else {
            Assert-GpInputAction $after['input'] 'InputEventJoypadButton' 'button_index' 1 $true
            Assert-GpInputAction $after['input'] 'InputEventJoypadButton' 'button_index' 1 $false
            if ($index -eq 12) {
                if ($launch['restart']['deadline_tick'] -ne -1 -or $launch['velocity'][0] -le 0 -or
                    $launch['velocity'][2] -le 0 -or [Math]::Atan2($launch['velocity'][2], $launch['velocity'][0]) -gt 0.2) {
                    throw 'Penalty fine aim has the wrong direction/rate or invents a four-second deadline.'
                }
                $applied = @(Get-GpAppliedInputs $after)
                $trigger = @(Find-GpInput $applied 'InputEventJoypadMotion' 'axis' 4)
                $held = @($trigger | Where-Object { $_['axis_value'] -eq 1.0 })
                $released = @($trigger | Where-Object { $_['axis_value'] -eq 0.0 })
                $horizontal = @(Find-GpInput $applied 'InputEventJoypadMotion' 'axis' 0)
                if ($held.Count -ne 1 -or $released.Count -ne 1 -or $released[0]['tick'] - $held[0]['tick'] -lt 9 -or
                    @($horizontal | Where-Object { [Math]::Abs($_['axis_value'] - 0.8) -lt 0.00001 -and
                        $_['tick'] -eq $held[0]['tick'] }).Count -ne 1) {
                    throw 'Penalty lacks the actual held/released LT and simultaneous fine horizontal input.'
                }
                $angle = [Math]::Atan2($launch['velocity'][2], $launch['velocity'][0])
                if ($angle -le 0.02 -or $angle -gt ($released[0]['tick'] - $held[0]['tick']) * [Math]::PI / 360.0 + 0.001) {
                    throw 'Penalty aim exceeds the real 30-degree-per-second input window.'
                }
                Assert-GpNear $Case['before']['actors'][$Case['before']['selected_actor_id']]['position'] `
                    $after['state']['actors'][$Case['before']['selected_actor_id']]['position'] 0.001 'stationary penalty fine aim'
            }
        }
    }
    else {
        $choices = @($events | Where-Object { $_['kind'] -eq 10 -and $_['reason'] -ceq 'spot_changed' })
        if ($after['phase'] -cne 'RESTART_PAUSE' -or $after['restart']['kind'] -ne 7 -or
            -not $after['restart']['has_spot_choice'] -or $after['restart']['spot_choice'] -ne 1 -or
            $choices.Count -ne 2 -or $choices[0]['restart']['spot_choice'] -ne 2 -or
            $choices[1]['restart']['spot_choice'] -ne 1 -or
            $choices[0]['restart']['deadline_tick'] -ne $choices[1]['restart']['deadline_tick'] -or
            @($events | Where-Object { $_['kind'] -in @(1, 2, 11) }).Count -ne 0 -or
            $after['selected_actor_id'] -ne $Case['before']['selected_actor_id'] -or
            -not $after['hud_fouls'].Contains('predefinido')) {
            throw 'Sixth-foul choice replayed, renewed its clock, fabricated a pass/shot or lost the seeded-counter HUD.'
        }
        Assert-GpNear $choices[0]['restart']['spot'] $choices[0]['restart']['offence_spot'] 0.001 'offence spot choice'
        Assert-GpInputAction $after['input'] 'InputEventKey' 'physical_keycode' 76 $true
        Assert-GpInputAction $after['input'] 'InputEventJoypadButton' 'button_index' 2 $true
        Assert-GpInputAction $after['input'] 'InputEventKey' 'physical_keycode' 74 $true
    }
    if ($index -in @(0, 4, 5, 6, 10, 11, 12)) {
        $launches = @($events | Where-Object { $_['kind'] -in @(1, 2) })
        if ($launches.Count -ne 1) { throw 'Input evidence needs exactly one physical launch.' }
        $class = if ($index -in @(0, 4, 10)) { 'InputEventKey' } else { 'InputEventJoypadButton' }
        $code = if ($index -in @(0, 10)) { 74 } elseif ($index -eq 4) { 75 } elseif ($index -in @(5, 6)) { 0 } else { 1 }
        Assert-GpLaunchInput $end $launches[0] $class $code
    }
}
