#Requires -Version 7.2
param(
    [int]$ChildDelaySeconds = 2,
    [int]$ChildExitCode = 0,
    [switch]$ExitBeforeChild
)

$ErrorActionPreference = 'Stop'
$info = [Diagnostics.ProcessStartInfo]::new()
$info.FileName = Join-Path $PSHOME 'pwsh.exe'
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = -not $ExitBeforeChild
$info.RedirectStandardError = -not $ExitBeforeChild
foreach ($argument in @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'process_probe.ps1'),
        '-Value', 'real owned child', '-DelaySeconds', [string]$ChildDelaySeconds, '-ExitCode', [string]$ChildExitCode)) {
    $info.ArgumentList.Add($argument)
}
$child = [Diagnostics.Process]::Start($info)
try {
    [Console]::Out.WriteLine('FUTSAL_CHILD_STARTED ' + (@{parent = $PID; child = $child.Id} | ConvertTo-Json -Compress))
    if ($ExitBeforeChild) {
        Start-Sleep -Milliseconds 500
        exit 0
    }
    $output = $child.StandardOutput.ReadToEndAsync()
    $errors = $child.StandardError.ReadToEndAsync()
    $child.WaitForExit()
    [Console]::Out.Write($output.GetAwaiter().GetResult())
    [Console]::Error.Write($errors.GetAwaiter().GetResult())
}
finally {
    $child.Dispose()
}
exit 0
