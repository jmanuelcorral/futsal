#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Common.ps1')
. (Join-Path $PSScriptRoot '..\MicroSliceValidation.ps1')
. (Join-Path $PSScriptRoot '..\GameplayValidation.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$directory = Join-Path $root ('tools\godot\runtime\presentation-helper-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$checks = [Collections.Generic.List[object]]::new()
$failure = $null
$complete = $false
$declaredDiagnostics = 0

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
    return $Value | ConvertTo-Json -Depth 64 | ConvertFrom-Json -AsHashtable -Depth 64
}

function Fixture-Report([string]$Stage) {
    $report = [ordered]@{
        ok = $true; passed = 0; total = 0; failures = @(); checks = @(); duplicate_checks = @(); headless = $true
        native_errors = [ordered]@{error_count = 0; script_error_count = 0; shader_error_count = 0; warning_count = 0; entries = @()}
    }
    foreach ($name in Get-GodotPresentationCompletionChecks $Stage) {
        $report.checks += @{name = $name; passed = $true}
    }
    if ($Stage -ceq 'gestures') {
        $report['expected_error_counts'] = [ordered]@{}
        $report['observed_expected_error_counts'] = [ordered]@{}
        $report['unexpected_errors'] = @()
        foreach ($message in $expected.Keys) {
            $bare = $message.Substring(7)
            $reason = $bare.Substring($policy.prefix.Length)
            $count = $expected[$message]
            $report.expected_error_counts[$bare] = $count
            $report.observed_expected_error_counts[$bare] = $count
            for ($index = 1; $index -le $count; $index++) {
                $report.checks += @{name = "Rechazo explícito $reason caso=$index"; passed = $true}
                $report.checks += @{name = "Sin pose alternativa silenciosa tras $reason caso=$index"; passed = $true}
                $report.native_errors.entries += @{
                    function = 'push_error'; file = 'synthetic-fixture.cpp'; line = 1
                    code = ''; rationale = $bare; type = 0
                }
                $report.native_errors.error_count++
            }
        }
    }
    $report.total = $report.checks.Count
    $report.passed = $report.total
    return $report
}

function Fixture-Result($Report, [string]$Stage) {
    $lines = [Collections.Generic.List[string]]::new()
    if ($Stage -ceq 'gestures') {
        foreach ($message in $expected.Keys) {
            for ($index = 0; $index -lt $expected[$message]; $index++) {
                $lines.Add($message)
                $lines.Add('   at: push_error (synthetic-fixture.cpp:1)')
            }
        }
    }
    return [pscustomobject]@{
        ExitCode = 0
        Stdout = $contract.presentationReportPrefixes[$Stage] + ' ' + ($Report | ConvertTo-Json -Depth 64 -Compress)
        Stderr = $lines -join "`n"
    }
}

try {
    $contract = Get-GodotGameplayContract
    $policy = Get-GodotPresentationDiagnosticContract
    $athlete = 'const PRESENTATION_ERROR: String = "' + $policy.prefix + '"'
    $sourceLines = [Collections.Generic.List[string]]::new()
    $sourceLines.Add('print("FUTSAL_GESTURE_TESTS " + JSON.stringify({}))')
    foreach ($reason in $policy.minimumCases.Keys) {
        for ($index = 0; $index -lt $policy.minimumCases[$reason]; $index++) {
            $sourceLines.Add('_expect_error("' + $reason + '", view, callable)')
        }
    }
    $source = $sourceLines -join "`n"
    $expected = Get-GodotGestureExpectedErrors $source $athlete
    Check 'exact diagnostic policy comes from source calls, not a native assertion total' (
        $expected.Count -eq $policy.minimumCases.Count)
    Rejected 'unknown rejection reason cannot widen the expected-error policy' {
        Get-GodotGestureExpectedErrors ($source + "`n_expect_error(`"unreviewed`", view, callable)") $athlete
    }
    Rejected 'missing rejection cases cannot silently narrow mandatory coverage' {
        Get-GodotGestureExpectedErrors ($source.Replace('_expect_error("context_ticks", view, callable)', '')) $athlete
    }
    Rejected 'renamed marker cannot be guessed or accepted as the old gesture suite' {
        Get-GodotGestureExpectedErrors ($source.Replace('FUTSAL_GESTURE_TESTS', 'FUTSAL_OTHER_TESTS')) $athlete
    }
    Rejected 'changed presentation prefix needs explicit review' {
        Get-GodotGestureExpectedErrors $source ($athlete.Replace('AthleteView', 'OtherView'))
    }
    $more = Get-GodotGestureExpectedErrors ($source + "`n_expect_error(`"gesture_vectors`", view, callable)") $athlete
    Check 'additional declared occurrences are counted, not frozen to a former total' (
        $more['ERROR: ' + $policy.prefix + 'gesture_vectors'] -eq $expected['ERROR: ' + $policy.prefix + 'gesture_vectors'] + 1)

    foreach ($stage in @('gestures', 'visual-native')) {
        $valid = Fixture-Report $stage
        $allowance = if ($stage -ceq 'gestures') { $expected } else { @{} }
        $null = Read-GodotPresentationReport (Fixture-Result $valid $stage) -Stage $stage -ExpectedPresentationErrors $allowance
        Check "$stage typed logger, checks and raw-output fixture accepted" $true
        foreach ($change in @(@{checks = @()}, @{duplicate_checks = @('duplicate')}, @{headless = 'true'},
                @{native_errors = $null}, @{unexpected_errors = @('unexpected')})) {
            $bad = Copy-Fixture $valid
            foreach ($key in $change.Keys) { $bad[$key] = $change[$key] }
            Rejected ("$stage invalid report shape: " + ($change | ConvertTo-Json -Compress)) {
                Read-GodotPresentationReport (Fixture-Result $bad $stage) -Stage $stage -ExpectedPresentationErrors $allowance
            }
        }
        foreach ($field in @('error_count', 'script_error_count', 'shader_error_count', 'warning_count')) {
            foreach ($value in @('0', $true, 1)) {
                $bad = Copy-Fixture $valid
                $bad.native_errors[$field] = $value
                Rejected "$stage invalid native counter $field $($value.GetType().Name):$value" {
                    Read-GodotPresentationReport (Fixture-Result $bad $stage) -Stage $stage -ExpectedPresentationErrors $allowance
                }
            }
        }
        foreach ($diagnostic in @('SCRIPT ERROR: synthetic load failure', 'SHADER ERROR: synthetic pre-initialize failure',
                'ERROR: synthetic engine failure', 'WARNING: synthetic warning', 'Parse Error: synthetic parser failure')) {
            $raw = Fixture-Result $valid $stage
            $raw.Stderr += "`n$diagnostic"
            Rejected "$stage raw diagnostics before logger installation still fail: $($diagnostic.Replace(':', ''))" {
                Read-GodotPresentationReport $raw -Stage $stage -ExpectedPresentationErrors $allowance
            }
        }
        $raw = Fixture-Result $valid $stage
        $raw.ExitCode = 1
        Rejected "$stage nonzero exit cannot be hidden by a green logger report" {
            Read-GodotPresentationReport $raw -Stage $stage -ExpectedPresentationErrors $allowance
        }
        $bad = Copy-Fixture $valid
        $bad.checks = @($bad.checks | Where-Object { $_['name'] -cne (Get-GodotPresentationCompletionChecks $stage)[0] })
        $bad.total = $bad.checks.Count
        $bad.passed = $bad.total
        Rejected "$stage cannot omit completion evidence even with self-consistent totals" {
            Read-GodotPresentationReport (Fixture-Result $bad $stage) -Stage $stage -ExpectedPresentationErrors $allowance
        }
    }
    $gesture = Fixture-Report 'gestures'
    foreach ($field in @('expected_error_counts', 'observed_expected_error_counts')) {
        foreach ($kind in @('missing', 'wrong-count', 'string-count', 'extra-key')) {
            $bad = Copy-Fixture $gesture
            $first = @($bad[$field].Keys)[0]
            switch ($kind) {
                'missing' { $bad[$field] = $null }
                'wrong-count' { $bad[$field][$first]++ }
                'string-count' { $bad[$field][$first] = [string]$bad[$field][$first] }
                'extra-key' { $bad[$field]['unreviewed diagnostic'] = 1 }
            }
            Rejected "gesture $field $kind cannot override source/raw measurements" {
                Read-GodotPresentationReport (Fixture-Result $bad 'gestures') -Stage gestures -ExpectedPresentationErrors $expected
            }
        }
    }
    foreach ($change in @(@{type = 2}, @{type = '0'}, @{line = '1'}, @{rationale = 'unrelated diagnostic'},
            @{code = $null}, @{function = $true})) {
        $bad = Copy-Fixture $gesture
        foreach ($key in $change.Keys) { $bad.native_errors.entries[0][$key] = $change[$key] }
        Rejected ('malformed or non-error logger entry: ' + ($change | ConvertTo-Json -Compress)) {
            Read-GodotPresentationReport (Fixture-Result $bad 'gestures') -Stage gestures -ExpectedPresentationErrors $expected
        }
    }
    $bad = Copy-Fixture $gesture
    $bad.native_errors.entries = @()
    Rejected 'reported native counters without actual entries are insufficient' {
        Read-GodotPresentationReport (Fixture-Result $bad 'gestures') -Stage gestures -ExpectedPresentationErrors $expected
    }
    $bad = Copy-Fixture $gesture
    $bad.checks = @($bad.checks | Where-Object { $_['name'] -cne 'Rechazo explícito gesture_kind caso=1' })
    $bad.total = $bad.checks.Count
    $bad.passed = $bad.total
    Rejected 'actual rejection assertion is required in addition to count dictionaries' {
        Read-GodotPresentationReport (Fixture-Result $bad 'gestures') -Stage gestures -ExpectedPresentationErrors $expected
    }
    $codeOnly = Copy-Fixture $gesture
    foreach ($entry in $codeOnly.native_errors.entries) { $entry.code = $entry.rationale; $entry.rationale = '' }
    $null = Read-GodotPresentationReport (Fixture-Result $codeOnly 'gestures') -Stage gestures -ExpectedPresentationErrors $expected
    Check 'native code fallback is used only when rationale is empty, matching the producer' $true
    $raw = Fixture-Result $gesture 'gestures'
    $raw.Stderr = ''
    Rejected 'logger report cannot replace missing raw expected diagnostic lines' {
        Read-GodotPresentationReport $raw -Stage gestures -ExpectedPresentationErrors $expected
    }
    $raw = Fixture-Result $gesture 'gestures'
    $raw.Stderr += "`n" + @($expected.Keys)[0]
    Rejected 'extra expected-looking diagnostic is not silently ignored' {
        Read-GodotPresentationReport $raw -Stage gestures -ExpectedPresentationErrors $expected
    }
    $raw = Fixture-Result $gesture 'gestures'
    $raw.Stderr = $raw.Stderr.Replace(@($expected.Keys)[0], @($expected.Keys)[0] + ' extra')
    Rejected 'diagnostic prefixes do not allow trailing or altered messages' {
        Read-GodotPresentationReport $raw -Stage gestures -ExpectedPresentationErrors $expected
    }
    $raw = Fixture-Result $gesture 'gestures'
    Rejected 'gesture errors remain forbidden without an explicit source-derived allowance' { Assert-GodotOutput $raw }
    Rejected 'presentation allowance cannot bypass the independent HUD policy' { Assert-GodotOutput $raw -ExpectedErrors $expected }
    $hud = Get-MatchHudExpectedErrors
    $hudLines = [Collections.Generic.List[string]]::new()
    foreach ($message in $hud.Keys) { for ($index = 0; $index -lt $hud[$message]; $index++) { $hudLines.Add($message) } }
    Assert-GodotOutput ([pscustomobject]@{ExitCode = 0; Stdout = ''; Stderr = $hudLines -join "`n"}) -ExpectedErrors $hud
    Check 'existing exact HUD diagnostic family remains separate and accepted' $true
    $visual = Fixture-Report 'visual-native'
    $loader = "WARNING: GENERAL - Message Id Number: 0 | Message Id Name: Loader Message`n" +
        "`twindows_read_data_files_in_registry: Registry lookup failed to get layer manifest files.`n" +
        "`tObjects - 1`n`t`tObject[0] - VK_OBJECT_TYPE_INSTANCE, Handle 123`n" +
        '   at: _debug_messenger_callback (drivers/vulkan/rendering_context_driver_vulkan.cpp:654)'
    $raw = Fixture-Result $visual 'visual-native'
    $raw.Stderr = $loader
    $null = Read-GodotPresentationReport $raw -Stage visual-native -AllowKnownVulkanLayerWarning
    Check 'one exact pre-initialize Vulkan loader block still requires its existing opt-in' $true
    Rejected 'known Vulkan block without opt-in remains a failure' { Read-GodotPresentationReport $raw -Stage visual-native }
    $raw.Stderr += "`n$loader"
    Rejected 'two Vulkan blocks remain forbidden' { Read-GodotPresentationReport $raw -Stage visual-native -AllowKnownVulkanLayerWarning }

    $actualSource = Get-Content -LiteralPath (Join-Path $root 'game\tests\test_match_gestures.gd') -Raw -Encoding utf8
    $actualAthlete = Get-Content -LiteralPath (Join-Path $root 'game\match\presentation\athletes\athlete_view.gd') -Raw -Encoding utf8
    $actualExpected = Get-GodotGestureExpectedErrors $actualSource $actualAthlete
    foreach ($count in $actualExpected.Values) { $declaredDiagnostics += $count }
    Check 'published gesture source binds the actual marker and declared negative calls without execution' ($declaredDiagnostics -gt 0)
    $visualSource = Get-Content -LiteralPath (Join-Path $root 'game\tests\test_match_visuals.gd') -Raw -Encoding utf8
    Check 'published visual source preserves FUTSAL_VISUAL_TESTS' ((Get-GodotNativeReportPrefix $visualSource) -ceq 'FUTSAL_VISUAL_TESTS')
    foreach ($file in @('..\Common.ps1', '..\GameplayValidation.ps1', '..\Test-MicroSlice.ps1', 'Test-PresentationValidation.ps1')) {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file), [ref]$null, [ref]$errors)
        Check "presentation-related PowerShell parses: $file" ($errors.Count -eq 0)
    }
    Assert-GodotOutput ([pscustomobject]@{
        ExitCode = 0; Stderr = ''
        Stdout = 'FUTSAL_PRESENTATION_VALIDATION_TESTS ' + (@{checks = $checks.ToArray()} | ConvertTo-Json -Depth 32 -Compress)
    })
    Check 'the helper structured output itself satisfies the production wrapper output policy' $true
    $complete = $true
}
catch {
    $failure = $_.Exception.Message
    $checks.Add([ordered]@{name = 'presentation fixture suite completed'; passed = $false; error = $failure})
}
$failed = @($checks | Where-Object { -not $_['passed'] }).Count
$report = [ordered]@{
    ok = $complete -and $failed -eq 0; total = $checks.Count; passed = $checks.Count - $failed; checks = $checks.ToArray()
    nativeValidated = $false; nativeDiagnosticsObserved = $false; sourceDeclaredGestureDiagnostics = $declaredDiagnostics
    scope = 'pure PowerShell fixtures and source-contract reads; NOT native component acceptance'
    error = $failure; evidence = $directory
}
if ($report.ok) {
    $null = ConvertFrom-GodotStructuredReport ([pscustomobject]@{
        Stdout = 'FUTSAL_PRESENTATION_VALIDATION_TESTS ' + ($report | ConvertTo-Json -Depth 32 -Compress)
    }) 'FUTSAL_PRESENTATION_VALIDATION_TESTS' -RequireChecks
}
$report | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath (Join-Path $directory 'result.json') -Encoding utf8
Write-Output ('FUTSAL_PRESENTATION_VALIDATION_TESTS ' + ($report | ConvertTo-Json -Depth 32 -Compress))
exit $(if ($report.ok) { 0 } else { 1 })
