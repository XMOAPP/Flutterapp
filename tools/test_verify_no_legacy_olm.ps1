[CmdletBinding()]
param()

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$ErrorActionPreference = "Stop"
$verifier = Join-Path $PSScriptRoot "verify_no_legacy_olm.ps1"
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "xmo_olm_gate_" + [Guid]::NewGuid().ToString("N")
)

function Invoke-Gate {
    param(
        [string]$Root,
        [string]$Artifact,
        [switch]$RequireRustCrypto
    )

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $verifier,
        "-ProjectRoot", $Root,
        "-Artifact", $Artifact,
        "-CheckDependencies"
    )
    if ($RequireRustCrypto) {
        $arguments += "-RequireRustCrypto"
    }

    $output = & "$PSHOME\powershell.exe" @arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    return $exitCode
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $artifact = Join-Path $testRoot "app-release.aab"

    Set-Content -LiteralPath (Join-Path $testRoot "pubspec.yaml") -Value @"
name: test_app
dependencies:
  flutter_olm:
    path: third_party/flutter_olm
"@
    Set-Content -LiteralPath (Join-Path $testRoot "pubspec.lock") -Value @"
packages:
  olm:
    dependency: transitive
"@
    New-Item `
        -ItemType Directory `
        -Path (Join-Path $testRoot "third_party/flutter_olm") | Out-Null

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open(
        $artifact,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        $entry = $zip.CreateEntry("base/lib/arm64-v8a/libolm.so")
        $stream = $entry.Open()
        try {
            $stream.WriteByte(0)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $zip.Dispose()
    }

    if ((Invoke-Gate -Root $testRoot -Artifact $artifact) -ne 0) {
        throw "Audit mode must report legacy Olm without failing."
    }
    if ((Invoke-Gate `
            -Root $testRoot `
            -Artifact $artifact `
            -RequireRustCrypto) -eq 0) {
        throw "Cutover mode must reject legacy Olm."
    }

    Remove-Item -LiteralPath (Join-Path $testRoot "third_party") -Recurse
    Set-Content -LiteralPath (Join-Path $testRoot "pubspec.yaml") -Value @"
name: test_app
dependencies: {}
"@
    Set-Content -LiteralPath (Join-Path $testRoot "pubspec.lock") -Value @"
packages: {}
"@
    Remove-Item -LiteralPath $artifact

    $zip = [System.IO.Compression.ZipFile]::Open(
        $artifact,
        [System.IO.Compression.ZipArchiveMode]::Create
    )
    try {
        $entry = $zip.CreateEntry("base/lib/arm64-v8a/libxmo_crypto.so")
        $stream = $entry.Open()
        try {
            $stream.WriteByte(0)
        } finally {
            $stream.Dispose()
        }
    } finally {
        $zip.Dispose()
    }

    if ((Invoke-Gate `
            -Root $testRoot `
            -Artifact $artifact `
            -RequireRustCrypto) -ne 0) {
        throw "Cutover mode must accept an artifact without legacy Olm."
    }

    Write-Host "PASS: legacy Olm release-gate tests passed."
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
