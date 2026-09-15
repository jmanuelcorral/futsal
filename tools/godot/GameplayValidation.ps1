#Requires -Version 7.2
Set-StrictMode -Version Latest

function Get-GodotGameplayContract {
    return Get-Content -LiteralPath (Join-Path $PSScriptRoot 'gameplay-contract.json') -Raw -Encoding utf8 |
        ConvertFrom-Json -AsHashtable -Depth 16
}

function Get-GodotGameplayStages([string]$Root, $Contract = (Get-GodotGameplayContract)) {
    $stages = [ordered]@{}
    foreach ($name in $Contract['requiredNativeTests'].Keys) { $stages[$name] = $Contract['requiredNativeTests'][$name] }
    foreach ($name in $Contract['requiredWhenPresent'].Keys) {
        if (Test-Path -LiteralPath (Join-Path $Root $Contract['requiredWhenPresent'][$name]) -PathType Leaf) {
            $stages[$name] = $Contract['requiredWhenPresent'][$name]
        }
    }
    return $stages
}

function Get-GodotGameplayNativeArguments {
    param(
        [Parameter(Mandatory)][ValidateSet('ai-tactics', 'rules', 'gameplay-rules', 'camera', 'gameplay-runtime', 'aim-guide', 'gestures')][string]$Stage,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    if (-not [IO.Path]::IsPathFullyQualified($Project) -or -not [IO.Path]::IsPathFullyQualified($ScriptPath)) {
        throw 'Native gameplay arguments require resolved project and script paths.'
    }
    $relative = (Get-GodotGameplayContract)['requiredNativeTests'][$Stage]
    $expected = Join-Path $Project ('tests\' + [IO.Path]::GetFileName($relative))
    if (-not [IO.Path]::GetFullPath($ScriptPath).Equals([IO.Path]::GetFullPath($expected), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Native stage identity disagrees with its source-defined suite script.'
    }
    $arguments = @('--headless', '--path', $Project, '--audio-driver', 'Dummy')
    if ($Stage -ceq 'gameplay-rules') { $arguments += @('--fixed-fps', '60') }
    return $arguments + @('--script', $ScriptPath)
}

function Test-GodotNativeChecksRequired([string]$Stage, $Contract = (Get-GodotGameplayContract)) {
    return $Stage -cnotin $Contract['legacyChecksOptionalStages']
}

function Assert-GodotGameplayContractBinding([string]$Root, $Contract = (Get-GodotGameplayContract)) {
    $text = [IO.File]::ReadAllText((Join-Path $Root $Contract['repositoryPlan']))
    $start = $text.IndexOf('### 4.3. Iteración de jugabilidad 0.4', [StringComparison]::Ordinal)
    if ($start -lt 0) { throw 'Canonical gameplay contract section is missing.' }
    $end = $text.IndexOf('## 5. Criterios de salida por gate', $start, [StringComparison]::Ordinal)
    if ($end -le $start) { throw 'Canonical gameplay contract section is incomplete.' }
    $section = $text.Substring($start, $end - $start).Replace("`r`n", "`n").Trim()
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($section))).ToLowerInvariant()
    if ($Contract['canonicalSectionSha256'] -isnot [string] -or $hash -cne $Contract['canonicalSectionSha256']) {
        throw 'Canonical gameplay contract changed; review its binding overrides before accepting reports.'
    }
    if (-not $section.Contains('| `RestartState`: contacto del lanzamiento | `launch_contact_id: int = -1` |') -or
        -not $section.Contains('`RestartState.launch_contact_id: int = -1`') -or
        $Contract['acceptedRuleOverrides']['originalLaunchEpisodeField'] -cne 'RestartState.launch_contact_id' -or
        $Contract['acceptedRuleOverrides']['secondTouchUsesEpisodeIdentityNotTickGrace'] -isnot [bool] -or
        -not $Contract['acceptedRuleOverrides']['secondTouchUsesEpisodeIdentityNotTickGrace']) {
        throw 'The accepted second-touch contract requires physical episode identity, not a time-grace surrogate.'
    }
    $criteria = [regex]::Matches($section, '(?m)^\| (G\d{2}) \| (.+) \|$')
    if ($criteria.Count -ne 32 -or $Contract['acceptanceCriteria'] -isnot [Collections.IDictionary] -or
        $Contract['acceptanceCriteria'].Count -ne 32 -or $Contract['acceptanceIds'] -isnot [Collections.IList] -or
        $Contract['acceptanceIds'].Count -ne 32 -or @($Contract['acceptanceIds'] | Sort-Object -Unique).Count -ne 32) {
        throw 'Canonical acceptance requires all thirty-two distinct criteria, not labels alone.'
    }
    foreach ($criterion in $criteria) {
        $id = $criterion.Groups[1].Value
        if ($id -cnotin $Contract['acceptanceIds'] -or
            $Contract['acceptanceCriteria'][$id] -cne $criterion.Groups[2].Value) {
            throw "Gameplay criterion $id disagrees with the canonical contract."
        }
    }
    $exercises = [regex]::Matches($section, '(?m)^\| `([A-Z][A-Z0-9_]+)` \| (\d+) \|$')
    if ($exercises.Count -ne 12 -or $Contract['trainingExercises'] -isnot [Collections.IDictionary] -or
        $Contract['trainingExercises'].Count -ne 12) { throw 'Require the twelve production training exercise enum values.' }
    foreach ($exercise in $exercises) {
        $value = $Contract['trainingExercises'][$exercise.Groups[1].Value]
        if (-not (Test-GodotGameplayInteger $value) -or $value -ne [int]$exercise.Groups[2].Value) {
            throw "Gameplay exercise $($exercise.Groups[1].Value) disagrees with the canonical enum."
        }
    }
    $tuningRows = [regex]::Matches($section,
        '(?m)^\| `(foul_[a-z_]+): (int|float)` \| ([0-9.]+) [^|]+\| ([0-9.]+)–([0-9.]+) [^|]+\|$')
    if ($tuningRows.Count -ne 3 -or $Contract['foulTuning'] -isnot [Collections.IDictionary] -or
        $Contract['foulTuning'].Count -ne 3) { throw 'Require the three canonical foul-tuning declarations.' }
    foreach ($row in $tuningRows) {
        $name = $row.Groups[1].Value
        $rule = $Contract['foulTuning'][$name]
        if ($rule -isnot [Collections.IDictionary] -or $rule['type'] -cne $row.Groups[2].Value) {
            throw "Foul tuning $name disagrees with its canonical type."
        }
        $index = 3
        foreach ($field in @('initial', 'minimum', 'maximum')) {
            $value = [double]::Parse($row.Groups[$index].Value, [Globalization.CultureInfo]::InvariantCulture)
            if (-not (Test-GodotGameplayFiniteNumber $rule[$field]) -or $rule[$field] -ne $value) {
                throw "Foul tuning $name $field disagrees with the canonical declaration."
            }
            $index++
        }
    }
}

function Get-GodotGameplayRuntimeDependencies($Contract = (Get-GodotGameplayContract)) {
    $dependencies = [Collections.Generic.List[string]]::new()
    try { Assert-GodotGameplayContractBinding ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) $Contract }
    catch { $dependencies.Add("Canonical G01-G32 binding: $($_.Exception.Message)") }
    if ($Contract['runtimeCliFlag'] -cne '--gameplay-smoke' -or $Contract['runtimeReportPrefix'] -cne 'FUTSAL_GAMEPLAY_SMOKE') {
        $dependencies.Add('Gameplay CLI/marker must match the real --gameplay-smoke producer.')
    }
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    foreach ($path in @('game\diagnostics\gameplay_smoke.gd', 'game\diagnostics\match_smoke.gd',
            'tools\godot\GameplayRuntimeValidation.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf)) { $dependencies.Add("Missing runtime source: $path") }
    }
    $driver = Join-Path $root 'game\diagnostics\gameplay_smoke.gd'
    if (Test-Path -LiteralPath $driver -PathType Leaf) {
        $source = [IO.File]::ReadAllText($driver)
        foreach ($literal in @('extends "res://diagnostics/match_smoke.gd"', 'has("--gameplay-smoke")',
                'return "FUTSAL_GAMEPLAY_SMOKE"', '"-gameplay-captures"', '"athlete_presentations"', '"visible_home_options"')) {
            if (-not $source.Contains($literal)) { $dependencies.Add("Runtime producer contract changed: $literal") }
        }
    }
    return $dependencies.ToArray()
}

function Assert-GodotGameplayComponentReport([System.Collections.IDictionary]$Report) {
    if ($Report['failures'] -isnot [Collections.IList] -or $Report['failures'].Count -ne 0) {
        throw 'New gameplay suites require an explicit empty failure array.'
    }
    if ($Report.Contains('complete') -and ($Report['complete'] -isnot [bool] -or -not $Report['complete'])) {
        throw 'Gameplay suite did not complete.'
    }
    foreach ($field in @('errors', 'integration_errors', 'unexpected_integration_errors', 'unexpected_command_refusals')) {
        if ($Report.Contains($field) -and ($Report[$field] -isnot [Collections.IList] -or $Report[$field].Count -ne 0)) {
            throw "Unexpected or malformed gameplay $field."
        }
    }
    if ($Report.Contains('command_refusals') -and
        ($Report['command_refusals'] -isnot [Collections.IList] -or $Report['command_refusals'].Count -ne 0)) {
        throw 'Exact producer-defined command refusal accounting pending; no generic allowance.'
    }
    foreach ($field in @('expected_refusals', 'expected_validation_errors')) {
        if ($Report.Contains($field) -and
            (($Report[$field] -isnot [long] -and $Report[$field] -isnot [int]) -or $Report[$field] -ne 0)) {
            throw "Exact producer-defined negative-case accounting pending for $field; no generic allowance."
        }
    }
}

function Get-GodotGestureExpectedErrors([string]$TestSource, [string]$AthleteSource) {
    $policy = Get-GodotPresentationDiagnosticContract
    if ((Get-GodotNativeReportPrefix $TestSource) -cne 'FUTSAL_GESTURE_TESTS') {
        throw 'The gesture suite must emit its actual FUTSAL_GESTURE_TESTS marker.'
    }
    $prefixes = [regex]::Matches($AthleteSource, '(?m)^const PRESENTATION_ERROR: String = "([^"\r\n]+)"\r?$')
    if ($prefixes.Count -ne 1 -or $prefixes[0].Groups[1].Value -cne $policy.prefix) {
        throw 'Athlete presentation diagnostic prefix changed; review the exact producer contract.'
    }
    $counts = [ordered]@{}
    foreach ($call in [regex]::Matches($TestSource, '(?m)^[ \t]*_expect_error\("([a-z_]+)",')) {
        $reason = $call.Groups[1].Value
        if ($reason -cnotin $policy.minimumCases.Keys) { throw "Unreviewed gesture diagnostic reason: $reason" }
        $message = 'ERROR: ' + $policy.prefix + $reason
        if (-not $counts.Contains($message)) { $counts[$message] = 0 }
        $counts[$message]++
    }
    foreach ($reason in $policy.minimumCases.Keys) {
        $message = 'ERROR: ' + $policy.prefix + $reason
        if (-not $counts.Contains($message) -or $counts[$message] -lt $policy.minimumCases[$reason]) {
            throw "Required native gesture negative cases missing: $reason"
        }
    }
    return $counts
}

function Get-GodotPresentationCompletionChecks([string]$Stage) {
    if ($Stage -ceq 'gestures') {
        return @(
            'Escenarios de gestos completados'
            'Identificadores de comprobación de gestos únicos'
            'Errores intencionales medidos coinciden exactamente con casos negativos'
            'Sin errores nativos inesperados ni errores de script o shader'
        )
    }
    if ($Stage -ceq 'visual-native') {
        return @(
            'Escenarios de marca dinámica completados'
            'Escenarios de áreas y postes completados'
            'Identificadores de comprobación visual únicos'
            'Sin errores nativos inesperados en la prueba visual'
        )
    }
    throw "Unknown presentation stage: $Stage"
}

function Read-GodotPresentationReport {
    param($Result, [ValidateSet('gestures', 'visual-native')][string]$Stage,
        [System.Collections.IDictionary]$ExpectedPresentationErrors = @{}, [switch]$AllowKnownVulkanLayerWarning)
    $contract = Get-GodotGameplayContract
    $report = ConvertFrom-GodotStructuredReport $Result $contract['presentationReportPrefixes'][$Stage] -RequireChecks
    # Logger starts at _initialize; independent raw output validation still catches earlier failures.
    Assert-GodotOutput $Result -ExpectedPresentationErrors $ExpectedPresentationErrors `
        -AllowKnownVulkanLayerWarning:$AllowKnownVulkanLayerWarning
    Assert-GodotGameplayComponentReport $report
    if ($report['duplicate_checks'] -isnot [Collections.IList] -or $report['duplicate_checks'].Count -ne 0 -or
        $report['headless'] -isnot [bool] -or $report['native_errors'] -isnot [Collections.IDictionary]) {
        throw 'Presentation report needs complete typed duplicate/logger/context evidence.'
    }
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($check in $report['checks']) { [void]$names.Add($check['name']) }
    foreach ($name in Get-GodotPresentationCompletionChecks $Stage) {
        if (-not $names.Contains($name)) { throw "Presentation completion evidence missing: $name" }
    }
    $policy = Get-GodotPresentationDiagnosticContract
    $expected = [ordered]@{}
    foreach ($message in $ExpectedPresentationErrors.Keys) { $expected[$message.Substring(7)] = $ExpectedPresentationErrors[$message] }
    if ($Stage -ceq 'visual-native' -and $expected.Count -ne 0) { throw 'Visual regression has no expected native errors.' }
    if ($Stage -ceq 'gestures') {
        foreach ($reason in $policy.minimumCases.Keys) {
            $message = $policy.prefix + $reason
            if (-not $expected.Contains($message) -or $expected[$message] -lt $policy.minimumCases[$reason]) {
                throw "Expected gesture source evidence missing: $reason"
            }
            for ($occurrence = 1; $occurrence -le $expected[$message]; $occurrence++) {
                foreach ($name in @("Rechazo explícito $reason caso=$occurrence", "Sin pose alternativa silenciosa tras $reason caso=$occurrence")) {
                    if (-not $names.Contains($name)) { throw "Native negative-case observation missing: $name" }
                }
            }
        }
        foreach ($field in @('expected_error_counts', 'observed_expected_error_counts')) {
            $counts = $report[$field]
            if ($counts -isnot [Collections.IDictionary] -or $counts.Count -ne $expected.Count) {
                throw "Gesture $field does not match the source-declared negative cases."
            }
            foreach ($message in $expected.Keys) {
                if ($message -cnotin $counts.Keys -or -not (Test-GodotGameplayInteger $counts[$message]) -or
                    $counts[$message] -ne $expected[$message]) { throw "Incorrect gesture $field for $message" }
            }
        }
        if ($report['unexpected_errors'] -isnot [Collections.IList] -or $report['unexpected_errors'].Count -ne 0) {
            throw 'Unexpected gesture logger entries are not permitted.'
        }
    }
    elseif ($report.Contains('expected_error_counts') -or $report.Contains('observed_expected_error_counts')) {
        throw 'Visual regression cannot declare new diagnostic allowances.'
    }
    if ($report.Contains('unexpected_errors') -and
        ($report['unexpected_errors'] -isnot [Collections.IList] -or $report['unexpected_errors'].Count -ne 0)) {
        throw 'Unexpected presentation errors are not permitted.'
    }
    $native = $report['native_errors']
    $total = 0
    foreach ($count in $expected.Values) { $total += $count }
    foreach ($field in @('error_count', 'script_error_count', 'shader_error_count', 'warning_count')) {
        $count = $native[$field]
        $wanted = if ($field -ceq 'error_count') { $total } else { 0 }
        if (-not (Test-GodotGameplayInteger $count) -or $count -ne $wanted) {
            throw "Unexpected or malformed presentation $field."
        }
    }
    if ($native['entries'] -isnot [Collections.IList] -or $native['entries'].Count -ne $total) {
        throw 'Native logger entries and actual diagnostic counters disagree.'
    }
    $observed = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    foreach ($entry in $native['entries']) {
        if ($entry -isnot [Collections.IDictionary] -or -not (Test-GodotGameplayInteger $entry['type']) -or
            $entry['type'] -ne 0 -or -not (Test-GodotGameplayInteger $entry['line']) -or $entry['line'] -lt 0) {
            throw 'Only actual normal-error Logger entries may represent deliberate presentation rejections.'
        }
        foreach ($field in @('function', 'file', 'code', 'rationale')) {
            if ($entry[$field] -isnot [string]) { throw "Malformed native Logger entry $field." }
        }
        $message = if ([string]::IsNullOrEmpty($entry['rationale'])) { $entry['code'] } else { $entry['rationale'] }
        if ($message -cnotin $expected.Keys) { throw "Unexpected presentation Logger message: $message" }
        if (-not $observed.ContainsKey($message)) { $observed[$message] = 0 }
        $observed[$message]++
    }
    foreach ($message in $expected.Keys) {
        if (-not $observed.ContainsKey($message) -or $observed[$message] -ne $expected[$message]) {
            throw "Actual Logger entries do not support the expected rejection count for $message"
        }
    }
    return $report
}

function Test-GodotGameplayInteger($Value) {
    return ($Value -is [int] -or $Value -is [long])
}

function Test-GodotGameplayFiniteNumber($Value) {
    return (($Value -is [int] -or $Value -is [long] -or $Value -is [single] -or
        $Value -is [double] -or $Value -is [decimal]) -and [double]::IsFinite([double]$Value))
}

# These consume canonical DTO fields after decoding, not an invented producer JSON envelope.
function Assert-GodotGameplayFoulTuning {
    param($Tuning, [switch]$RequireDefaults, $Contract = (Get-GodotGameplayContract))
    if ($Tuning -isnot [Collections.IDictionary] -or $Contract['foulTuning'] -isnot [Collections.IDictionary] -or
        $Contract['foulTuning'].Count -ne 3) { throw 'Foul tuning needs the canonical fields and declared limits.' }
    foreach ($field in @('foul_challenge_window_ticks', 'foul_min_closing_speed', 'foul_reckless_closing_speed')) {
        $rule = $Contract['foulTuning'][$field]
        if ($rule -isnot [Collections.IDictionary] -or $rule['type'] -cnotin @('int', 'float')) {
            throw "Missing or malformed foul-tuning declaration: $field."
        }
        $value = $Tuning[$field]
        if (-not (Test-GodotGameplayFiniteNumber $value) -or
            ($rule['type'] -ceq 'int' -and -not (Test-GodotGameplayInteger $value)) -or
            $value -lt $rule['minimum'] -or $value -gt $rule['maximum']) {
            throw "Invalid canonical foul tuning: $field."
        }
        if ($RequireDefaults -and $value -ne $rule['initial']) { throw "Default foul tuning changed: $field." }
    }
    if ($Tuning['foul_reckless_closing_speed'] -le $Tuning['foul_min_closing_speed']) {
        throw 'Reckless closing speed must be strictly greater than the minimum closing speed.'
    }
}

function Assert-GodotGameplayReadyRestartTiming($Restart, $PlacementStartedTick, $Tick) {
    if ($Restart -isnot [Collections.IDictionary] -or
        -not (Test-GodotGameplayInteger $PlacementStartedTick) -or -not (Test-GodotGameplayInteger $Tick)) {
        throw 'Restart timing needs a typed state and actual integer placement/observation ticks.'
    }
    foreach ($field in @('id', 'kind', 'stage', 'stage_started_tick', 'placement_end_tick', 'ready_tick', 'deadline_tick')) {
        if (-not (Test-GodotGameplayInteger $Restart[$field])) { throw "Restart timing requires integer $field." }
    }
    if ($Restart['id'] -le 0 -or $Restart['kind'] -notin 1..7 -or $Restart['stage'] -ne 3 -or
        $PlacementStartedTick -lt 0 -or $Restart['placement_end_tick'] -lt ($PlacementStartedTick + 60) -or
        $Restart['ready_tick'] -lt $Restart['placement_end_tick'] -or $Tick -lt $Restart['ready_tick'] -or
        $Restart['stage_started_tick'] -ne $Restart['ready_tick']) {
        throw 'READY must follow at least sixty actual placement ticks; global READY is not a restart stage.'
    }
    $deadline = if ($Restart['kind'] -eq 6) { -1 } else { $Restart['ready_tick'] + 240 }
    if ($Restart['deadline_tick'] -ne $deadline) { throw 'Only the 6m penalty has no four-second restart deadline.' }
}

function Assert-GodotGameplayRestartLaunchWindow($Restart, $Tick, $Executable) {
    if ($Restart -isnot [Collections.IDictionary] -or -not (Test-GodotGameplayInteger $Tick) -or
        $Executable -isnot [bool]) { throw 'Launch window requires typed restart, tick and executable evidence.' }
    foreach ($field in @('kind', 'stage', 'ready_tick', 'deadline_tick')) {
        if (-not (Test-GodotGameplayInteger $Restart[$field])) { throw "Launch window requires integer $field." }
    }
    if ($Restart['kind'] -notin 1..7 -or $Restart['stage'] -notin 1..4 -or $Tick -lt 0 -or
        ($Restart['stage'] -eq 3 -and $Restart['ready_tick'] -lt 0)) { throw 'Unknown restart kind/stage or invalid observed ready tick.' }
    if ($Executable -and ($Restart['stage'] -ne 3 -or $Tick -lt $Restart['ready_tick'] -or
        ($Restart['kind'] -eq 6 -and $Restart['deadline_tick'] -ne -1) -or
        ($Restart['kind'] -ne 6 -and ($Restart['deadline_tick'] -ne ($Restart['ready_tick'] + 240) -or
            $Tick -ge $Restart['deadline_tick'])))) {
        throw 'An accepted restart launch requires READY and tick strictly before its deadline; a penalty is exempt.'
    }
}

function Assert-GodotGameplayAccumulatedFoulDecision($Decision) {
    if ($Decision -isnot [Collections.IDictionary] -or
        -not (Test-GodotGameplayInteger $Decision['kind']) -or $Decision['kind'] -notin 0..3 -or
        -not (Test-GodotGameplayInteger $Decision['foul_verdict']) -or $Decision['foul_verdict'] -notin 0..3 -or
        $Decision['counts_as_accumulated_foul'] -isnot [bool] -or
        $Decision['restart'] -isnot [Collections.IDictionary] -or
        -not (Test-GodotGameplayInteger $Decision['restart']['kind']) -or $Decision['restart']['kind'] -notin 0..7) {
        throw 'Accumulated-foul evidence requires the typed canonical RuleDecision.'
    }
    $isFoul = $Decision['kind'] -eq 3
    if ($isFoul -and $Decision['foul_verdict'] -notin @(2, 3)) { throw 'A confirmed foul must be late or reckless, not clean/missing contact.' }
    $counts = $isFoul -and $Decision['restart']['kind'] -in @(4, 7)
    if ($Decision['counts_as_accumulated_foul'] -ne $counts) {
        throw 'Only confirmed accumulable direct fouls count; penalties, indirects and expiry do not.'
    }
}

function Get-GodotGameplayEvidencePaths {
    param([Parameter(Mandatory)][string]$RunPath,
        [Parameter(Mandatory)][ValidateSet('source-headless', 'source-rendered', 'artifact-headless', 'artifact-rendered')][string]$Stage)
    if (-not [IO.Path]::IsPathFullyQualified($RunPath)) { throw 'Gameplay evidence requires an absolute owned run directory.' }
    $directory = Join-Path ([IO.Path]::GetFullPath($RunPath)) "gameplay-$Stage"
    return [pscustomobject]@{
        Directory = $directory
        ReportPath = Join-Path $directory 'report.json'
        CaptureDirectory = Join-Path $directory 'report-gameplay-captures'
    }
}

. (Join-Path $PSScriptRoot 'GameplayRuntimeValidation.ps1')
. (Join-Path $PSScriptRoot 'GameplayNativeValidation.ps1')

function Get-GodotGameplayInvocation {
    param([Parameter(Mandatory)]$Paths,
        [Parameter(Mandatory)][ValidateSet('source-headless', 'source-rendered', 'artifact-headless', 'artifact-rendered')][string]$Stage,
        [Parameter(Mandatory)]$Installation, [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$Artifact, [ValidateRange(-1, 32)][int]$GpuIndex = -1)
    $headless = $Stage.EndsWith('-headless', [StringComparison]::Ordinal)
    $exported = $Stage.StartsWith('artifact-', [StringComparison]::Ordinal)
    foreach ($path in @($Paths.ReportPath, $Paths.Directory, $Project, $Artifact, $Installation.consolePath, $Installation.godotPath)) {
        if (-not [IO.Path]::IsPathFullyQualified($path)) { throw 'Gameplay invocation requires resolved absolute paths.' }
    }
    # Reproducción fija del diagnóstico de entrada; no mide FPS ni cambia el arranque normal.
    $arguments = @('--audio-driver', 'Dummy', '--fixed-fps', '60')
    if (-not $exported) { $arguments += @('--path', $Project) }
    if ($headless) { $arguments += '--headless' }
    else {
        $arguments += @('--windowed', '--resolution', '1920x1080', '--rendering-method', 'forward_plus',
            '--rendering-driver', 'vulkan', '--verbose')
        if ($GpuIndex -ge 0) { $arguments += @('--gpu-index', [string]$GpuIndex) }
    }
    $arguments += @('--', '--gameplay-smoke', "--report-path=$($Paths.ReportPath)")
    return [pscustomobject]@{
        Arguments = $arguments; Headless = $headless; EditorBinary = -not $exported
        Executable = $(if ($exported) { $Artifact } else { $Installation.consolePath })
        NativeExecutable = $(if ($exported) { $Artifact } else { $Installation.godotPath })
        ExpectedChild = $(if ($exported) { '' } else { $Installation.godotPath })
        WorkingDirectory = $(if ($exported) { [IO.Path]::GetDirectoryName($Artifact) } else { $Project })
    }
}

function Assert-GodotGameplayFreshPaths($Paths) {
    if (Test-Path -LiteralPath $Paths.Directory) {
        throw 'Gameplay invocation directory already exists; source/artifact or prior evidence must never be overwritten.'
    }
}

function Assert-GodotGameplayCaptureFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$CaptureDirectory,
        [Parameter(Mandatory)][datetime]$StartedAt, [Parameter(Mandatory)][string]$Sha256)
    if (-not [IO.Path]::IsPathFullyQualified($Path) -or -not [IO.Path]::IsPathFullyQualified($CaptureDirectory) -or
        $Sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Capture requires absolute paths and a lowercase SHA-256.' }
    $root = [IO.Path]::GetFullPath($CaptureDirectory).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetExtension($full) -ine '.png') { throw 'Capture escaped its owned invocation directory.' }
    $file = Get-Item -LiteralPath $full -ErrorAction Stop
    if ($file.PSIsContainer -or $file.Length -le 1024 -or $file.Length -gt 50000000 -or
        $file.LastWriteTimeUtc -lt $StartedAt.ToUniversalTime() -or
        $file.LastWriteTimeUtc -gt [DateTime]::UtcNow.AddSeconds(1)) { throw 'Missing, stale, future-dated or invalid-sized capture.' }
    $ancestor = $file
    while ($null -ne $ancestor) {
        if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Capture evidence may not traverse a link/reparse point.' }
        $ancestor = if ($ancestor -is [IO.FileInfo]) { $ancestor.Directory } else { $ancestor.Parent }
    }
    if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Sha256) {
        throw 'Capture bytes and reported SHA-256 disagree.'
    }
    Add-Type -AssemblyName System.Drawing
    $stream = [IO.File]::OpenRead($full)
    $image = $null
    try {
        $image = [Drawing.Image]::FromStream($stream, $false, $true)
        if ($image.Width -ne 1920 -or $image.Height -ne 1080 -or
            $image.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid) {
            throw 'Capture is not an actual decodable 1920x1080 PNG.'
        }
        $bitmap = [Drawing.Bitmap]::new($image)
        try {
            $colors = [Collections.Generic.HashSet[int]]::new()
            foreach ($x in @(100, 480, 960, 1440, 1800)) {
                foreach ($y in @(100, 300, 540, 800, 980)) { [void]$colors.Add($bitmap.GetPixel($x, $y).ToArgb()) }
            }
            if ($colors.Count -lt 2) { throw 'Uniform image cannot serve as gameplay capture evidence.' }
        }
        finally { $bitmap.Dispose() }
    }
    finally {
        if ($null -ne $image) { $image.Dispose() }
        $stream.Dispose()
    }
}

# This checks case identities only; Read-GodotGameplayRuntimeReport additionally validates their observations.
function Assert-GodotGameplayCoverage($Records, $Contract = (Get-GodotGameplayContract)) {
    if ($Records -isnot [Collections.IList] -or
        $Records.Count -ne $Contract['runtimeCaseNames'].Count * $Contract['modes'].Count) {
        throw 'Require the actual 28 runtime scenarios across micro and preview; G01-G32 is combined evidence.'
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $ids = @((Get-GodotGameplayCasePolicy).Keys)
    foreach ($record in $Records) {
        if ($record -isnot [Collections.IDictionary] -or $record['case'] -cnotin $ids -or
            $record['source_script'] -cne 'res://match/match.gd' -or
            $record['passed'] -isnot [bool] -or -not $record['passed'] -or
            -not $seen.Add($record['case'])) {
            throw 'Duplicate, missing, malformed or failed gameplay coverage identity.'
        }
    }
}

function Assert-GodotGameplayCaptureCoverage($Records, [string]$CaptureDirectory, [datetime]$StartedAt,
    $Contract = (Get-GodotGameplayContract)) {
    if ($Records -isnot [Collections.IList] -or
        $Records.Count -ne $Contract['captureExerciseIds'].Count * $Contract['modes'].Count) {
        throw 'Require twenty distinct capture contexts, ten per explicit mode.'
    }
    $contexts = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $files = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $hashes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($record in $Records) {
        if ($record -isnot [Collections.IDictionary] -or
            ($record['mode'] -isnot [int] -and $record['mode'] -isnot [long]) -or $record['mode'] -notin $Contract['modes'] -or
            $record['exercise'] -cnotin $Contract['captureExerciseIds'] -or
            -not $contexts.Add("$($record['mode']):$($record['exercise'])") -or
            -not $files.Add($record['path']) -or -not $hashes.Add($record['sha256'])) {
            throw 'Repeated or malformed capture mode/exercise/path/hash.'
        }
        foreach ($field in @('tick', 'selected_actor_id', 'training_exercise', 'phase')) {
            if ($record[$field] -isnot [int] -and $record[$field] -isnot [long]) { throw "Capture requires integer $field." }
        }
        $maxActor = if ($record['mode'] -eq 0) { 3 } else { 9 }
        if ($record['tick'] -le 0 -or $record['selected_actor_id'] -lt 0 -or $record['selected_actor_id'] -gt $maxActor -or
            $record['selected_actor_id'] % 2 -ne 0 -or $record['training_exercise'] -notin $Contract['trainingExercises'].Values) {
            throw 'Capture context lacks an actual tick/catalog exercise/HOME selection.'
        }
        foreach ($field in @('restart', 'camera', 'input')) {
            if ($record[$field] -isnot [Collections.IDictionary] -or $record[$field].Count -eq 0) {
                throw "Missing normalized capture $field context; raw producer semantics remain a separate required decoder."
            }
        }
        $rule = $Contract['captureContextRules'][$record['exercise']]
        if ($record['phase'] -ne $rule['phase'] -or
            ($null -ne $rule['trainingExercise'] -and $record['training_exercise'] -ne $rule['trainingExercise']) -or
            ($rule.Contains('selectedActor') -and $record['selected_actor_id'] -ne $rule['selectedActor'])) {
            throw 'Capture phase, production exercise or selected actor disagrees with the required moment.'
        }
        if ($rule.Contains('restartKind') -and
            (-not (Test-GodotGameplayInteger $record['restart']['kind']) -or
                $record['restart']['kind'] -ne $rule['restartKind'] -or
                -not (Test-GodotGameplayInteger $record['restart']['stage']) -or
                $record['restart']['stage'] -notin $rule['restartStages'])) {
            throw 'Capture contains the wrong restart kind/stage, not the required preparation or release.'
        }
        $event = $record['accepted_event']
        if ($rule['acceptedEventRequired'] -or $null -ne $event) {
            if ($event -isnot [Collections.IDictionary] -or
                -not (Test-GodotGameplayInteger $event['kind']) -or $event['kind'] -notin 0..12 -or
                -not (Test-GodotGameplayInteger $event['actor_id']) -or
                -not (Test-GodotGameplayInteger $event['tick']) -or $event['tick'] -le 0 -or $event['tick'] -gt $record['tick']) {
                throw 'Capture requires a real typed accepted event when the specified moment depends on one.'
            }
            if ($rule['acceptedEventRequired']) {
                $actor = if ($rule.Contains('eventActor')) { $rule['eventActor'] } else { $record['selected_actor_id'] }
                if ($event['kind'] -ne $rule['eventKind'] -or $event['actor_id'] -ne $actor) {
                    throw 'The accepted event kind/actor does not match the keeper release or dribble contact.'
                }
                foreach ($pair in @(@('launchKind', 'launch_kind'), @('gestureKind', 'gesture_kind'))) {
                    if ($rule.Contains($pair[0]) -and
                        (-not (Test-GodotGameplayInteger $event[$pair[1]]) -or $event[$pair[1]] -ne $rule[$pair[0]])) {
                        throw "Capture has the wrong $($pair[1]); physical keeper throws and gestures are distinct."
                    }
                }
            }
        }
        Assert-GodotGameplayCaptureFile $record['path'] $CaptureDirectory $StartedAt $record['sha256']
    }
}
