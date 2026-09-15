#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\PowerAvailability.ps1')
$checks = [Collections.Generic.List[object]]::new()
$leases = [Collections.Generic.List[object]]::new()
$failure = $null

function Check([string]$Name, [bool]$Passed) {
    $checks.Add(@{ name = $Name; passed = $Passed })
    if (-not $Passed) { throw "FAIL $Name" }
}

try {
    $headless = [Futsal.Tooling.ValidationPowerRequest]::new($false)
    $leases.Add($headless)
    Check 'headless request has a live native handle' (-not $headless.IsClosed)
    Check 'headless validation requests system availability' $headless.SystemRequested
    Check 'headless validation requests execution availability' $headless.ExecutionRequested
    Check 'headless validation does not request a lit display' (-not $headless.DisplayRequested)
    $rendered = [Futsal.Tooling.ValidationPowerRequest]::new($true)
    $leases.Add($rendered)
    Check 'rendered validation has its own live native request' (-not $rendered.IsClosed)
    Check 'rendered validation requests system and execution' ($rendered.SystemRequested -and $rendered.ExecutionRequested)
    Check 'rendered validation requests a lit display' $rendered.DisplayRequested
    $rendered.Dispose()
    Check 'normal disposal closes the rendered request handle' $rendered.IsClosed
    Check 'disposing one request does not dispose another' (-not $headless.IsClosed)
    $rendered.Dispose()
    Check 'repeated disposal remains safe' $rendered.IsClosed
    $headless.Dispose()
    Check 'headless request is released too' $headless.IsClosed

    $interrupted = [Futsal.Tooling.ValidationPowerRequest]::new($true)
    $leases.Add($interrupted)
    $sentinel = $false
    try {
        try { throw 'intentional validation failure' }
        finally { $interrupted.Dispose() }
    }
    catch { $sentinel = $_.Exception.Message -ceq 'intentional validation failure' }
    Check 'finally preserves the original validation failure' $sentinel
    Check 'finally releases availability after failure' $interrupted.IsClosed

    $broken = [Futsal.Tooling.ValidationPowerRequest]::new($true)
    $leases.Add($broken)
    $flags = [Reflection.BindingFlags]'NonPublic,Instance,Static'
    $type = $broken.GetType()
    $handle = $type.GetField('handle', $flags).GetValue($broken)
    $clear = $type.GetMethod('PowerClearRequest', $flags)
    $displayType = [Enum]::ToObject($clear.GetParameters()[1].ParameterType, 0)
    # Consume only this fixture's display request to exercise a real native clear failure.
    Check 'negative fixture clears its own display request once' ([bool]$clear.Invoke($null, @($handle, $displayType)))
    $nativeFailure = $null
    try { $broken.Dispose() }
    catch {
        $nativeFailure = $_.Exception
        while ($null -ne $nativeFailure.InnerException) { $nativeFailure = $nativeFailure.InnerException }
    }
    Check 'native clear failure is propagated rather than ignored' ($nativeFailure -is [ComponentModel.Win32Exception])
    Check 'native clear failure retains a Windows error code' ($nativeFailure.NativeErrorCode -ne 0)
    Check 'failed clear still closes its own handle and remaining requests' $broken.IsClosed
}
catch {
    $failure = $_.ToString()
    if ($checks.Count -eq 0 -or $checks[$checks.Count - 1].passed) {
        $checks.Add(@{ name = 'native power availability suite completed'; passed = $false })
    }
}
finally {
    foreach ($lease in $leases) { if (-not $lease.IsClosed) { $lease.Dispose() } }
}
$report = @{
    ok = $null -eq $failure; passed = @($checks | Where-Object passed).Count
    total = $checks.Count; checks = $checks.ToArray(); error = $failure
    scope = 'Native scoped power-request lifecycle; no forced suspend, policy change or FPS claim.'
}
Write-Output ('FUTSAL_POWER_REQUEST_TESTS ' + ($report | ConvertTo-Json -Depth 8 -Compress))
if ($null -ne $failure) { exit 1 }
