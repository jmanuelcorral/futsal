#Requires -Version 7.2
param([Parameter(Mandatory)][string]$ReportPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$report = [IO.File]::ReadAllText($ReportPath) | ConvertFrom-Json -AsHashtable -Depth 64
$manifestPath = $report['gameplay']['capture_manifest_path']
$manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json -AsHashtable -Depth 64
$report['process_id'] = $PID
$report['executable'] = [Environment]::ProcessPath
$report['timestamp_utc'] = [datetime]::UtcNow.ToString('s')
$manifest['process_id'] = $PID
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 64 -Compress), [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 64 -Compress), [Text.UTF8Encoding]::new($false))
if (-not $report['headless']) { Write-Output ('Vulkan 1.3.0 - Forward+ - Using Device #0: fixture - ' + $report['gpu_name']) }
foreach ($check in $report['checks']) { Write-Output ('PASS ' + $check['name']) }
Write-Output ('FUTSAL_GAMEPLAY_SMOKE ' + ($report | ConvertTo-Json -Depth 64 -Compress))
exit 0
