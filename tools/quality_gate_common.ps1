$ErrorActionPreference = "Stop"

function ConvertTo-ProcessArgument {
    param([string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Stop-ProcessTree {
    param([System.Diagnostics.Process]$Process)

    if ($Process.HasExited) {
        return
    }

    try {
        $Process.Kill($true)
        return
    } catch {
        # Windows PowerShell can run on a .NET runtime without Kill(bool).
    }

    if ($env:OS -eq 'Windows_NT') {
        try {
            $taskkill = Start-Process `
                -FilePath "$env:SystemRoot\System32\taskkill.exe" `
                -ArgumentList @('/PID', $Process.Id, '/T', '/F') `
                -WindowStyle Hidden `
                -PassThru `
                -Wait
            if ($taskkill.ExitCode -eq 0 -or $Process.HasExited) {
                return
            }
        } catch {
            # Fall through to terminating at least the command process.
        }
    }

    if (!$Process.HasExited) {
        $Process.Kill()
    }
}

function Protect-QualityGateLog {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    $redacted = $Text -replace '(?i)(access[_-]?token|authorization|api[_-]?key|password|secret)(\s*[=:]\s*)[^\s,;"}]+', '$1$2<redacted>'
    $redacted = $redacted -replace 'syt_[A-Za-z0-9._~-]+', '<redacted-matrix-token>'
    return $redacted
}

function Set-ProtectedQualityGateLog {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Text
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
            Set-Content $Path (Protect-QualityGateLog $Text) -Encoding UTF8
            return
        } catch [System.IO.IOException] {
            $lastError = $_
            Start-Sleep -Milliseconds 200
        }
    }

    throw $lastError
}

function Invoke-BoundedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Command,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][string]$LogDirectory
    )

    if ($Command.Count -eq 0) {
        throw "Command cannot be empty."
    }

    New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
    $safeName = ($Name -replace '[^A-Za-z0-9_-]', '_').ToLowerInvariant()
    $stdoutPath = Join-Path $LogDirectory "$safeName.stdout.log"
    $stderrPath = Join-Path $LogDirectory "$safeName.stderr.log"
    Remove-Item $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

    $resolved = Get-Command $Command[0] -ErrorAction Stop
    $executable = if ($resolved.Source) { $resolved.Source } else { $resolved.Path }
    $argumentLine = (@($Command | Select-Object -Skip 1) | ForEach-Object {
        ConvertTo-ProcessArgument $_
    }) -join ' '

    $startFile = $executable
    $startArguments = $argumentLine
    $batchWrapperPath = $null
    if ([IO.Path]::GetExtension($executable) -in @('.bat', '.cmd')) {
        $batchWrapperPath = Join-Path $LogDirectory "$safeName.runner.cmd"
        $batchCommand = 'call "' + $executable + '"'
        if (![string]::IsNullOrWhiteSpace($argumentLine)) {
            $batchCommand += " $argumentLine"
        }
        Set-Content $batchWrapperPath @(
            '@echo off',
            $batchCommand,
            'exit /b %ERRORLEVEL%'
        ) -Encoding ASCII
        $startFile = $env:ComSpec
        $startArguments = "/d /c call `"$batchWrapperPath`""
    }

    Write-Host "Running $Name (timeout: ${TimeoutSeconds}s)..."
    $startedAt = Get-Date
    $process = Start-Process `
        -FilePath $startFile `
        -ArgumentList $startArguments `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    $timedOut = !$completed
    if ($timedOut) {
        Stop-ProcessTree $process
        $process.WaitForExit()
    } else {
        $process.WaitForExit()
    }

    $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw } else { '' }
    $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw } else { '' }
    Set-ProtectedQualityGateLog -Path $stdoutPath -Text $stdout
    Set-ProtectedQualityGateLog -Path $stderrPath -Text $stderr
    if ($null -ne $batchWrapperPath) {
        Remove-Item $batchWrapperPath -Force -ErrorAction SilentlyContinue
    }

    $processExitCode = $process.ExitCode
    $exitCode = if ($timedOut) {
        124
    } elseif ($null -eq $processExitCode) {
        0
    } else {
        $processExitCode
    }
    $elapsed = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
    if ($exitCode -ne 0) {
        Write-Host "$Name failed with exit $exitCode after ${elapsed}s."
        if ($timedOut) {
            Write-Host "$Name exceeded its ${TimeoutSeconds}s timeout and its process tree was stopped."
        }
        @($stdout, $stderr) -join [Environment]::NewLine |
            Select-String -Pattern '.*' |
            Select-Object -Last 80 |
            ForEach-Object { Write-Host $_.Line }
    }

    return [pscustomobject]@{
        Name = $Name
        ExitCode = $exitCode
        TimedOut = $timedOut
        ElapsedSeconds = $elapsed
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    }
}
