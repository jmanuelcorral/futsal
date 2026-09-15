#Requires -Version 7.2
Set-StrictMode -Version Latest

function Get-GodotAimGuideNegativeCases {
    return @('origin_nan', 'direction_nan', 'direction_nonplanar', 'velocity_inf', 'speed_nan',
        'power_inf', 'power_negative', 'opposite_velocity', 'render_nan', 'missing_reason', 'null_solution',
        'invalid_actor', 'rival_receiver', 'speed_mismatch', 'shot_receiver')
}

function Assert-GodotLiteralNegativeCases([string]$Source, [string[]]$Cases) {
    $arrays = [regex]::Matches($Source, '(?s)for invalid: String in \[([^\]]+)\]:')
    if ($arrays.Count -ne 1) { throw 'Expected one explicit source-defined invalid-input matrix.' }
    $actual = @([regex]::Matches($arrays[0].Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    if (($actual -join "`n") -cne ($Cases -join "`n")) { throw 'Native negative-case source changed; review the exact diagnostic policy.' }
}

function Get-GodotAimGuideExpectedErrors([string]$TestSource, [string]$GuideSource) {
    $cases = @(Get-GodotAimGuideNegativeCases)
    Assert-GodotLiteralNegativeCases $TestSource $cases
    $message = 'WorldAimGuide.present: solución o posición de render no válida.'
    if (-not $GuideSource.Contains("const INVALID_SOLUTION: String = `"$message`"") -or
        -not $TestSource.Contains('"new_expected_error_counts": {GuideScript.INVALID_SOLUTION: _expected_errors}')) {
        throw 'Aim-guide diagnostic constructor no longer matches its explicit policy.'
    }
    return [ordered]@{("ERROR: $message") = $cases.Count}
}

function Assert-GodotHudDiagnosticSource([string]$TestSource, [string]$HudSource) {
    Assert-GodotLiteralNegativeCases $TestSource (Get-MatchHudRestartNegativeCases)
    foreach ($pair in @(@('SELECTION_ERROR', 'MatchHUD.set_selected_actor: se requiere identidad válida y control humano de un actor local.'),
            @('RESTART_ERROR', 'MatchHUD.present_restart: estado de reanudación incoherente o no válido.'))) {
        if (-not $HudSource.Contains("const $($pair[0]): String = `"$($pair[1])`"")) { throw 'HUD diagnostic source changed.' }
    }
}

function Get-GodotGameplayNativeDiagnostics([string]$Stage, [string]$Root) {
    $policy = [ordered]@{aimGuideErrors = @{}; developmentWarnings = @{}}
    if ($Stage -ceq 'aim-guide') {
        $policy.aimGuideErrors = Get-GodotAimGuideExpectedErrors `
            ([IO.File]::ReadAllText((Join-Path $Root 'game\tests\test_match_aim_guide.gd'))) `
            ([IO.File]::ReadAllText((Join-Path $Root 'game\match\presentation\aim\world_aim_guide.gd')))
    }
    elseif ($Stage -ceq 'gameplay-runtime') {
        $source = [IO.File]::ReadAllText((Join-Path $Root 'game\tests\test_match_gameplay_runtime.gd'))
        $hostSource = [IO.File]::ReadAllText((Join-Path $Root 'game\match\match.gd'))
        if (-not $source.Contains('_begin_negative("G30 ejercicio fuera de catálogo", ERR_INVALID_PARAMETER, false)') -or
            -not $hostSource.Contains('_development_error(ERR_INVALID_PARAMETER, "Ejercicio de entrenamiento no válido")')) {
            throw 'Native gameplay invalid-exercise diagnostic contract changed.'
        }
        $policy.developmentWarnings = [ordered]@{'WARNING: Ejercicio de entrenamiento no válido' = 1}
    }
    return $policy
}

function Assert-GodotNativePrintedChecks($Result, $Report) {
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $raw = [regex]::Matches($Result.Stdout, '(?m)^PASS ([^\r\n]+)\r?$')
    if ($raw.Count -ne $Report['checks'].Count -or $Result.Stdout -match '(?m)^FAIL ') {
        throw 'Printed native assertions and structured checks disagree.'
    }
    foreach ($line in $raw) {
        if (-not $names.Add($line.Groups[1].Value)) { throw 'Repeated native printed assertion.' }
    }
    foreach ($check in $Report['checks']) {
        if (-not $names.Contains($check['name'])) { throw 'Structured assertion has no matching native output.' }
    }
}

function Assert-GodotNativeCheck($Report, [string]$Name) {
    $matched = [Collections.Generic.List[object]]::new()
    foreach ($check in $Report['checks']) {
        if ($check['name'] -ceq $Name) { $matched.Add($check) }
    }
    if ($matched.Count -ne 1 -or $matched[0]['passed'] -isnot [bool] -or -not $matched[0]['passed']) {
        throw "Missing actual native assertion: $Name"
    }
}

function Assert-GodotNativeEmpty($Report, [string[]]$Fields) {
    foreach ($field in $Fields) {
        if ($Report[$field] -isnot [Collections.IList] -or $Report[$field].Count -ne 0) {
            throw "Native $field must be an explicitly empty array."
        }
    }
}

function Assert-GodotNativeClassification($Report) {
    foreach ($field in @('expected_checks', 'negative_cases', 'expected_negative_cases')) {
        Assert-GpInteger $Report[$field] $field 1
    }
    if ($Report['expected_checks'] -ne $Report['total'] -or $Report['negative_cases'] -ne $Report['expected_negative_cases']) {
        throw 'Classification counts disagree with actual assertions.'
    }
    foreach ($check in $Report['checks']) { Assert-GpBoolean $check['negative'] 'classification polarity' }
    if (@($Report['checks'] | Where-Object { $_['negative'] }).Count -ne $Report['negative_cases']) {
        throw 'A negative classification count must come from its actual check records, not diagnostic allowances.'
    }
    foreach ($field in @('expected_errors', 'expected_warnings', 'expected_refusals')) { Assert-GpInteger $Report[$field] $field 0 0 }
}

function Assert-GodotNativeRuleGroups($Report, [string]$Source) {
    $definitions = [regex]::Matches($Source, '_run_group\("([^"]+)", _test_[a-z0-9_]+, ([0-9]+), ([0-9]+)\)')
    if ($definitions.Count -eq 0 -or $Report['groups'] -isnot [Collections.IList] -or
        $Report['groups'].Count -ne $definitions.Count) { throw 'Rules groups do not cover the actual source matrix.' }
    $total = 2
    $negative = 0
    for ($index = 0; $index -lt $definitions.Count; $index++) {
        $definition = $definitions[$index]
        $name = $definition.Groups[1].Value
        $expected = [int]$definition.Groups[2].Value
        $expectedNegative = [int]$definition.Groups[3].Value
        $group = $Report['groups'][$index]
        if ($group -isnot [Collections.IDictionary] -or $group['name'] -cne $name) { throw 'Reordered or unknown native rules group.' }
        foreach ($field in @('actual', 'expected')) { Assert-GpInteger $group[$field] "rules.$field" $expected $expected }
        foreach ($field in @('actual_negatives', 'expected_negatives')) {
            Assert-GpInteger $group[$field] "rules.$field" $expectedNegative $expectedNegative
        }
        $items = @($Report['checks'] | Where-Object { $_['name'].StartsWith($name + '_', [StringComparison]::Ordinal) })
        if ($items.Count -ne $expected + 2 -or @($items | Where-Object { $_['negative'] }).Count -ne $expectedNegative) {
            throw 'Rules group counts are not supported by its actual labelled checks.'
        }
        Assert-GodotNativeCheck $Report ($name + '_exact_case_count')
        Assert-GodotNativeCheck $Report ($name + '_exact_negative_count')
        $total += $expected + 2
        $negative += $expectedNegative
    }
    if ($Report['total'] -ne $total -or $Report['negative_cases'] -ne $negative) { throw 'Rules matrix cannot be replaced by a partial self-consistent report.' }
}

function Assert-GodotGameplayAuthorityCompletion($Report, [string]$Source) {
    $required = @(
        'foul_tuning', 'catalogue', 'finishing_guards', 'touch_and_query', 'boundaries_and_mirror',
        'expiry_and_choices', 'opponent_ready', 'hand_ownership', 'direct_goals', 'release_episode_continuity',
        'separate_touches', 'dribbles', 'physical_fouls', 'seventh_foul', 'extensions',
        'extended_expiry', 'world_isolation'
    )
    $declarations = [regex]::Matches($Source, '(?m)^const GROUPS: Array\[String\] = \[([^\]]+)\]')
    if ($declarations.Count -ne 1) { throw 'Missing source-defined full physical-suite group catalogue.' }
    $declared = @([regex]::Matches($declarations[0].Groups[1].Value, '"([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value })
    Assert-GpEqual $declared $required 'full physical-suite source catalogue'
    $selected = $Report['selected_groups']
    if ($selected -isnot [Collections.IList] -or $selected.Count -ne $required.Count) {
        throw 'Full physical-suite evidence requires all seventeen groups; a partial selector is not a full run.'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in $selected) {
        if ($name -isnot [string] -or $name -cnotin $required -or -not $seen.Add($name)) {
            throw 'Full physical-suite groups must be distinct known identities, never summed selector duplicates.'
        }
    }
    Assert-GpBoolean $Report['complete'] 'physical suite complete' $true
    Assert-GpBoolean $Report['watchdog_probe'] 'physical watchdog probe' $false
    if ($Report['watchdog_failure'] -isnot [string] -or $Report['watchdog_failure'] -cne '') {
        throw 'Physical-suite watchdog failure must be explicitly empty.'
    }
    Assert-GpInteger $Report['pending_step_budget'] 'physical pending step budget' 0 0
    Assert-GpInteger $Report['requested_physics_steps'] 'physical requested steps' 1
    Assert-GpInteger $Report['physics_steps'] 'physical observed steps' $Report['requested_physics_steps']
    Assert-GodotNativeEmpty $Report @('diagnostics')
}

function Get-GodotGameplayHomeDribbleCases {
    # Reviewed finite G02 matrix, independent of the report and aggregate totals.
    $cases = [ordered]@{}
    $checks = @(
        'public fixture owns the reachable ball with HOME unselected and AI off'
        'initial dribble refusal preserves state, sequence and events'
        'refusal never releases an impulse or consumes gesture recovery'
        'same rejected sequence can queue a legal dribble on the next tick'
        'retry produces one real cut rather than a stale forbidden impulse'
        'no stale goalward impulse scores after the safe retry'
    )
    foreach ($row in @(
            @('pace outside carry exclusion', @(17.45, 0.12, 0.0)),
            @('neutral pace outside carry exclusion', @(17.45, 0.12, 0.0)),
            @('pace inside carry exclusion', @(19.05, 0.12, 0.0)),
            @('cut from negative side outside exclusion', @(16.9, 0.12, -1.45)),
            @('cut from positive side outside exclusion', @(16.9, 0.12, 1.45)))) {
        $cases['G02 HOME forbidden dribble ' + $row[0]] = @{
            exercise = 0; ball = $row[1]; checks = $checks; refusal = 'goal-directed physical dribble'
        }
    }
    foreach ($side in @(-1, 1)) {
        $suffix = if ($side -eq -1) { '-1.0' } else { '1.0' }
        $cases["G02 HOME cut with inherited velocity side=$suffix"] = @{
            exercise = 0; ball = @(16.9, 0.12, (1.55 * $side)); refusal = 'inertia makes the real cut a finish'
            checks = @(
                'public lateral movement builds actual cut inertia'
                'nominal cut misses but observed body inertia aims through the mouth'
                'inertial cut refusal is atomic'
                'no cut impulse is hidden behind its nominal lateral direction'
            )
        }
        $cases["G02 HOME dribble turns goalward before contact side=$suffix"] = @{
            exercise = 0; ball = @(17.45, 0.12, (1.75 * $side)); refusal = 'changed physical heading at execution'
            checks = @(
                'current physical forward ray misses the goal before the queued turn'
                'safe current impulse is accepted before the native turn'
                'execution revalidates the new heading before release and recovery'
                'deferred refusal prevents a goal without rewriting physics or score'
                'execution refusal leaves recovery available to the next safe cut'
                'new lateral intent releases the ball physically'
            )
        }
    }
    $checks = @(
        'legal fixture still has the unselected HOME owner'
        'non-finishing dribble is accepted rather than blanket banned'
        'accepted gesture carries its real contact and directional impulse'
        'ball physically travels in the legal direction without focus or teleport'
    )
    foreach ($row in @(
            @('retreat inside exclusion', @(17.95, 0.12, 0.0)),
            @('advance beside goal mouth', @(17.45, 0.12, 2.4)),
            @('negative cut inside exclusion', @(19.05, 0.12, 0.0)),
            @('positive cut inside exclusion', @(19.05, 0.12, 0.0)))) {
        $cases['G02 legal unselected HOME dribble ' + $row[0]] = @{exercise = 0; ball = $row[1]; checks = $checks}
    }
    $checks = @(
        'legal finisher owns the ball with no AI or goalkeeper in its path'
        'selected HOME or AWAY retains the threatening dribble'
        'legal finish comes from the actual dribble impulse'
        'native complete-ball crossing proves the threatened goal is reachable'
    )
    foreach ($row in @(
            @('selected field pace', 0, 1, @(17.45, 0.12, 0.0)),
            @('AWAY pace at opposite end', 1, -1, @(-17.45, 0.12, 0.0)),
            @('selected HOME keeper pace', 2, 1, @(17.45, 0.12, 0.0)),
            @('selected field cut from negative side', 0, 1, @(16.9, 0.12, -1.45)),
            @('selected field cut from positive side', 0, 1, @(16.9, 0.12, 1.45)))) {
        $required = @($checks)
        if ($row[1] -eq 2) {
            $required += @('public off-ball switch selects the keeper, not an origin flag', 'keeper becomes the actual current human')
        }
        $cases['G02 legal physical dribble goal ' + $row[0]] = @{
            exercise = 0; ball = $row[3]; checks = $required; goalActor = $row[1]; goalSign = $row[2]; minimumSpeed = 4.0
        }
    }
    $cases['G02 mirrored HOME dribble after a public corner and reception'] = @{
        exercise = 4; ball = @(-19.85, 0.12, -9.85); refusal = 'HOME finish toward the mirrored negative end'
        goalActor = -1; goalSign = -1; minimumSpeed = 7.0
        checks = @(
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
    }
    $cases['G02 accidental HOME body deflection remains a goal'] = @{
        exercise = 0; ball = @(18.4, 0.4, 0.0); initialVelocity = @(-31.0, 0.0, 0.0); deflection = $true
        checks = @(
            'real uncommanded body collision precedes the complete-ball crossing'
            'physical accidental HOME goal is not erased by finishing policy'
        )
    }
    return $cases
}

function Get-GodotGameplayHomeDribbleRefusals {
    $expected = [ordered]@{}
    $cases = Get-GodotGameplayHomeDribbleCases
    foreach ($mode in @(0, 1)) {
        foreach ($name in $cases.Keys) {
            $rule = $cases[$name]
            if (-not $rule.Contains('refusal')) { continue }
            $scope = "$name; mode=$mode; exercise=$($rule.exercise)"
            $expected[$scope] = @{
                label = $rule.refusal; actor = $(if ($mode -eq 0) { 2 } else { 4 })
                code = 4; message = 'Allied dribble cannot intentionally finish'
                assertion = $(if ($rule.refusal -ceq 'changed physical heading at execution') {
                    'execution revalidates the new heading before release and recovery'
                } else { 'expected refusal ' + $rule.refusal })
            }
        }
    }
    return $expected
}

function ConvertFrom-GodotNativeVectorText($Value, [string]$Context) {
    if ($Value -isnot [string]) { throw "$Context requires the native vector string." }
    $number = '([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)'
    $match = [regex]::Match($Value, '^\(' + $number + ',[ \t]*' + $number + ',[ \t]*' + $number + '\)$')
    if (-not $match.Success) { throw "$Context contains a malformed native vector." }
    $vector = @(1..3 | ForEach-Object {
        [double]::Parse($match.Groups[$_].Value, [Globalization.CultureInfo]::InvariantCulture)
    })
    Assert-GodotFiniteVector $vector $Context
    return ,$vector
}

function Assert-GodotGameplayHomeDribbleCoverage($Report, [string]$Source) {
    $group = [regex]::Match($Source, '(?ms)^func _finishing_guards\(mode: Setup\.Mode\) -> void:\r?\n(?<body>.*?)(?=^func |\z)')
    foreach ($method in @('_home_dribble_finishing', '_home_dribble_revalidation', '_legal_home_dribbles',
            '_legal_dribble_goals', '_mirrored_home_dribble', '_accidental_home_goal')) {
        if (-not $group.Success -or -not $group.Groups['body'].Value.Contains("await $method(mode)")) {
            throw "Full native finishing_guards source omitted its actual $method traversal."
        }
    }
    $observed = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($scenario in $Report['scenarios']) {
        if (-not $observed.TryAdd($scenario['name'], $scenario)) { throw 'Repeated physical G02 scenario identity.' }
    }
    $cases = Get-GodotGameplayHomeDribbleCases
    foreach ($mode in @(0, 1)) {
        foreach ($name in $cases.Keys) {
            $rule = $cases[$name]
            $scope = "$name; mode=$mode; exercise=$($rule.exercise)"
            if (-not $observed.ContainsKey($scope)) { throw "Missing actual G02 dribble scenario: $scope" }
            $scenario = $observed[$scope]
            foreach ($check in $rule.checks) { Assert-GodotNativeCheck $Report "$scope/$check" }
            $ball = ConvertFrom-GodotNativeVectorText $scenario['ball'] "$scope initial ball"
            if ((Get-GodotVectorDistanceSquared $ball $rule.ball) -gt 0.00000001) {
                throw "G02 scenario no longer proves its actual initial ball geometry: $scope"
            }
            if ($rule.Contains('initialVelocity')) {
                $velocity = ConvertFrom-GodotNativeVectorText $scenario['velocity'] "$scope initial velocity"
                if ((Get-GodotVectorDistanceSquared $velocity $rule.initialVelocity) -gt 0.00000001) {
                    throw 'The accidental goal requires the actual incoming physical ball, not a commanded finish.'
                }
            }
            if ($rule.Contains('goalActor')) {
                $goal = $scenario['native_dribble_goal']
                if ($goal -isnot [Collections.IDictionary]) { throw "Missing actual dribble-to-goal observations: $scope" }
                $actor = if ($rule.goalActor -eq -1) { if ($mode -eq 0) { 2 } else { 4 } } else { $rule.goalActor }
                Assert-GpInteger $goal['actor_id'] 'native dribble goal actor' $actor $actor
                Assert-GpInteger $goal['dribble_tick'] 'native dribble contact tick' 1
                Assert-GpInteger $goal['goal_tick'] 'later complete-ball goal tick' 1
                if ($goal['goal_tick'] -le $goal['dribble_tick']) { throw 'A dribble goal must follow the actual physical release.' }
                $velocity = ConvertFrom-GodotNativeVectorText $goal['velocity'] "$scope dribble velocity"
                if ((Get-GpLength $velocity) -le $rule.minimumSpeed -or $velocity[0] * $rule.goalSign -le 0 -or
                    ($rule.goalActor -eq -1 -and $velocity[0] -ge -7.0)) {
                    throw 'Native dribble finish lost its actual impulse or attacking direction.'
                }
            }
            if ($rule.Contains('deflection')) {
                $goal = $scenario['native_deflection_goal']
                if ($goal -isnot [Collections.IDictionary]) { throw 'Missing native uncommanded contact-to-goal observations.' }
                $actor = if ($mode -eq 0) { 2 } else { 4 }
                Assert-GpInteger $goal['actor_id'] 'native accidental goal actor' $actor $actor
                Assert-GpInteger $goal['contact_tick'] 'native accidental contact tick' 1
                Assert-GpInteger $goal['goal_tick'] 'native accidental goal tick' 1
                if ($goal['goal_tick'] -le $goal['contact_tick']) { throw 'An accidental goal must follow the uncommanded body collision.' }
            }
        }
    }
}

function Get-GodotGameplayAuthorityRefusalPolicy {
    return [ordered]@{
        'nonselected HOME shot' = @{code = 4; message = 'Launch refused: allied_shot_forbidden'}
        'free pass aimed through goal mouth' = @{code = 4; message = 'Launch refused: allied_disguised_shot_forbidden'}
        'goalward HOME carry' = @{code = 4; message = 'Unselected HOME cannot deliberately carry into the goal mouth'}
        'diagnostic before pure queries' = @{code = 31; message = 'Move must be a finite vector of length <= 1'}
        'lost contact at execution' = @{code = 2; message = 'Possession/contact was lost before the kick tick'; assertion = 'stale guide cannot force a physical kick'}
        'deadline precedes pending kick' = @{code = 2; message = 'Restart deadline elapsed before the pending action'; assertion = 'deadline tick expires before applying any kick'}
        'sixth requires SHOT, never PASS' = @{code = 4; message = 'Launch refused: launch_rule'}
        'gesture cannot be replayed during recovery' = @{code = 44; message = 'Action is cooling down'}
        'no backward third gesture' = @{code = 2; message = 'Backward input does not define a third dribble'}
        'no control switch to prolong the extended attack' = @{code = 2; message = 'Action unavailable in the current rule context'}
        'unknown exercise' = @{code = 31; message = 'Unknown catalogued training exercise'; assertion = 'unknown catalogue entry is rejected atomically'}
        'unordered thresholds' = @{code = 31; message = 'Ordinary and reckless closing-speed thresholds must be ordered'; assertion = 'production reset rejects equal or reversed thresholds atomically'}
    }
}

function Assert-GodotGameplayAuthorityRefusals($Report) {
    Assert-GodotNativeEmpty $Report @('unexpected_refusals', 'pending_refusals')
    Assert-GpBoolean $Report['duplicate_names'] 'duplicate native names' $false
    $records = $Report['negative_cases']
    if ($records -isnot [Collections.IList] -or $records.Count -eq 0) { throw 'Missing actual authority refusal observations.' }
    Assert-GpInteger $Report['expected_refusals'] 'actual authority refusal count' $records.Count $records.Count
    $policy = Get-GodotGameplayAuthorityRefusalPolicy
    $homeDribbles = Get-GodotGameplayHomeDribbleRefusals
    $homeLabels = @($homeDribbles.Values | ForEach-Object { $_.label } | Sort-Object -Unique)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $coverage = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $records) {
        if ($record -isnot [Collections.IDictionary] -or $record['expected'] -isnot [Collections.IDictionary] -or
            $record['scope'] -isnot [string] -or $record['scope'] -cnotmatch '; mode=([01])(?:; exercise=[0-9]+)?$') {
            throw 'Authority refusal omitted its actual mode/scope and predeclared expectation.'
        }
        $mode = $Matches[1]
        $expected = $record['expected']
        $scope = $record['scope']
        if ($expected['name'] -isnot [string] -or -not $expected['name'].StartsWith($scope + '/', [StringComparison]::Ordinal) -or
            -not $seen.Add($expected['name'])) { throw 'Duplicated or detached authority refusal expectation.' }
        $label = $expected['name'].Substring($scope.Length + 1)
        Assert-GpBoolean $record['matched'] 'actual refusal matched' $true
        foreach ($field in @('actor_id', 'code')) {
            Assert-GpInteger $record[$field] "refusal.$field" -1 100
            Assert-GpInteger $expected[$field] "expected refusal.$field" $record[$field] $record[$field]
        }
        if ($record['message'] -isnot [string] -or $record['message'] -cne $expected['message']) { throw 'Actual refusal differs from its predeclared message.' }
        if ($label -ceq 'out-of-domain configuration') {
            if ($record['actor_id'] -ne -1 -or $record['code'] -ne 31 -or
                $scope -cnotmatch '^G28 rejected foul tuning (foul_challenge_window_ticks|foul_min_closing_speed|foul_reckless_closing_speed) (below minimum|above maximum|NaN|infinite); mode=[01]$') {
                throw 'Malformed out-of-domain tuning observation.'
            }
            $field = $Matches[1]
            $limits = @{foul_challenge_window_ticks = @(1.0, 60.0); foul_min_closing_speed = @(0.1, 4.0); foul_reckless_closing_speed = @(2.0, 20.0)}
            $bounds = [regex]::Match($record['message'], '^' + $field + ' must be finite and within \[([0-9]+(?:\.[0-9]+)?), ([0-9]+(?:\.[0-9]+)?)\]$')
            if (-not $bounds.Success -or
                [double]::Parse($bounds.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) -ne $limits[$field][0] -or
                [double]::Parse($bounds.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture) -ne $limits[$field][1]) {
                throw 'Tuning refusal message does not match its actual parameter.'
            }
            $assertion = 'production start refuses invalid tuning without changing the active world'
        }
        elseif ($label -cin $homeLabels) {
            if (-not $homeDribbles.Contains($scope)) { throw 'G02 dribble refusal is detached from its reviewed physical scenario.' }
            $rule = $homeDribbles[$scope]
            if ($label -cne $rule.label -or $record['actor_id'] -ne $rule.actor -or
                $record['code'] -ne $rule.code -or $record['message'] -cne $rule.message) {
                throw 'G02 dribble refusal changes its stage, actual HOME carrier or exact code/message.'
            }
            $assertion = $rule.assertion
        }
        else {
            if (-not $policy.Contains($label)) { throw "Unreviewed gameplay authority refusal: $label" }
            $rule = $policy[$label]
            if ($record['code'] -ne $rule.code -or $record['message'] -cne $rule.message) { throw "Wrong code/message for $label" }
            if ($label -in @('unknown exercise', 'unordered thresholds')) {
                if ($record['actor_id'] -ne -1) { throw 'Configuration refusal cannot target a gameplay actor.' }
            }
            elseif ($record['actor_id'] -lt 0 -or $record['actor_id'] -gt $(if ($mode -eq '0') { 3 } else { 9 })) {
                throw 'Command refusal has no active actor.'
            }
            $assertion = if ($rule.Contains('assertion')) { $rule.assertion } else { 'expected refusal ' + $label }
        }
        Assert-GodotNativeCheck $Report ($scope + '/' + $assertion)
        [void]$coverage.Add("$mode/$label")
    }
    foreach ($mode in @(0, 1)) {
        foreach ($label in @($policy.Keys) + @('out-of-domain configuration')) {
            if (-not $coverage.Contains("$mode/$label")) { throw "Missing actual authority negative coverage: $mode/$label" }
        }
    }
    foreach ($scope in $homeDribbles.Keys) {
        if (-not $seen.Contains("$scope/$($homeDribbles[$scope].label)")) {
            throw "Missing actual G02 dribble refusal: $scope"
        }
    }
}

function Get-GodotGameplayEpisodeCases {
    return [ordered]@{
        'G10 original hands release remains continuous until real shape separation' = @{
            exercise = 6; secondContact = $false
            checks = @(
                'hands fixture begins with actual sphere and keeper shape overlap'
                'hands fixture releases through the production authority'
                'continuous physical release beyond t plus one is not a second touch'
                'pause preserves the active release without resetting its identity'
                'paused release has no clock-based contact expiry'
                'resume preserves the same physical flight'
                'release reaches actual separation without inventing another restart'
            )
        }
        'G10 separate original-taker touch' = @{
            exercise = 1; secondContact = $true
            checks = @(
                'first legal stroke does not manufacture a double touch'
                'original kick remains one permitted episode'
                'a new native self-contact episode creates an indirect rather than another shot'
                'double touch never increments accumulated fouls'
            )
        }
    }
}

function Assert-GodotGameplayAuthorityScenarios($Report) {
    if ($Report['scenarios'] -isnot [Collections.IList] -or $Report['scenarios'].Count -eq 0) { throw 'Missing physical gameplay scenarios.' }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $catalogue = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $physical = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $episodes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $episodeCases = Get-GodotGameplayEpisodeCases
    foreach ($scenario in $Report['scenarios']) {
        if ($scenario -isnot [Collections.IDictionary] -or $scenario['name'] -isnot [string] -or
            [string]::IsNullOrWhiteSpace($scenario['name']) -or -not $names.Add($scenario['name'])) { throw 'Repeated or malformed physical scenario.' }
        Assert-GpInteger $scenario['mode'] 'scenario mode' 0 1
        Assert-GpInteger $scenario['exercise'] 'scenario exercise' 0 11
        Assert-GpInteger $scenario['start_error'] 'actual start result' 0 0
        if (-not $scenario['name'].EndsWith("; mode=$($scenario['mode']); exercise=$($scenario['exercise'])", [StringComparison]::Ordinal)) {
            throw 'Physical scenario identity disagrees with its actual setup.'
        }
        Assert-GodotNativeCheck $Report ($scenario['name'] + '/production start')
        if ($scenario['name'].StartsWith('G01/G08/G30/G32 catalogue;', [StringComparison]::Ordinal)) {
            [void]$catalogue.Add("$($scenario['mode'])/$($scenario['exercise'])")
        }
        if ($scenario['name'] -cmatch '^G20/G21/G28 physical ([a-z_]+);') {
            [void]$physical.Add("$($scenario['mode'])/$($Matches[1])")
            Assert-GodotNativeCheck $Report ($scenario['name'] + '/ACTOR_ACTOR evidence comes from a real kinematic collision')
        }
        if ($scenario.Contains('physical_challenge')) {
            $challenge = $scenario['physical_challenge']
            if ($challenge -isnot [Collections.IDictionary]) { throw 'Malformed physical challenge observation.' }
            foreach ($field in @('accepted', 'challenged', 'collision')) { Assert-GpBoolean $challenge[$field] "physical challenge $field" $true }
            foreach ($field in @('started_tick', 'contact_tick', 'live_ticks')) { Assert-GpInteger $challenge[$field] "physical challenge $field" 0 }
            if ($challenge['live_ticks'] -le 0 -or $challenge['contact_tick'] - $challenge['started_tick'] -ne $challenge['live_ticks']) {
                throw 'Physical challenge duration is inconsistent with its real contact tick.'
            }
        }
        if ($scenario.Contains('launch_contact_id')) {
            Assert-GpInteger $scenario['launch_contact_id'] 'scenario original episode identity' -1
        }
        if ($scenario.Contains('native_second_contact')) {
            $contact = $scenario['native_second_contact']
            if ($contact -isnot [Collections.IDictionary]) { throw 'Missing native second-contact observation.' }
            Assert-GpInteger $scenario['launch_contact_id'] 'original launch episode' 0
            Assert-GpInteger $contact['contact_id'] 'second native episode' 0
            if ($contact['contact_id'] -eq $scenario['launch_contact_id']) {
                throw 'A continuous original physical episode cannot be reported as a new second touch.'
            }
            Assert-GpInteger $contact['actor_id'] 'second touching actor' 0 $(if ($scenario['mode'] -eq 0) { 3 } else { 9 })
            Assert-GpInteger $contact['tick'] 'second contact tick' 1
            if ($contact['surface'] -isnot [string] -or $contact['surface'] -cne 'athlete') {
                throw 'A native self-contact must identify the actual athlete surface, not a post or wall.'
            }
        }
        foreach ($name in $episodeCases.Keys) {
            if (-not $scenario['name'].StartsWith($name + ';', [StringComparison]::Ordinal)) { continue }
            $rule = $episodeCases[$name]
            if ($scenario['exercise'] -ne $rule.exercise -or
                $scenario.Contains('native_second_contact') -ne $rule.secondContact) {
                throw 'Physical episode evidence disagrees with its source-defined continuous-release or second-touch scenario.'
            }
            Assert-GpInteger $scenario['launch_contact_id'] 'accepted original launch episode' 0
            if ($rule.secondContact -and $scenario['native_second_contact']['actor_id'] -ne 0) {
                throw 'The source-defined original-taker touch must come from actor zero.'
            }
            foreach ($check in $rule.checks) { Assert-GodotNativeCheck $Report ($scenario['name'] + '/' + $check) }
            [void]$episodes.Add("$($scenario['mode'])/$name")
        }
    }
    foreach ($mode in @(0, 1)) {
        foreach ($exercise in 0..11) {
            if (-not $catalogue.Contains("$mode/$exercise")) { throw 'Both modes require every actual physical catalogue scenario.' }
        }
        foreach ($label in @('ordinary', 'gentle', 'expired', 'clean', 'late', 'reckless', 'penalty', 'historical', 'late_window')) {
            if (-not $physical.Contains("$mode/$label")) { throw "Missing real physical foul/contact scenario $mode/$label" }
        }
        foreach ($name in $episodeCases.Keys) {
            if (-not $episodes.Contains("$mode/$name")) { throw "Missing actual G10 physical episode scenario $mode/$name" }
        }
    }
}

function Get-GodotNativeHostCases([string]$Stage) {
    $cases = [Collections.Generic.List[string]]::new()
    if ($Stage -ceq 'camera') {
        foreach ($mode in @(0, 1)) {
            $cases.Add("broadcast-framing/$mode")
            foreach ($exercise in 2..5) {
                $cases.Add("corner/$mode/$exercise")
                foreach ($action in @(1, 2)) { $cases.Add("trace/$mode/$exercise/$action") }
            }
            foreach ($kind in @('lifecycle', 'opponent', 'expiry-reset')) { $cases.Add("$kind/$mode") }
        }
        $cases.Add('legacy-counterexample')
    }
    else {
        foreach ($name in @('abi', 'invalid-exercise', 'terminal')) { $cases.Add($name) }
        foreach ($mode in @(0, 1)) {
            foreach ($exercise in 0..11) { $cases.Add("catalog/$mode/$exercise") }
            foreach ($name in @('keeper', 'precision', 'choice', 'guide')) { $cases.Add("$name/$mode") }
            foreach ($gesture in 0..2) { $cases.Add("dribble/$mode/$gesture") }
        }
    }
    return $cases.ToArray() | Sort-Object -CaseSensitive
}

function Assert-GodotNativeHostReport($Report, [string]$Stage) {
    $cases = @(Get-GodotNativeHostCases $Stage)
    foreach ($field in @('expected_cases', 'completed_cases')) {
        if ($Report[$field] -isnot [Collections.IList] -or ($Report[$field] -join "`n") -cne ($cases -join "`n")) {
            throw "Native host $field is not its complete source-defined traversal."
        }
        foreach ($case in $Report[$field]) { if ($case -isnot [string]) { throw 'Host case IDs must be native strings.' } }
    }
    foreach ($case in $cases) { Assert-GodotNativeCheck $Report ("recorrido finito, caso único: " + $case) }
    foreach ($name in @('G01 default intacto antes de resets: FREE_PLAY, 0/10/9',
            'G25 D física mueve el default antes de un drill', 'G25 liberación física frena el default',
            'suite completa, ningún caso perdido por aborto asíncrono', 'diagnósticos exactos hasta la finalización',
            'identificadores de comprobación únicos hasta la finalización')) {
        Assert-GodotNativeCheck $Report $name
    }
    # Our stage matrix is authoritative; the report cannot opt out by removing an expected case.
    if ('legacy-counterexample' -cin $cases) {
        Assert-GodotNativeCheck $Report 'contraejemplo rechazado fue ejercitado por cámaras nativas'
    }
    Assert-GodotNativeEmpty $Report @('unexpected_integration_errors', 'unexpected_command_refusals')
    if ($Report['main_scene'] -cne 'res://match/match.tscn') { throw 'Native host was not the configured playable main.' }
    foreach ($kind in @('key', 'joy_button', 'joy_motion')) { Assert-GpInteger $Report['native_events'][$kind] "native $kind events" 1 }
    Assert-GpInteger $Report['mouse_events'] 'native mouse event count' 0
    foreach ($field in @('command_refusals', 'expected_command_refusals', 'camera_samples', 'transition_samples', 'athlete_presentations')) {
        if ($Report[$field] -isnot [Collections.IList]) { throw "Native host requires array $field." }
    }
    if ($Report['trace_coverage'] -isnot [Collections.IDictionary]) { throw 'Native host omitted trace coverage.' }
    if ($Stage -ceq 'camera') {
        Assert-GpInteger $Report['expected_development_errors'] 'camera expected diagnostics' 0 0
        Assert-GodotNativeEmpty $Report @('command_refusals', 'expected_command_refusals')
        Assert-GodotNativeBroadcastFraming $Report
        Assert-GodotNativeCameraTraces $Report
    }
    else {
        Assert-GpInteger $Report['expected_development_errors'] 'invalid exercise diagnostic' 1 1
        Assert-GodotNativeCheck $Report 'diagnóstico exacto de negativa: G30 ejercicio fuera de catálogo'
        Assert-GodotNativeGameplayRefusals $Report
        if ($Report['athlete_presentations'].Count -eq 0) { throw 'Gameplay host omitted actual rendered athlete poses.' }
        foreach ($sample in $Report['athlete_presentations']) {
            if ($sample -isnot [Collections.IDictionary] -or $sample['case'] -isnot [string]) { throw 'Invalid native athlete observation.' }
            if ($sample.Contains('pose')) {
                Assert-GpPose $sample['pose'] '/root/Match'
                Assert-GodotFiniteVector $sample['render_ball_position'] 'prepared keeper render ball'
                if ($sample['pose']['actor_id'] -ne 2) { throw 'Ready-hands evidence is not the actual HOME keeper.' }
                foreach ($hand in $sample['pose']['hands']) {
                    $distance = Get-GodotVectorDistanceSquared $hand['origin'] $sample['render_ball_position']
                    if ($distance -lt 0.063 * 0.063 -or $distance -gt 0.165 * 0.165) { throw 'Native keeper hands miss the real rendered ball.' }
                }
            }
            else {
                Assert-GpInteger $sample['event_id'] 'accepted native gesture event' 0
                Assert-GpInteger $sample['accepted_tick'] 'accepted native gesture tick' 1
                foreach ($field in @('at_contact', 'advanced')) {
                    Assert-GpPose $sample[$field] '/root/Match'
                    if ($sample[$field]['contact_tick'] -ne $sample['accepted_tick']) { throw 'Native gesture age differs from its accepted event.' }
                }
                $before = $sample['at_contact']; $after = $sample['advanced']
                if ($after['actor_id'] -ne $before['actor_id'] -or $after['gesture_kind'] -ne $before['gesture_kind'] -or
                    $after['context_tick'] -le $before['context_tick'] -or $after['render_tick'] -le $before['render_tick'] -or
                    $after['gesture_progress'] -le $before['gesture_progress'] -or
                    (($before['feet'] | ConvertTo-Json -Compress -Depth 16) -ceq ($after['feet'] | ConvertTo-Json -Compress -Depth 16) -and
                        ($before['hands'] | ConvertTo-Json -Compress -Depth 16) -ceq ($after['hands'] | ConvertTo-Json -Compress -Depth 16))) {
                    throw 'Native host athlete pose did not actually progress after accepted contact.'
                }
            }
        }
    }
}

function Assert-GodotNativeGameplayRefusals($Report) {
    $expected = @()
    foreach ($mode in @(0, 1)) {
        $prefix = "G09/G22 m$mode sexta acumulada"
        $expected += @{case = "${prefix}: secuencia repetida"; id = 0; code = 31; message = 'Sequence must increase per actor within [0, 2147483647]'}
        $expected += @{case = "${prefix}: pase prohibido en READY"; id = 0; code = 4; message = 'Launch refused: launch_rule'}
    }
    foreach ($field in @('command_refusals', 'expected_command_refusals')) {
        if ($Report[$field].Count -ne $expected.Count) { throw 'Native gameplay requires exactly its observed sequence/READY refusals in both modes.' }
        for ($index = 0; $index -lt $expected.Count; $index++) {
            $row = $Report[$field][$index]
            if ($row -isnot [Collections.IDictionary]) { throw 'Malformed native gameplay refusal.' }
            foreach ($key in @('id', 'code')) { Assert-GpInteger $row[$key] "refusal $key" $expected[$index][$key] $expected[$index][$key] }
            if ($row['message'] -cne $expected[$index].message -or
                ($field -ceq 'expected_command_refusals' -and $row['case'] -cne $expected[$index].case)) {
                throw 'Native gameplay refusal differs from the actual actor/code/message/case.'
            }
            Assert-GodotNativeCheck $Report $expected[$index].case
        }
    }
    foreach ($mode in @(0, 1)) {
        $prefix = "G09/G22 m$mode sexta acumulada"
        Assert-GodotNativeCheck $Report "${prefix}: rechazo real de autoridad: aviso producido por la ruta real es visible"
        Assert-GodotNativeCheck $Report "${prefix}: mostrar el rechazo no pausa ni renueva cuatro segundos"
    }
}

function Assert-GodotNativeBroadcastFraming($Report) {
    $caseIds = @('broadcast-framing/0', 'broadcast-framing/1')
    $records = @()
    foreach ($sample in $Report['camera_samples']) {
        if ($sample -isnot [Collections.IDictionary] -or $sample['case'] -isnot [string]) {
            throw 'Native camera samples require a typed record and case identity.'
        }
        if ($sample['case'].StartsWith('broadcast-framing', [StringComparison]::Ordinal)) { $records += $sample }
    }
    if ($records.Count -ne 16) { throw 'Broadcast framing requires eight actual observations in each of the two modes.' }
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($caseId in $caseIds) {
        foreach ($end in @(-1, 1)) {
            foreach ($side in @(-1, 1)) {
                foreach ($selected in @(0, 2)) { [void]$expected.Add("$caseId/$end/$side/$selected") }
            }
        }
        Assert-GodotNativeCheck $Report "$caseId no modifica actores ni estado del partido real"
    }
    foreach ($sample in $records) {
        $caseId = $sample['case']
        if ($caseId -cnotin $caseIds) { throw 'Unknown native broadcast-framing mode or case.' }
        $mode = if ($caseId -ceq 'broadcast-framing/0') { 0 } else { 1 }
        foreach ($field in @('end', 'side')) {
            Assert-GpNumber $sample[$field] "broadcast $field" -1 1
            if ($sample[$field] -notin @(-1.0, 1.0)) { throw 'Broadcast framing must exercise both actual ends and sides.' }
        }
        Assert-GpInteger $sample['selected_actor_id'] 'broadcast selected actor' 0 2
        $selected = $sample['selected_actor_id']
        if ($selected -notin @(0, 2)) { throw 'Broadcast framing must cover field player zero and goalkeeper two.' }
        $end = [int]$sample['end']; $side = [int]$sample['side']
        if (-not $expected.Remove("$caseId/$end/$side/$selected")) {
            throw 'Duplicated broadcast observation cannot replace a missing end/side/focus combination.'
        }
        # Eight vertices per box: micro frames only the selected actor; preview frames all ten.
        $points = if ($mode -eq 0) { 16 } else { 88 }
        Assert-GpInteger $sample['tested_points'] 'broadcast tested bounding-box points' $points $points
        Assert-GpInteger $sample['outside_count'] 'broadcast clipped points' 0 0
        $label = "$caseId extremo=$end banda=$side foco=$selected"
        Assert-GodotNativeCheck $Report "$label conserva la orientación fija usada para calcular el encuadre"
        Assert-GodotNativeCheck $Report "$label no recorta extremos de atletas ni esfera del balón"
        $camera = $sample['camera']
        if ($camera -isnot [Collections.IDictionary] -or $camera['mode'] -isnot [string] -or $camera['mode'] -cne 'broadcast') {
            throw 'Native broadcast-framing evidence must use the production broadcast context.'
        }
        Assert-GpInteger $camera['tick'] 'broadcast camera tick' 0
        Assert-GpNumber $camera['fov'] 'broadcast camera FOV' 46 60
        $ball = @(($end * 19.85), 0.105, ($side * 8.0))
        Assert-GpCameraTracking $camera $ball
        if ([Math]::Abs($camera['rotation'][2]) -gt 0.0001) { throw 'Broadcast camera has an unexpected roll.' }
        $axes = Get-GpCameraAxes $camera
        # Reviewed production OFFSET/PREVIEW_OFFSET, not an axis inferred from this report.
        $offset = if ($mode -eq 0) { @(0.0, 17.0, 23.0) } else { @(0.0, 18.0, 25.0) }
        $length = Get-GpLength $offset
        $back = @(0.0, ($offset[1] / $length), ($offset[2] / $length))
        if ((Get-GpDot $axes.right @(1.0, 0.0, 0.0)) -le 0.999999 -or
            (Get-GpDot $axes.back $back) -le 0.999999) {
            throw 'Broadcast pose rotated away from the fixed production framing basis.'
        }
        # The report contains point counts, not athlete vertices. Require their native checks above;
        # independently project the eight known ball bounds without inventing actor coordinates.
        foreach ($x in @(-0.105, 0.105)) {
            foreach ($y in @(-0.105, 0.105)) {
                foreach ($z in @(-0.105, 0.105)) {
                    $delta = @(($ball[0] + $x - $camera['position'][0]), ($ball[1] + $y - $camera['position'][1]),
                        ($ball[2] + $z - $camera['position'][2]))
                    $depth = -(Get-GpDot $delta $axes.back)
                    if ($depth -le 0.0) { throw 'Broadcast ball bounds lie behind the reported camera.' }
                    $half = [Math]::Tan($camera['fov'] * [Math]::PI / 360.0) * $depth
                    $px = 0.5 + (Get-GpDot $delta $axes.right) / (2.0 * $half * 1920.0 / 1080.0)
                    $py = 0.5 - (Get-GpDot $delta $axes.up) / (2.0 * $half)
                    if ($px -lt 0.0 -or $px -gt 1.0 -or $py -lt 0.0 -or $py -gt 1.0) {
                        throw 'Broadcast zero outside_count contradicts the projected full ball bounds.'
                    }
                }
            }
        }
    }
    if ($expected.Count -ne 0) { throw 'Incomplete native broadcast-framing combinations.' }
}

function Assert-GodotNativeCameraTraces($Report) {
    $traceIds = @(Get-GodotNativeHostCases 'camera' | Where-Object { $_.StartsWith('trace/') })
    if ($Report['trace_coverage'].Count -ne $traceIds.Count) { throw 'Camera omitted a mode/corner/pass-or-shot trace.' }
    $expectedSamples = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($id in $traceIds) {
        $trace = $Report['trace_coverage'][$id]
        if ($trace -isnot [Collections.IDictionary]) { throw 'Missing native camera trace.' }
        $mode = [int]$id.Split('/')[1]
        Assert-GodotIntegerList $trace['ready_actor_ids'] $(if ($mode -eq 0) { @(0..3) } else { @(0..9) }) 'Ready native actors'
        Assert-GpInteger $trace['receiver_id'] 'camera trace actual receiver' 0 $(if ($mode -eq 0) { 3 } else { 9 })
        if ($trace['receiver_id'] % 2 -ne 0) { throw 'Camera trace receiver is not HOME.' }
        foreach ($pair in @(@('entry', 60), @('return', 46))) {
            if ($trace[$pair[0] + '_ticks'] -isnot [Collections.IList]) { throw 'Camera ticks require an actual typed array.' }
            Assert-GodotIntegerList $trace[$pair[0] + '_ticks'] @(0..$pair[1]) 'Complete native camera ticks'
            foreach ($tick in 0..$pair[1]) { [void]$expectedSamples.Add("$id/$($pair[0])/$tick") }
        }
    }
    if ($Report['transition_samples'].Count -ne $expectedSamples.Count) { throw 'Missing or extra native per-tick camera samples.' }
    foreach ($sample in $Report['transition_samples']) {
        if ($sample -isnot [Collections.IDictionary] -or $sample['case'] -cnotin $traceIds -or
            $sample['direction'] -cnotin @('entry', 'return')) { throw 'Unrecognized native camera transition sample.' }
        Assert-GpInteger $sample['elapsed'] 'native camera elapsed tick' 0 60
        if (-not $expectedSamples.Remove("$($sample['case'])/$($sample['direction'])/$($sample['elapsed'])")) {
            throw 'Duplicated or unexpected native camera sample.'
        }
        Assert-GpBoolean $sample['behind'] 'native camera ball behind' $false
        Assert-GpBoolean $sample['sphere_in_frame'] 'native camera sphere visible' $true
        Assert-GodotNativeEmpty $sample @('blockers')
        Assert-GpNumber $sample['travel'] 'native camera travel' 0 3.49999999
        Assert-GpNumber $sample['turn_radians'] 'native camera turn' 0 0.34999999
        $camera = $sample['camera']
        if ($camera -isnot [Collections.IDictionary]) { throw 'Missing actual native camera pose.' }
        foreach ($field in @('position', 'rotation')) { Assert-GodotFiniteVector $camera[$field] "native camera $field" }
        if ([Math]::Abs($camera['rotation'][2]) -gt 0.0001) { throw 'Native trace camera has an unexpected roll.' }
        Assert-GodotFiniteVector $sample['ball'] 'native trace ball'
        Assert-GpCameraTracking $camera $sample['ball']
        Assert-GpNumber $camera['fov'] 'native camera FOV' 46 60
        $tick = $sample['elapsed'] + $(if ($sample['direction'] -ceq 'return') { 61 } else { 0 })
        Assert-GpInteger $camera['tick'] 'native camera authority tick' $tick $tick
        $axes = Get-GpCameraAxes $camera
        $delta = @(($sample['ball'][0] - $camera['position'][0]), ($sample['ball'][1] - $camera['position'][1]), ($sample['ball'][2] - $camera['position'][2]))
        $depth = -(Get-GpDot $delta $axes.back)
        if ($depth -le 0.1) { throw 'Camera sample claims a visible ball actually behind its near plane.' }
        $half = [Math]::Tan($camera['fov'] * [Math]::PI / 360.0) * $depth
        $screen = @((0.5 + (Get-GpDot $delta $axes.right) / (2.0 * $half * 1920.0 / 1080.0)),
            (0.5 - (Get-GpDot $delta $axes.up) / (2.0 * $half)))
        if ($sample['screen'] -isnot [Collections.IList] -or $sample['screen'].Count -ne 2) { throw 'Camera omitted its actual normalized native projection.' }
        foreach ($index in @(0, 1)) {
            Assert-GpNumber $sample['screen'][$index] 'native normalized coordinate' 0 1
            if ([Math]::Abs($sample['screen'][$index] - $screen[$index]) -gt 0.0001) { throw 'Native screen position disagrees with actual camera depth/pose.' }
        }
        foreach ($x in @(-0.105, 0.105)) {
            foreach ($y in @(-0.105, 0.105)) {
                foreach ($z in @(-0.105, 0.105)) {
                    $point = @(($delta[0] + $x), ($delta[1] + $y), ($delta[2] + $z))
                    $pointDepth = -(Get-GpDot $point $axes.back)
                    if ($pointDepth -le 0.1) { throw 'Native ball bounds intersect the camera near plane.' }
                    $pointHalf = [Math]::Tan($camera['fov'] * [Math]::PI / 360.0) * $pointDepth
                    $px = 0.5 + (Get-GpDot $point $axes.right) / (2.0 * $pointHalf * 1920.0 / 1080.0)
                    $py = 0.5 - (Get-GpDot $point $axes.up) / (2.0 * $pointHalf)
                    if ($px -lt 0.035 -or $px -gt 0.965 -or $py -lt 0.12 -or $py -gt 0.88) {
                        throw 'Native sphere-in-frame flag disagrees with its full world-space ball bounds.'
                    }
                }
            }
        }
    }
}

function Read-GodotGameplayNativeReport {
    param($Result, [ValidateSet('ai-tactics', 'rules', 'gameplay-rules', 'camera', 'gameplay-runtime', 'aim-guide')][string]$Stage,
        [string]$Source, [Collections.IDictionary]$Diagnostics)
    $prefix = Get-GodotNativeReportPrefix $Source
    $prefixes = @{
        'ai-tactics' = 'FUTSAL_MATCH_AI_TACTICS_TESTS'; rules = 'FUTSAL_MATCH_RULES_TESTS'
        'gameplay-rules' = 'FUTSAL_GAMEPLAY_RULES_TESTS'; camera = 'FUTSAL_MATCH_CAMERA_TESTS'
        'gameplay-runtime' = 'FUTSAL_MATCH_GAMEPLAY_RUNTIME_TESTS'; 'aim-guide' = 'FUTSAL_AIM_GUIDE_TESTS'
    }
    if ($prefix -cne $prefixes[$Stage]) { throw 'Native stage source marker changed from its declared protocol.' }
    $report = ConvertFrom-GodotStructuredReport $Result $prefix -RequireChecks
    Assert-GodotOutput $Result -ExpectedAimGuideErrors $Diagnostics['aimGuideErrors'] -ExpectedDevelopmentWarnings $Diagnostics['developmentWarnings']
    Assert-GodotNativeEmpty $report @('failures')
    if ($Stage -cin @('camera', 'gameplay-runtime')) {
        # Both inherit test_match_integration._check: all checks are serialized,
        # but only failures are printed separately. Do not fabricate PASS lines.
        if ($Result.Stdout -match '(?m)^(?:PASS|FAIL) ') {
            throw 'Host native suites require their actual structured-only success protocol and no printed failure.'
        }
    }
    else { Assert-GodotNativePrintedChecks $Result $report }
    if ($report.Contains('wall_seconds')) { Assert-GpNumber $report['wall_seconds'] 'native suite wall time' 0 180 }
    if ($Stage -cne 'aim-guide') {
        Assert-GpBoolean $report['headless'] 'native headless' $true
        if ($report['engine'] -cne '4.7.2-stable (official)') { throw 'Native gameplay suite used the wrong engine.' }
        if ($Stage -cne 'gameplay-rules') { Assert-GpBoolean $report['complete'] 'native complete' $true }
    }
    if ($Stage -cin @('ai-tactics', 'rules')) {
        Assert-GodotGameplayComponentReport $report
        Assert-GodotNativeClassification $report
        Assert-GpInteger $report['process_id'] 'native process identity' 1
        if ($Stage -ceq 'rules') {
            if ($report['scope'] -cne 'pure-match-rules-contract') { throw 'Incorrect pure-rules scope.' }
            Assert-GpBoolean $report['physical_episode_collection_tested'] 'classification is not physical evidence' $false
            Assert-GodotNativeRuleGroups $report $Source
        }
        else {
            if ($report['production_entrypoint'] -cne 'MatchAI.decide' -or $report['scope'] -cne 'playing-and-restart-ai-policy-with-caller-filter') {
                throw 'AI report did not exercise its actual production policy/caller.'
            }
            Assert-GpBoolean $report['authority_guard_tested'] 'policy is not authority guard evidence' $false
            Assert-GpInteger $report['observed_refusals'] 'AI actual refusals' 0 0
            Assert-GpInteger $report['policy_decisions'] 'actual policy observations' 1
            foreach ($pair in @(@('EXPECTED_CHECKS', 'total'), @('EXPECTED_NEGATIVE_CASES', 'negative_cases'))) {
                $match = [regex]::Match($Source, '(?m)^const ' + $pair[0] + ': int = ([0-9]+)\r?$')
                if (-not $match.Success -or $report[$pair[1]] -ne [int]$match.Groups[1].Value) { throw 'AI finite source matrix changed or was not completed.' }
            }
            foreach ($name in @('native_headless_jolt_sixty_hz_environment', 'production_caller_reports_zero_unexpected_command_refusals',
                    'report_semantic_check_names_are_unique', 'report_negative_case_count_matches_contract', 'report_semantic_case_count_matches_contract')) {
                Assert-GodotNativeCheck $report $name
            }
        }
    }
    elseif ($Stage -ceq 'gameplay-rules') {
        Assert-GodotGameplayAuthorityCompletion $report $Source
        Assert-GodotGameplayAuthorityRefusals $report
        Assert-GodotGameplayAuthorityScenarios $report
        Assert-GodotGameplayHomeDribbleCoverage $report $Source
        Assert-GodotNativeCheck $report 'completion/every refusal matches an exact actor/code/message expectation'
    }
    elseif ($Stage -ceq 'aim-guide') {
        $messages = $Diagnostics['aimGuideErrors']
        if ($messages.Count -ne 1) { throw 'Aim guide requires its reviewed exact diagnostics.' }
        $message = @($messages.Keys)[0].Substring(7)
        $count = $messages[@($messages.Keys)[0]]
        Assert-GpInteger $report['expected_validation_errors'] 'aim-guide validation count' $count $count
        if ($report['new_expected_error_counts'] -isnot [Collections.IDictionary] -or $report['new_expected_error_counts'].Count -ne 1 -or
            $message -cnotin $report['new_expected_error_counts'].Keys) { throw 'Aim-guide message accounting changed.' }
        Assert-GpInteger $report['new_expected_error_counts'][$message] 'aim-guide observed diagnostics' $count $count
        foreach ($case in Get-GodotAimGuideNegativeCases) { Assert-GodotNativeCheck $report "invalid $case hides every stale arrow" }
        Assert-GodotNativeCheck $report 'aim guide suite reached completion'
    }
    else { Assert-GodotNativeHostReport $report $Stage }
    if ($Stage -cin @('ai-tactics', 'gameplay-rules')) {
        if ($report['physics'] -cne 'Jolt Physics') { throw 'Native suite requires actual Jolt physics.' }
        Assert-GpInteger $report['physics_hz'] 'native physics rate' 60 60
    }
    return $report
}
