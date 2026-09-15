#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$BlenderPath,
    [switch]$KeepArchive
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
$localPath = Join-Path $PSScriptRoot 'local.json'
$cache = Join-Path $PSScriptRoot '.cache'
$archivePath = Join-Path $cache $release.archive

function Receive-File([string]$Uri, [string]$Destination) {
    & curl.exe --fail --location --silent --show-error --proto '=https' --tlsv1.2 `
        --retry 2 --connect-timeout 20 --max-time 1200 --output $Destination $Uri
    if ($LASTEXITCODE -ne 0) {
        throw "Download failed ($LASTEXITCODE): $Uri"
    }
}

if (-not $BlenderPath -and (Test-Path -LiteralPath $localPath -PathType Leaf)) {
    $local = Get-Content -LiteralPath $localPath -Raw | ConvertFrom-Json
    $BlenderPath = $local.blenderPath
    if (-not (Test-Path -LiteralPath $BlenderPath -PathType Leaf)) {
        throw "Saved Blender path no longer exists. Supply -BlenderPath explicitly or remove tools\blender\local.json."
    }
}

if (-not $BlenderPath) {
    $installRoot = Join-Path $env:LOCALAPPDATA 'Programs\Blender'
    $directoryName = [IO.Path]::GetFileNameWithoutExtension($release.archive)
    $destination = Join-Path $installRoot $directoryName
    $BlenderPath = Join-Path $destination 'blender.exe'
    if (-not (Test-Path -LiteralPath $BlenderPath -PathType Leaf)) {
        if (Test-Path -LiteralPath $destination) {
            throw "Incomplete or unexpected installation at $destination; inspect it before retrying."
        }
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        $checksumPath = Join-Path $cache "blender-$($release.version).sha256"
        Receive-File $release.checksumsUrl $checksumPath
        $expectedLine = '^' + [regex]::Escape($release.sha256) + '\s+\*?' + [regex]::Escape($release.archive) + '$'
        if (-not (Get-Content -LiteralPath $checksumPath | Where-Object { $_ -match $expectedLine })) {
            throw 'The official checksum file does not match the pinned release. Nothing will be executed.'
        }
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            Write-Host "Downloading official Blender $($release.version) LTS (no elevation)."
            Receive-File $release.url $archivePath
        }
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $release.sha256) {
            throw "Blender ZIP checksum mismatch: $actualHash. Remove only $archivePath and retry."
        }
        Write-Host "Verified official ZIP SHA256: $actualHash"
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
        Expand-Archive -LiteralPath $archivePath -DestinationPath $installRoot
        if (-not (Test-Path -LiteralPath $BlenderPath -PathType Leaf)) {
            throw "Official archive did not produce $BlenderPath."
        }
    }
}

$BlenderPath = (Resolve-Path -LiteralPath $BlenderPath).Path
$versionOutput = & $BlenderPath --version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Blender --version failed: $versionOutput"
}
$versionLine = @($versionOutput)[0].ToString()
if ($versionLine -notmatch ('^Blender ' + [regex]::Escape($release.version) + '(?:\s|$)')) {
    throw "Expected pinned Blender $($release.version), received: $versionLine. Existing installations are not changed."
}
$local = [ordered]@{
    blenderPath = $BlenderPath
    version = $release.version
    versionOutput = $versionLine
    binarySha256 = (Get-FileHash -LiteralPath $BlenderPath -Algorithm SHA256).Hash.ToLowerInvariant()
    officialArchiveSha256 = $release.sha256
    verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
}
$local | ConvertTo-Json | Set-Content -LiteralPath $localPath -Encoding utf8
if (-not $KeepArchive -and (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    Remove-Item -LiteralPath $archivePath
}
Write-Host $versionLine
Write-Host "Blender path: $BlenderPath"
Write-Host "Machine-specific inventory: $localPath"
