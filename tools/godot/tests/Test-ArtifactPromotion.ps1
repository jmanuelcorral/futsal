#Requires -Version 7.2
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\ArtifactPromotion.ps1')
$checks = [Collections.Generic.List[object]]::new()
$work = Join-Path $PSScriptRoot ('..\runtime\artifact-promotion-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$work = (Resolve-Path -LiteralPath $work).Path
$failure = $null

function Check([string]$Name, [bool]$Passed) {
    $checks.Add(@{ name = $Name; passed = $Passed })
    if (-not $Passed) { throw "FAIL $Name" }
}

function Rejected([string]$Name, [scriptblock]$Action) {
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Check $Name $rejected
}

function New-Fixture([string]$Name, [switch]$MissingActive) {
    $directory = Join-Path $work $Name
    New-Item -ItemType Directory -Path $directory | Out-Null
    $candidate = Join-Path $directory 'candidate.exe'
    $active = Join-Path $directory 'active.exe'
    [IO.File]::WriteAllBytes($candidate, [byte[]]@(2, 4, 6, 8, 10))
    if (-not $MissingActive) { [IO.File]::WriteAllBytes($active, [byte[]]@(1, 3, 5, 7, 9)) }
    return @{
        directory = $directory; Candidate = $candidate; Destination = $active
        BackupPath = Join-Path $directory 'previous-artifact\FutsalG1.exe'
        ExpectedSha256 = Get-GodotArtifactSha256 $candidate
        PreviousSha256 = Get-GodotArtifactSha256 $active -AllowMissing
    }
}

function Publish-Fixture($Fixture) {
    $arguments = @{}
    foreach ($key in @('Candidate', 'Destination', 'BackupPath', 'ExpectedSha256', 'PreviousSha256')) {
        $arguments[$key] = $Fixture[$key]
    }
    return Publish-GodotArtifact @arguments
}

function Exercise-RunnerGate($Gate, $Fixture, [string]$RequestedScope = 'All', $ValidationError = $null,
    [bool]$FailedCheck = $false) {
    & {
        param($body, $fixture, $scopeValue, $errorValue, $failedCheck)
        $Scope = $scopeValue; $failure = $errorValue
        $checks = [Collections.Generic.List[object]]::new()
        $checks.Add(@{name = 'fixture validation'; passed = -not $failedCheck})
        $artifact = $fixture.Candidate; $activeArtifact = $fixture.Destination
        $candidateSha256 = $fixture.ExpectedSha256; $previousArtifactSha256 = $fixture.PreviousSha256
        $runPath = $fixture.directory; $artifactPromotion = $null; $promotionFailure = $null
        function Add-Check([string]$Name, [bool]$Passed) {
            $checks.Add(@{name = $Name; passed = $Passed})
            if (-not $Passed) { throw "FAIL $Name" }
        }
        . ([scriptblock]::Create($body))
        return @{ promotion = $artifactPromotion; failure = $failure; promotionFailure = $promotionFailure }
    } $Gate.Extent.Text $Fixture $RequestedScope $ValidationError $FailedCheck
}

try {
    $first = New-Fixture 'first' -MissingActive
    $published = Publish-Fixture $first
    Check 'first promotion creates the active file without an overwrite fallback' ($published.promoted -and -not $published.reusedIdentical)
    Check 'first promotion records that no previous executable existed' ($published.previousSha256 -ceq '' -and $published.backup -ceq '')
    Check 'validated candidate remains at the native evidence path' (
        (Get-GodotArtifactSha256 $first.Candidate) -ceq $first.ExpectedSha256 -and
        (Get-GodotArtifactSha256 $first.Destination) -ceq $first.ExpectedSha256)
    $replacement = New-Fixture 'replacement'
    $published = Publish-Fixture $replacement
    Check 'atomic replacement publishes the validated bytes' (
        $published.promoted -and (Get-GodotArtifactSha256 $replacement.Destination) -ceq $replacement.ExpectedSha256)
    Check 'atomic replacement preserves the previous actual executable bytes' (
        $published.backup -ceq $replacement.BackupPath -and
        (Get-GodotArtifactSha256 $replacement.BackupPath) -ceq $replacement.PreviousSha256)
    $identical = New-Fixture 'identical'
    [IO.File]::Copy($identical.Candidate, $identical.Destination, $true)
    $identical.PreviousSha256 = $identical.ExpectedSha256
    $stamp = (Get-Item -LiteralPath $identical.Destination).LastWriteTimeUtc
    $published = Publish-Fixture $identical
    Check 'identical validated bytes avoid rewriting the active executable' (
        $published.reusedIdentical -and $published.promoted -and
        (Get-Item -LiteralPath $identical.Destination).LastWriteTimeUtc -eq $stamp -and
        -not (Test-Path -LiteralPath $identical.BackupPath))

    foreach ($case in @('candidate-changed', 'active-changed', 'backup-exists', 'same-path', 'locked-active')) {
        $fixture = New-Fixture $case
        $lock = $null
        switch ($case) {
            'candidate-changed' { $fixture.ExpectedSha256 = $fixture.PreviousSha256 }
            'active-changed' { $fixture.PreviousSha256 = $fixture.ExpectedSha256 }
            'backup-exists' {
                New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($fixture.BackupPath)) | Out-Null
                [IO.File]::WriteAllText($fixture.BackupPath, 'protected existing backup')
            }
            'same-path' { $fixture.BackupPath = $fixture.Destination }
            'locked-active' {
                $lock = [IO.File]::Open($fixture.Destination, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            }
        }
        $before = Get-GodotArtifactSha256 $fixture.Destination
        $candidateBefore = Get-GodotArtifactSha256 $fixture.Candidate
        $backupBefore = Get-GodotArtifactSha256 $fixture.BackupPath -AllowMissing
        try { Rejected "$case cannot promote" { Publish-Fixture $fixture } }
        finally { if ($null -ne $lock) { $lock.Dispose() } }
        Check "$case preserves active executable bytes" ((Get-GodotArtifactSha256 $fixture.Destination) -ceq $before)
        Check "$case preserves candidate bytes" ((Get-GodotArtifactSha256 $fixture.Candidate) -ceq $candidateBefore)
        Check "$case preserves any existing backup" ((Get-GodotArtifactSha256 $fixture.BackupPath -AllowMissing) -ceq $backupBefore)
        Check "$case leaves no owned staging executable behind" (
            @(Get-ChildItem -LiteralPath $fixture.directory -Filter '.futsal-candidate-*.exe' -File).Count -eq 0)
    }
    Rejected 'directories cannot pretend to be missing active executables' { Get-GodotArtifactSha256 $work -AllowMissing }
    Rejected 'required missing candidate is an explicit error' { Get-GodotArtifactSha256 (Join-Path $work 'missing.exe') }

    $runner = Join-Path $PSScriptRoot '..\Test-MicroSlice.ps1'
    $ast = [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$null, [ref]$null)
    $gates = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Clauses[0].Item1.Extent.Text.Contains('$Scope -eq ''All'' -and $null -eq $failure') -and
        $node.Extent.Text.Contains('Publish-GodotArtifact')
    }, $true))
    Check 'runner has one actual final promotion gate' ($gates.Count -eq 1)
    foreach ($case in @('export-failure', 'artifact-failure', 'power-release-failure', 'failed-check', 'helpers')) {
        $fixture = New-Fixture "gate-$case"
        $errorValue = if ($case -like '*failure') { $case } else { $null }
        $scopeValue = if ($case -ceq 'helpers') { 'Helpers' } else { 'All' }
        $outcome = Exercise-RunnerGate $gates[0] $fixture $scopeValue $errorValue ($case -ceq 'failed-check')
        Check "actual runner gate rejects $case without promoting" ($null -eq $outcome.promotion)
        Check "actual runner gate preserves active bytes on $case" (
            (Get-GodotArtifactSha256 $fixture.Destination) -ceq $fixture.PreviousSha256 -and
            -not (Test-Path -LiteralPath $fixture.BackupPath))
    }
    $fixture = New-Fixture 'gate-success'
    $outcome = Exercise-RunnerGate $gates[0] $fixture
    Check 'actual runner gate promotes only the fully successful candidate' (
        $null -eq $outcome.failure -and $outcome.promotion.promoted -and
        (Get-GodotArtifactSha256 $fixture.BackupPath) -ceq $fixture.PreviousSha256)
    $fixture = New-Fixture 'gate-promotion-failure'
    $fixture.ExpectedSha256 = $fixture.PreviousSha256
    $outcome = Exercise-RunnerGate $gates[0] $fixture
    Check 'actual runner gate retains promotion errors for the failed summary and final rethrow' (
        $null -ne $outcome.failure -and $null -ne $outcome.promotionFailure -and
        (Get-GodotArtifactSha256 $fixture.Destination) -ceq $fixture.PreviousSha256)
    $source = [IO.File]::ReadAllText($runner)
    Check 'All exports and executes a run-scoped candidate, not the active legacy destination' (
        $source.Contains('$candidateDirectory = Join-Path $runPath ''candidate''') -and
        $source.Contains('$artifact = Join-Path $candidateDirectory ''FutsalG1.exe''') -and
        $source.Contains('$directory = if ($Exported) { $candidateDirectory }'))
    Check 'promotion occurs after scoped power release and before result persistence' (
        $source.IndexOf('$powerRequest.Dispose()') -lt $source.IndexOf('Publish-GodotArtifact -Candidate') -and
        $source.IndexOf('Publish-GodotArtifact -Candidate') -lt $source.IndexOf('$summary = [ordered]@{'))
    $foundation = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\Test-Godot.ps1'))
    Check 'foundation exports only its isolated diagnostic and has no publication call' (
        $foundation.Contains('$buildPath = Join-Path $runPath ''diagnostic-artifact''') -and
        -not $foundation.Contains('Publish-GodotArtifact ') -and $foundation.Contains('artifactPromoted = $false'))
}
catch {
    $failure = $_.ToString()
    if ($checks.Count -eq 0 -or $checks[$checks.Count - 1].passed) {
        $checks.Add(@{name = 'artifact promotion suite completed'; passed = $false})
    }
}
$report = @{
    ok = $null -eq $failure; passed = @($checks | Where-Object passed).Count
    total = $checks.Count; checks = $checks.ToArray(); error = $failure; evidence = $work
    scope = 'Native file preservation and actual runner publication gate; not gameplay, GPU or product acceptance.'
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $work 'result.json') -Encoding utf8
Write-Output ('FUTSAL_ARTIFACT_PROMOTION_TESTS ' + ($report | ConvertTo-Json -Depth 8 -Compress))
if ($null -ne $failure) { exit 1 }
