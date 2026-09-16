#Requires -Version 7.2
[CmdletBinding()]
param(
    [ValidateRange(-1, 32)][int]$GpuIndex = -1,
    [switch]$AllowKnownVulkanLayerWarning
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'PowerAvailability.ps1')
. (Join-Path $PSScriptRoot 'ArtifactPromotion.ps1')
$local = Get-GodotInstallation
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
$metadata = (Get-Content -LiteralPath (Join-Path $root 'config\toolchain.json') -Raw | ConvertFrom-Json).godot
$sourceIdentity = Get-GodotExpectedProjectIdentity
$runtime = Join-Path $PSScriptRoot 'runtime'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N')
$runPath = Join-Path $runtime $runId
$activeArtifact = Join-Path $root 'build\windows\FutsalG1.exe'
$buildPath = Join-Path $runPath 'diagnostic-artifact'
$artifactPath = Join-Path $buildPath 'FutsalG1.exe'
$previousArtifactSha256 = ''
$diagnosticScene = 'res://bootstrap/bootstrap.tscn'
$probeName = '_pipeline_probe_' + [guid]::NewGuid().ToString('N') + '.glb'
$probePath = Join-Path $project "assets\$probeName"
$blendPath = Join-Path $runPath 'pipeline-probe.blend'
$checks = [Collections.Generic.List[object]]::new()
$ownedResults = [Collections.Generic.List[object]]::new()
$reports = [ordered]@{}
$failure = $null
$lock = $null
$powerRequest = $null
$powerReleaseFailure = $null
$lockPath = Join-Path $runtime 'test.lock'
$started = (Get-Date).ToUniversalTime().ToString('o')

function Add-Check([string]$Name, [bool]$Passed) {
    $checks.Add([ordered]@{ name = $Name; passed = $Passed })
    if (-not $Passed) { throw "Check failed: $Name" }
}

function Invoke-Engine([string]$Stage, [string[]]$Arguments, [int]$Timeout = 120, [string]$Executable = $local.consolePath,
    [string]$Directory = $project, [string]$ExpectedChild = '') {
    try {
        $result = Invoke-GodotProcess -FilePath $Executable -Arguments $Arguments `
            -WorkingDirectory $Directory -LogPrefix (Join-Path $runPath $Stage) -TimeoutSeconds $Timeout `
            -ExpectedChildExecutable $ExpectedChild
        $ownedResults.Add($result)
        Assert-GodotOutput $result -AllowKnownVulkanLayerWarning:($AllowKnownVulkanLayerWarning -and $Stage -match 'rendered$')
        return $result
    }
    catch {
        $checks.Add([ordered]@{ name = "$Stage native process"; passed = $false })
        throw
    }
}

function Read-Report([string]$Stage, [string]$Path, [Parameter(Mandatory)]$ProcessResult, [switch]$RequireRuntimeIdentity) {
    Add-Check "$Stage report was created by this run" (Test-Path -LiteralPath $Path -PathType Leaf)
    $report = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($report.PSObject.Properties.Name -contains 'input_schema_version') {
        Add-Check "$Stage exact player-control version and diagnostic input schema" (
            $report.project_version -ceq $sourceIdentity.projectVersion -and
            $report.input_schema_version -is [long] -and $report.input_schema_version -eq 3)
    }
    foreach ($check in $report.checks) { Add-Check "$Stage / $($check.name)" ([bool]$check.passed) }
    Add-Check "$Stage assertion count agrees with results" ($report.total -eq @($report.checks).Count -and
        $report.passed -eq @($report.checks | Where-Object passed).Count -and $report.ok)
    $reports[$Stage] = [ordered]@{ path = $Path; passed = $report.passed; total = $report.total }
    if ($RequireRuntimeIdentity -or $report.PSObject.Properties.Name -contains 'process_id') {
        $reportedId = $null
        if ($report.PSObject.Properties.Name -contains 'process_id') { $reportedId = $report.process_id }
        Add-Check "$Stage report PID belongs to an observed, completed runtime identity" (
            Test-GodotReportedProcess $ProcessResult $reportedId)
    }
    Write-Host "$Stage : $($report.passed)/$($report.total)"
    return $report
}

function Test-Png([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    return $bytes.Length -gt 1024 -and [Convert]::ToHexString([byte[]]$bytes[0..7]) -eq '89504E470D0A1A0A'
}

New-Item -ItemType Directory -Path $runtime -Force | Out-Null
try {
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
}
catch {
    throw "Another validation owns $lockPath (or a previous shell was interrupted). Inspect that run; it was not overwritten."
}
try {
    New-Item -ItemType Directory -Path $runPath, $buildPath -Force | Out-Null
    Write-Host "Godot independent technical diagnosis and asset pipeline (NOT preview gameplay validation): $runPath"
    $powerRequest = [Futsal.Tooling.ValidationPowerRequest]::new($true)
    Add-Check 'scoped Windows availability acquired for this validation' (-not $powerRequest.IsClosed)
    $previousArtifactSha256 = Get-GodotArtifactSha256 $activeArtifact -AllowMissing
    Assert-GodotProjectConfiguration (Get-Content -LiteralPath (Join-Path $project 'project.godot') -Raw)
    Add-Check 'foundation targets current source and schema 3, not historical artifact acceptance' (
        $sourceIdentity.projectVersion -ceq '0.5.0-preview' -and $sourceIdentity.inputSchemaVersion -eq 3)
    $scripts = Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -Recurse -File |
        Where-Object { $_.Name -notin @('Install-Godot.ps1', 'Test-InstallerReuse.ps1') -and $_.FullName -notlike "$runtime\*" }
    foreach ($script in $scripts) {
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$parseErrors)
        Add-Check "PowerShell syntax: $($script.Name)" ($parseErrors.Count -eq 0)
    }
    $shell = (Get-Process -Id $PID).Path
    $processProbe = Join-Path $PSScriptRoot 'tests\process_probe.ps1'
    $argumentValue = Join-Path $runPath 'a path with spaces'
    $argumentsResult = Invoke-GodotProcess -FilePath $shell `
        -Arguments @('-NoProfile', '-File', $processProbe, '-Value', $argumentValue) `
        -WorkingDirectory $runPath -LogPrefix (Join-Path $runPath 'process-arguments') -TimeoutSeconds 15
    $argumentReport = $argumentsResult.Stdout | ConvertFrom-Json
    $ownedResults.Add($argumentsResult)
    Add-Check 'process helper preserves arguments with spaces' ($argumentReport.value -eq $argumentValue)
    $nonzeroRejected = $false
    $nonzeroResult = $null
    try {
        $null = Invoke-GodotProcess -FilePath $shell -Arguments @('-NoProfile', '-File', $processProbe, '-ExitCode', '7') `
            -WorkingDirectory $runPath -LogPrefix (Join-Path $runPath 'process-nonzero') -TimeoutSeconds 15
    }
    catch {
        $nonzeroRejected = $_.ToString() -match 'exited 7'
        $nonzeroResult = $_.Exception.Data['GodotProcessResult']
    }
    Add-Check 'process helper propagates nonzero exit' $nonzeroRejected
    Add-Check 'nonzero process retains an original-handle exit witness' (Test-GodotProcessCompletion $nonzeroResult)
    $ownedResults.Add($nonzeroResult)
    $timeoutRejected = $false
    $timeoutResult = $null
    try {
        $null = Invoke-GodotProcess -FilePath $shell -Arguments @('-NoProfile', '-File', $processProbe, '-DelaySeconds', '30') `
            -WorkingDirectory $runPath -LogPrefix (Join-Path $runPath 'process-timeout') -TimeoutSeconds 2
    }
    catch {
        $timeoutRejected = $_.ToString() -match 'Timed out after 2 seconds'
        $timeoutResult = $_.Exception.Data['GodotProcessResult']
    }
    Add-Check 'process helper enforces timeout' $timeoutRejected
    $timeoutReport = Get-Content -LiteralPath (Join-Path $runPath 'process-timeout.stdout.log') -Raw | ConvertFrom-Json
    Add-Check 'timed-out owned process was stopped using its original identity' (
        Test-GodotReportedProcess $timeoutResult $timeoutReport.processId)
    $ownedResults.Add($timeoutResult)
    foreach ($file in $local.templateFiles) {
        Add-Check "installed official template integrity: $([IO.Path]::GetFileName($file.path))" (
            (Test-Path -LiteralPath $file.path -PathType Leaf) -and
            (Get-FileHash -LiteralPath $file.path -Algorithm SHA512).Hash.ToLowerInvariant() -eq $file.sha512
        )
    }
    $version = Invoke-Engine 'version' @('--version')
    Add-Check 'native editor version matches verified inventory' ($version.Stdout.Trim() -eq $local.versionOutput)
    $help = Invoke-Engine 'help' @('--help')
    foreach ($option in @('--import', '--check-only', '--gpu-index', '--rendering-method', '--export-debug')) {
        Add-Check "installed engine supports $option" $help.Stdout.Contains($option)
    }

    $blenderInventory = Join-Path $root 'tools\blender\local.json'
    if (-not (Test-Path -LiteralPath $blenderInventory -PathType Leaf)) {
        throw 'Blender must be installed for this full pipeline validation. Run tools\blender\Install-Blender.ps1 first.'
    }
    $blender = Get-Content -LiteralPath $blenderInventory -Raw | ConvertFrom-Json
    Add-Check 'registered Blender binary integrity' (
        (Get-FileHash -LiteralPath $blender.blenderPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $blender.binarySha256
    )
    $workPath = Join-Path $runPath 'blender-work'
    New-Item -ItemType Directory -Path $workPath -Force | Out-Null
    $exportResult = Invoke-GodotProcess -FilePath $blender.blenderPath -Arguments @(
        '--background', '--factory-startup', '--disable-autoexec', '--python-exit-code', '2',
        '--python', (Join-Path $PSScriptRoot 'export_probe.py'), '--',
        '--blend-path', $blendPath, '--glb-path', $probePath
    ) -WorkingDirectory $runPath -LogPrefix (Join-Path $runPath 'blender-export') `
        -Environment @{ TEMP = $workPath; TMP = $workPath; DISABLE_TELEMETRY = 'true' } -TimeoutSeconds 120
    $ownedResults.Add($exportResult)
    Add-Check 'Blender executed the actual GLB exporter' $exportResult.Stdout.Contains('FUTSAL_PIPELINE_EXPORT ')
    Add-Check 'source .blend exists outside game project' (Test-Path -LiteralPath $blendPath -PathType Leaf)
    $glbBytes = [IO.File]::ReadAllBytes($probePath)
    Add-Check 'export has binary glTF header' ([Text.Encoding]::ASCII.GetString($glbBytes, 0, 4) -eq 'glTF')

    $null = Invoke-Engine 'editor-import' @('--headless', '--path', $project, '--editor', '--import') 180
    Add-Check 'Godot created a real GLB import sidecar' (Test-Path -LiteralPath "$probePath.import" -PathType Leaf)
    foreach ($script in Get-ChildItem -LiteralPath $project -Filter '*.gd' -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($project, $script.FullName).Replace('\', '/')
        $null = Invoke-Engine "script-$($script.BaseName)" @('--headless', '--path', $project, '--check-only', '--script', "res://$relative")
        Add-Check "native GDScript parse/type check: $relative" $true
    }
    $nativePath = Join-Path $runPath 'native-tests.json'
    $nativeResult = Invoke-Engine 'native-tests' @('--headless', '--path', $project, '--script', 'res://tests/test_bootstrap.gd', '--',
        "--pipeline-scene=res://assets/$probeName", "--report-path=$nativePath")
    $null = Read-Report 'native-tests' $nativePath $nativeResult
    $headlessPath = Join-Path $runPath 'source-headless.json'
    $headlessResult = Invoke-Engine 'source-headless' @('--headless', '--path', $project, $diagnosticScene, '--',
        '--smoke-test', "--report-path=$headlessPath") -ExpectedChild $local.godotPath
    $headless = Read-Report 'source-headless' $headlessPath $headlessResult -RequireRuntimeIdentity
    Add-Check 'explicit headless diagnostic ran with editor binary' ([bool]$headless.editor_binary -and
        $headless.diagnostic_scene -eq $diagnosticScene)

    $gpuArguments = @('--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan', '--verbose',
        '--resolution', '1920x1080', '--audio-driver', 'Dummy')
    if ($GpuIndex -ge 0) { $gpuArguments += @('--gpu-index', [string]$GpuIndex) }
    $renderPath = Join-Path $runPath 'source-rendered.json'
    $renderPng = Join-Path $runPath 'source-rendered.png'
    $renderResult = Invoke-Engine 'source-rendered' (@('--path', $project, $diagnosticScene) + $gpuArguments + @('--', '--smoke-test',
        "--report-path=$renderPath", "--capture-path=$renderPng")) 180 -ExpectedChild $local.godotPath
    $rendered = Read-Report 'source-rendered' $renderPath $renderResult -RequireRuntimeIdentity
    Add-Check 'source GPU evidence includes real PNG' ($rendered.gpu_validated -and (Test-Png $renderPng))
    Add-Check 'source runtime really used Vulkan Forward+' ($rendered.rendering_method -eq 'forward_plus' -and $rendered.rendering_driver -eq 'vulkan')

    # Only these GUID-scoped probe files belong to this run; no game assets are deleted.
    Remove-Item -LiteralPath $probePath, "$probePath.import", $blendPath
    $importedPath = Join-Path $project '.godot\imported'
    Get-ChildItem -LiteralPath $importedPath -Filter "$probeName-*" -File | Remove-Item
    Add-Check 'synthetic source and runtime probe removed before export' (
        -not (Test-Path -LiteralPath $probePath) -and -not (Test-Path -LiteralPath $blendPath)
    )
    $null = Invoke-Engine 'windows-export' @('--headless', '--path', $project, '--export-debug', 'Windows Desktop', $artifactPath) 300
    Add-Check 'native Windows debug executable exported' ((Test-Path -LiteralPath $artifactPath -PathType Leaf) -and
        (Get-Item -LiteralPath $artifactPath).Length -gt 1000000)
    $artifactHeadlessPath = Join-Path $runPath 'artifact-headless.json'
    $artifactHeadlessResult = Invoke-Engine 'artifact-headless' @('--headless', '--', '--diagnostic-bootstrap', '--smoke-test', "--report-path=$artifactHeadlessPath") `
        120 $artifactPath $buildPath
    $artifactHeadless = Read-Report 'artifact-headless' $artifactHeadlessPath $artifactHeadlessResult -RequireRuntimeIdentity
    Add-Check 'exported app selected its bundled diagnostic without CLI path override' (
        $artifactHeadless.diagnostic_scene -eq $diagnosticScene -and $artifactHeadless.diagnostic_mode_requested)
    Add-Check 'built artifact is not the editor' (-not [bool]$artifactHeadless.editor_binary)
    Add-Check 'built executable booted from its own path' (
        [IO.Path]::GetFullPath($artifactHeadless.executable) -eq $artifactPath
    )
    $artifactRenderPath = Join-Path $runPath 'artifact-rendered.json'
    $artifactPng = Join-Path $runPath 'artifact-rendered.png'
    $artifactRenderResult = Invoke-Engine 'artifact-rendered' ($gpuArguments + @('--', '--diagnostic-bootstrap', '--smoke-test',
        "--report-path=$artifactRenderPath", "--capture-path=$artifactPng")) 180 $artifactPath $buildPath
    $artifactRendered = Read-Report 'artifact-rendered' $artifactRenderPath $artifactRenderResult -RequireRuntimeIdentity
    Add-Check 'exported artifact produced a real Forward+ PNG' ($artifactRendered.gpu_validated -and (Test-Png $artifactPng))
    Add-Check 'artifact used the same native GPU as source' ($artifactRendered.gpu_name -eq $rendered.gpu_name)
    Add-Check 'export is self-contained without a sidecar PCK' (-not (Test-Path -LiteralPath (Join-Path $buildPath 'FutsalG1.pck')))
    Add-Check 'diagnostic export leaves the active gameplay executable byte-identical or absent' (
        $artifactPath -ine $activeArtifact -and
        (Get-GodotArtifactSha256 $activeArtifact -AllowMissing) -ceq $previousArtifactSha256)
    Add-Check 'owned invocation completion records are present' ($ownedResults.Count -gt 0)
    foreach ($ownedResult in $ownedResults) {
        Add-Check "owned invocation exited: $($ownedResult.ProcessId) / $($ownedResult.ProcessStartTimeUtcTicks)" (
            Test-GodotProcessCompletion $ownedResult)
    }
}
catch {
    $failure = $_.ToString()
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
        foreach ($path in @($probePath, "$probePath.import", $blendPath, "${blendPath}1")) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
        }
        $importedPath = Join-Path $project '.godot\imported'
        if (Test-Path -LiteralPath $importedPath) {
            Get-ChildItem -LiteralPath $importedPath -Filter "$probeName-*" -File | Remove-Item
        }
        $workPath = Join-Path $runPath 'blender-work'
        if (Test-Path -LiteralPath $workPath) { Remove-Item -LiteralPath $workPath -Recurse }
        $driverInventory = @(Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate)
        $summary = [ordered]@{
            ok = ($null -eq $failure)
            scope = 'independent technical diagnosis and asset pipeline; NOT preview gameplay validation'
            gameplayValidated = $false
            diagnosticScene = $diagnosticScene
            allowKnownVulkanLayerWarning = [bool]$AllowKnownVulkanLayerWarning
            powerAvailability = [ordered]@{
                acquired = $null -ne $powerRequest
                displayRequested = $true
                released = $null -ne $powerRequest -and $powerRequest.IsClosed -and $null -eq $powerReleaseFailure
                changesGlobalPowerPolicy = $false
            }
            startedAt = $started
            completedAt = (Get-Date).ToUniversalTime().ToString('o')
            godotVersion = $local.versionOutput
            projectVersion = $sourceIdentity.projectVersion
            inputSchemaVersion = $sourceIdentity.inputSchemaVersion
            runPath = $runPath
            gpuIndexOverride = $GpuIndex
            windowsDriverInventory = $driverInventory
            artifact = $artifactPath
            activeGameplayArtifact = $activeArtifact
            previousArtifactSha256 = $previousArtifactSha256
            artifactPromoted = $false
            reports = $reports
            processCompletions = @($ownedResults | Select-Object ProcessId, ProcessStartTimeUtcTicks, RuntimeProcessIds, ExitCode, ExitWitnesses,
                OutputComplete, StdoutComplete, StderrComplete)
            passed = @($checks | Where-Object { $_.passed }).Count
            total = $checks.Count
            checks = $checks.ToArray()
            error = $failure
        }
        if (Test-Path -LiteralPath $artifactPath -PathType Leaf) {
            $summary['artifactSha256'] = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        $json = $summary | ConvertTo-Json -Depth 8
        $json | Set-Content -LiteralPath (Join-Path $runPath 'result.json') -Encoding utf8
        $json | Set-Content -LiteralPath (Join-Path $runtime 'smoke-result.json') -Encoding utf8
        Write-Host "Godot checks: $($summary.passed)/$($summary.total); ok=$($summary.ok)"
        Write-Host "Evidence: $(Join-Path $runPath 'result.json')"
    }
    finally {
        if ($null -ne $lock) {
            $lock.Dispose()
            Remove-Item -LiteralPath $lockPath
        }
    }
    if ($null -ne $powerReleaseFailure) { throw $powerReleaseFailure }
}
