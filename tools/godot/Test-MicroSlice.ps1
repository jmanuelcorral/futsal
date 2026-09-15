#Requires -Version 7.2
[CmdletBinding()]
param(
    [ValidateSet('All', 'Components', 'Gameplay', 'GameplayRuntime', 'Helpers')][string]$Scope = 'All',
    [ValidateRange(-1, 32)][int]$GpuIndex = -1,
    [switch]$AllowKnownVulkanLayerWarning
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'PowerAvailability.ps1')
. (Join-Path $PSScriptRoot 'ArtifactPromotion.ps1')
. (Join-Path $PSScriptRoot 'MicroSliceValidation.ps1')
. (Join-Path $PSScriptRoot 'GameplayValidation.ps1')
$local = Get-GodotInstallation
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
$metadata = (Get-Content -LiteralPath (Join-Path $root 'config\toolchain.json') -Raw | ConvertFrom-Json).godot
$runtime = Join-Path $PSScriptRoot 'runtime'
$runPath = Join-Path $runtime ('preview-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N'))
$buildPath = Join-Path $root 'build\windows'
$activeArtifact = Join-Path $buildPath 'FutsalG1.exe'
$candidateDirectory = Join-Path $runPath 'candidate'
$artifact = Join-Path $candidateDirectory 'FutsalG1.exe'
$previousArtifactSha256 = ''
$candidateSha256 = ''
$artifactPromotion = $null
$promotionFailure = $null
$checks = [Collections.Generic.List[object]]::new()
$stages = [ordered]@{}
$reports = [ordered]@{}
$pendingDependencies = [Collections.Generic.List[string]]::new()
$previewTests = [ordered]@{
    'preview-core' = 'game\tests\test_match_preview.gd'
    'development-menu' = 'game\tests\test_match_dev_menu.gd'
    'preview-integration' = 'game\tests\test_match_preview_integration.gd'
    'player-control' = 'game\tests\test_match_player_control.gd'
}
$gameplayTests = Get-GodotGameplayStages $root
$visualTests = [ordered]@{}
$ownedResults = [Collections.Generic.List[object]]::new()
$startedAt = [DateTime]::UtcNow
$watch = [Diagnostics.Stopwatch]::StartNew()
$lock = $null
$powerRequest = $null
$powerReleaseFailure = $null
$failure = $null
$lockPath = Join-Path $runtime 'test.lock'

function Add-Check([string]$Name, [bool]$Passed) {
    $checks.Add([ordered]@{ name = $Name; passed = $Passed })
    if (-not $Passed) { throw "Check failed: $Name" }
}

function Invoke-Stage(
    [string]$Name, [string[]]$Arguments, [int]$Timeout = 120,
    [string]$Executable = $local.consolePath, [string]$Directory = $project,
    [System.Collections.IDictionary]$ExpectedErrors = @{}, [bool]$Rendered = $false,
    [System.Collections.IDictionary]$ExpectedDevelopmentWarnings = @{},
    [string]$ExpectedChild = '', [System.Collections.IDictionary]$ExpectedPresentationErrors = @{},
    [System.Collections.IDictionary]$ExpectedAimGuideErrors = @{}
) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $result = Invoke-GodotProcess -FilePath $Executable -Arguments $Arguments `
            -WorkingDirectory $Directory -LogPrefix (Join-Path $runPath $Name) -TimeoutSeconds $Timeout `
            -ExpectedChildExecutable $ExpectedChild
        $ownedResults.Add($result)
        Assert-GodotOutput -Result $result -ExpectedErrors $ExpectedErrors `
            -ExpectedDevelopmentWarnings $ExpectedDevelopmentWarnings `
            -ExpectedPresentationErrors $ExpectedPresentationErrors `
            -ExpectedAimGuideErrors $ExpectedAimGuideErrors `
            -AllowKnownVulkanLayerWarning:($Rendered -and $AllowKnownVulkanLayerWarning)
        $stages[$Name] = [ordered]@{
            processId = $result.ProcessId; runtimeProcessIds = $result.RuntimeProcessIds
            processStartTimeUtcTicks = $result.ProcessStartTimeUtcTicks; exitWitnesses = $result.ExitWitnesses
            outputComplete = $result.OutputComplete; stdoutComplete = $result.StdoutComplete; stderrComplete = $result.StderrComplete
            wallSeconds = [Math]::Round($clock.Elapsed.TotalSeconds, 3)
            stdout = "$Name.stdout.log"; stderr = "$Name.stderr.log"
            expectedHudErrors = $ExpectedErrors
            expectedPresentationErrors = $ExpectedPresentationErrors
            expectedAimGuideErrors = $ExpectedAimGuideErrors
            expectedDevelopmentWarnings = $ExpectedDevelopmentWarnings
            fixedStepWithoutRealtimeSynchronization = '--fixed-fps' -cin $Arguments
            renderedFpsEvidence = $false
            knownVulkanLayerWarningObserved = $Rendered -and $result.Stderr.Contains(
                'windows_read_data_files_in_registry: Registry lookup failed to get layer manifest files.')
        }
        return $result
    }
    catch {
        $checks.Add([ordered]@{ name = "$Name native process/output"; passed = $false })
        throw
    }
}

function Save-NativeReport([string]$Name, $Result, [string]$Prefix,
    [System.Collections.IDictionary]$ExpectedPresentationErrors = @{},
    [string]$NativeSource = '', [System.Collections.IDictionary]$NativeDiagnostics = @{}) {
    if ($Name -cin @('gestures', 'visual-native')) {
        $report = Read-GodotPresentationReport $Result -Stage $Name -ExpectedPresentationErrors $ExpectedPresentationErrors `
            -AllowKnownVulkanLayerWarning:($AllowKnownVulkanLayerWarning -and $stages[$Name].knownVulkanLayerWarningObserved)
    }
    elseif ($gameplayTests.Contains($Name)) {
        $report = Read-GodotGameplayNativeReport $Result -Stage $Name -Source $NativeSource -Diagnostics $NativeDiagnostics
    }
    else {
        $report = ConvertFrom-GodotStructuredReport -Result $Result -Prefix $Prefix `
            -RequireChecks:(Test-GodotNativeChecksRequired $Name)
    }
    $path = Join-Path $runPath "$Name.json"
    $report | ConvertTo-Json -Depth 64 | Set-Content -LiteralPath $path -Encoding utf8
    $reports[$Name] = [ordered]@{ path = $path; passed = $report['passed']; total = $report['total'] }
    Add-Check "$Name native structured results and output validated" $true
    Write-Host "$Name : $($report['passed'])/$($report['total']) ($($stages[$Name].wallSeconds)s wall)"
    return $report
}

function Invoke-Game([string]$Name, [bool]$Headless, [bool]$Exported) {
    $reportPath = Join-Path $runPath "$Name.json"
    $capturePath = if ($Headless) { '' } else { Join-Path $runPath "$Name.png" }
    Add-Check "$Name evidence paths did not exist before launch" (
        -not (Test-Path -LiteralPath $reportPath) -and ($Headless -or -not (Test-Path -LiteralPath $capturePath)))
    # El smoke heredado comparte la reproducción fija del gameplay, en fuente/.exe y headless/render.
    # Es temporización diagnóstica, no rendimiento 1080p60; el arranque normal sigue en tiempo real.
    $arguments = @('--audio-driver', 'Dummy', '--fixed-fps', '60')
    if (-not $Exported) { $arguments += @('--path', $project) }
    if ($Headless) { $arguments += '--headless' }
    else {
        $arguments += @('--windowed', '--resolution', '1920x1080', '--rendering-method', 'forward_plus',
            '--rendering-driver', 'vulkan', '--verbose')
        if ($GpuIndex -ge 0) { $arguments += @('--gpu-index', [string]$GpuIndex) }
    }
    $arguments += @('--', '--smoke-test', "--report-path=$reportPath")
    if (-not $Headless) { $arguments += "--capture-path=$capturePath" }
    $stageStart = [DateTime]::UtcNow
    $executable = if ($Exported) { $artifact } else { $local.consolePath }
    $nativeExecutable = if ($Exported) { $artifact } else { $local.godotPath }
    $directory = if ($Exported) { $candidateDirectory } else { $project }
    $child = if ($Exported) { '' } else { $local.godotPath }
    $result = Invoke-Stage -Name $Name -Arguments $arguments -Timeout 180 -Executable $executable `
        -Directory $directory -Rendered (-not $Headless) -ExpectedChild $child
    $report = Read-GodotGameReport -Result $result -ReportPath $reportPath -StartedAt $stageStart `
        -EditorBinary (-not $Exported) -Headless $Headless -Executable $nativeExecutable `
        -ProjectVersion $metadata.projectVersion -InputSchemaVersion $metadata.inputSchemaVersion -CapturePath $capturePath
    $reports[$Name] = [ordered]@{ path = $reportPath; passed = $report['passed']; total = $report['total'] }
    Add-Check "$Name actual main, current-run identity, inputs and HUD validated" $true
    Write-Host "$Name : $($report['passed'])/$($report['total']) ($($stages[$Name].wallSeconds)s wall)"
    return $report
}

function Invoke-GameplayRuntime([string]$Name, [bool]$Headless, [bool]$Exported) {
    $paths = Get-GodotGameplayEvidencePaths -RunPath $runPath -Stage $Name
    Assert-GodotGameplayFreshPaths $paths
    $invocation = Get-GodotGameplayInvocation -Paths $paths -Stage $Name -Installation $local `
        -Project $project -Artifact $artifact -GpuIndex $GpuIndex
    if ($Headless -ne $invocation.Headless -or $Exported -eq $invocation.EditorBinary) {
        throw 'Gameplay stage identity disagrees with its source/artifact or rendering route.'
    }
    New-Item -ItemType Directory -Path $paths.Directory | Out-Null
    $start = [datetime]::UtcNow
    $stage = "gameplay-$Name"
    $result = Invoke-Stage -Name $stage -Arguments $invocation.Arguments -Timeout 180 -Executable $invocation.Executable `
        -Directory $invocation.WorkingDirectory -Rendered (-not $Headless) -ExpectedChild $invocation.ExpectedChild
    $report = Read-GodotGameplayRuntimeReport -Result $result -ReportPath $paths.ReportPath -StartedAt $start `
        -Executable $invocation.NativeExecutable -Headless $Headless -EditorBinary (-not $Exported) -CaptureDirectory $paths.CaptureDirectory `
        -AllowKnownVulkanLayerWarning:($AllowKnownVulkanLayerWarning -and -not $Headless)
    $reports[$stage] = [ordered]@{
        path = $paths.ReportPath; passed = $report['passed']; total = $report['total']
        manifest = $report['gameplay']['capture_manifest_path']; gameplayCases = $report['gameplay']['cases'].Count
        savedPngCount = $report['gameplay']['saved_png_count']
    }
    Add-Check "$stage actual 28-case production traversal, native identity and scoped evidence validated" $true
    Write-Host "$stage : $($report['passed'])/$($report['total']); $($report['gameplay']['saved_png_count']) PNG"
    return $report
}

New-Item -ItemType Directory -Path $runtime -Force | Out-Null
try {
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
}
catch { throw "Another validation owns $lockPath. Inspect its process; do not overwrite its lock." }
try {
    New-Item -ItemType Directory -Path $runPath -Force | Out-Null
    Write-Host "Experimental preview validation ($Scope): $runPath"
    $powerRequest = [Futsal.Tooling.ValidationPowerRequest]::new($Scope -eq 'All')
    Add-Check 'scoped Windows availability acquired for this validation' (-not $powerRequest.IsClosed)
    if ($Scope -eq 'All') { $previousArtifactSha256 = Get-GodotArtifactSha256 $activeArtifact -AllowMissing }
    $shell = (Get-Process -Id $PID).Path
    $powerResult = Invoke-Stage -Name 'power-availability-helper' -Executable $shell -Directory $root `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'tests\Test-PowerAvailability.ps1'))
    $null = Save-NativeReport 'power-availability-helper' $powerResult 'FUTSAL_POWER_REQUEST_TESTS'
    $promotionResult = Invoke-Stage -Name 'artifact-promotion-helper' -Executable $shell -Directory $root `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'tests\Test-ArtifactPromotion.ps1'))
    $null = Save-NativeReport 'artifact-promotion-helper' $promotionResult 'FUTSAL_ARTIFACT_PROMOTION_TESTS'
    $helperResult = Invoke-Stage -Name 'validation-helper' -Executable $shell -Directory $root `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'tests\Test-MicroSliceValidation.ps1'))
    $null = Save-NativeReport 'validation-helper' $helperResult 'FUTSAL_PREVIEW_VALIDATION_TESTS'
    $gameplayHelper = Invoke-Stage -Name 'gameplay-validation-helper' -Executable $shell -Directory $root `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'tests\Test-GameplayValidation.ps1'))
    $null = Save-NativeReport 'gameplay-validation-helper' $gameplayHelper 'FUTSAL_GAMEPLAY_VALIDATION_TESTS'
    $presentationHelper = Invoke-Stage -Name 'presentation-validation-helper' -Executable $shell -Directory $root `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'tests\Test-PresentationValidation.ps1'))
    $null = Save-NativeReport 'presentation-validation-helper' $presentationHelper 'FUTSAL_PRESENTATION_VALIDATION_TESTS'
    $runtimeHelper = Invoke-Stage -Name 'gameplay-runtime-helper' -Executable $shell -Directory $root -Timeout 300 `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'tests\Test-GameplayRuntimeValidation.ps1'))
    $null = Save-NativeReport 'gameplay-runtime-helper' $runtimeHelper 'FUTSAL_GAMEPLAY_RUNTIME_VALIDATION_TESTS'
    $nativeHelper = Invoke-Stage -Name 'gameplay-native-helper' -Executable $shell -Directory $root `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'tests\Test-GameplayNativeValidation.ps1'))
    $null = Save-NativeReport 'gameplay-native-helper' $nativeHelper 'FUTSAL_GAMEPLAY_NATIVE_VALIDATION_TESTS'
    $completionResult = Invoke-Stage -Name 'process-completion-helper' -Executable $shell -Directory $root `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'tests\Test-ProcessCompletion.ps1'))
    $null = Save-NativeReport 'process-completion-helper' $completionResult 'FUTSAL_PROCESS_COMPLETION_TESTS'
    if ($Scope -ne 'Helpers') {
        $settings = Get-Content -LiteralPath (Join-Path $project 'project.godot') -Raw
        foreach ($path in @('game\match\match.tscn', 'game\match\match.gd', 'game\tests\test_match_integration.gd',
                'game\match\presentation\development\match_dev_menu.gd', 'game\match\presentation\development\match_dev_menu.tscn') +
                @($previewTests.Values) + @($gameplayTests.Values)) {
            if (-not (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf)) {
                $pendingDependencies.Add($path)
            }
        }
        $visualCandidates = [ordered]@{
            'visual-native' = 'game\tests\test_match_visuals.gd'
            'visual-motion' = 'tools\godot\tests\test_visual_motion.gd'
        }
        if (-not (Test-Path -LiteralPath (Join-Path $root 'game\tests\test_match_visuals.gd') -PathType Leaf)) {
            $pendingDependencies.Add('game\tests\test_match_visuals.gd (existing visual regression remains mandatory)')
        }
        foreach ($name in $visualCandidates.Keys) {
            $path = $visualCandidates[$name]
            if (Test-Path -LiteralPath (Join-Path $root $path) -PathType Leaf) {
                $visualTests[$name] = Join-Path $root $path
            }
        }
        if ($Scope -eq 'All' -and $visualTests.Count -eq 0) {
            $pendingDependencies.Add('Lambert native visual coverage: ' + ($visualCandidates.Values -join ' OR '))
        }
        $reportSources = @((@($previewTests.Values) + @($gameplayTests.Values)) | ForEach-Object { Join-Path $root $_ })
        if ($Scope -eq 'All') { $reportSources += @($visualTests.Values) }
        foreach ($path in $reportSources) {
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                try { $null = Get-GodotNativeReportPrefix (Get-Content -LiteralPath $path -Raw) }
                catch { $pendingDependencies.Add("Native report contract for $path : $_") }
            }
        }
        $negativeSource = Join-Path $root $previewTests['preview-integration']
        if (Test-Path -LiteralPath $negativeSource -PathType Leaf) {
            $negativeDependency = Get-GodotDevelopmentNegativeDependency (Get-Content -LiteralPath $negativeSource -Raw)
            if (-not [string]::IsNullOrEmpty($negativeDependency)) { $pendingDependencies.Add($negativeDependency) }
        }
        foreach ($dependency in Get-GodotGameplayRuntimeDependencies) { $pendingDependencies.Add($dependency) }
        foreach ($name in $gameplayTests.Keys) {
            try { $null = Get-GodotGameplayNativeDiagnostics $name $root }
            catch { $pendingDependencies.Add("$name diagnostics: $_") }
        }
        Assert-GodotHudDiagnosticSource `
            ([IO.File]::ReadAllText((Join-Path $project 'tests\test_match_hud.gd'))) `
            ([IO.File]::ReadAllText((Join-Path $project 'match\presentation\hud\match_hud.gd')))
        if ($pendingDependencies.Count -gt 0) {
            throw ("Preview producer dependencies pending: " + ($pendingDependencies -join '; ') +
                '. No gameplay, GPU or export stage ran. -Scope Helpers remains independent; no silent test skip or diagnostic fallback.')
        }
        Assert-GodotProjectConfiguration $settings
        if ($metadata.projectVersion -ne '0.4.0-preview' -or $metadata.inputSchemaVersion -ne 3) {
            throw 'Gameplay preview requires toolchain version 0.4.0-preview and input schema 3.'
        }
        $mainSource = Get-Content -LiteralPath (Join-Path $project 'match\match.gd') -Raw
        if (-not $mainSource.Contains('--smoke-test') -or -not $mainSource.Contains('res://diagnostics/match_smoke.gd')) {
            throw 'Preview smoke hook pending: after normal startup, invoke run(simulation, hud) only for --smoke-test. No game process was launched.'
        }
        if (-not $mainSource.Contains('--gameplay-smoke') -or -not $mainSource.Contains('res://diagnostics/gameplay_smoke.gd')) {
            throw 'Actual main has no explicit gameplay-smoke route after normal production startup.'
        }
        $ready = [regex]::Match($mainSource, '(?s)func _ready\(\)[^:]*:\s*(.*?)(?=\nfunc |\z)').Groups[1].Value.TrimStart()
        $ready = [regex]::Replace($ready, '(?m)^[\t ]*#[^\r\n]*\r?$', '').TrimStart()
        Add-Check 'fixed exported diagnostic route remains the first ready branch' (
            $ready.StartsWith('if OS.get_cmdline_user_args().has("--diagnostic-bootstrap"):') -and
            $mainSource.Contains('res://bootstrap/bootstrap.tscn'))
        Add-Check 'metadata names the real preview main and legacy output path' (
            $metadata.mainScene -eq 'res://match/match.tscn' -and $metadata.debugArtifact -eq 'build\windows\FutsalG1.exe')
    }
    if ($Scope -eq 'All') {
        $null = Invoke-Stage -Name 'editor-import' -Arguments @('--headless', '--path', $project, '--editor', '--import') -Timeout 180
        $scripts = Get-ChildItem -LiteralPath $project -Filter '*.gd' -Recurse -File
    }
    elseif ($Scope -eq 'Components') {
        $scripts = @(
            Get-Item -LiteralPath (Join-Path $project 'tests\test_match_simulation.gd')
            Get-Item -LiteralPath (Join-Path $project 'tests\test_match_hud.gd')
            Get-Item -LiteralPath (Join-Path $project 'diagnostics\match_smoke.gd')
            Get-Item -LiteralPath (Join-Path $project 'tests\test_match_integration.gd')
            foreach ($path in $previewTests.Values) { Get-Item -LiteralPath (Join-Path $root $path) }
            foreach ($path in $gameplayTests.Values) { Get-Item -LiteralPath (Join-Path $root $path) }
        )
    }
    elseif ($Scope -eq 'Gameplay') {
        $scripts = @($gameplayTests.Values | ForEach-Object { Get-Item -LiteralPath (Join-Path $root $_) })
    }
    elseif ($Scope -eq 'GameplayRuntime') {
        $scripts = @(
            Get-Item -LiteralPath (Join-Path $project 'diagnostics\match_smoke.gd')
            Get-Item -LiteralPath (Join-Path $project 'diagnostics\gameplay_smoke.gd')
        )
    }
    else { $scripts = @() }
    foreach ($script in $scripts) {
        $relative = [IO.Path]::GetRelativePath($project, $script.FullName).Replace('\', '/')
        $stageName = 'parse-' + $relative.Replace('/', '-').Replace('.', '-')
        $null = Invoke-Stage -Name $stageName -Arguments @('--headless', '--path', $project, '--check-only', '--script', "res://$relative")
        Add-Check "native parse/type check: $relative" $true
    }
    if ($Scope -notin @('Helpers', 'Gameplay', 'GameplayRuntime')) {
        $nativeArguments = @('--headless', '--path', $project, '--audio-driver', 'Dummy', '--script')
        $inputResult = Invoke-Stage -Name 'input-schema-unit' -Arguments ($nativeArguments + (Join-Path $PSScriptRoot 'tests\test_input_schema.gd'))
        $null = Save-NativeReport 'input-schema-unit' $inputResult 'FUTSAL_INPUT_SCHEMA_TESTS'
        $driverResult = Invoke-Stage -Name 'smoke-driver-unit' -Arguments ($nativeArguments + (Join-Path $PSScriptRoot 'tests\test_match_smoke.gd'))
        $null = Save-NativeReport 'smoke-driver-unit' $driverResult 'FUTSAL_SMOKE_HELPER_TESTS'
        $coreResult = Invoke-Stage -Name 'simulation' -Arguments ($nativeArguments + 'res://tests/test_match_simulation.gd')
        $core = Save-NativeReport 'simulation' $coreResult 'FUTSAL_MATCH_TESTS'
        Add-Check 'simulation printed assertions agree with native result' (
            [regex]::Matches($coreResult.Stdout, '(?m)^PASS ').Count -eq $core['passed'] -and
            [regex]::Matches($coreResult.Stdout, '(?m)^FAIL ').Count -eq 0)
        foreach ($matrix in @(@('contacts', 'contact_cases', 'contact_passed', 24), @('shots', 'shot_cases', 'shot_passed', 50))) {
            $cases = @($core[$matrix[0]])
            Add-Check "$($matrix[0]) native matrix is complete and all cases pass" (
                $cases.Count -eq $matrix[3] -and $core[$matrix[1]] -eq $cases.Count -and $core[$matrix[2]] -eq $cases.Count -and
                @($cases | Where-Object { $_['passed'] -isnot [bool] -or -not $_['passed'] }).Count -eq 0 -and
                @($cases | ForEach-Object { $_['id'] } | Sort-Object -Unique).Count -eq $cases.Count)
        }
        Assert-GodotSimulationRefusals $coreResult $core
        Add-Check 'simulation refusals match actual native negative assertions' $true
        $hudErrors = Get-MatchHudExpectedErrors
        $hudResult = Invoke-Stage -Name 'hud' -Arguments ($nativeArguments + 'res://tests/test_match_hud.gd') -ExpectedErrors $hudErrors
        $hud = Save-NativeReport 'hud' $hudResult 'FUTSAL_HUD_TESTS'
        Assert-GodotHudReport $hud
        Add-Check 'HUD diagnostic count agrees with exact native messages' $true
        $guardResult = Invoke-Stage -Name 'entrypoint-guards' -Executable $shell -Directory $root `
            -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'tests\Test-DefaultEntrypoint.ps1'))
        $null = Save-NativeReport 'entrypoint-guards' $guardResult 'FUTSAL_ENTRYPOINT_GUARD_TESTS'
        $integrationResult = Invoke-Stage -Name 'integration' -Arguments ($nativeArguments + 'res://tests/test_match_integration.gd')
        $integration = Save-NativeReport 'integration' $integrationResult 'FUTSAL_MATCH_INTEGRATION_TESTS'
        Add-Check 'integration reports no errors or command refusals' (
            $integration.Contains('integration_errors') -and @($integration['integration_errors']).Count -eq 0 -and
            $integration.Contains('command_refusals') -and @($integration['command_refusals']).Count -eq 0)
        Add-Check 'integration observed real keyboard, joy motion and button events' (
            $integration['native_events']['key'] -gt 0 -and $integration['native_events']['joy_motion'] -gt 0 -and
            $integration['native_events']['joy_button'] -gt 0 -and $integration['physics_hz'] -eq 60 -and
            $integration['main_scene'] -eq 'res://match/match.tscn')
        foreach ($name in $previewTests.Keys) {
            $path = Join-Path $root $previewTests[$name]
            $prefix = Get-GodotNativeReportPrefix (Get-Content -LiteralPath $path -Raw)
            if ($name -eq 'player-control' -and $prefix -cne 'FUTSAL_PLAYER_CONTROL_TESTS') {
                throw 'The mandatory player-control suite must report FUTSAL_PLAYER_CONTROL_TESTS.'
            }
            $developmentWarnings = if ($name -eq 'preview-integration') {
                Get-DevelopmentIntegrationExpectedWarnings
            } else { @{} }
            $result = Invoke-Stage -Name $name -Arguments ($nativeArguments + $path) `
                -ExpectedDevelopmentWarnings $developmentWarnings
            $report = Save-NativeReport $name $result $prefix
            if ($name -eq 'preview-integration') {
                Assert-PreviewIntegrationReport $report
                Add-Check 'preview integration labels intentional failures and rejects unexpected ones' $true
                continue
            }
            if ($name -eq 'player-control') {
                Assert-GodotPlayerControlReport $report
                Add-Check 'player-control F01-F12, real input/focus and exact refusals validated' $true
                continue
            }
            foreach ($field in @('integration_errors', 'command_refusals', 'errors')) {
                if ($report.Contains($field)) {
                    Add-Check "$name $field is empty" (@($report[$field]).Count -eq 0)
                }
            }
        }
    }
    if ($Scope -notin @('Helpers', 'GameplayRuntime')) {
        foreach ($name in $gameplayTests.Keys) {
            $path = Join-Path $root $gameplayTests[$name]
            $nativeArguments = @(Get-GodotGameplayNativeArguments -Stage $name -Project $project -ScriptPath $path)
            $source = Get-Content -LiteralPath $path -Raw -Encoding utf8
            $prefix = Get-GodotNativeReportPrefix $source
            $presentationErrors = @{}
            $nativeDiagnostics = Get-GodotGameplayNativeDiagnostics $name $root
            if ($name -ceq 'gestures') {
                $athleteSource = Get-Content -LiteralPath (Join-Path $root 'game\match\presentation\athletes\athlete_view.gd') -Raw -Encoding utf8
                $presentationErrors = Get-GodotGestureExpectedErrors $source $athleteSource
            }
            $result = Invoke-Stage -Name $name -Arguments $nativeArguments -ExpectedPresentationErrors $presentationErrors `
                -ExpectedAimGuideErrors $nativeDiagnostics.aimGuideErrors -ExpectedDevelopmentWarnings $nativeDiagnostics.developmentWarnings
            $report = Save-NativeReport $name $result $prefix -ExpectedPresentationErrors $presentationErrors `
                -NativeSource $source -NativeDiagnostics $nativeDiagnostics
            Add-Check "$name native assertions and strict diagnostics validated" $true
        }
    }
    if ($Scope -eq 'GameplayRuntime') { $null = Invoke-GameplayRuntime 'source-headless' $true $false }
    if ($Scope -eq 'All') {
        $visualArguments = @('--path', $project, '--audio-driver', 'Dummy', '--windowed', '--resolution', '1920x1080',
            '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan')
        if ($GpuIndex -ge 0) { $visualArguments += @('--gpu-index', [string]$GpuIndex) }
        foreach ($name in $visualTests.Keys) {
            $path = $visualTests[$name]
            $visualPrefix = Get-GodotNativeReportPrefix (Get-Content -LiteralPath $path -Raw)
            $visualResult = Invoke-Stage -Name $name -Arguments ($visualArguments + @('--script', $path)) `
                -Rendered $true -ExpectedChild $local.godotPath
            $null = Save-NativeReport $name $visualResult $visualPrefix
        }
        $null = Invoke-Game 'source-headless' $true $false
        $sourceRendered = Invoke-Game 'source-rendered' $false $false
        $null = Invoke-GameplayRuntime 'source-headless' $true $false
        $gameplaySourceRendered = Invoke-GameplayRuntime 'source-rendered' $false $false
        foreach ($file in $local.templateFiles) {
            Add-Check "official template integrity: $([IO.Path]::GetFileName($file.path))" (
                (Test-Path -LiteralPath $file.path -PathType Leaf) -and
                (Get-FileHash -LiteralPath $file.path -Algorithm SHA512).Hash.ToLowerInvariant() -eq $file.sha512)
        }
        New-Item -ItemType Directory -Path $candidateDirectory | Out-Null
        Add-Check 'export destination is isolated from the active executable and did not exist' (
            $artifact -ine $activeArtifact -and -not (Test-Path -LiteralPath $artifact))
        $exportStart = [DateTime]::UtcNow
        $null = Invoke-Stage -Name 'windows-export' -Arguments @('--headless', '--path', $project,
            '--export-debug', 'Windows Desktop', $artifact) -Timeout 300
        Add-Check 'fresh isolated Windows preview candidate with embedded PCK exported' (
            (Test-Path -LiteralPath $artifact -PathType Leaf) -and (Get-Item -LiteralPath $artifact).Length -gt 1000000 -and
            (Get-Item -LiteralPath $artifact).LastWriteTimeUtc -ge $exportStart -and
            -not (Test-Path -LiteralPath (Join-Path $candidateDirectory 'FutsalG1.pck')))
        $candidateSha256 = Get-GodotArtifactSha256 $artifact
        Add-Check 'export did not replace the previously active executable' (
            (Get-GodotArtifactSha256 $activeArtifact -AllowMissing) -ceq $previousArtifactSha256)
        $null = Invoke-Game 'artifact-headless' $true $true
        $artifactRendered = Invoke-Game 'artifact-rendered' $false $true
        $null = Invoke-GameplayRuntime 'artifact-headless' $true $true
        $gameplayArtifactRendered = Invoke-GameplayRuntime 'artifact-rendered' $false $true
        Add-Check 'source and standalone use the same native GPU' (
            $sourceRendered['gpu_name'] -ceq $artifactRendered['gpu_name'] -and
            $sourceRendered['gpu_api'] -ceq $artifactRendered['gpu_api'])
        Add-Check 'legacy and gameplay source/artifact renders use the same measured native GPU' (
            $gameplaySourceRendered['gpu_name'] -ceq $sourceRendered['gpu_name'] -and
            $gameplayArtifactRendered['gpu_name'] -ceq $sourceRendered['gpu_name'] -and
            $gameplaySourceRendered['gpu_api'] -ceq $sourceRendered['gpu_api'] -and
            $gameplayArtifactRendered['gpu_api'] -ceq $sourceRendered['gpu_api'])
    }
    Add-Check 'every stage retains its original owned completion evidence' (
        $ownedResults.Count -gt 0 -and $ownedResults.Count -eq $stages.Count)
    foreach ($ownedResult in $ownedResults) {
        Add-Check "owned invocation exited: $($ownedResult.ProcessId) / $($ownedResult.ProcessStartTimeUtcTicks)" (
            Test-GodotProcessCompletion $ownedResult)
    }
}
catch {
    $failure = $_.ToString()
    if ($checks.Count -eq 0 -or $checks[$checks.Count - 1].passed) {
        $checks.Add([ordered]@{ name = "requested $Scope validation completed"; passed = $false })
    }
    throw
}
finally {
    try {
        if ($null -ne $powerRequest) {
            $powerRequest.Dispose()
            Add-Check 'scoped Windows availability released after validation' $powerRequest.IsClosed
        }
    }
    catch {
        $powerReleaseFailure = $_
        $failure = (@($failure, $_.ToString()) | Where-Object { -not [string]::IsNullOrEmpty($_) }) -join "`n"
        $checks.Add([ordered]@{ name = 'scoped Windows availability released after validation'; passed = $false })
    }
    try {
        if ($Scope -eq 'All' -and $null -eq $failure -and
            @($checks | Where-Object { -not $_.passed }).Count -eq 0) {
            try {
                $artifactPromotion = Publish-GodotArtifact -Candidate $artifact -Destination $activeArtifact `
                    -BackupPath (Join-Path $runPath 'previous-artifact\FutsalG1.exe') `
                    -ExpectedSha256 $candidateSha256 -PreviousSha256 $previousArtifactSha256
                Add-Check 'validated candidate promoted with verified previous artifact preservation' $artifactPromotion.promoted
            }
            catch {
                $promotionFailure = $_
                $artifactPromotion = $_.Exception.Data['ArtifactPromotion']
                $failure = $_.ToString()
                $checks.Add([ordered]@{ name = 'validated artifact promotion'; passed = $false })
            }
        }
        $summary = [ordered]@{
            ok = $null -eq $failure
            scope = $Scope
            gameplayValidated = $null -eq $failure -and $Scope -eq 'All'
            productGatesAccepted = $false
            startedAt = $startedAt.ToString('o')
            completedAt = [DateTime]::UtcNow.ToString('o')
            wallSeconds = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
            godotVersion = $local.versionOutput
            projectVersion = $metadata.projectVersion
            inputSchemaVersion = $metadata.inputSchemaVersion
            runPath = $runPath
            gpuIndexOverride = $GpuIndex
            allowKnownVulkanLayerWarning = [bool]$AllowKnownVulkanLayerWarning
            powerAvailability = [ordered]@{
                acquired = $null -ne $powerRequest
                displayRequested = $Scope -eq 'All'
                released = $null -ne $powerRequest -and $powerRequest.IsClosed -and $null -eq $powerReleaseFailure
                changesGlobalPowerPolicy = $false
            }
            stages = $stages
            reports = $reports
            pendingDependencies = $pendingDependencies.ToArray()
            runnerPassed = @($checks | Where-Object { $_.passed }).Count
            runnerTotal = $checks.Count
            checks = $checks.ToArray()
            error = $failure
            limitations = 'Automatic native behavior and rendering only; no human game feel, art acceptance or rendered FPS.'
        }
        if ($Scope -eq 'All') {
            $summary['windowsDriverInventory'] = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate)
            $summary['artifact'] = $activeArtifact
            $summary['validatedCandidate'] = $artifact
            $summary['artifactPromotion'] = $artifactPromotion
            $summary['previousArtifactSha256'] = $previousArtifactSha256
            $summary['artifactSha256'] = Get-GodotArtifactSha256 $activeArtifact -AllowMissing
            $summary['candidateSha256'] = Get-GodotArtifactSha256 $artifact -AllowMissing
        }
        $json = $summary | ConvertTo-Json -Depth 64
        $json | Set-Content -LiteralPath (Join-Path $runPath 'result.json') -Encoding utf8
        $json | Set-Content -LiteralPath (Join-Path $runtime 'preview-result.json') -Encoding utf8
        Write-Host "Preview $Scope runner checks: $($summary.runnerPassed)/$($summary.runnerTotal); ok=$($summary.ok)"
        Write-Host "Evidence: $(Join-Path $runPath 'result.json')"
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
            Remove-Item -LiteralPath $lockPath
        }
    }
    if ($null -ne $powerReleaseFailure) { throw $powerReleaseFailure }
    if ($null -ne $promotionFailure) { throw $promotionFailure }
}
