#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$GodotPath,
    [switch]$RemoveArchives
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not $IsWindows) { throw 'This installer is for Windows x86_64.' }
$release = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release.json') -Raw | ConvertFrom-Json
$cache = Join-Path $PSScriptRoot '.cache'
$runtime = Join-Path $PSScriptRoot 'runtime'
$installRoot = Join-Path $env:LOCALAPPDATA "Programs\Godot\$($release.version)-$($release.status)"
$templatesRoot = Join-Path $env:APPDATA "Godot\export_templates\$($release.templates.directory)"
$localPath = Join-Path $PSScriptRoot 'local.json'
$candidates = [Collections.Generic.List[string]]::new()
if ($GodotPath) {
    $GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
    $candidates.Add($GodotPath)
}
elseif (Test-Path -LiteralPath $localPath -PathType Leaf) {
    $previous = Get-Content -LiteralPath $localPath -Raw | ConvertFrom-Json
    if ($previous.version -eq $release.version) { $candidates.Add($previous.godotPath) }
}
$candidates.Add((Join-Path $installRoot $release.editor.executable))
foreach ($name in @($release.editor.executable, 'godot', 'godot4')) {
    $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $candidates.Add($command.Source) }
}
Write-Host 'Checking existing focused Godot paths without executing unknown binaries.'
foreach ($candidate in $candidates | Select-Object -Unique) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { Write-Host "Found: $candidate" }
}

function Receive-GodotFile([string]$Uri, [string]$Destination) {
    & curl.exe --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --tlsv1.2 `
        --retry 2 --connect-timeout 20 --max-time 1800 --output $Destination $Uri
    if ($LASTEXITCODE -ne 0) { throw "Download failed ($LASTEXITCODE): $Uri" }
}

function Get-VerifiedArchive($Artifact, [string[]]$Checksums) {
    $pattern = '^' + [regex]::Escape($Artifact.sha512) + '\s+\*?' + [regex]::Escape($Artifact.archive) + '$'
    if (-not ($Checksums | Where-Object { $_ -cmatch $pattern })) {
        throw "Official SHA512 manifest disagrees with pin for $($Artifact.archive). Nothing will be executed."
    }
    $path = Join-Path $cache $Artifact.archive
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $download = Join-Path $cache "$($Artifact.archive).$([guid]::NewGuid().ToString('N')).download"
        try {
            Write-Host "Downloading official $($Artifact.archive)."
            Receive-GodotFile $Artifact.url $download
            if ((Get-FileHash -LiteralPath $download -Algorithm SHA512).Hash.ToLowerInvariant() -ne $Artifact.sha512) {
                throw "Downloaded SHA512 mismatch for $($Artifact.archive). Nothing will be extracted or executed."
            }
            Move-Item -LiteralPath $download -Destination $path
        }
        finally {
            if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download }
        }
    }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA512).Hash.ToLowerInvariant() -ne $Artifact.sha512) {
        throw "Cached archive checksum mismatch at $path. Inspect it; no automatic replacement."
    }
    Write-Host "Official SHA512 verified: $($Artifact.archive)"
    return $path
}

function Get-EntryHash([IO.Compression.ZipArchiveEntry]$Entry) {
    $stream = $Entry.Open()
    $algorithm = [Security.Cryptography.SHA512]::Create()
    try { return [Convert]::ToHexString($algorithm.ComputeHash($stream)).ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}

function Install-VerifiedEntry([IO.Compression.ZipArchiveEntry]$Entry, [string]$Destination) {
    $expected = Get-EntryHash $Entry
    if (Test-Path -LiteralPath $Destination) {
        if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or
            (Get-FileHash -LiteralPath $Destination -Algorithm SHA512).Hash.ToLowerInvariant() -ne $expected) {
            throw "Existing file differs from the verified release: $Destination. It was not overwritten."
        }
    }
    else {
        New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Destination, $false)
    }
    if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA512).Hash.ToLowerInvariant() -ne $expected) {
        throw "Extracted file integrity failure: $Destination."
    }
    return [ordered]@{ path = $Destination; sha512 = $expected }
}

New-Item -ItemType Directory -Path $cache, $runtime -Force | Out-Null
$checksumPath = Join-Path $cache 'SHA512-SUMS.txt'
Receive-GodotFile $release.checksumsUrl $checksumPath
$checksums = Get-Content -LiteralPath $checksumPath
$editorArchive = Get-VerifiedArchive $release.editor $checksums
$templateArchive = Get-VerifiedArchive $release.templates $checksums
$zip = [IO.Compression.ZipFile]::OpenRead($editorArchive)
try {
    $mainEntry = $zip.GetEntry($release.editor.executable)
    $consoleEntry = $zip.GetEntry($release.editor.consoleExecutable)
    if (-not $mainEntry -or -not $consoleEntry) { throw 'Pinned editor entries missing in official archive.' }
    $mainHash = Get-EntryHash $mainEntry
    $chosen = $null
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $candidate -Algorithm SHA512).Hash.ToLowerInvariant() -eq $mainHash) {
                $chosen = (Resolve-Path -LiteralPath $candidate).Path
                break
            }
            if ($GodotPath) { throw "Explicit -GodotPath is not the verified standard $($release.version) executable." }
            Write-Host "Preserving unrelated Godot binary: $candidate"
        }
    }
    if ($chosen) { $installRoot = Split-Path $chosen -Parent }
    $mainPath = Join-Path $installRoot $release.editor.executable
    if ($chosen) { $mainPath = $chosen }
    if ([IO.Path]::GetExtension($mainPath) -ine '.exe') {
        throw 'The verified Windows Godot executable must have an .exe extension for its console companion.'
    }
    $consoleName = [IO.Path]::GetFileNameWithoutExtension($mainPath) + '_console.exe'
    $consolePath = Join-Path $installRoot $consoleName
    $editorFiles = @(
        (Install-VerifiedEntry $mainEntry $mainPath)
        (Install-VerifiedEntry $consoleEntry $consolePath)
    )
}
finally { $zip.Dispose() }

$zip = [IO.Compression.ZipFile]::OpenRead($templateArchive)
try {
    $entries = @($zip.Entries | Where-Object { $_.FullName -match '^templates/(windows[^/]*|version\.txt)$' })
    foreach ($required in $release.templates.requiredFiles) {
        if (-not ($entries | Where-Object { $_.Name -eq $required })) { throw "Missing official export template: $required" }
    }
    $templateFiles = @(
        foreach ($entry in $entries) {
            Install-VerifiedEntry $entry (Join-Path $templatesRoot $entry.Name)
        }
    )
}
finally { $zip.Dispose() }
if ((Get-Content -LiteralPath (Join-Path $templatesRoot 'version.txt') -Raw).Trim() -ne $release.templates.directory) {
    throw 'Installed export template version does not match the pin.'
}
$versionResult = Invoke-GodotProcess -FilePath $consolePath -Arguments @('--version') `
    -WorkingDirectory $PSScriptRoot -LogPrefix (Join-Path $runtime 'install-version') -TimeoutSeconds 30
$version = $versionResult.Stdout.Trim()
if ($version -notmatch ('^' + [regex]::Escape("$($release.version).stable.official.") + '[0-9a-f]+$')) {
    throw "Unexpected Godot runtime version: $version."
}
$local = [ordered]@{
    version = $release.version
    edition = $release.edition
    versionOutput = $version
    godotPath = $mainPath
    consolePath = $consolePath
    templatesPath = $templatesRoot
    editorArchiveSha512 = $release.editor.sha512
    templatesArchiveSha512 = $release.templates.sha512
    editorFiles = $editorFiles
    templateFiles = $templateFiles
    verifiedAt = (Get-Date).ToUniversalTime().ToString('o')
}
$local | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $localPath -Encoding utf8
if ($RemoveArchives) {
    Remove-Item -LiteralPath $editorArchive, $templateArchive
}
Write-Host "Verified Godot $version (standard, no .NET)."
Write-Host "Executable: $mainPath"
Write-Host "Windows templates: $templatesRoot"
Write-Host "Ignored machine inventory: $localPath"
