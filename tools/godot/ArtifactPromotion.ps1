#Requires -Version 7.2
Set-StrictMode -Version Latest

function Get-GodotArtifactSha256 {
    param([Parameter(Mandatory)][string]$Path, [switch]$AllowMissing)
    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
        if ($AllowMissing) { return '' }
        throw "Artifact does not exist: $Path"
    }
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Artifact must be a regular file: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Publish-GodotArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$BackupPath,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedSha256,
        [Parameter(Mandatory)][AllowEmptyString()][ValidatePattern('^$|^[a-f0-9]{64}$')][string]$PreviousSha256
    )
    $paths = @($Candidate, $Destination, $BackupPath)
    if (@($paths | Where-Object { -not [IO.Path]::IsPathFullyQualified($_) }).Count -ne 0) {
        throw 'Artifact promotion requires absolute paths.'
    }
    $paths = @($paths | ForEach-Object { [IO.Path]::GetFullPath($_) })
    if (@($paths | Sort-Object -Unique).Count -ne 3) {
        throw 'Candidate, active executable and backup must be distinct files.'
    }
    $Candidate, $Destination, $BackupPath = $paths
    if ((Get-GodotArtifactSha256 $Candidate) -cne $ExpectedSha256) {
        throw 'Candidate bytes changed after export/validation; nothing was promoted.'
    }
    if ((Get-GodotArtifactSha256 $Destination -AllowMissing) -cne $PreviousSha256) {
        throw 'Active executable changed during validation; nothing was promoted.'
    }
    if (Test-Path -LiteralPath $BackupPath -ErrorAction Stop) {
        throw 'Promotion backup already exists and will not be overwritten.'
    }
    $promotion = [ordered]@{
        promoted = $false; reusedIdentical = $PreviousSha256 -ceq $ExpectedSha256
        candidate = $Candidate; artifact = $Destination; sha256 = $ExpectedSha256
        previousSha256 = $PreviousSha256; backup = ''
    }
    if ($promotion.reusedIdentical) {
        $promotion.promoted = $true
        return $promotion
    }
    $directory = [IO.Path]::GetDirectoryName($Destination)
    $temporary = Join-Path $directory ('.futsal-candidate-' + [guid]::NewGuid().ToString('N') + '.exe')
    $ownsTemporary = $false
    try {
        New-Item -ItemType Directory -Path $directory, ([IO.Path]::GetDirectoryName($BackupPath)) -Force -ErrorAction Stop | Out-Null
        $output = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $ownsTemporary = $true
        try {
            $input = [IO.File]::OpenRead($Candidate)
            try { $input.CopyTo($output); $output.Flush($true) }
            finally { $input.Dispose() }
        }
        finally { $output.Dispose() }
        if ((Get-GodotArtifactSha256 $temporary) -cne $ExpectedSha256 -or
            (Get-GodotArtifactSha256 $Destination -AllowMissing) -cne $PreviousSha256) {
            throw 'Promotion preconditions changed; the active executable was not replaced.'
        }
        if ([string]::IsNullOrEmpty($PreviousSha256)) {
            [IO.File]::Move($temporary, $Destination)
        }
        else {
            # Keep the validated candidate at its evidence path; NTFS preserves the previous active file atomically.
            [IO.File]::Replace($temporary, $Destination, $BackupPath)
            $promotion.backup = $BackupPath
        }
        $promotion.promoted = $true
        if ((Get-GodotArtifactSha256 $Destination) -cne $ExpectedSha256 -or
            (-not [string]::IsNullOrEmpty($PreviousSha256) -and
            (Get-GodotArtifactSha256 $BackupPath) -cne $PreviousSha256)) {
            throw "Promoted or backup bytes changed; preserved recovery evidence is at $BackupPath."
        }
        return $promotion
    }
    catch {
        $_.Exception.Data['ArtifactPromotion'] = $promotion
        throw
    }
    finally {
        if ($ownsTemporary -and (Test-Path -LiteralPath $temporary -ErrorAction Stop)) {
            Remove-Item -LiteralPath $temporary -ErrorAction Stop
        }
    }
}
