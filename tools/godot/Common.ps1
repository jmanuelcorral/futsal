#Requires -Version 7.2
Set-StrictMode -Version Latest

# Native Godot reports and redirected PowerShell wrappers use the same encoding.
if ([Console]::IsOutputRedirected) {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
}

if (-not ('Futsal.Tooling.ProcessExitWitness' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;
namespace Futsal.Tooling {
    public sealed class ProcessOutputCapture {
        private readonly object gate = new object();
        private readonly StringBuilder text = new StringBuilder();
        private bool stopped, eof;
        public Task Completion { get; }
        public bool Complete { get { lock (gate) return eof; } }
        public string Text { get { lock (gate) return text.ToString(); } }
        public ProcessOutputCapture(StreamReader reader) {
            Completion = ReadAsync(reader);
            // Abandoned readers can fault when their process streams are disposed.
            _ = Completion.ContinueWith(task => { _ = task.Exception; },
                TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously);
        }
        private async Task ReadAsync(StreamReader reader) {
            var buffer = new char[4096];
            while (true) {
                int count = await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
                lock (gate) {
                    if (stopped) return;
                    if (count == 0) { eof = true; return; }
                    text.Append(buffer, 0, count);
                }
            }
        }
        public void Stop() { lock (gate) stopped = true; }
    }
    public static class ProcessOwnership {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct ProcessEntry {
            public uint Size, Usage, Id;
            public IntPtr Heap;
            public uint Module, Threads, Parent;
            public int Priority;
            public uint Flags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessBasicInformation {
            public IntPtr ExitStatus, Peb, Affinity, Priority, Id, Parent;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern SafeFileHandle CreateToolhelp32Snapshot(uint flags, uint id);
        [DllImport("kernel32.dll", EntryPoint = "Process32FirstW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool First(SafeFileHandle snapshot, ref ProcessEntry entry);
        [DllImport("kernel32.dll", EntryPoint = "Process32NextW", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool Next(SafeFileHandle snapshot, ref ProcessEntry entry);
        [DllImport("ntdll.dll")]
        private static extern int NtQueryInformationProcess(SafeProcessHandle process, int kind,
            out ProcessBasicInformation info, int size, out int returned);
        [DllImport("kernel32.dll", EntryPoint = "QueryFullProcessImageNameW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ImageName(SafeProcessHandle process, uint flags, StringBuilder name, ref int size);
        public static int[] ChildCandidates(int parent) {
            using (var snapshot = CreateToolhelp32Snapshot(2, 0)) {
                if (snapshot.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                var entry = new ProcessEntry { Size = (uint)Marshal.SizeOf<ProcessEntry>() };
                var result = new List<int>();
                if (!First(snapshot, ref entry)) throw new Win32Exception(Marshal.GetLastWin32Error());
                do {
                    if (entry.Parent == parent) result.Add(checked((int)entry.Id));
                } while (Next(snapshot, ref entry));
                if (Marshal.GetLastWin32Error() != 18) throw new Win32Exception(Marshal.GetLastWin32Error());
                return result.ToArray();
            }
        }
        public static int ParentId(Process process) {
            ProcessBasicInformation info;
            int returned;
            int status = NtQueryInformationProcess(process.SafeHandle, 0, out info,
                Marshal.SizeOf<ProcessBasicInformation>(), out returned);
            if (status != 0) throw new InvalidOperationException("Cannot verify parent from process handle: " + status);
            return checked((int)info.Parent.ToInt64());
        }
        public static string Executable(Process process) {
            var text = new StringBuilder(32768);
            int size = text.Capacity;
            if (!ImageName(process.SafeHandle, 0, text, ref size)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return text.ToString();
        }
    }
    public sealed class ProcessExitWitness {
        public int ProcessId { get; }
        public int ParentProcessId { get; }
        public long StartTimeUtcTicks { get; }
        public long ExitTimeUtcTicks { get; }
        public int ExitCode { get; }
        private ProcessExitWitness(Process process, long start, int parent) {
            ProcessId = process.Id;
            ParentProcessId = parent;
            StartTimeUtcTicks = start;
            ExitTimeUtcTicks = process.ExitTime.ToUniversalTime().Ticks;
            ExitCode = process.ExitCode;
        }
        public static ProcessExitWitness Capture(Process process, int expectedId, long expectedStart, int parent) {
            if (process == null || expectedId <= 0 || parent <= 0 ||
                process.Id != expectedId || process.StartTime.ToUniversalTime().Ticks != expectedStart ||
                ProcessOwnership.ParentId(process) != parent)
                throw new InvalidOperationException("Owned process identity does not match its original handle.");
            if (!process.WaitForExit(0) || !process.HasExited)
                throw new InvalidOperationException("The original owned process has not exited.");
            return new ProcessExitWitness(process, expectedStart, parent);
        }
    }
}
'@
}

function Find-GodotOwnedChildren([Diagnostics.Process]$Parent, [string]$Executable) {
    $parentStart = $Parent.StartTime.ToUniversalTime().Ticks
    foreach ($candidate in [Futsal.Tooling.ProcessOwnership]::ChildCandidates($Parent.Id)) {
        $child = $null
        $retained = $false
        try {
            $child = [Diagnostics.Process]::GetProcessById($candidate)
            $null = $child.SafeHandle
            $start = $child.StartTime.ToUniversalTime().Ticks
            # The snapshot supplies candidates only; parent, image and times come from the opened identity.
            if ([Futsal.Tooling.ProcessOwnership]::ParentId($child) -ne $Parent.Id -or $start -lt $parentStart -or
                ($Parent.HasExited -and $start -gt $Parent.ExitTime.ToUniversalTime().Ticks)) { continue }
            if ([IO.Path]::GetFullPath([Futsal.Tooling.ProcessOwnership]::Executable($child)) -ine
                [IO.Path]::GetFullPath($Executable)) { continue }
            $retained = $true
            [pscustomobject]@{ Process = $child; ProcessId = $child.Id; StartTimeUtcTicks = $start }
        }
        catch [ArgumentException] { continue }
        catch [ComponentModel.Win32Exception] {
            if ($_.Exception.NativeErrorCode -ne 87) { throw }
        }
        finally {
            if ($null -ne $child -and -not $retained) { $child.Dispose() }
        }
    }
}

function Test-GodotProcessCompletion($Result) {
    if ($null -eq $Result) { return $false }
    foreach ($property in @('ProcessId', 'ProcessStartTimeUtcTicks', 'RuntimeProcessIds', 'ExpectedChildExecutable',
            'ExitCode', 'ExitWitnesses', 'OutputComplete', 'StdoutComplete', 'StderrComplete')) {
        if ($property -notin $Result.PSObject.Properties.Name) { return $false }
    }
    if (($Result.ProcessId -isnot [int] -and $Result.ProcessId -isnot [long]) -or $Result.ProcessId -le 0 -or
        $Result.ProcessStartTimeUtcTicks -isnot [long] -or $Result.ProcessStartTimeUtcTicks -le 0 -or
        ($Result.ExitCode -isnot [int] -and $Result.ExitCode -isnot [long]) -or
        $Result.ExpectedChildExecutable -isnot [string] -or
        $Result.RuntimeProcessIds -isnot [Collections.IList] -or $Result.RuntimeProcessIds.Count -eq 0 -or
        $Result.ExitWitnesses -isnot [Collections.IList]) { return $false }
    foreach ($property in @('OutputComplete', 'StdoutComplete', 'StderrComplete')) {
        if ($Result.$property -isnot [bool] -or -not $Result.$property) { return $false }
    }
    $runtimeIds = [Collections.Generic.HashSet[int]]::new()
    foreach ($id in $Result.RuntimeProcessIds) {
        if (($id -isnot [int] -and $id -isnot [long]) -or $id -le 0 -or -not $runtimeIds.Add($id)) { return $false }
    }
    if ([string]::IsNullOrEmpty($Result.ExpectedChildExecutable)) {
        if ($runtimeIds.Count -ne 1 -or -not $runtimeIds.Contains($Result.ProcessId)) { return $false }
    }
    elseif ($runtimeIds.Contains($Result.ProcessId)) { return $false }
    $expected = [Collections.Generic.HashSet[int]]::new($runtimeIds)
    [void]$expected.Add($Result.ProcessId)
    if ($Result.ExitWitnesses.Count -ne $expected.Count) { return $false }
    foreach ($witness in $Result.ExitWitnesses) {
        if ($witness -isnot [Futsal.Tooling.ProcessExitWitness] -or -not $expected.Remove($witness.ProcessId) -or
            $witness.ExitTimeUtcTicks -lt $witness.StartTimeUtcTicks) { return $false }
        if ($witness.ProcessId -eq $Result.ProcessId) {
            if ($witness.StartTimeUtcTicks -ne $Result.ProcessStartTimeUtcTicks -or $witness.ExitCode -ne $Result.ExitCode) { return $false }
        }
        elseif ($witness.ParentProcessId -ne $Result.ProcessId -or
            $witness.StartTimeUtcTicks -lt $Result.ProcessStartTimeUtcTicks) { return $false }
    }
    return $expected.Count -eq 0
}

function Test-GodotReportedProcess($Result, $ProcessId) {
    return (($ProcessId -is [int] -or $ProcessId -is [long]) -and $ProcessId -gt 0 -and
        (Test-GodotProcessCompletion $Result) -and $ProcessId -in $Result.RuntimeProcessIds)
}

function Get-GodotExpectedProjectIdentity {
    return [pscustomobject]@{ projectVersion = '0.5.0-preview'; inputSchemaVersion = 3 }
}

function Assert-GodotProjectConfiguration {
    param([Parameter(Mandatory)][string]$Settings)
    $identity = Get-GodotExpectedProjectIdentity
    $required = [ordered]@{
        'config/name' = '"Futsal — Laboratorio 5v5"'
        'config/version' = '"' + $identity.projectVersion + '"'
        'run/main_scene' = '"res://match/match.tscn"'
        'preparation/input_schema_version' = [string]$identity.inputSchemaVersion
    }
    foreach ($key in $required.Keys) {
        $pattern = '(?m)^' + [regex]::Escape($key + '=' + $required[$key]) + '\r?$'
        if ($Settings -notmatch $pattern) {
            throw "Gameplay preview requires exact $key=$($required[$key]); no old-schema or diagnostic fallback."
        }
    }
}

function Get-GodotInstallation {
    $release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
    $inventoryPath = Join-Path $PSScriptRoot 'local.json'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw 'Run tools\godot\Install-Godot.ps1 first; no Godot installation is registered.'
    }
    $local = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
    if ($local.version -ne $release.version -or $local.editorArchiveSha512 -ne $release.editor.sha512 -or
        $local.templatesArchiveSha512 -ne $release.templates.sha512) {
        throw 'Godot inventory and release pin disagree. Run Install-Godot.ps1 to verify the installation.'
    }
    foreach ($file in $local.editorFiles) {
        if (-not (Test-Path -LiteralPath $file.path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $file.path -Algorithm SHA512).Hash.ToLowerInvariant() -ne $file.sha512) {
            throw "Godot binary missing or changed: $($file.path). Nothing will be executed."
        }
    }
    return $local
}

function Invoke-GodotProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$LogPrefix,
        [System.Collections.IDictionary]$Environment = @{},
        [string]$ExpectedChildExecutable = '',
        [ValidateRange(0, 3600)][int]$TimeoutSeconds = 120
    )
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FilePath
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
    $info.CreateNoWindow = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    foreach ($key in $Environment.Keys) { $info.Environment[$key] = [string]$Environment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $started = $false
    $processStart = 0L
    $stdout = $null
    $stderr = $null
    $stdoutCapture = $null
    $stderrCapture = $null
    $children = [Collections.Generic.List[object]]::new()
    $result = $null
    $failure = $null
    try {
        New-Item -ItemType Directory -Path (Split-Path $LogPrefix -Parent) -Force | Out-Null
        $started = $process.Start()
        if (-not $started) { throw "Could not start $FilePath." }
        $null = $process.SafeHandle
        $processStart = $process.StartTime.ToUniversalTime().Ticks
        $stdoutCapture = [Futsal.Tooling.ProcessOutputCapture]::new($process.StandardOutput)
        $stderrCapture = [Futsal.Tooling.ProcessOutputCapture]::new($process.StandardError)
        $stdout = $stdoutCapture.Completion
        $stderr = $stderrCapture.Completion
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while ($true) {
            if ($children.Count -eq 0 -and -not [string]::IsNullOrEmpty($ExpectedChildExecutable)) {
                foreach ($child in @(Find-GodotOwnedChildren $process $ExpectedChildExecutable)) {
                    $children.Add($child)
                }
            }
            $launcherExited = $process.WaitForExit(25)
            $activeChildren = @($children | Where-Object { -not $_.Process.WaitForExit(0) })
            if ($launcherExited -and $activeChildren.Count -eq 0 -and $stdout.IsCompleted -and $stderr.IsCompleted) { break }
            if ($TimeoutSeconds -gt 0 -and [DateTime]::UtcNow -ge $deadline) {
                throw "Timed out after $TimeoutSeconds seconds: $FilePath (owned PID $($process.Id))."
            }
            if ($launcherExited) {
                if ($activeChildren.Count -gt 0) { [void]$activeChildren[0].Process.WaitForExit(25) }
                # Both reads already run asynchronously. Wait on a pending reader, avoiding
                # runtime-specific WhenAll overload binding; the outer loop still owns the deadline.
                elseif (-not $stdout.IsCompleted) { [void]$stdout.Wait(25) }
                elseif (-not $stderr.IsCompleted) { [void]$stderr.Wait(25) }
            }
        }
        [void]$stdout.GetAwaiter().GetResult()
        [void]$stderr.GetAwaiter().GetResult()
        $output = $stdoutCapture.Text
        $errors = $stderrCapture.Text
        if ($process.ExitCode -ne 0) {
            throw "$FilePath exited $($process.ExitCode).`n$output`n$errors"
        }
        if (-not [string]::IsNullOrEmpty($ExpectedChildExecutable) -and $children.Count -eq 0) {
            throw 'No owned runtime child handle was observed; report PIDs cannot fill that ownership gap.'
        }
        foreach ($child in $children) {
            if ($child.Process.ExitCode -ne 0) {
                throw "Runtime child exited $($child.Process.ExitCode) (owned PID $($child.ProcessId)).`n$output`n$errors"
            }
        }
    }
    catch { $failure = $_ }
    finally {
        try {
            # Exit-code availability is not the kernel exit signal; wait on every retained original handle.
            if ($started) {
                if (-not $process.HasExited) { $process.Kill($true) }
                $process.WaitForExit()
            }
            foreach ($child in $children) {
                if (-not $child.Process.HasExited) { $child.Process.Kill($true) }
                $child.Process.WaitForExit()
            }
            $drainWatch = [Diagnostics.Stopwatch]::StartNew()
            while ((($null -ne $stdout -and -not $stdout.IsCompleted) -or
                    ($null -ne $stderr -and -not $stderr.IsCompleted)) -and $drainWatch.ElapsedMilliseconds -lt 1000) {
                [Threading.Thread]::Sleep(10)
            }
            if ($null -ne $stdoutCapture) { $stdoutCapture.Stop() }
            if ($null -ne $stderrCapture) { $stderrCapture.Stop() }
            if ($started) {
                $witnesses = @([Futsal.Tooling.ProcessExitWitness]::Capture($process, $process.Id, $processStart, $PID))
                foreach ($child in $children) {
                    $witnesses += [Futsal.Tooling.ProcessExitWitness]::Capture(
                        $child.Process, $child.ProcessId, $child.StartTimeUtcTicks, $process.Id)
                }
                $runtimeIds = @($process.Id)
                if (-not [string]::IsNullOrEmpty($ExpectedChildExecutable)) { $runtimeIds = @($children | ForEach-Object ProcessId) }
                $stdoutComplete = $null -ne $stdoutCapture -and $stdoutCapture.Complete
                $stderrComplete = $null -ne $stderrCapture -and $stderrCapture.Complete
                $result = [pscustomobject]@{
                    Stdout = $(if ($null -ne $stdoutCapture) { $stdoutCapture.Text } else { '' })
                    Stderr = $(if ($null -ne $stderrCapture) { $stderrCapture.Text } else { '' })
                    OutputComplete = $stdoutComplete -and $stderrComplete
                    StdoutComplete = $stdoutComplete; StderrComplete = $stderrComplete
                    ExitCode = $process.ExitCode; ProcessId = $process.Id
                    ProcessStartTimeUtcTicks = $processStart; ExpectedChildExecutable = $ExpectedChildExecutable
                    RuntimeProcessIds = $runtimeIds; ExitWitnesses = $witnesses
                }
            }
            if ($null -ne $result) {
                [IO.File]::WriteAllText("$LogPrefix.stdout.log", $result.Stdout)
                [IO.File]::WriteAllText("$LogPrefix.stderr.log", $result.Stderr)
            }
        }
        finally {
            foreach ($child in $children) { $child.Process.Dispose() }
            $process.Dispose()
        }
    }
    if ($null -ne $failure) {
        $failure.Exception.Data['GodotProcessResult'] = $result
        $PSCmdlet.ThrowTerminatingError($failure)
    }
    if (-not (Test-GodotProcessCompletion $result)) { throw 'Incomplete owned-process exit or redirected-output evidence.' }
    return $result
}

function Get-GodotPresentationDiagnosticContract {
    return @{
        prefix = 'AthleteView rejected invalid presentation data: '
        minimumCases = [ordered]@{
            gesture_kind = 1; gesture_vectors = 2; gesture_direction = 1; gesture_window = 1
            interpolation_weight = 1; frame_parameters = 1; launch_kind = 1; event_kind = 1
            event_contact = 1; snapshot_context_required = 1; context_ticks = 1
        }
    }
}

function Assert-GodotOutput {
    param(
        [Parameter(Mandatory)]$Result,
        [System.Collections.IDictionary]$ExpectedErrors = @{},
        [System.Collections.IDictionary]$ExpectedDevelopmentWarnings = @{},
        [switch]$AllowKnownVulkanLayerWarning,
        [System.Collections.IDictionary]$ExpectedPresentationErrors = @{},
        [System.Collections.IDictionary]$ExpectedAimGuideErrors = @{}
    )
    if ($Result.ExitCode -ne 0) { throw "Godot exited $($Result.ExitCode)." }
    if ('OutputComplete' -in $Result.PSObject.Properties.Name -and
        ($Result.OutputComplete -isnot [bool] -or -not $Result.OutputComplete)) {
        throw 'Redirected process output is incomplete; exit zero is not sufficient evidence.'
    }
    $output = ($Result.Stdout + "`n" + $Result.Stderr).Replace("`r`n", "`n")
    $output = [regex]::Replace($output, '\x1b\[[0-?]*[ -/]*[@-~]', '')
    foreach ($message in $ExpectedErrors.Keys) {
        if ($message -isnot [string] -or -not $message.StartsWith('ERROR: MatchHUD.', [StringComparison]::Ordinal) -or
            ($ExpectedErrors[$message] -isnot [int] -and $ExpectedErrors[$message] -isnot [long]) -or
            $ExpectedErrors[$message] -lt 1) {
            throw "Invalid expected HUD diagnostic: $message"
        }
        $pattern = '(?m)^' + [regex]::Escape([string]$message) + '$'
        $count = [regex]::Matches($output, $pattern).Count
        if ($count -ne [int]$ExpectedErrors[$message]) {
            throw "Expected $($ExpectedErrors[$message]) occurrences of '$message'; observed $count."
        }
        $output = [regex]::Replace($output, $pattern, '')
    }
    foreach ($message in $ExpectedAimGuideErrors.Keys) {
        $expected = $ExpectedAimGuideErrors[$message]
        if ($message -cne 'ERROR: WorldAimGuide.present: solución o posición de render no válida.' -or
            ($expected -isnot [int] -and $expected -isnot [long]) -or $expected -lt 1) {
            throw "Invalid expected aim-guide diagnostic: $message"
        }
        $pattern = '(?m)^' + [regex]::Escape($message) + '$'
        $count = [regex]::Matches($output, $pattern).Count
        if ($count -ne $expected) { throw "Expected $expected occurrences of '$message'; observed $count." }
        $output = [regex]::Replace($output, $pattern, '')
    }
    $presentation = Get-GodotPresentationDiagnosticContract
    $presentationPrefix = 'ERROR: ' + $presentation.prefix
    foreach ($message in $ExpectedPresentationErrors.Keys) {
        $expected = $ExpectedPresentationErrors[$message]
        if ($message -isnot [string] -or -not $message.StartsWith($presentationPrefix, [StringComparison]::Ordinal) -or
            $message.Substring($presentationPrefix.Length) -cnotin $presentation.minimumCases.Keys -or
            ($expected -isnot [int] -and $expected -isnot [long]) -or $expected -lt 1) {
            throw "Invalid expected presentation diagnostic: $message"
        }
        $pattern = '(?m)^' + [regex]::Escape($message) + '$'
        $count = [regex]::Matches($output, $pattern).Count
        if ($count -ne $expected) { throw "Expected $expected occurrences of '$message'; observed $count." }
        $output = [regex]::Replace($output, $pattern, '')
    }
    foreach ($message in $ExpectedDevelopmentWarnings.Keys) {
        if ($message -isnot [string] -or
            ($message -cnotmatch '^WARNING: (?:Modo de desarrollo |No se pudo cambiar la IA: |No se pudo aplicar el entrenamiento: |Cierra Desarrollo )' -and
                $message -cne 'WARNING: Ejercicio de entrenamiento no válido') -or
            ($ExpectedDevelopmentWarnings[$message] -isnot [int] -and $ExpectedDevelopmentWarnings[$message] -isnot [long]) -or
            $ExpectedDevelopmentWarnings[$message] -lt 1) {
            throw "Invalid expected development diagnostic: $message"
        }
        $pattern = '(?m)^' + [regex]::Escape([string]$message) + '$'
        $count = [regex]::Matches($output, $pattern).Count
        if ($count -ne [int]$ExpectedDevelopmentWarnings[$message]) {
            throw "Expected $($ExpectedDevelopmentWarnings[$message]) occurrences of '$message'; observed $count."
        }
        $output = [regex]::Replace($output, $pattern, '')
    }
    if ($AllowKnownVulkanLayerWarning) {
        # One documented Windows loader warning, not an allowance for Vulkan/engine warnings in general.
        $pattern = '(?m)^WARNING: GENERAL - Message Id Number: 0 \| Message Id Name: Loader Message\n' +
            '\twindows_read_data_files_in_registry: Registry lookup failed to get layer manifest files\.\n' +
            '\tObjects - 1\n\t\tObject\[0\] - VK_OBJECT_TYPE_INSTANCE, Handle [0-9]+\n' +
            '   at: _debug_messenger_callback \(drivers/vulkan/rendering_context_driver_vulkan\.cpp:654\)$'
        $count = [regex]::Matches($output, $pattern).Count
        if ($count -gt 1) { throw "Unexpected repeated Vulkan registry warning ($count)." }
        $output = [regex]::Replace($output, $pattern, '')
    }
    if ($output -match '(?m)^[ \t]*(?:SCRIPT ERROR:|SHADER ERROR:|ERROR:|WARNING:|.*Parse Error:)') {
        throw "Godot reported an unexpected error or warning.`n$($Result.Stdout)`n$($Result.Stderr)"
    }
}
