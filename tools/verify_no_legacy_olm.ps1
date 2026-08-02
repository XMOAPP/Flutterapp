[CmdletBinding()]
param(
    [string]$Artifact = "build/app/outputs/bundle/release/app-release.aab",
    [string]$ProjectRoot,
    [switch]$CheckDependencies,
    [switch]$RequireRustCrypto,
    [switch]$AllowMissingArtifact
)

$ErrorActionPreference = "Stop"
$resolvedProjectRoot = if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    (Resolve-Path $ProjectRoot).Path
}
$artifactPath = if ([System.IO.Path]::IsPathRooted($Artifact)) {
    $Artifact
} else {
    Join-Path $resolvedProjectRoot $Artifact
}

$legacyFindings = [System.Collections.Generic.List[string]]::new()

if ($CheckDependencies -or $RequireRustCrypto) {
    $pubspecPath = Join-Path $resolvedProjectRoot "pubspec.yaml"
    $lockPath = Join-Path $resolvedProjectRoot "pubspec.lock"
    $legacyPackagePath = Join-Path $resolvedProjectRoot "third_party/flutter_olm"

    if (Test-Path -LiteralPath $pubspecPath -PathType Leaf) {
        $pubspec = Get-Content -LiteralPath $pubspecPath -Raw
        if ($pubspec -match '(?m)^\s*flutter_olm\s*:') {
            $legacyFindings.Add("pubspec.yaml declares flutter_olm")
        }
    }

    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        $lockfile = Get-Content -LiteralPath $lockPath -Raw
        if ($lockfile -match '(?m)^\s{2}(flutter_olm|olm)\s*:') {
            $legacyFindings.Add("pubspec.lock resolves a legacy Olm package")
        }
    }

    if (Test-Path -LiteralPath $legacyPackagePath) {
        $legacyFindings.Add("third_party/flutter_olm is present")
    }
}

if (Test-Path -LiteralPath $artifactPath -PathType Leaf) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = $null

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($artifactPath)
        @(
            $archive.Entries |
                Where-Object { $_.FullName -match '(^|/)libolm\.so$' } |
                ForEach-Object { $_.FullName }
        ) | ForEach-Object {
            $legacyFindings.Add("artifact contains $_")
        }
    } finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
} elseif (-not $AllowMissingArtifact) {
    Write-Error "Release artifact not found: $artifactPath"
    exit 2
} else {
    Write-Host "INFO: release artifact was not checked because it does not exist: $artifactPath"
}

if ($legacyFindings.Count -gt 0) {
    $summary = $legacyFindings -join "; "
    if ($RequireRustCrypto) {
        Write-Error "Rust-crypto cutover gate failed: $summary"
        exit 1
    }

    Write-Warning "Legacy Olm is still active: $summary"
    Write-Host "AUDIT: current builds remain on the legacy Matrix crypto path."
    Write-Host "Run with -RequireRustCrypto only after the Rust adapter and migration tests pass."
    exit 0
}

Write-Host "PASS: no legacy Olm dependency or packaged libolm.so was found."
exit 0
