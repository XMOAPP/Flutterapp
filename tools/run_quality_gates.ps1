param(
    [switch]$SkipFlutter,
    [switch]$SkipBackend,
    [int]$FormatTimeoutSeconds = 180,
    [int]$AnalyzeTimeoutSeconds = 420,
    [int]$TestTimeoutSeconds = 600,
    [string]$ReportPath = "build/quality_gate/quality_gate_report.md"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "quality_gate_common.ps1")

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

$reportFullPath = Join-Path $projectRoot $ReportPath
$logDirectory = Split-Path $reportFullPath -Parent
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

$env:DART_DISABLE_ANALYTICS = "true"
$env:DART_TOOL_HOME = Join-Path $logDirectory "dart_tool_home"
New-Item -ItemType Directory -Force -Path $env:DART_TOOL_HOME | Out-Null
$originalAppData = $env:APPDATA
$isolatedAppData = Join-Path $logDirectory "appdata"
New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null

$flutterPath = (Get-Command flutter -ErrorAction Stop).Source
$flutterBinPath = Split-Path $flutterPath -Parent
$dartPath = Join-Path $flutterBinPath "cache\dart-sdk\bin\dart.exe"
$flutterToolsSnapshot = Join-Path $flutterBinPath "cache\flutter_tools.snapshot"
if (!(Test-Path $dartPath)) {
    throw "Unable to find the Dart SDK bundled with Flutter at $dartPath"
}
if (!(Test-Path $flutterToolsSnapshot)) {
    throw "Unable to find Flutter tools at $flutterToolsSnapshot"
}

$results = [System.Collections.Generic.List[object]]::new()

function Add-Gate {
    param([string]$Name, [string[]]$Command, [int]$TimeoutSeconds)

    $result = Invoke-BoundedCommand `
        -Name $Name `
        -Command $Command `
        -TimeoutSeconds $TimeoutSeconds `
        -LogDirectory $logDirectory
    $results.Add($result) | Out-Null
}

# Check both unstaged and staged changes. A passing test suite does not catch
# whitespace errors that would make a commit fail in CI or during review.
Add-Gate "Git working-tree diff check" @("git", "diff", "--check") 30
Add-Gate "Git staged diff check" @("git", "diff", "--cached", "--check") 30

if (!$SkipFlutter) {
    $env:APPDATA = $isolatedAppData
    Add-Gate "Flutter format check" @(
        $dartPath, "format", "--output=none", "--set-exit-if-changed",
        "lib", "test", "integration_test"
    ) $FormatTimeoutSeconds
    $env:APPDATA = $originalAppData
    # Invoke flutter_tools through Dart on Windows so Start-Process owns the
    # actual process and can terminate the complete tree deterministically.
    Add-Gate "Flutter analyze" @(
        $dartPath, $flutterToolsSnapshot, "analyze", "--no-pub"
    ) $AnalyzeTimeoutSeconds
    Add-Gate "Flutter test" @(
        $dartPath, $flutterToolsSnapshot, "test", "--no-pub", "--reporter", "expanded"
    ) $TestTimeoutSeconds
}

if (!$SkipBackend) {
    $env:APPDATA = $isolatedAppData
    Push-Location "auth_server"
    try {
        Add-Gate "Auth server format check" @(
            $dartPath, "format", "--output=none", "--set-exit-if-changed",
            "bin", "lib", "test"
        ) $FormatTimeoutSeconds
        Add-Gate "Auth server analyze" @($dartPath, "analyze") $AnalyzeTimeoutSeconds
        Add-Gate "Auth server test" @($dartPath, "test", "--reporter", "expanded") $TestTimeoutSeconds
    } finally {
        Pop-Location
        $env:APPDATA = $originalAppData
    }
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# XMO Deterministic Quality Gate") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Gate | Result | Exit | Timed out | Duration | Logs |") | Out-Null
$lines.Add("|---|---|---:|---|---:|---|") | Out-Null
foreach ($result in $results) {
    $status = if ($result.ExitCode -eq 0) { "PASS" } else { "FAIL" }
    $logs = "$(Split-Path $result.StdoutPath -Leaf), $(Split-Path $result.StderrPath -Leaf)"
    $lines.Add("| $($result.Name) | $status | $($result.ExitCode) | $($result.TimedOut) | $($result.ElapsedSeconds)s | $logs |") | Out-Null
}

$failures = @($results | Where-Object { $_.ExitCode -ne 0 })
$lines.Add("") | Out-Null
$lines.Add("Result: **$(if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' })**") | Out-Null
Set-Content $reportFullPath $lines -Encoding UTF8

Write-Host "Quality gate report written to $ReportPath"
if ($failures.Count -gt 0) {
    exit 1
}
