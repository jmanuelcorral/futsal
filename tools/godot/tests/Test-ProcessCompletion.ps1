#Requires -Version 7.2
[CmdletBinding()]
param([switch]$NativeProbe)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\Common.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$directory = Join-Path $root ('tools\godot\runtime\process-completion-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$shell = Join-Path $PSHOME 'pwsh.exe'
$probe = Join-Path $PSScriptRoot 'process_probe.ps1'
$treeProbe = Join-Path $PSScriptRoot 'process_tree_probe.ps1'
$checks = [Collections.Generic.List[object]]::new()
$controlled = [Collections.Generic.List[Diagnostics.Process]]::new()
$observed = [ordered]@{}
$failure = $null
$completed = $false
$lock = $null

function Check([string]$Name, [bool]$Passed) {
    $checks.Add([ordered]@{name = $Name; passed = $Passed})
    if (-not $Passed) { throw "FAIL $Name" }
}

function Rejected([string]$Name, [scriptblock]$Action) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Check $Name $rejected
}

function Start-Controlled {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $shell
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-File', $probe, '-DelaySeconds', '120')) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($info)
    $null = $process.SafeHandle
    $controlled.Add($process)
    return $process
}

function Run-Probe([string]$Name, [string[]]$Arguments, [string]$ExpectedChild = '', [int]$Timeout = 15) {
    return Invoke-GodotProcess -FilePath $shell -Arguments $Arguments -ExpectedChildExecutable $ExpectedChild `
        -WorkingDirectory $root -LogPrefix (Join-Path $directory $Name) -TimeoutSeconds $Timeout
}

function Fail-Probe([string]$Name, [string[]]$Arguments, [string]$Message, [string]$ExpectedChild = '', [int]$Timeout = 15) {
    $record = $null
    try { $null = Run-Probe $Name $Arguments $ExpectedChild $Timeout } catch { $record = $_ }
    $observed["$Name-failure"] = $(if ($null -ne $record) { $record.Exception.ToString() } else { 'Invocation unexpectedly succeeded.' })
    Check "$Name still fails the invocation" ($null -ne $record -and $record.Exception.Message -match $Message)
    return $record.Exception.Data['GodotProcessResult']
}

function Copy-Result($Result) {
    $copy = [ordered]@{}
    foreach ($property in $Result.PSObject.Properties) { $copy[$property.Name] = $property.Value }
    return [pscustomobject]$copy
}

function Exercise-BootstrapReader($Definition, $Result, [string]$Path) {
    & {
        param($source, $actualResult, $reportPath)
        $reports = [ordered]@{}
        function Add-Check([string]$Name, [bool]$Passed) { if (-not $Passed) { throw "FAIL $Name" } }
        . ([scriptblock]::Create($source))
        $null = Read-Report -Stage 'bootstrap-process-probe' -Path $reportPath -ProcessResult $actualResult -RequireRuntimeIdentity
    } $Definition $Result $Path 6>$null
}

function Test-PostExitPipeDrain {
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot '..\Common.ps1'), [ref]$null, [ref]$null)
    $branches = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text -ceq '$launcherExited'
    }, $true))
    Check 'pipe regression exercises the single actual production post-exit wait branch' ($branches.Count -eq 1)
    Check 'post-exit pipe wait no longer depends on overloaded Task aggregation' (
        -not $branches[0].Extent.Text.Contains('::WhenAll(', [StringComparison]::Ordinal))
    $wait = [scriptblock]::Create($branches[0].Extent.Text)
    $pipes = @(); $writers = @(); $readers = @()
    try {
        # Real incomplete ReadToEndAsync tasks have runtime subclasses that TaskCompletionSource
        # fixtures miss. Own both pipe ends locally; no orphan child or PID lookup is needed.
        foreach ($index in 0..1) {
            $pipe = [IO.Pipes.AnonymousPipeServerStream]::new(
                [IO.Pipes.PipeDirection]::In, [IO.HandleInheritability]::None)
            $pipes += $pipe
            $writers += [IO.Pipes.AnonymousPipeClientStream]::new(
                [IO.Pipes.PipeDirection]::Out, $pipe.ClientSafePipeHandle)
            $readers += [IO.StreamReader]::new($pipe)
        }
        $launcherExited = $true
        $activeChildren = @()
        $stdout = $readers[0].ReadToEndAsync()
        $stderr = $readers[1].ReadToEndAsync()
        Check 'both redirected readers are genuinely pending after simulated launcher exit' (
            -not $stdout.IsCompleted -and -not $stderr.IsCompleted)
        $output = @(& $wait)
        Check 'post-exit wait returns with both asynchronous pipes still pending' (
            $output.Count -eq 0 -and -not $stdout.IsCompleted -and -not $stderr.IsCompleted)
        $writers[1].Dispose()
        Check 'owned stderr pipe reaches EOF within a bounded wait' ($stderr.Wait(2000))
        $output = @(& $wait)
        Check 'post-exit wait handles mixed completed and pending real reader tasks' (
            $output.Count -eq 0 -and $stderr.IsCompleted -and -not $stdout.IsCompleted)
        $writers[0].Dispose()
        Check 'owned stdout pipe reaches EOF within a bounded wait' ($stdout.Wait(2000))
        $output = @(& $wait)
        Check 'post-exit wait also handles both drained pipes without emitting task results' (
            $output.Count -eq 0 -and $stdout.GetAwaiter().GetResult() -ceq '' -and $stderr.GetAwaiter().GetResult() -ceq '')

        foreach ($pending in @('stdout', 'stderr')) {
            $mixedPipe = [IO.Pipes.AnonymousPipeServerStream]::new(
                [IO.Pipes.PipeDirection]::In, [IO.HandleInheritability]::None)
            $mixedWriter = [IO.Pipes.AnonymousPipeClientStream]::new(
                [IO.Pipes.PipeDirection]::Out, $mixedPipe.ClientSafePipeHandle)
            $mixedReader = [IO.StreamReader]::new($mixedPipe)
            $emptyStream = [IO.MemoryStream]::new()
            $eofReader = [IO.StreamReader]::new($emptyStream)
            try {
                $pendingTask = $mixedReader.ReadToEndAsync()
                $finishedTask = $eofReader.ReadToEndAsync()
                $stdout = if ($pending -ceq 'stdout') { $pendingTask } else { $finishedTask }
                $stderr = if ($pending -ceq 'stderr') { $pendingTask } else { $finishedTask }
                Check "$pending pending fixture mixes synchronous EOF and actual asynchronous reader task types" (
                    $finishedTask.IsCompleted -and -not $pendingTask.IsCompleted -and
                    $finishedTask.GetType() -ne $pendingTask.GetType())
                $output = @(& $wait)
                Check "post-exit wait handles only $pending pending without dropping the other reader" (
                    $output.Count -eq 0 -and -not $pendingTask.IsCompleted -and $finishedTask.GetAwaiter().GetResult() -ceq '')
                $mixedWriter.Dispose()
                Check "$pending mixed reader reaches actual EOF within a bounded wait" ($pendingTask.Wait(2000))
            }
            finally {
                $mixedWriter.Dispose(); $mixedReader.Dispose(); $mixedPipe.Dispose()
                $eofReader.Dispose(); $emptyStream.Dispose()
            }
        }
    }
    finally {
        foreach ($writer in $writers) { $writer.Dispose() }
        foreach ($reader in $readers) { $reader.Dispose() }
        foreach ($pipe in $pipes) { $pipe.Dispose() }
    }
}

function Test-WrapperPipeTimeout {
    $common = Join-Path $PSScriptRoot '..\Common.ps1'
    $lines = [IO.File]::ReadAllLines($common)
    $anchors = @(for ($index = 0; $index -lt $lines.Length; $index++) {
        if ($lines[$index].Trim() -ceq '$launcherExited = $process.WaitForExit(25)') { $index + 1 }
    })
    Check 'pipe timeout observer has one production polling anchor' ($anchors.Count -eq 1)
    $script:pipeObservation = @{
        child = $null; failure = $null; prefix = (Join-Path $directory 'untracked-pipe-timeout')
        executable = $shell
    }
    $breakpoint = $null
    try {
        # Observe the live fixture child without changing the wrapper's empty child set.
        $breakpoint = Set-PSBreakpoint -Script $common -Line $anchors[0] -Action {
            if ($LogPrefix -ceq $script:pipeObservation.prefix -and $null -eq $script:pipeObservation.child) {
                try {
                    $found = @(Find-GodotOwnedChildren $process $script:pipeObservation.executable)
                    if ($found.Count -gt 1) {
                        foreach ($entry in $found) { $entry.Process.Dispose() }
                        throw 'Pipe fixture unexpectedly launched more than one child.'
                    }
                    if ($found.Count -eq 1) { $script:pipeObservation.child = $found[0] }
                }
                catch { $script:pipeObservation.failure = $_.Exception.Message }
            }
        }
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $timed = Fail-Probe 'untracked-pipe-timeout' @('-NoProfile', '-File', $treeProbe,
            '-ChildDelaySeconds', '8', '-ExitBeforeChild') 'Timed out after 2 seconds' '' 2
        $clock.Stop()
        $observed['untracked-pipe-timeout'] = $timed
        $observed['untracked-pipe-timeout-seconds'] = $clock.Elapsed.TotalSeconds
        Check 'fixture observer retained its live child identity without lookup after return' (
            $null -ne $script:pipeObservation.child -and $null -eq $script:pipeObservation.failure)
        Check 'complete wrapper returns before inherited pipes reach EOF' ($clock.Elapsed.TotalSeconds -lt 5)
        $held = $script:pipeObservation.child
        Check 'untracked pipe writer is still alive through its original fixture handle' (-not $held.Process.HasExited)
        Check 'timeout preserves the exited launcher witness but does not adopt the pipe writer' (
            $timed.ExitCode -eq 0 -and $timed.ExpectedChildExecutable -ceq '' -and
            $timed.ExitWitnesses.Count -eq 1 -and $timed.ExitWitnesses[0] -is [Futsal.Tooling.ProcessExitWitness] -and
            $held.ProcessId -notin $timed.RuntimeProcessIds)
        Check 'incomplete pipe evidence cannot satisfy invocation completion' (
            -not $timed.OutputComplete -and -not $timed.StdoutComplete -and -not $timed.StderrComplete -and
            -not (Test-GodotProcessCompletion $timed))
        Check 'incremental stdout survives abandonment and is persisted without a fake EOF' (
            $timed.Stdout.Contains('FUTSAL_CHILD_STARTED ', [StringComparison]::Ordinal) -and
            [IO.File]::ReadAllText($script:pipeObservation.prefix + '.stdout.log') -ceq $timed.Stdout)
        Rejected 'output assertions reject incomplete redirected evidence even with exit zero' { Assert-GodotOutput $timed }
        Check 'pipe timeout does not terminate the unrelated controlled process' (-not $unrelated.HasExited)
    }
    finally {
        if ($null -ne $breakpoint) { Remove-PSBreakpoint -Breakpoint $breakpoint }
        if ($null -ne $script:pipeObservation.child) {
            $held = $script:pipeObservation.child.Process
            if (-not $held.HasExited) { $held.Kill($true) }
            $held.WaitForExit()
            $held.Dispose()
        }
    }
}

try {
    if ($NativeProbe) {
        $lock = [IO.File]::Open((Join-Path $root 'tools\godot\runtime\test.lock'),
            [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    }
    $unrelated = Start-Controlled
    $running = Start-Controlled
    $runningStart = $running.StartTime.ToUniversalTime().Ticks
    Rejected 'running original owned handle cannot produce an exit witness' {
        [Futsal.Tooling.ProcessExitWitness]::Capture($running, $running.Id, $runningStart, $PID)
    }
    Check 'rejecting a running handle does not stop it' (-not $running.HasExited)
    $candidates = @(Find-GodotOwnedChildren $running $shell)
    Check 'same-executable unrelated live process is not an owned child' ($candidates.Count -eq 0 -and -not $unrelated.HasExited)
    Test-PostExitPipeDrain
    Test-WrapperPipeTimeout

    $normal = Run-Probe 'normal' @('-NoProfile', '-File', $probe, '-Value', 'a path with spaces')
    Assert-GodotOutput $normal
    $normalReport = $normal.Stdout | ConvertFrom-Json
    $observed['normal'] = $normal
    Check 'real owned exit has an immutable original-handle witness' (Test-GodotProcessCompletion $normal)
    Check 'native stdout identity belongs to that completed process' (Test-GodotReportedProcess $normal $normalReport.processId)
    Check 'argument and normal-exit behavior are preserved' ($normalReport.value -ceq 'a path with spaces' -and $normal.ExitCode -eq 0)
    Rejected 'captured process identity cannot be overwritten' { $normal.ExitWitnesses[0].ProcessId = $unrelated.Id }
    Check 'retained completed witness is not tied to the continued existence of a PID entry' (
        $normal.ExitWitnesses[0].ExitTimeUtcTicks -ge $normal.ExitWitnesses[0].StartTimeUtcTicks)

    $running.Kill($true)
    $running.WaitForExit()
    Rejected 'original handle rejects a controlled different process identity' {
        [Futsal.Tooling.ProcessExitWitness]::Capture($running, $unrelated.Id, $runningStart, $PID)
    }
    Rejected 'original handle rejects a controlled different creation identity' {
        [Futsal.Tooling.ProcessExitWitness]::Capture($running, $running.Id, ($runningStart + 1), $PID)
    }
    Rejected 'an exited handle cannot forge a different parent ownership relationship' {
        [Futsal.Tooling.ProcessExitWitness]::Capture($running, $running.Id, $runningStart, $unrelated.Id)
    }
    $retained = [Futsal.Tooling.ProcessExitWitness]::Capture($running, $running.Id, $runningStart, $PID)
    Check 'exit can be witnessed while the terminated original kernel handle is retained' ($retained.ProcessId -eq $running.Id)
    Check 'identity mismatch did not stop the unrelated live process' (-not $unrelated.HasExited)

    foreach ($change in @(
            @{ProcessId = $unrelated.Id}, @{ProcessId = 0}, @{ProcessId = [string]$normal.ProcessId},
            @{ProcessStartTimeUtcTicks = ($normal.ProcessStartTimeUtcTicks + 1)}, @{ExitCode = 7},
            @{RuntimeProcessIds = @()}, @{RuntimeProcessIds = @($unrelated.Id)},
            @{RuntimeProcessIds = @($normal.ProcessId, $normal.ProcessId)}, @{RuntimeProcessIds = @([string]$normal.ProcessId)},
            @{OutputComplete = $false}, @{OutputComplete = 'true'}, @{OutputComplete = 1},
            @{StdoutComplete = $false}, @{StderrComplete = $false},
            @{ExitWitnesses = @()}, @{ExitWitnesses = @($normal.ExitWitnesses[0], $normal.ExitWitnesses[0])},
            @{ExitWitnesses = @([pscustomobject]@{ProcessId = $normal.ProcessId; ExitCode = 0})})) {
        $mutant = Copy-Result $normal
        foreach ($key in $change.Keys) { $mutant.$key = $change[$key] }
        Check ('invalid/missing completion evidence fails: ' + ($change | ConvertTo-Json -Compress -Depth 5)) (
            -not (Test-GodotProcessCompletion $mutant))
    }
    $missing = Copy-Result $normal
    $missing.PSObject.Properties.Remove('ProcessId')
    Check 'missing launcher identity cannot make an empty aggregation green' (-not (Test-GodotProcessCompletion $missing))
    $missingOutput = Copy-Result $normal
    $missingOutput.PSObject.Properties.Remove('OutputComplete')
    Check 'missing output-completion evidence cannot inherit completed process witnesses' (
        -not (Test-GodotProcessCompletion $missingOutput))
    foreach ($id in @($null, 0, [string]$normal.ProcessId, [double]$normal.ProcessId, $unrelated.Id)) {
        Check "reported PID must be a real owned integer: $id / $($null -eq $id) / $($id -is [double])" (
            -not (Test-GodotReportedProcess $normal $id))
    }

    $nonzero = Fail-Probe 'nonzero' @('-NoProfile', '-File', $probe, '-ExitCode', '7') 'exited 7'
    $observed['nonzero'] = $nonzero
    Check 'nonzero exit retains real completion and exit code seven' (
        (Test-GodotProcessCompletion $nonzero) -and $nonzero.ExitCode -eq 7)
    $exitOne = Fail-Probe 'nonzero-one' @('-NoProfile', '-File', $probe, '-ExitCode', '1',
        '-Value', 'retained stdout for exit one') 'exited 1'
    $observed['nonzero-one'] = $exitOne
    $exitOneReport = $exitOne.Stdout | ConvertFrom-Json
    Check 'exit one remains a failed invocation with its original completed witness and unmodified stdout' (
        (Test-GodotProcessCompletion $exitOne) -and $exitOne.ExitCode -eq 1 -and
        $exitOne.ExitWitnesses[0].ExitCode -eq 1 -and
        (Test-GodotReportedProcess $exitOne $exitOneReport.processId) -and
        $exitOneReport.value -ceq 'retained stdout for exit one')
    $timeout = Fail-Probe 'timeout' @('-NoProfile', '-File', $probe, '-DelaySeconds', '30') 'Timed out after 2 seconds' '' 2
    $observed['timeout'] = $timeout
    Check 'timeout retains actual cleanup completion instead of a late PID lookup' (Test-GodotProcessCompletion $timeout)
    $timeoutReport = $timeout.Stdout | ConvertFrom-Json
    Check 'timeout stdout cannot supply an unobserved process identity' (Test-GodotReportedProcess $timeout $timeoutReport.processId)

    $child = Run-Probe 'child' @('-NoProfile', '-File', $treeProbe) $shell
    $observed['child'] = $child
    $spawn = (($child.Stdout -split '\r?\n' | Where-Object { $_ -like 'FUTSAL_CHILD_STARTED *' }) -replace '^FUTSAL_CHILD_STARTED ', '') |
        ConvertFrom-Json
    Check 'real child and launcher both have separate exit witnesses' (
        (Test-GodotProcessCompletion $child) -and $child.ExitWitnesses.Count -eq 2 -and
        $child.ProcessId -eq $spawn.parent -and $child.RuntimeProcessIds.Count -eq 1)
    Check 'real child stdout PID binds to its observed original child handle' (Test-GodotReportedProcess $child $spawn.child)
    Check 'launcher PID cannot impersonate a required runtime child' (-not (Test-GodotReportedProcess $child $child.ProcessId))
    Check 'a live same-executable process was neither adopted nor stopped' (
        $unrelated.Id -notin $child.RuntimeProcessIds -and -not $unrelated.HasExited)
    $childNonzero = Fail-Probe 'child-nonzero' @('-NoProfile', '-File', $treeProbe,
        '-ChildDelaySeconds', '1', '-ChildExitCode', '7') 'Runtime child exited 7' $shell
    $observed['child-nonzero'] = $childNonzero
    Check 'launcher exit zero cannot hide actual runtime child exit seven' (
        (Test-GodotProcessCompletion $childNonzero) -and $childNonzero.ExitCode -eq 0 -and
        @($childNonzero.ExitWitnesses | Where-Object ExitCode -eq 7).Count -eq 1)
    Check 'negative child reports must use an actually observed completed child identity' (
        Test-GodotReportedProcess $childNonzero $childNonzero.RuntimeProcessIds[0])
    $treeTimeout = Fail-Probe 'tree-timeout' @('-NoProfile', '-File', $treeProbe, '-ChildDelaySeconds', '30') `
        'Timed out after 2 seconds' $shell 2
    $observed['tree-timeout'] = $treeTimeout
    Check 'timeout observes both owned launcher and child termination' (
        (Test-GodotProcessCompletion $treeTimeout) -and $treeTimeout.ExitWitnesses.Count -eq 2)
    $orphanTimeout = Fail-Probe 'child-outlives-launcher' @('-NoProfile', '-File', $treeProbe,
        '-ChildDelaySeconds', '30', '-ExitBeforeChild') 'Timed out after 3 seconds' $shell 3
    $observed['child-outlives-launcher'] = $orphanTimeout
    Check 'exited launcher does not make its running owned child complete' (
        (Test-GodotProcessCompletion $orphanTimeout) -and $orphanTimeout.ExitCode -eq 0 -and
        $orphanTimeout.ExitWitnesses.Count -eq 2 -and
        $orphanTimeout.ExitWitnesses[1].ExitTimeUtcTicks -gt $orphanTimeout.ExitWitnesses[0].ExitTimeUtcTicks)
    $missingChild = Fail-Probe 'missing-child' @('-NoProfile', '-File', $probe) 'No owned runtime child handle' $shell
    $observed['missing-child'] = $missingChild
    Check 'missing expected child cannot borrow a live unrelated executable' (
        -not (Test-GodotProcessCompletion $missingChild) -and -not $unrelated.HasExited)
    Check 'missing child cannot be repaired from the unrelated reported PID' (
        -not (Test-GodotReportedProcess $missingChild $unrelated.Id))

    $diagnostic = Run-Probe 'error-output' @('-NoProfile', '-Command', '[Console]::Error.WriteLine("ERROR: deliberate process-output probe")')
    Rejected 'completion proof does not suppress existing unexpected-output rejection' { Assert-GodotOutput $diagnostic }
    $encoding = Run-Probe 'encoding' @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'process_encoding_probe.ps1'),
        '-LogPrefix', (Join-Path $directory 'encoding-child'))
    Assert-GodotOutput $encoding
    $decoded = $encoding.Stdout | ConvertFrom-Json
    Check 'UTF-8 reader/writer and legacy CP437 wrapper remain correct' (
        $decoded.stdout_ok -and $decoded.stderr_ok -and $decoded.parent_code_page -eq 437 -and
        (Test-GodotProcessCompletion $encoding))
    foreach ($stream in @('Output', 'Error')) {
        $invalid = Fail-Probe "invalid-utf8-$stream" @('-NoProfile', '-Command',
            "[Console]::OpenStandard$stream().WriteByte(255)") 'Unable to translate bytes'
        $observed["invalid-utf8-$stream"] = $invalid
        Check "$stream decoding failure retains the launcher witness without accepting incomplete text" (
            $invalid.ExitWitnesses.Count -eq 1 -and -not $invalid.OutputComplete -and
            -not (Test-GodotProcessCompletion $invalid))
    }

    $foundationPath = Join-Path $PSScriptRoot '..\Test-Godot.ps1'
    $ast = [Management.Automation.Language.Parser]::ParseFile($foundationPath, [ref]$null, [ref]$null)
    $reader = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Read-Report'}, $false)
    $reportPath = Join-Path $directory 'bootstrap-report.json'
    $report = @{ok = $true; passed = 1; total = 1; checks = @(@{name = 'fixture'; passed = $true}); process_id = $normalReport.processId}
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
    Exercise-BootstrapReader $reader.Extent.Text $normal $reportPath
    Check 'actual foundation bootstrap reader accepts its completed native identity' $true
    $report.process_id = $unrelated.Id
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
    Rejected 'actual foundation bootstrap reader rejects an unrelated live report PID' {
        Exercise-BootstrapReader $reader.Extent.Text $normal $reportPath
    }
    [void]$report.Remove('process_id')
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
    Rejected 'actual foundation bootstrap reader requires runtime PID instead of silently omitting it' {
        Exercise-BootstrapReader $reader.Extent.Text $normal $reportPath
    }
    foreach ($name in @('Common.ps1', 'Test-MicroSlice.ps1', 'Test-Godot.ps1',
            'ArtifactPromotion.ps1', 'tests\Test-ArtifactPromotion.ps1',
            'tests\Test-ProcessCompletion.ps1', 'tests\process_tree_probe.ps1', 'tests\Test-DefaultEntrypoint.ps1')) {
        $path = Join-Path $PSScriptRoot "..\$name"
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        Check "coupled process tooling parses: $name" ($errors.Count -eq 0)
    }
    foreach ($name in @('Test-MicroSlice.ps1', 'Test-Godot.ps1')) {
        $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\$name") -Raw
        Check "$name aggregates original completion witnesses, not late owned PID queries" (
            $source.Contains('Test-GodotProcessCompletion $ownedResult') -and
            $source -notmatch 'Get-Process\s+-Id\s+\$(ownedPid|timeoutReport)' -and -not $source.Contains('$ownedPids'))
    }
    $guards = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Test-DefaultEntrypoint.ps1') -Raw
    Check 'negative entrypoint runner uses original child completion, never report-PID liveness' (
        $guards.Contains('-ExpectedChildExecutable $local.godotPath') -and
        $guards.Contains('Test-GodotReportedProcess $failedResult $report[') -and $guards -notmatch 'Get-Process\s+-Id')

    if ($NativeProbe) {
        $godot = Get-GodotInstallation
        foreach ($mode in @('delayed', 'immediate')) {
            $arguments = @('--headless', '--path', (Join-Path $root 'game'), '--audio-driver', 'Dummy',
                '--script', (Join-Path $PSScriptRoot 'process_probe.gd'))
            if ($mode -eq 'immediate') { $arguments += @('--', '--immediate') }
            $native = Invoke-GodotProcess -FilePath $godot.consolePath -ExpectedChildExecutable $godot.godotPath `
                -Arguments $arguments -WorkingDirectory $root -LogPrefix (Join-Path $directory "native-$mode") -TimeoutSeconds 15
            Assert-GodotOutput $native
            $lines = @($native.Stdout -split '\r?\n' | Where-Object { $_ -like 'FUTSAL_PROCESS_PROBE *' })
            Check "$mode native process emitted exactly one identity record" ($lines.Count -eq 1)
            $record = $lines[0].Substring('FUTSAL_PROCESS_PROBE '.Length) | ConvertFrom-Json
            $observed["native-$mode"] = $native
            Check "$mode actual Godot console child has completed identity evidence" (
                (Test-GodotReportedProcess $native $record.process_id) -and $native.ProcessId -ne $record.process_id)
            Check "$mode native probe is headless and uses the canonical engine" (
                $record.headless -eq $true -and [IO.Path]::GetFullPath($record.executable) -ieq [IO.Path]::GetFullPath($godot.godotPath))
        }
    }
    Check 'late aggregation still uses the original completed identity' (Test-GodotProcessCompletion $normal)
    Check 'all helper operations leave the unrelated live process untouched' (-not $unrelated.HasExited)
    $completed = $true
}
catch {
    $failure = $_.Exception.Message
    $checks.Add([ordered]@{name = 'process lifecycle suite reached completion'; passed = $false; error = $failure})
}
finally {
    foreach ($process in $controlled) {
        if (-not $process.HasExited) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $process.Dispose()
    }
    if ($null -ne $lock) {
        $lock.Dispose()
        Remove-Item -LiteralPath (Join-Path $root 'tools\godot\runtime\test.lock')
    }
}
$failed = @($checks | Where-Object { -not $_['passed'] }).Count
$report = [ordered]@{
    ok = $completed -and $failed -eq 0; passed = $checks.Count - $failed; total = $checks.Count; checks = $checks.ToArray()
    scope = 'real owned process completion/identity; NOT game, export or GPU validation'
    nativeProbe = [bool]$NativeProbe; evidence = $directory; error = $failure
    observed = $observed
}
$report | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $directory 'result.json') -Encoding utf8
Write-Output ('FUTSAL_PROCESS_COMPLETION_TESTS ' + ($report | ConvertTo-Json -Compress -Depth 16))
exit $(if ($report.ok) { 0 } else { 1 })
