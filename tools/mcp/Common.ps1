#Requires -Version 7.2
Set-StrictMode -Version Latest

function Invoke-CheckedTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [System.Collections.IDictionary]$Environment = @{},
        [int]$TimeoutSeconds = 120
    )
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FilePath
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    foreach ($key in $Environment.Keys) { $info.Environment[$key] = [string]$Environment[$key] }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw "Could not start $FilePath" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Timed out after $TimeoutSeconds seconds: $FilePath (owned PID $($process.Id))."
        }
        $output = $stdout.GetAwaiter().GetResult()
        $errors = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "$FilePath exited $($process.ExitCode).`n$output`n$errors"
        }
        [pscustomobject]@{ Stdout = $output; Stderr = $errors; ExitCode = $process.ExitCode }
    }
    finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $process.Dispose()
    }
}

function Get-ToolingEnvironment([string]$Root) {
    $cache = Join-Path $Root 'tools\mcp\.cache'
    $work = Join-Path $cache 'work'
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    @{
        UV_CACHE_DIR = (Join-Path $cache 'uv')
        UV_PYTHON_INSTALL_DIR = (Join-Path $cache 'python')
        UV_PYTHON_PREFERENCE = 'only-managed'
        UV_DEFAULT_INDEX = 'https://pypi.org/simple'
        UV_HTTP_TIMEOUT = '60'
        UV_HTTP_RETRIES = '2'
        TEMP = $work
        TMP = $work
        DISABLE_TELEMETRY = 'true'
        BLENDER_MCP_SAFE_MODE = '1'
    }
}
