#Requires -Version 7.2
param([Parameter(Mandatory)][string]$LogPrefix)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Common.ps1')
$previous = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(437)
    $value = "Parqu$([char]0x00e9) $([char]0x2014) IA: s$([char]0x00ed) $([char]0x2713)"
    $result = Invoke-GodotProcess -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -Arguments @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'process_probe.ps1'),
            '-Value', $value, '-Utf8') `
        -WorkingDirectory $PSScriptRoot -LogPrefix $LogPrefix -TimeoutSeconds 20
    $decoded = $result.Stdout | ConvertFrom-Json
    if ($decoded.value -cne $value) { throw 'UTF-8 stdout was corrupted by the parent code page.' }
    if ($result.Stderr.TrimEnd("`r", "`n") -cne $value) { throw 'UTF-8 stderr was corrupted by the parent code page.' }
    [Console]::Out.WriteLine('{"stdout_ok":true,"stderr_ok":true,"parent_code_page":437}')
}
finally {
    [Console]::OutputEncoding = $previous
}
