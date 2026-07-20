param(
    [string]$LogDirectory = "build/quality_gate_self_test",
    [switch]$IncludeFlutter
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "quality_gate_common.ps1")

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$timeoutResult = Invoke-BoundedCommand `
    -Name "Timeout self test" `
    -Command @(
        $powershell,
        "-NoProfile",
        "-Command",
        "Start-Sleep -Seconds 3"
    ) `
    -TimeoutSeconds 1 `
    -LogDirectory $LogDirectory

if (!$timeoutResult.TimedOut -or $timeoutResult.ExitCode -ne 124) {
    throw "Timeout self test failed: exit=$($timeoutResult.ExitCode), timedOut=$($timeoutResult.TimedOut)"
}

$protected = Protect-QualityGateLog `
    "access_token=visible password:visible syt_user_visible"
if ($protected -match "visible" -or
    $protected -notmatch "<redacted>" -or
    $protected -notmatch "<redacted-matrix-token>") {
    throw "Log redaction self test failed."
}

$batchProbe = Join-Path $LogDirectory "batch_probe.cmd"
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
Set-Content $batchProbe "@echo batch-ok" -Encoding ASCII
try {
    $batchResult = Invoke-BoundedCommand `
        -Name "Batch invocation self test" `
        -Command @($batchProbe) `
        -TimeoutSeconds 10 `
        -LogDirectory $LogDirectory
    if ($batchResult.ExitCode -ne 0 -or $batchResult.TimedOut) {
        throw "Batch invocation self test failed: exit=$($batchResult.ExitCode), timedOut=$($batchResult.TimedOut)"
    }
} finally {
    Remove-Item $batchProbe -Force -ErrorAction SilentlyContinue
}

if ($IncludeFlutter) {
    $flutter = (Get-Command flutter -ErrorAction Stop).Source
    $flutterBin = Split-Path $flutter -Parent
    $dart = Join-Path $flutterBin "cache\dart-sdk\bin\dart.exe"
    $flutterToolsSnapshot = Join-Path $flutterBin "cache\flutter_tools.snapshot"
    $flutterResult = Invoke-BoundedCommand `
        -Name "Flutter tools invocation self test" `
        -Command @($dart, $flutterToolsSnapshot, "--version") `
        -TimeoutSeconds 60 `
        -LogDirectory $LogDirectory
    if ($flutterResult.ExitCode -ne 0 -or $flutterResult.TimedOut) {
        throw "Flutter invocation self test failed: exit=$($flutterResult.ExitCode), timedOut=$($flutterResult.TimedOut)"
    }
}

Write-Host "Quality-gate timeout, redaction, and batch invocation self tests passed."
