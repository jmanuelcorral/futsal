#Requires -Version 7.2
param(
    [string]$Value,
    [int]$DelaySeconds = 0,
    [int]$ExitCode = 0,
    [switch]$Utf8
)

$line = @{ processId = $PID; value = $Value } | ConvertTo-Json -Compress
if ($Utf8) {
    $output = [Text.Encoding]::UTF8.GetBytes($line + [Environment]::NewLine)
    $errors = [Text.Encoding]::UTF8.GetBytes($Value + [Environment]::NewLine)
    [Console]::OpenStandardOutput().Write($output, 0, $output.Length)
    [Console]::OpenStandardError().Write($errors, 0, $errors.Length)
}
else {
    [Console]::Out.WriteLine($line)
}
if ($DelaySeconds -gt 0) { Start-Sleep -Seconds $DelaySeconds }
exit $ExitCode
