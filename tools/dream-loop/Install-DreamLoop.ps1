#Requires -Version 7.2
[CmdletBinding()]
param([switch]$VerifyOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$destination = Join-Path $root '.github\skills\dream-loop'
$pin = Get-Content -LiteralPath (Join-Path $destination 'UPSTREAM.json') -Raw | ConvertFrom-Json
$cache = Join-Path $PSScriptRoot '.cache'
New-Item -ItemType Directory -Path $cache -Force | Out-Null

function Get-GitBlobHash([byte[]]$Bytes) {
    $prefix = [Text.Encoding]::UTF8.GetBytes("blob $($Bytes.Length)`0")
    $payload = [byte[]]::new($prefix.Length + $Bytes.Length)
    [Array]::Copy($prefix, 0, $payload, 0, $prefix.Length)
    [Array]::Copy($Bytes, 0, $payload, $prefix.Length, $Bytes.Length)
    [Convert]::ToHexString([Security.Cryptography.SHA1]::HashData($payload)).ToLowerInvariant()
}

$results = @()
foreach ($entry in $pin.files.PSObject.Properties) {
    $target = Join-Path $destination $entry.Name
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        if ($VerifyOnly) { throw "Missing vendored file: $target" }
        $download = Join-Path $cache ($entry.Name + '.download')
        & curl.exe --fail --location --silent --show-error --proto '=https' --tlsv1.2 `
            --retry 2 --connect-timeout 20 --max-time 120 --output $download `
            "https://raw.githubusercontent.com/achimala/dream-loop/$($pin.commit)/$($entry.Name)"
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $($entry.Name)" }
        $blob = & git hash-object --no-filters -- $download
        if ($LASTEXITCODE -ne 0 -or $blob -ne $entry.Value.gitBlobSha1) {
            throw "Upstream Git blob mismatch: $($entry.Name). No file was installed."
        }
        Move-Item -LiteralPath $download -Destination $target
    }
    $blob = & git hash-object --no-filters -- $target
    if (-not $VerifyOnly -and $blob -ne $entry.Value.gitBlobSha1) {
        $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($target))
        $normalized = [Text.Encoding]::UTF8.GetBytes($text.Replace("`r`n", "`n"))
        if ((Get-GitBlobHash $normalized) -eq $entry.Value.gitBlobSha1) {
            [IO.File]::WriteAllBytes($target, $normalized)
            $blob = & git hash-object --no-filters -- $target
        }
    }
    $sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $blob -ne $entry.Value.gitBlobSha1 -or
        (Get-Item -LiteralPath $target).Length -ne $entry.Value.bytes -or $sha256 -ne $entry.Value.sha256) {
        throw "Vendored file changed: $target. Refusing to overwrite local edits."
    }
    $results += [ordered]@{
        file = $entry.Name
        bytes = (Get-Item -LiteralPath $target).Length
        gitBlobSha1 = $blob
        sha256 = $sha256
    }
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $cache 'verification.json') -Encoding utf8
$results | ConvertTo-Json
Write-Host 'dream-loop: exact upstream files installed; reload Copilot to discover the project skill.'
Write-Host 'The visual build loop is not running: an approved reference or authorized image generator is still required.'
