#Requires -Version 7.2
Set-StrictMode -Version Latest

function Get-MatchHudExpectedErrors {
    return [ordered]@{
        'ERROR: MatchHUD.update_score: los marcadores deben estar entre 0 y 999.' = 2
        'ERROR: MatchHUD.update_clock: los segundos deben ser finitos.' = 3
        'ERROR: MatchHUD.set_shot_charge: la carga debe ser finita.' = 3
        'ERROR: MatchHUD.home_color: se requiere un color RGB finito, normalizado y opaco.' = 1
        'ERROR: MatchHUD.away_dorsal: el dorsal debe estar entre 0 y 99.' = 1
        'ERROR: MatchHUD.show_event: la duración debe ser positiva y finita.' = 4
        'ERROR: MatchHUD.show_result: se requieren marcadores válidos y un mensaje no vacío.' = 2
        'ERROR: MatchHUD.set_selected_actor: se requiere identidad válida y control humano de un actor local.' = 6
        'ERROR: MatchHUD.present_restart: estado de reanudación incoherente o no válido.' = (Get-MatchHudRestartNegativeCases).Count
    }
}

function Get-MatchHudRestartNegativeCases {
    return @('null', 'null_restart', 'bad_kind', 'bad_stage', 'nan_spot', 'negative_fouls', 'wrong_taker_team',
        'field_goal_clearance', 'penalty_deadline', 'illegal_penalty_pass', 'renewed_deadline',
        'own_taker_can_move', 'live_context_during_ready', 'unknown_exercise', 'wrong_extension_id')
}

function Get-MatchHudNewExpectedErrors {
    return [ordered]@{
        'MatchHUD.set_selected_actor: se requiere identidad válida y control humano de un actor local.' = 6
        'MatchHUD.present_restart: estado de reanudación incoherente o no válido.' = (Get-MatchHudRestartNegativeCases).Count
    }
}

function Get-MatchHudRequiredCheckNames {
    foreach ($context in @('null actor', 'id=1 team=1 role=0 human=true', 'id=4 team=0 role=0 human=false',
            'id=-1 team=0 role=0 human=true', 'id=10 team=0 role=0 human=true', 'id=0 team=0 role=99 human=true')) {
        foreach ($label in @('invalid selection returns ERR_INVALID_PARAMETER', 'invalid selection leaves the entire presentation unchanged')) {
            "$label [case: selected_actor; $context]"
        }
    }
    foreach ($case in Get-MatchHudRestartNegativeCases) {
        foreach ($label in @('returns explicit invalid-parameter error', 'rejection leaves every visible restart field intact')) {
            "$label [case: restart_presentation; invalid restart $case]"
        }
    }
    foreach ($label in @('HUD suite reached completion', 'selected actor scenarios reached completion',
            'restart presentation scenarios reached completion', 'restart feedback surface scenarios reached completion')) {
        "$label [case: completion]"
    }
}

function Assert-GodotHudReport([System.Collections.IDictionary]$Report) {
    $count = ((Get-MatchHudExpectedErrors).Values | Measure-Object -Sum).Sum
    if (($Report['expected_validation_errors'] -isnot [int] -and $Report['expected_validation_errors'] -isnot [long]) -or
        $Report['expected_validation_errors'] -ne $count) {
        throw 'HUD report requires the exact integer count of source-defined expected validation diagnostics.'
    }
    if ($Report['failures'] -isnot [System.Collections.IList] -or $Report['failures'].Count -ne 0) {
        throw 'HUD report requires an empty typed failure array.'
    }
    $expected = Get-MatchHudNewExpectedErrors
    $counts = $Report['new_expected_error_counts']
    if ($counts -isnot [Collections.IDictionary] -or $counts.Count -ne $expected.Count) {
        throw 'HUD must separately account for its selected-actor and restart diagnostics.'
    }
    foreach ($message in $expected.Keys) {
        if ($message -cnotin $counts.Keys -or ($counts[$message] -isnot [int] -and $counts[$message] -isnot [long]) -or
            $counts[$message] -ne $expected[$message]) { throw "Incorrect HUD diagnostic accounting: $message" }
    }
    if ($Report['checks'] -isnot [Collections.IList]) { throw 'Current HUD diagnostics require their actual typed negative assertions.' }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($check in $Report['checks']) {
        if ($check -isnot [Collections.IDictionary] -or $check['name'] -isnot [string] -or
            [string]::IsNullOrWhiteSpace($check['name']) -or -not $names.Add($check['name']) -or
            $check['passed'] -isnot [bool] -or -not $check['passed']) { throw 'Invalid or repeated HUD assertion.' }
    }
    foreach ($name in Get-MatchHudRequiredCheckNames) {
        if (-not $names.Contains($name)) { throw "HUD omitted its actual negative/completion assertion: $name" }
    }
}

function Get-DevelopmentIntegrationNegativeCases {
    $invalidIntent = 'AI intent IDs must be unique active actors'
    $invalidSetup = 'A training setup must describe exactly the actors of its explicit mode'
    $busyAi = 'Defer AI changes until after the simulation tick/event delivery'
    $busySetup = 'Defer reset/start/pause until after simulation event delivery'
    return @(
        @{case = 'modo inválido de UI'; code = 31; warning = 'WARNING: Modo de desarrollo no válido'; refusal = $null}
        @{case = 'ID negativo en IA desde UI'; code = 31; warning = "WARNING: No se pudo cambiar la IA: $invalidIntent"; refusal = $invalidIntent}
        @{case = 'IDs inválidos [2, 2]'; code = 31; warning = "WARNING: No se pudo cambiar la IA: $invalidIntent"; refusal = $invalidIntent}
        @{case = 'IDs inválidos [20]'; code = 31; warning = "WARNING: No se pudo cambiar la IA: $invalidIntent"; refusal = $invalidIntent}
        @{case = 'setup incompleto'; code = 31; warning = "WARNING: No se pudo aplicar el entrenamiento: $invalidSetup"; refusal = $invalidSetup}
        @{case = 'reanudar con desarrollo abierto'; code = 44; warning = 'WARNING: Cierra Desarrollo antes de continuar'; refusal = $null}
        @{case = 'reentrada IA durante pase'; code = 44; warning = "WARNING: No se pudo cambiar la IA: $busyAi"; refusal = $busyAi}
        @{case = 'reentrada de modo durante pase'; code = 44; warning = "WARNING: No se pudo aplicar el entrenamiento: $busySetup"; refusal = $busySetup}
    )
}

function Get-DevelopmentIntegrationExpectedWarnings {
    $warnings = [ordered]@{}
    foreach ($case in Get-DevelopmentIntegrationNegativeCases) {
        if (-not $warnings.Contains($case.warning)) { $warnings[$case.warning] = 0 }
        $warnings[$case.warning] += 1
    }
    return $warnings
}

function Get-GodotDevelopmentNegativeDependency([string]$Source) {
    if ($Source.Contains('_begin_negative("humano en IA desde UI"') -or
        $Source -match 'var\s+invalid_ids\s*:\s*Array\[int\]\s*=\s*\[\s*0\s*\]') {
        return 'Preview development negative still treats intent [0] as invalid; its producer must use an inactive/unknown actor ID.'
    }
    return ''
}

function Assert-PreviewIntegrationReport([System.Collections.IDictionary]$Report) {
    $policy = @(Get-DevelopmentIntegrationNegativeCases)
    foreach ($field in @('unexpected_integration_errors', 'unexpected_command_refusals')) {
        if (-not $Report.Contains($field) -or $Report[$field] -isnot [System.Collections.IList] -or
            @($Report[$field]).Count -ne 0) {
            throw "Preview integration requires empty $field."
        }
    }
    if (($Report['expected_development_errors'] -isnot [int] -and
            $Report['expected_development_errors'] -isnot [long]) -or
        $Report['expected_development_errors'] -ne $policy.Count) {
        throw 'Preview integration must account for exactly the documented negative cases.'
    }
    Assert-GodotIntegerList $Report['error_codes'] @($policy | ForEach-Object { $_.code }) 'Development error codes'
    $actual = @($Report['command_refusals'])
    $expected = @($Report['expected_command_refusals'])
    $refusals = @($policy | Where-Object { $null -ne $_.refusal })
    if ($actual.Count -ne $refusals.Count -or $expected.Count -ne $refusals.Count) {
        throw 'Preview integration must label exactly its documented authority refusals.'
    }
    $cases = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($index = 0; $index -lt $refusals.Count; $index++) {
        $item = $actual[$index]
        $label = $expected[$index]
        if ($item -isnot [System.Collections.IDictionary] -or $label -isnot [System.Collections.IDictionary] -or
            $label['case'] -isnot [string] -or [string]::IsNullOrWhiteSpace($label['case']) -or
            -not $cases.Add($label['case']) -or $item['message'] -isnot [string] -or
            [string]::IsNullOrWhiteSpace($item['message']) -or $item['message'] -cne $label['message'] -or
            $item['message'] -cne $refusals[$index].refusal -or $label['case'] -cne $refusals[$index].case) {
            throw 'Preview integration contains an unlabelled or mismatched refusal.'
        }
        Assert-GodotIntegerList @($item['code'], $item['id']) @($refusals[$index].code, -1) 'Authority refusal'
        Assert-GodotIntegerList @($label['code'], $label['id']) @($refusals[$index].code, -1) 'Labelled authority refusal'
    }
}

function Assert-GodotSimulationRefusals($Result, [System.Collections.IDictionary]$Report) {
    $count = [regex]::Matches($Result.Stdout, '(?m)^PASS expected refusal: [^\r\n]+\r?$').Count
    if (($Report['expected_refusals'] -isnot [int] -and $Report['expected_refusals'] -isnot [long]) -or
        $count -lt 1 -or $Report['expected_refusals'] -ne $count) {
        throw 'Simulation refusal count must match its actual successful native negative assertions, not a historical total.'
    }
}

function Get-GodotPlayerControlNegativeCases {
    param([ValidateSet('0.3.0-preview', '0.4.0-preview', '0.5.0-preview')][string]$ProjectVersion = '0.5.0-preview')
    $contact = if ($ProjectVersion -ceq '0.3.0-preview') {
        'A kick requires possession and reachable ball contact'
    } else { 'Launch refused: unreachable_ball' }
    $phase = if ($ProjectVersion -ceq '0.3.0-preview') {
        'Commands require PLAYING phase'
    } else { 'Commands require live play or a ready restart' }
    return [ordered]@{
        'F03 switch sin candidato' = @{code = 2; ids = @(0); message = 'No teammate lies in the requested switch direction'}
        'F07 rechazo de cooldown' = @{code = 44; ids = @(0); message = 'Action is cooling down'}
        'F07 pase sin contacto' = @{code = 2; ids = @(0); message = $contact}
        'F07 receptor rival' = @{code = 31; ids = @(0); message = 'Pass target must be a different actor on the same team'}
        'F08 antiguo seleccionado no autorizado' = @{code = 4; ids = @(0); message = 'Human input controls only the currently selected actor'}
        'F08 comando dentro de evento' = @{code = 44; ids = @(8); message = 'Submit human commands between simulation ticks/events'}
        'F11 comando tras FINISHED' = @{code = 2; ids = @(8); message = $phase}
    }
}

function Assert-GodotPlayerControlReport([System.Collections.IDictionary]$Report,
    [string]$ProjectVersion = '0.5.0-preview', [int]$InputSchemaVersion = 3) {
    if ($Report['complete'] -isnot [bool] -or -not $Report['complete'] -or
        $Report['source_script'] -cne 'res://match/match.gd' -or $Report['main_scene'] -cne 'res://match/match.tscn' -or
        $Report['project_version'] -cne $ProjectVersion -or $Report['engine'] -cne '4.7.2-stable (official)' -or
        $Report['headless'] -isnot [bool] -or -not $Report['headless'] -or
        ($Report['input_schema_version'] -isnot [long] -and $Report['input_schema_version'] -isnot [int]) -or
        $Report['input_schema_version'] -ne $InputSchemaVersion) {
        throw 'Player-control integration must finish the exact version/schema main and its actual shutdown.'
    }
    foreach ($field in @('failures', 'integration_errors', 'unexpected_integration_errors', 'unexpected_command_refusals')) {
        if ($Report[$field] -isnot [System.Collections.IList] -or @($Report[$field]).Count -ne 0) {
            throw "Player-control integration must report empty $field."
        }
    }
    $cases = @($Report['cases_completed'])
    $required = @(1..12 | ForEach-Object { 'F{0:d2}' -f $_ })
    if ($Report['cases_completed'] -isnot [System.Collections.IList] -or ($cases -join ',') -cne ($required -join ',')) {
        throw 'All explicitly specified F01–F12 behavior cases must complete in order.'
    }
    foreach ($pair in @(@('key', 100), @('joy_button', 30), @('joy_motion', 30))) {
        $count = $Report['native_events'][$pair[0]]
        if (($count -isnot [long] -and $count -isnot [int]) -or $count -le $pair[1]) {
            throw "Missing actual player-control native input: $($pair[0])."
        }
    }
    if (($Report['mouse_events'] -isnot [long] -and $Report['mouse_events'] -isnot [int]) -or $Report['mouse_events'] -lt 2) {
        throw 'Player-control integration must exercise the actual UI mouse path.'
    }
    $policy = Get-GodotPlayerControlNegativeCases -ProjectVersion $ProjectVersion
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $actual = @($Report['command_refusals'])
    $labelled = @($Report['expected_command_refusals'])
    if ($Report['command_refusals'] -isnot [System.Collections.IList] -or
        $Report['expected_command_refusals'] -isnot [System.Collections.IList] -or $actual.Count -ne $labelled.Count -or
        $actual.Count -ne $policy.Count) {
        throw 'Player-control refusals require matching typed actual/labelled records.'
    }
    for ($index = 0; $index -lt $actual.Count; $index++) {
        $item = $actual[$index]
        $label = $labelled[$index]
        if ($item -isnot [System.Collections.IDictionary] -or $label -isnot [System.Collections.IDictionary] -or
            $label['case'] -isnot [string] -or -not $policy.Contains($label['case']) -or
            $label['case'] -cne @($policy.Keys)[$index]) {
            throw 'Unrecognized player-control refusal case.'
        }
        $expected = $policy[$label['case']]
        foreach ($row in @($item, $label)) {
            if (($row['code'] -isnot [long] -and $row['code'] -isnot [int]) -or $row['code'] -ne $expected.code -or
                ($row['id'] -isnot [long] -and $row['id'] -isnot [int]) -or $row['id'] -notin $expected.ids -or
                $row['message'] -isnot [string] -or $row['message'] -cne $expected.message) {
                throw 'Player-control refusal differs from its real source-defined code, actor or message.'
            }
        }
        if ($item['id'] -ne $label['id']) { throw 'Refusal label changes the actual rejected actor.' }
        [void]$seen.Add($label['case'])
    }
    if ($seen.Count -ne $policy.Count) { throw 'Player-control negative behavior coverage is incomplete.' }
    $focusReasons = @('pass', 'off_ball_switch')
    $requiredFocusCoverage = @('mode-0', 'mode-1', 'pass', 'off_ball_switch', 'pass-0-2', 'pass-2-0', 'all-off')
    if ($ProjectVersion -cin @('0.4.0-preview', '0.5.0-preview')) {
        # §4.3 adds native HOME-taker selection; F11 must actually exercise it.
        $focusReasons += 'restart_taker'
        $requiredFocusCoverage += 'restart_taker'
    }
    $coverage = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($Report['focus_changes'] -isnot [System.Collections.IList]) { throw 'Missing native focus event records.' }
    foreach ($event in $Report['focus_changes']) {
        if ($event -isnot [System.Collections.IDictionary]) { throw 'Malformed native focus event.' }
        foreach ($field in @('old_id', 'selected_actor_id', 'target_id', 'mode', 'tick', 'owner_id')) {
            if ($event[$field] -isnot [long] -and $event[$field] -isnot [int]) { throw "Focus event requires integer $field." }
        }
        $ids = if ($event['mode'] -eq 1) { @(0..9) } elseif ($event['mode'] -eq 0) { @(0..3) } else { @() }
        $selected = $event['selected_actor_id']
        if ($ids.Count -eq 0 -or $selected -notin $ids -or $selected % 2 -ne 0 -or $selected -ne $event['target_id'] -or
            $event['old_id'] -notin $ids -or $event['old_id'] % 2 -ne 0 -or $event['old_id'] -eq $selected -or
            $event['tick'] -lt 1 -or $event['owner_id'] -notin (@(-1) + $ids) -or
            $event['reason'] -isnot [string] -or $event['reason'] -cnotin $focusReasons -or
            ($event['reason'] -cin @('pass', 'restart_taker') -and $event['owner_id'] -ne -1)) {
            throw 'Focus must change HOME identity through switch, accepted pass or the versioned restart taker, without granting possession.'
        }
        if ($event['ai_intent_actor_ids'] -isnot [System.Collections.IList] -or
            $event['ai_actor_ids'] -isnot [System.Collections.IList]) { throw 'Focus event omitted configured/effective AI arrays.' }
        $previous = -1
        foreach ($id in $event['ai_intent_actor_ids']) {
            if (($id -isnot [long] -and $id -isnot [int]) -or $id -notin $ids -or $id -le $previous) {
                throw 'Focus event has malformed AI intent.'
            }
            $previous = $id
        }
        Assert-GodotIntegerList $event['ai_actor_ids'] @($event['ai_intent_actor_ids'] | Where-Object { $_ -ne $selected }) 'Focus effective AI'
        [void]$coverage.Add("mode-$($event['mode'])")
        [void]$coverage.Add([string]$event['reason'])
        [void]$coverage.Add("$($event['reason'])-$($event['old_id'])-$selected")
        if (@($event['ai_intent_actor_ids']).Count -eq 0) { [void]$coverage.Add('all-off') }
    }
    foreach ($item in $requiredFocusCoverage) {
        if (-not $coverage.Contains($item)) { throw "Missing actual player-control behavior evidence: $item." }
    }
    if ($ProjectVersion -cin @('0.4.0-preview', '0.5.0-preview')) {
        $motion = $Report['camera_handoff_motion']
        if ($motion -isnot [Collections.IDictionary]) {
            throw 'F12 requires the actual typed camera_handoff_motion observation.'
        }
        foreach ($field in @('start_tick', 'end_tick', 'sampled_frames')) {
            if (($motion[$field] -isnot [long] -and $motion[$field] -isnot [int]) -or $motion[$field] -lt 0) {
                throw "F12 camera motion requires nonnegative integer $field."
            }
        }
        # The authority window and process-frame sampling use different clocks.
        # Ordinary scheduling may produce more images than fixed-60 diagnostics.
        if ($motion['end_tick'] - $motion['start_tick'] -lt 50 -or
            $motion['sampled_frames'] -lt 1 -or $motion['sampled_frames'] -gt 6000 -or
            $motion['consecutive'] -isnot [bool] -or -not $motion['consecutive']) {
            throw 'F12 must observe consecutive process frames over the complete 50-tick authority window within its 6000-sample cap.'
        }
        $step = $motion['maximum_step']
        if (($step -isnot [int] -and $step -isnot [long] -and $step -isnot [double] -and $step -isnot [single]) -or
            -not [double]::IsFinite([double]$step) -or $step -lt 0 -or $step -ge 1.0) {
            throw 'F12 maximum camera translation per observed image must be finite and in [0, 1) metres.'
        }
        foreach ($field in @('minimum_right_dot', 'focus_progress_x')) {
            $value = $motion[$field]
            if (($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [single]) -or
                -not [double]::IsFinite([double]$value)) {
                throw "F12 requires the finite numeric $field observation."
            }
        }
        if ($motion['minimum_right_dot'] -le 0.999 -or $motion['minimum_right_dot'] -gt 1.000001 -or
            $motion['focus_progress_x'] -le 1.0) {
            throw 'F12 must preserve broadcast orientation and advance focus towards the selected keeper.'
        }
        foreach ($field in @('ball_visible', 'keeper_visible')) {
            if ($motion[$field] -isnot [bool] -or -not $motion[$field]) {
                throw "F12 requires the real visible $field observation."
            }
        }
        foreach ($pair in @(@('end_phase', 1), @('selected_actor_id', 2))) {
            $value = $motion[$pair[0]]
            if (($value -isnot [int] -and $value -isnot [long]) -or $value -ne $pair[1]) {
                throw "F12 requires the actual integer $($pair[0])=$($pair[1])."
            }
        }
        if ($motion['camera_mode'] -isnot [string] -or $motion['camera_mode'] -cne 'broadcast') {
            throw 'F12 must finish in actual broadcast mode.'
        }
    }
}

function ConvertFrom-GodotStructuredReport {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Prefix,
        [switch]$RequireChecks
    )
    $lines = @($Result.Stdout -split '\r?\n' | Where-Object { $_.StartsWith("$Prefix ") })
    if ($lines.Count -ne 1) { throw "Expected exactly one $Prefix report; observed $($lines.Count)." }
    $report = $lines[0].Substring($Prefix.Length + 1) | ConvertFrom-Json -AsHashtable -Depth 64
    if ($report -isnot [System.Collections.IDictionary] -or $report['ok'] -isnot [bool] -or -not $report['ok']) {
        throw "$Prefix did not report boolean ok=true."
    }
    foreach ($field in @('passed', 'total')) {
        if ($report[$field] -isnot [long] -and $report[$field] -isnot [int]) {
            throw "$Prefix requires an integer $field."
        }
    }
    if ($report['total'] -lt 1 -or $report['passed'] -ne $report['total']) {
        throw "$Prefix has empty or inconsistent assertion counts."
    }
    if ($report.Contains('failures') -and @($report['failures']).Count -ne 0) {
        throw "$Prefix includes failures despite ok=true."
    }
    if ($RequireChecks -or $report.Contains('checks')) {
        if ($report['checks'] -isnot [System.Collections.IList]) { throw "$Prefix requires a typed check array." }
        $checks = @($report['checks'])
        if ($checks.Count -ne $report['total']) { throw "$Prefix check array and total disagree." }
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($check in $checks) {
            if ($check -isnot [System.Collections.IDictionary] -or $check['name'] -isnot [string] -or
                [string]::IsNullOrWhiteSpace($check['name'])) { throw "$Prefix contains a malformed check identity." }
            if (-not $names.Add($check['name'])) { throw "$Prefix contains duplicate check identity '$($check['name'])'." }
            if ($check['passed'] -isnot [bool] -or -not $check['passed']) { throw "$Prefix contains a failed or malformed check '$($check['name'])'." }
        }
    }
    return $report
}

function Test-GodotPng {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -le 1024 -or [Convert]::ToHexString([byte[]]$bytes[0..7]) -ne '89504E470D0A1A0A' -or
        [Text.Encoding]::ASCII.GetString($bytes, 12, 4) -ne 'IHDR') { return $false }
    $width = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 16))
    $height = [Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($bytes, 20))
    return $width -eq 1920 -and $height -eq 1080
}

function Get-GodotNativeReportPrefix {
    param([Parameter(Mandatory)][string]$Source)
    $markers = @([regex]::Matches($Source, '\bprint\(\s*"(FUTSAL_[A-Z0-9_]+_TESTS)\s+"') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $markers += @([regex]::Matches($Source,
        '(?m)^func _test_marker\(\) -> String:\r?\n[ \t]+return "(FUTSAL_[A-Z0-9_]+_TESTS)"\r?$') |
        ForEach-Object { $_.Groups[1].Value })
    $markers = @($markers | Sort-Object -Unique)
    if ($markers.Count -ne 1) {
        throw 'Native producer must declare one literal printed or _test_marker() report prefix; no guessed prefix is accepted.'
    }
    return $markers[0]
}

function Assert-GodotIntegerList($Actual, [int[]]$Expected, [string]$Context) {
    $values = @($Actual)
    if ($values.Count -ne $Expected.Count) { throw "$Context has an incorrect identity count." }
    for ($index = 0; $index -lt $values.Count; $index++) {
        if (($values[$index] -isnot [long] -and $values[$index] -isnot [int]) -or $values[$index] -ne $Expected[$index]) {
            throw "$Context must contain the exact sorted integer identities."
        }
    }
}

function Assert-GodotFiniteVector($Vector, [string]$Context) {
    if (@($Vector).Count -ne 3) { throw "$Context requires a three-component vector." }
    foreach ($value in $Vector) {
        if (($value -isnot [double] -and $value -isnot [long] -and $value -isnot [int]) -or
            -not [double]::IsFinite([double]$value)) { throw "$Context contains a nonfinite/nonnumeric component." }
    }
}

function Assert-GodotModeState {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$State,
        [ValidateSet(0, 1)][int]$Mode,
        [AllowEmptyCollection()][int[]]$AiIntentIds,
        [ValidateSet('PLAYING', 'PAUSED', 'RESTART_PAUSE')][string]$Phase,
        [int]$SelectedActorId = 0
    )
    $ids = if ($Mode -eq 1) { @(0..9) } else { @(0..3) }
    if (($State['mode'] -isnot [long] -and $State['mode'] -isnot [int]) -or $State['mode'] -ne $Mode -or
        ($State['actor_count'] -isnot [long] -and $State['actor_count'] -isnot [int]) -or
        $State['actor_count'] -ne $ids.Count -or $State['phase'] -ne $Phase) {
        throw "Expected exact mode $Mode, $($ids.Count) actors and phase $Phase; another composition is not interchangeable."
    }
    Assert-GodotIntegerList $State['physical_actor_ids'] $ids 'Native physical bodies'
    if (($State['selected_actor_id'] -isnot [long] -and $State['selected_actor_id'] -isnot [int]) -or
        $State['selected_actor_id'] -ne $SelectedActorId -or $SelectedActorId -notin $ids -or $SelectedActorId % 2 -ne 0) {
        throw 'The selected actor must be the expected active HOME identity, including its keeper.'
    }
    $previous = -1
    foreach ($id in $AiIntentIds) {
        if ($id -notin $ids -or $id -le $previous) { throw 'Expected AI intent must be sorted, unique active IDs.' }
        $previous = $id
    }
    Assert-GodotIntegerList $State['ai_intent_actor_ids'] $AiIntentIds 'Configured AI intent'
    $effectiveAi = @($AiIntentIds | Where-Object { $_ -ne $SelectedActorId })
    Assert-GodotIntegerList $State['ai_actor_ids'] $effectiveAi 'Effective AI excludes exactly the selected actor'
    $actors = @($State['actors'])
    Assert-GodotIntegerList @($actors | ForEach-Object { $_['id'] }) $ids 'Snapshot actors'
    foreach ($actor in $actors) {
        $id = $actor['id']
        $role = if ($id -in @(2, 3)) { 1 } else { 0 }
        if ($actor['team'] -ne ($id % 2) -or $actor['role'] -ne $role -or
            $actor['human'] -isnot [bool] -or $actor['human'] -ne ($id -eq $SelectedActorId) -or
            ($actor['sequence'] -isnot [long] -and $actor['sequence'] -isnot [int])) {
            throw "Incorrect native actor team/role/control/sequence: $id."
        }
        Assert-GodotFiniteVector $actor['position'] "Actor $id position"
        Assert-GodotFiniteVector $actor['velocity'] "Actor $id velocity"
    }
    if (($State['tick'] -isnot [long] -and $State['tick'] -isnot [int]) -or $State['tick'] -lt 0 -or
        ($State['seconds_remaining'] -isnot [double] -and $State['seconds_remaining'] -isnot [long] -and
            $State['seconds_remaining'] -isnot [int]) -or
        -not [double]::IsFinite([double]$State['seconds_remaining']) -or $State['seconds_remaining'] -le 0) {
        throw 'Mode evidence requires an actual finite running clock and integer tick.'
    }
    Assert-GodotFiniteVector $State['ball_position'] 'Native ball position'
    Assert-GodotFiniteVector $State['ball_velocity'] 'Native ball velocity'
    if (@($State['score']).Count -ne 2) { throw 'Mode evidence requires both scores.' }
}

function Assert-GodotUnchangedState($Before, $After) {
    foreach ($field in @('mode', 'phase', 'tick', 'seconds_remaining', 'selected_actor_id', 'actors', 'physical_actor_ids',
            'score', 'ball_position', 'ball_velocity')) {
        if (($Before[$field] | ConvertTo-Json -Depth 16 -Compress) -cne
            ($After[$field] | ConvertTo-Json -Depth 16 -Compress)) {
            throw "Live AI change reset or mutated frozen state: $field."
        }
    }
}

function Assert-GodotPreviewTransitions([System.Collections.IDictionary]$Report, [switch]$Gameplay) {
    $changes = @($Report['mode_changes'])
    $transitions = @(
        @{before = 1; target = 0; intent = @(0..9)}
        @{before = 0; target = 1; intent = @()}
        @{before = 0; target = 1; intent = @(2)}
    )
    if ($Gameplay) {
        $transitions[2] = @{before = 0; target = 0; intent = @(2)}
        $transitions += @(
            @{before = 0; target = 1; intent = @()}
            @{before = 1; target = 1; intent = @()}
        )
    }
    if ($Report['mode_changes'] -isnot [System.Collections.IList] -or $changes.Count -ne $transitions.Count) {
        throw 'Require preview -> micro -> preview and the final preview restoration after keeper-control drills.'
    }
    for ($index = 0; $index -lt $transitions.Count; $index++) {
        $target = $transitions[$index].target
        $previous = $transitions[$index].before
        $beforeAi = $transitions[$index].intent
        $afterAi = if ($target -eq 1) { @(0..9) } else { @(0..3) }
        $change = $changes[$index]
        if ($change['route'] -ne 'production-dev-menu-signal' -or $change['requested_mode'] -ne $target) {
            throw 'Mode transitions must traverse the real development-panel connections in the requested order.'
        }
        $selectedBefore = if ($Gameplay -and $index -ge 3) { $change['before']['selected_actor_id'] } else { 0 }
        Assert-GodotModeState $change['before'] $previous $beforeAi 'PAUSED' $selectedBefore
        Assert-GodotModeState $change['after'] $target $afterAi 'PLAYING'
        if ($change['after']['seconds_remaining'] -le 119 -or
            ($change['after']['score'] -join ',') -ne '0,0') { throw 'Changing modes must begin a new default match.' }
    }
    $aiChanges = @($Report['ai_changes'])
    if ($aiChanges.Count -ne 2) { throw 'Live AI off/on and restart evidence is required independently for both modes.' }
    for ($index = 0; $index -lt 2; $index++) {
        $mode = 1 - $index
        $change = $aiChanges[$index]
        $allAi = if ($mode -eq 1) { @(1..9) } else { @(1..3) }
        $allIntent = if ($mode -eq 1) { @(0..9) } else { @(0..3) }
        if ($change['mode'] -ne $mode -or $change['route'] -ne 'production-dev-menu-signal') {
            throw 'AI evidence must exercise the real preview and micro development connections, not generic four-or-ten fixtures.'
        }
        foreach ($stage in @('before', 'on')) { Assert-GodotModeState $change[$stage] $mode $allIntent 'PAUSED' }
        foreach ($stage in @('off', 'on_before')) { Assert-GodotModeState $change[$stage] $mode @() 'PAUSED' }
        foreach ($stage in @('off_later', 'restarted_off')) { Assert-GodotModeState $change[$stage] $mode @() 'PLAYING' }
        Assert-GodotModeState $change['on_later'] $mode $allIntent 'PLAYING'
        Assert-GodotUnchangedState $change['before'] $change['off']
        Assert-GodotUnchangedState $change['on_before'] $change['on']
        foreach ($pair in @(@('off', 'off_later'), @('on', 'on_later'))) {
            if ($change[$pair[1]]['tick'] -le $change[$pair[0]]['tick'] -or
                $change[$pair[1]]['seconds_remaining'] -ge $change[$pair[0]]['seconds_remaining']) {
                throw 'The normal clock must advance after closing the development panel.'
            }
        }
        foreach ($id in $allAi) {
            $off = $change['off']['actors'][$id]
            $offLater = $change['off_later']['actors'][$id]
            $on = $change['on']['actors'][$id]
            $onLater = $change['on_later']['actors'][$id]
            $speedSquared = ($offLater['velocity'] | ForEach-Object { [Math]::Pow($_, 2) } | Measure-Object -Sum).Sum
            if ($offLater['sequence'] -ne $off['sequence'] -or $speedSquared -ge 0.0064 -or
                $onLater['sequence'] -le $on['sequence']) {
                throw "Actor $id did not stop/resume real AI commands in mode $mode."
            }
        }
        if ($change['restarted_off']['seconds_remaining'] -le 119 -or
            ($change['restarted_off']['score'] -join ',') -ne '0,0') {
            throw 'Real HUD restart did not preserve the selected mode/AI in a fresh match.'
        }
    }
    Assert-GodotModeState $Report['final_state'] 1 @(0..9) 'PLAYING'
    if ($Report['final_hud_mode'] -isnot [string] -or $Report['final_hud_mode'] -notmatch '(?i)5v5' -or
        $Report['final_hud_mode'] -notmatch '(?i)experimental') {
        throw 'The published PLAYING HUD must visibly identify the experimental 5v5 mode.'
    }
}

function Assert-GodotDefaultEntrypoint {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Report)
    $proof = $Report['default_entrypoint']
    if ($proof -isnot [System.Collections.IDictionary] -or $proof['verified'] -isnot [bool] -or -not $proof['verified']) {
        throw 'The untouched default entrypoint was not verified before driver setup.'
    }
    foreach ($name in @('before', 'after_wait', 'after_input')) {
        $state = $proof[$name]
        if ($state -isnot [System.Collections.IDictionary] -or $state['phase'] -ne 'PLAYING') {
            throw "Default entrypoint was not already PLAYING: $name."
        }
        Assert-GodotModeState $state 1 @(0..9) 'PLAYING'
        foreach ($field in @('tick', 'human_sequence', 'driver_start_calls')) {
            if ($state[$field] -isnot [long] -and $state[$field] -isnot [int]) {
                throw "Default entrypoint requires integer $field at $name."
            }
        }
        $seconds = $state['seconds_remaining']
        if (($seconds -isnot [double] -and $seconds -isnot [long] -and $seconds -isnot [int]) -or
            -not [double]::IsFinite([double]$seconds) -or $seconds -le 0 -or
            $state['tick'] -lt 0 -or $state['driver_start_calls'] -ne 0) {
            throw "Default entrypoint was reset/started by the driver or has invalid time: $name."
        }
    }
    foreach ($pair in @(@('before', 'after_wait'), @('after_wait', 'after_input'))) {
        $before = $proof[$pair[0]]
        $after = $proof[$pair[1]]
        if ($after['tick'] -le $before['tick'] -or $after['seconds_remaining'] -ge $before['seconds_remaining'] -or
            $after['human_sequence'] -le $before['human_sequence']) {
            throw 'Default ticks, clock and human command sequence did not advance without a driver start.'
        }
    }
    $inputs = @($Report['inputs'] | Where-Object { $_['control'] -eq 'default keyboard D' })
    if ($inputs.Count -ne 1 -or $inputs[0]['driver_start_calls'] -ne 0 -or
        $inputs[0]['device'] -ne 0 -or $inputs[0]['event_class'] -ne 'InputEventKey') {
        throw 'Missing physical device-0 input evidence before all driver setups.'
    }
    $inputProof = $inputs[0]
    foreach ($name in @('before', 'pressed', 'settled', 'released')) {
        $actor = $inputProof[$name]
        if ($actor -isnot [System.Collections.IDictionary] -or
            ($actor['sequence'] -isnot [long] -and $actor['sequence'] -isnot [int])) {
            throw "Missing default authoritative actor evidence: $name."
        }
        foreach ($field in @('position', 'velocity')) {
            $vector = @($actor[$field])
            if ($vector.Count -ne 3) { throw "Invalid default $name $field vector." }
            foreach ($value in $vector) {
                if (($value -isnot [double] -and $value -isnot [long] -and $value -isnot [int]) -or
                    -not [double]::IsFinite([double]$value)) { throw "Nonfinite default $name $field vector." }
            }
        }
    }
    $moved = 0.0
    $drift = 0.0
    $speed = 0.0
    for ($axis = 0; $axis -lt 3; $axis++) {
        $moved += [Math]::Pow($inputProof['pressed']['position'][$axis] - $inputProof['before']['position'][$axis], 2)
        $drift += [Math]::Pow($inputProof['released']['position'][$axis] - $inputProof['settled']['position'][$axis], 2)
        $speed += [Math]::Pow($inputProof['released']['velocity'][$axis], 2)
    }
    if (-not [double]::IsFinite($moved) -or $moved -le 0.09 -or $drift -ge 0.000625 -or $speed -ge 0.0064 -or
        $inputProof['pressed']['sequence'] -le $inputProof['before']['sequence'] -or
        $inputProof['released']['sequence'] -le $inputProof['pressed']['sequence']) {
        throw 'Default input did not move and stop the authoritative human while commands continued.'
    }
}

function Read-GodotBaseGameReport {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$ReportPath,
        [Parameter(Mandatory)][datetime]$StartedAt,
        [Parameter(Mandatory)][bool]$EditorBinary,
        [Parameter(Mandatory)][bool]$Headless,
        [Parameter(Mandatory)][string]$Executable,
        [string]$ProjectVersion = '0.5.0-preview',
        [int]$InputSchemaVersion = 3,
        [string]$CapturePath = '',
        [ValidateSet('Legacy', 'Gameplay')][string]$RuntimeProtocol = 'Legacy'
    )
    $gameplay = $RuntimeProtocol -ceq 'Gameplay'
    $prefix = if ($gameplay) { 'FUTSAL_GAMEPLAY_SMOKE' } else { 'FUTSAL_MATCH_SMOKE' }
    $scope = if ($gameplay) { 'playable-gameplay-runtime-smoke' } else { 'playable-preview-runtime-smoke' }
    $report = ConvertFrom-GodotStructuredReport -Result $Result -Prefix $prefix -RequireChecks
    foreach ($field in @('process_id', 'mode', 'final_mode', 'final_actor_count', 'initial_tick', 'final_tick',
            'input_schema_version', 'initial_selected_actor_id')) {
        if ($report[$field] -isnot [long] -and $report[$field] -isnot [int]) {
            throw "Native preview identity requires an integer $field."
        }
        if ($report['complete'] -isnot [bool] -or -not $report['complete'] -or
            $report['integration_errors'] -isnot [System.Collections.IList] -or @($report['integration_errors']).Count -ne 0) {
            throw 'The real smoke must complete every phase with no production integration errors through finalization.'
        }
    }
    if (-not [IO.Path]::IsPathFullyQualified($ReportPath) -or -not (Test-Path -LiteralPath $ReportPath -PathType Leaf) -or
        (Get-Item -LiteralPath $ReportPath).LastWriteTimeUtc -lt $StartedAt.ToUniversalTime()) {
        throw "A fresh current-run report was not created at $ReportPath."
    }
    $disk = Get-Content -LiteralPath $ReportPath -Raw | ConvertFrom-Json -AsHashtable -Depth 64
    if (($disk | ConvertTo-Json -Depth 64 -Compress) -cne ($report | ConvertTo-Json -Depth 64 -Compress)) {
        throw 'The report file and native stdout JSON disagree.'
    }
    if ($report['process_id'] -notin $Result.RuntimeProcessIds -or $report['process_id'] -le 0 -or
        [IO.Path]::GetFullPath([string]$report['report_path']) -ne [IO.Path]::GetFullPath($ReportPath)) {
        throw 'The report is not from the launched PID and requested report path.'
    }
    if ($report['scope'] -cne $scope -or $report['project_version'] -ne $ProjectVersion -or
        $report['project_name'] -ne 'Futsal — Laboratorio 5v5' -or
        $report['input_schema_version'] -ne $InputSchemaVersion -or
        $report['engine_version'] -ne '4.7.2-stable (official)' -or
        $report['main_scene'] -ne 'res://match/match.tscn' -or
        $report['configured_main_scene'] -ne 'res://match/match.tscn') {
        throw 'A diagnostic, historical G1 scene/version or other main cannot satisfy preview validation.'
    }
    if ($report['editor_binary'] -isnot [bool] -or $report['editor_binary'] -ne $EditorBinary -or
        $report['headless'] -isnot [bool] -or $report['headless'] -ne $Headless -or
        [IO.Path]::GetFullPath([string]$report['executable']) -ne [IO.Path]::GetFullPath($Executable)) {
        throw 'Native binary/mode identity disagrees with this launch.'
    }
    if ($report['viewport_width'] -ne 1920 -or $report['viewport_height'] -ne 1080 -or
        $report['physics_engine'] -ne 'Jolt Physics' -or $report['physics_ticks_per_second'] -ne 60 -or
        $report['capture_phase'] -ne 'PLAYING' -or $report['final_actor_count'] -ne 10 -or
        $report['mode'] -ne 1 -or $report['final_mode'] -ne 1 -or
        $report['initial_tick'] -lt 1 -or $report['final_tick'] -lt 1 -or $report['initial_selected_actor_id'] -ne 0 -or
        $report['initial_tick'] -ne $report['default_entrypoint']['after_wait']['tick'] -or
        $report['final_tick'] -ne $report['final_state']['tick'] -or
        $report['final_hud_selected'] -cne "CONTROL · ID 0`nCAMPO LOCAL") {
        throw 'Missing native viewport, physics, strict ten-actor preview or normal PLAYING evidence.'
    }
    $actors = @($report['loaded_actors'])
    if ($actors.Count -ne 10 -or (($actors | ForEach-Object { $_['id'] }) -join ',') -ne '0,1,2,3,4,5,6,7,8,9') {
        throw 'The loaded actor identities are not the ten preview actors.'
    }
    Assert-GodotIntegerList $report['initial_ai_actor_ids'] @(1..9) 'Default preview AI'
    Assert-GodotIntegerList $report['initial_ai_intent_actor_ids'] @(0..9) 'Default preview AI intent includes selected zero'
    Assert-GodotDefaultEntrypoint $report
    Assert-GodotPreviewTransitions $report -Gameplay:$gameplay
    $controls = @($report['inputs'] | ForEach-Object { $_['control'] })
    foreach ($control in @('keyboard D', 'keyboard W', 'joypad left X', 'joypad left Y',
            'Esc / Start', 'Start / Esc', 'Esc / Down / Enter restart', 'development AI mode 1', 'development AI mode 0')) {
        if ($control -notin $controls) { throw "Missing actual input evidence: $control" }
    }
    if (-not $report.Contains('command_rejections') -or @($report['command_rejections']).Count -ne 0) {
        throw 'The normal game path reported command rejections or omitted their evidence.'
    }
    if ($report['gpu_validated'] -isnot [bool]) { throw 'GPU validation must be a boolean.' }
    if ($Headless) {
        if ($report['gpu_validated'] -or $report['rendering_method'] -ne 'headless' -or
            $report['rendering_driver'] -ne 'dummy' -or -not [string]::IsNullOrEmpty($CapturePath) -or
            $report.Contains('capture_path')) { throw 'Headless execution cannot validate or capture the GPU.' }
    }
    else {
        $nativeHeaders = [regex]::Matches($Result.Stdout, '(?m)^Vulkan [^\r\n]+ - Forward\+ - Using Device[^\r\n]+')
        if (-not $report['gpu_validated'] -or $report['rendering_method'] -ne 'forward_plus' -or
            $report['rendering_driver'] -ne 'vulkan' -or [string]::IsNullOrWhiteSpace($report['gpu_name']) -or
            $nativeHeaders.Count -ne 1 -or
            -not $nativeHeaders[0].Value.EndsWith(' - ' + [string]$report['gpu_name'], [StringComparison]::Ordinal)) {
            throw 'The native Vulkan startup and GPU report do not agree.'
        }
        if (-not $gameplay) {
            if (-not [IO.Path]::IsPathFullyQualified($CapturePath) -or
                [IO.Path]::GetFullPath([string]$report['capture_path']) -ne [IO.Path]::GetFullPath($CapturePath) -or
                -not (Test-GodotPng $CapturePath) -or
                (Get-Item -LiteralPath $CapturePath).LastWriteTimeUtc -lt $StartedAt.ToUniversalTime()) {
                throw 'A fresh native 1920x1080 PNG was not saved at the requested path.'
            }
        }
    }
    if ($gameplay -and ($report.Contains('capture_path') -or -not [string]::IsNullOrEmpty($CapturePath))) {
        throw 'Gameplay protocol never accepts the legacy --capture-path or single-image shortcut.'
    }
    return $report
}

function Get-GodotFocusSmokeCases {
    return [ordered]@{
        'preview_off_ball_neutral' = @{mode = 1; from = 0; to = 4; intent = @(); reason = 'off_ball_switch'; input = 'InputEventKey:J'}
        'preview_off_ball_directional' = @{mode = 1; from = 0; to = 8; intent = @(); reason = 'off_ball_switch'; input = 'InputEventKey:J then physical Left in one frame'}
        'preview_pass_field' = @{mode = 1; from = 0; to = 4; intent = @(); reason = 'pass'; input = 'InputEventJoypadButton:A'}
        'micro_pass_keeper' = @{mode = 0; from = 0; to = 2; intent = @(2); reason = 'pass'; input = 'InputEventKey:J'}
        'micro_keeper_manual_return' = @{mode = 0; from = 2; to = 0; intent = @(2); reason = 'pass'; input = 'InputEventJoypadButton:A'}
        'micro_keeper_ai_return' = @{mode = 0; from = 0; to = 0; intent = @(2); reason = 'keeper_ai'; input = 'autonomous keeper; no human pass input'}
    }
}

function Get-GodotVectorDistanceSquared($Before, $After) {
    Assert-GodotFiniteVector $Before 'Before vector'
    Assert-GodotFiniteVector $After 'After vector'
    $distance = 0.0
    for ($axis = 0; $axis -lt 3; $axis++) { $distance += [Math]::Pow($After[$axis] - $Before[$axis], 2) }
    if (-not [double]::IsFinite($distance)) { throw 'Native vector difference is nonfinite.' }
    return $distance
}

function Assert-GodotRecordedMotion($Report, [string]$Control, [int]$Selected, [int]$Axis, [int]$Sign) {
    $records = @($Report['inputs'] | Where-Object { $_['control'] -ceq $Control })
    if ($records.Count -ne 1) { throw "Require one actual motion proof: $Control." }
    $proof = $records[0]
    if ($proof['event_class'] -cne 'InputEventKey' -or
        ($proof['device'] -isnot [int] -and $proof['device'] -isnot [long]) -or $proof['device'] -ne 0 -or
        ($proof['selected_actor_id'] -isnot [int] -and $proof['selected_actor_id'] -isnot [long]) -or
        $proof['selected_actor_id'] -ne $Selected -or
        ($proof['driver_start_calls'] -isnot [int] -and $proof['driver_start_calls'] -isnot [long]) -or
        $proof['driver_start_calls'] -lt 1) { throw "Wrong production input identity: $Control." }
    $sequence = -2
    foreach ($stage in @('before', 'pressed', 'settled', 'released')) {
        $actor = $proof[$stage]
        if ($actor -isnot [System.Collections.IDictionary] -or $actor['id'] -ne $Selected -or
            $actor['human'] -isnot [bool] -or -not $actor['human'] -or
            ($actor['sequence'] -isnot [int] -and $actor['sequence'] -isnot [long]) -or $actor['sequence'] -le $sequence) {
            throw "Wrong actor or nonadvancing command sequence in $Control/$stage."
        }
        foreach ($field in @('id', 'team', 'role')) {
            if ($actor[$field] -isnot [int] -and $actor[$field] -isnot [long]) { throw "Motion actor requires integer $field." }
        }
        if ($actor['team'] -ne 0 -or $actor['role'] -ne 0) { throw 'These movement proofs require the selected HOME field player.' }
        $sequence = $actor['sequence']
        Assert-GodotFiniteVector $actor['position'] "$Control/$stage position"
        Assert-GodotFiniteVector $actor['velocity'] "$Control/$stage velocity"
    }
    if (($proof['pressed']['position'][$Axis] - $proof['before']['position'][$Axis]) * $Sign -le 0.3 -or
        (Get-GodotVectorDistanceSquared $proof['settled']['position'] $proof['released']['position']) -ge 0.000625 -or
        (Get-GodotVectorDistanceSquared @(0, 0, 0) $proof['released']['velocity']) -ge 0.0064) {
        throw "$Control did not move the selected actor in the requested direction and stop on release."
    }
    return $proof
}

function Assert-GodotFocusState($State, $Expected, [int]$Selected, [int]$Owner) {
    if ($State -isnot [System.Collections.IDictionary]) { throw 'Missing complete native focus snapshot.' }
    foreach ($field in @('actors', 'physical_actor_ids', 'ai_intent_actor_ids', 'ai_actor_ids', 'score')) {
        if ($State[$field] -isnot [System.Collections.IList]) { throw "Focus snapshot requires an array $field." }
    }
    Assert-GodotModeState $State $Expected.mode $Expected.intent 'PLAYING' $Selected
    foreach ($field in @('ball_owner_id', 'human_sequence', 'driver_start_calls')) {
        if ($State[$field] -isnot [int] -and $State[$field] -isnot [long]) { throw "Focus snapshot requires integer $field." }
    }
    if ($State['tick'] -lt 1 -or $State['ball_owner_id'] -ne $Owner -or $State['driver_start_calls'] -lt 1 -or
        $State['human_sequence'] -lt 0 -or $State['human_sequence'] -ne $State['actors'][$Selected]['sequence']) {
        throw 'Focus snapshot owner, selected command feed or legal post-default drill identity disagrees.'
    }
    Assert-GodotIntegerList $State['score'] @(0, 0) 'Focus drill score'
    foreach ($actor in $State['actors']) {
        if ($actor['sequence'] -lt -1) { throw 'Actor sequence was reset outside its valid initial range.' }
    }
}

function Assert-GodotFocusProgress($Before, $After, [int[]]$AdvancingActors) {
    $ticks = $After['tick'] - $Before['tick']
    $elapsed = $Before['seconds_remaining'] - $After['seconds_remaining']
    if ($ticks -le 0 -or $elapsed -le 0 -or [Math]::Abs($elapsed - $ticks / 60.0) -gt 0.000001 -or
        $Before['driver_start_calls'] -ne $After['driver_start_calls']) {
        throw 'Focus evidence reset the match, stalled time or disagrees with the real 60 Hz clock.'
    }
    for ($index = 0; $index -lt $Before['actors'].Count; $index++) {
        $old = $Before['actors'][$index]['sequence']
        $new = $After['actors'][$index]['sequence']
        if ($new -lt $old -or ($index -in $AdvancingActors -and $new -le $old)) {
            throw "Focus did not preserve/advance the actual per-actor sequence for $index."
        }
        $active = @($Before['ai_actor_ids']) + @($After['ai_actor_ids']) +
            @($Before['selected_actor_id'], $After['selected_actor_id'])
        if ($index -notin $active -and $new -ne $old) {
            throw "Disabled actor $index received commands despite preserved all-off/partial intent."
        }
    }
}

function Assert-GodotFocusEvent($Event, [int]$Kind, [int]$Actor, [int]$Target, [int]$Selected,
    [int]$Owner, [string]$Reason, $Before, $After) {
    if ($Event -isnot [System.Collections.IDictionary]) { throw 'Malformed native focus/pass event.' }
    foreach ($field in @('id', 'tick', 'kind', 'actor', 'target', 'selected_actor_id', 'ball_owner_id')) {
        if ($Event[$field] -isnot [int] -and $Event[$field] -isnot [long]) { throw "Native event requires integer $field." }
    }
    if ($Event['id'] -lt 1 -or $Event['tick'] -le $Before['tick'] -or $Event['tick'] -gt $After['tick'] -or
        $Event['kind'] -ne $Kind -or $Event['actor'] -ne $Actor -or $Event['target'] -ne $Target -or
        $Event['selected_actor_id'] -ne $Selected -or $Event['ball_owner_id'] -ne $Owner -or
        $Event['reason'] -cne $Reason) { throw 'Wrong native event ordering, frame, authority or possession transition.' }
    if ($Event['score'] -isnot [System.Collections.IList]) { throw 'Native event requires an integer score array.' }
    Assert-GodotIntegerList $Event['score'] @(0, 0) 'Focus event score'
}

function Test-GodotSameEvent($Left, $Right) {
    if ($Right -isnot [System.Collections.IDictionary]) { return $false }
    if ($Right['reason'] -isnot [string] -or $Right['score'] -isnot [System.Collections.IList] -or
        $Right['score'].Count -ne 2) { return $false }
    foreach ($score in $Right['score']) {
        if ($score -isnot [int] -and $score -isnot [long]) { return $false }
    }
    foreach ($field in @('id', 'tick', 'kind', 'actor', 'target', 'selected_actor_id', 'ball_owner_id', 'reason')) {
        if ($field -ne 'reason' -and $Right[$field] -isnot [int] -and $Right[$field] -isnot [long]) { return $false }
        if ($Left[$field] -cne $Right[$field]) { return $false }
    }
    return ($Left['score'] -join ',') -ceq ($Right['score'] -join ',')
}

function Find-GodotRecordedEvent($History, $Expected) {
    $matches = @()
    for ($index = 0; $index -lt $History.Count; $index++) {
        if (Test-GodotSameEvent $Expected $History[$index]) { $matches += $index }
    }
    if ($matches.Count -ne 1) { throw 'A focus/pass event is missing or ambiguous in the actual production event history.' }
    return $matches[0]
}

function Find-GodotPassReception($History, $FocusEvent, $AfterKick, $Received, [int]$Selected) {
    $start = Find-GodotRecordedEvent $History $FocusEvent
    for ($index = $start + 1; $index -lt $History.Count; $index++) {
        $event = $History[$index]
        if ($event['kind'] -eq 4) { break }
        if ($event['kind'] -in @(1, 9) -or $event['selected_actor_id'] -ne $Selected) {
            throw 'Human pass lost receiver focus or was replaced before physical reception.'
        }
        if ($event['kind'] -eq 6 -and $event['actor'] -eq $Selected -and $event['reason'] -ceq 'received') {
            Assert-GodotFocusEvent $event 6 $Selected -1 $Selected $Selected 'received' $AfterKick $Received
            if ($event['id'] -le $FocusEvent['id']) { throw 'Reception preceded its accepted pass/focus event.' }
            return $event
        }
    }
    throw 'Claimed received possession has no matching physical reception event before the next restart.'
}

function Assert-GodotFocusEventWindow($History, $Case) {
    $first = Find-GodotRecordedEvent $History $Case['events'][0]
    $restart = $first - 1
    while ($restart -ge 0 -and $History[$restart]['kind'] -ne 4) { $restart -= 1 }
    $canonicalStart = @{
        id = 0; tick = 0; kind = 4; actor = -1; target = -1; selected_actor_id = 0
        ball_owner_id = -1; reason = 'training_start'; score = @(0, 0)
    }
    if ($restart -lt 0 -or -not (Test-GodotSameEvent $canonicalStart $History[$restart])) {
        throw 'Focus evidence has no actual canonical-start event delimiting its legal drill.'
    }
    $window = @()
    for ($index = $restart + 1; $index -lt $History.Count; $index++) {
        $event = $History[$index]
        if ($event['kind'] -eq 4) { break }
        if ($event['tick'] -isnot [int] -and $event['tick'] -isnot [long]) { throw 'Production event window requires integer ticks.' }
        if ($event['tick'] -gt $Case['before']['tick'] -and $event['tick'] -le $Case['after']['tick']) {
            $window += $event
        }
    }
    if ($window.Count -ne $Case['events'].Count) {
        throw 'Case evidence omitted or invented events from its actual before/after production window.'
    }
    for ($index = 0; $index -lt $window.Count; $index++) {
        if (-not (Test-GodotSameEvent $Case['events'][$index] $window[$index])) {
            throw 'Case event ordering differs from the complete production window.'
        }
    }
}

function Assert-GodotFocusChangesReport([System.Collections.IDictionary]$Report, [switch]$Gameplay) {
    $policy = Get-GodotFocusSmokeCases
    $cases = @($Report['focus_changes'])
    $expectedCount = $policy.Count + $(if ($Gameplay) { 4 } else { 0 })
    if ($Report['focus_changes'] -isnot [System.Collections.IList] -or $cases.Count -ne $expectedCount -or
        $Report['events'] -isnot [System.Collections.IList]) { throw 'Require all six source-defined focus cases and actual event history.' }
    if ($Gameplay) {
        $extra = @('m0/corner_pos_x_neg_z/accepted_pass', 'm0/keeper_clearance/manual_throw',
            'm1/corner_pos_x_neg_z/accepted_pass', 'm1/keeper_clearance/manual_throw')
        for ($index = 0; $index -lt $extra.Count; $index++) {
            if ($cases[$policy.Count + $index]['case'] -cne $extra[$index]) {
                throw 'Gameplay must retain six legacy focus cases followed by the four actual restart-pass cases.'
            }
        }
        $cases = @($cases[0..($policy.Count - 1)])
    }
    $names = @($policy.Keys)
    for ($index = 0; $index -lt $cases.Count; $index++) {
        $case = $cases[$index]
        if ($case -isnot [System.Collections.IDictionary] -or $case['case'] -cne $names[$index]) {
            throw 'Focus cases are missing, duplicated or out of production order.'
        }
        $expected = $policy[$names[$index]]
        $before = $case['before']
        $after = $case['after']
        if ($case['source_script'] -cne 'res://match/match.gd' -or $case['input'] -cne $expected.input -or
            $case['reason'] -cne $expected.reason -or $case['passed'] -isnot [bool] -or -not $case['passed']) {
            throw "Wrong real-host/input contract or failed focus case: $($case['case'])."
        }
        foreach ($field in @('before_selected_actor_id', 'after_selected_actor_id', 'before_ball_owner_id',
                'after_ball_owner_id', 'actor_count', 'expected_selected_actor_id')) {
            if ($case[$field] -isnot [int] -and $case[$field] -isnot [long]) { throw "Focus case requires integer $field." }
        }
        $beforeOwner = if ($expected.reason -ceq 'keeper_ai') { 2 } elseif ($expected.reason -ceq 'pass') { $expected.from } else { -1 }
        $afterOwner = if ($expected.reason -ceq 'keeper_ai') { 0 } else { -1 }
        Assert-GodotFocusState $before $expected $expected.from $beforeOwner
        Assert-GodotFocusState $after $expected $expected.to $afterOwner
        if ($case['before_selected_actor_id'] -ne $expected.from -or $case['after_selected_actor_id'] -ne $expected.to -or
            $case['expected_selected_actor_id'] -ne $expected.to -or $case['actor_count'] -ne $after['actor_count'] -or
            $case['before_ball_owner_id'] -ne $beforeOwner -or $case['after_ball_owner_id'] -ne $afterOwner) {
            throw 'Focus summaries do not match the actual before/after authority snapshots.'
        }
        foreach ($field in @('ai_intent_actor_ids', 'ai_actor_ids')) {
            if ($case[$field] -isnot [System.Collections.IList]) { throw "Focus case requires an array $field." }
        }
        Assert-GodotIntegerList $case['ai_intent_actor_ids'] $expected.intent 'Focus intent summary'
        Assert-GodotIntegerList $case['ai_actor_ids'] $after['ai_actor_ids'] 'Focus effective AI summary'
        $advancing = @($expected.from, $expected.to | Sort-Object -Unique)
        if ($expected.reason -ceq 'keeper_ai') { $advancing = @(0, 2) }
        Assert-GodotFocusProgress $before $after $advancing
        $events = @($case['events'])
        if ($case['events'] -isnot [System.Collections.IList]) { throw 'Focus case omitted native events.' }
        if ($expected.reason -ceq 'off_ball_switch') {
            if ($events.Count -ne 1) { throw 'Off-ball switch must emit one focus event and no pass.' }
            Assert-GodotFocusEvent $events[0] 9 $expected.from $expected.to $expected.to -1 'off_ball_switch' $before $after
            if ($case.Contains('received')) { throw 'A switch cannot present itself as a pass reception.' }
        }
        elseif ($expected.reason -ceq 'pass') {
            if ($events.Count -ne 2) { throw 'Accepted human pass must emit ordered PASS then FOCUS_CHANGED.' }
            Assert-GodotFocusEvent $events[0] 1 $expected.from $expected.to $expected.to -1 'kick' $before $after
            Assert-GodotFocusEvent $events[1] 9 $expected.from $expected.to $expected.to -1 'pass' $before $after
            if ($events[0]['id'] -ge $events[1]['id'] -or $events[0]['tick'] -ne $events[1]['tick']) {
                throw 'Focus must follow the accepted pass in its physical kick frame.'
            }
            $received = $case['received']
            Assert-GodotFocusState $received $expected $expected.to $expected.to
            Assert-GodotFocusProgress $after $received @($expected.to)
            if ((Get-GodotVectorDistanceSquared @(0, 0, 0) $after['ball_velocity']) -le 0.25 -or
                (Get-GodotVectorDistanceSquared $before['ball_position'] $after['ball_position']) -le 0.0001 -or
                (Get-GodotVectorDistanceSquared $after['ball_position'] $received['ball_position']) -le 0.01 -or
                (Get-GodotVectorDistanceSquared $received['ball_position'] $received['actors'][$expected.to]['position']) -ge
                    (Get-GodotVectorDistanceSquared $after['ball_position'] $after['actors'][$expected.to]['position'])) {
                throw 'Received possession lacks real ball flight toward the controlled receiver.'
            }
            $null = Find-GodotPassReception $Report['events'] $events[1] $after $received $expected.to
        }
        else {
            if ($events.Count -ne 2 -or $case.Contains('received')) { throw 'Keeper AI proof requires a pass and actual reception, without focus transfer.' }
            Assert-GodotFocusEvent $events[0] 1 2 0 0 -1 'kick' $before $after
            Assert-GodotFocusEvent $events[1] 6 0 -1 0 0 'received' $before $after
            if ($events[0]['id'] -ge $events[1]['id'] -or $events[0]['tick'] -ge $events[1]['tick'] -or
                (Get-GodotVectorDistanceSquared $before['ball_position'] $after['ball_position']) -le 0.01) {
                throw 'Keeper AI return requires physical flight and later reception with selection unchanged.'
            }
        }
        foreach ($event in $events) {
            $null = Find-GodotRecordedEvent $Report['events'] $event
        }
        Assert-GodotFocusEventWindow $Report['events'] $case
    }
    $direction = $cases[1]
    if ($direction['after']['actors'][8]['position'][0] -ge $direction['before']['actors'][8]['position'][0] -or
        $direction['after']['actors'][8]['velocity'][0] -ge 0) {
        throw 'The new selected actor stalled instead of preserving held physical Left movement.'
    }
    $manualBefore = $cases[4]['before']
    $keeperReceived = $cases[3]['received']
    foreach ($field in @('tick', 'seconds_remaining', 'driver_start_calls', 'human_sequence', 'ball_owner_id',
            'selected_actor_id', 'actors', 'ball_position', 'ball_velocity', 'ai_intent_actor_ids', 'ai_actor_ids')) {
        if (($manualBefore[$field] | ConvertTo-Json -Compress -Depth 16) -cne
            ($keeperReceived[$field] | ConvertTo-Json -Compress -Depth 16)) {
            throw 'Manual keeper return was reset/replaced instead of continuing the controlled keeper reception.'
        }
    }
    $keeperFocus = $cases[3]['events'][1]
    $keeperReception = Find-GodotPassReception $Report['events'] $keeperFocus $cases[3]['after'] $keeperReceived 2
    $keeperStart = Find-GodotRecordedEvent $Report['events'] $keeperFocus
    $manualStart = Find-GodotRecordedEvent $Report['events'] $cases[4]['events'][0]
    if ($manualStart -le $keeperStart -or $manualBefore['tick'] - $keeperReception['tick'] -lt 45) {
        throw 'Controlled keeper did not retain possession through the source-defined 45-tick manual-control hold.'
    }
    for ($index = $keeperStart + 1; $index -lt $manualStart; $index++) {
        $event = $Report['events'][$index]
        if ($event['selected_actor_id'] -ne 2 -or $event['kind'] -in @(1, 4, 9)) {
            throw 'A pass, restart or focus change replaced the controlled keeper hold before manual input.'
        }
    }
    $motion = Assert-GodotRecordedMotion $Report 'selected field D' 4 0 1
    $selected = $cases[0]['after']['actors'][4]
    if ($motion['driver_start_calls'] -ne $cases[0]['after']['driver_start_calls'] -or
        $motion['before']['sequence'] -ne $selected['sequence'] -or
        (Get-GodotVectorDistanceSquared $motion['before']['position'] $selected['position']) -gt 0.00000001) {
        throw 'Selected-player movement was proved only after replacing the real switched actor/drill.'
    }
    $null = Assert-GodotRecordedMotion $Report 'physical arrow Right' 0 0 1
    $null = Assert-GodotRecordedMotion $Report 'physical arrow Up' 0 2 -1
    if (-not $Gameplay -and $Report['final_state']['driver_start_calls'] -ne $cases[5]['after']['driver_start_calls']) {
        throw 'The published preview did not follow the complete keeper AI proof.'
    }
    $restoration = $Report['mode_changes'][2]['before']
    if ($restoration['driver_start_calls'] -ne $cases[5]['after']['driver_start_calls'] -or
        $restoration['tick'] -lt $cases[5]['after']['tick']) {
        throw 'Final preview restoration was detached from the completed keeper AI scenario.'
    }
}

function Read-GodotGameReport {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$ReportPath,
        [Parameter(Mandatory)][datetime]$StartedAt,
        [Parameter(Mandatory)][bool]$EditorBinary,
        [Parameter(Mandatory)][bool]$Headless,
        [Parameter(Mandatory)][string]$Executable,
        [string]$ProjectVersion = '0.5.0-preview',
        [int]$InputSchemaVersion = 3,
        [string]$CapturePath = ''
    )
    $report = Read-GodotBaseGameReport @PSBoundParameters
    Assert-GodotFocusChangesReport $report
    return $report
}
