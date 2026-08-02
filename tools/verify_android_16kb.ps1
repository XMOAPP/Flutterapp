[CmdletBinding()]
param(
    [string]$Artifact = "build/app/outputs/bundle/release/app-release.aab",
    [string]$BundletoolJar,
    [string]$AndroidSdk
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$artifactPath = if ([IO.Path]::IsPathRooted($Artifact)) {
    $Artifact
} else {
    Join-Path $projectRoot $Artifact
}

if (!(Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
    throw "AAB not found: $artifactPath"
}

if ([string]::IsNullOrWhiteSpace($AndroidSdk)) {
    $AndroidSdk = if ($env:ANDROID_SDK_ROOT) {
        $env:ANDROID_SDK_ROOT
    } elseif ($env:ANDROID_HOME) {
        $env:ANDROID_HOME
    } else {
        $localProperties = Join-Path $projectRoot "android/local.properties"
        $sdkLine = Get-Content -LiteralPath $localProperties |
            Where-Object { $_ -match '^sdk\.dir=' } |
            Select-Object -First 1
        if ($sdkLine) {
            ($sdkLine.Substring($sdkLine.IndexOf('=') + 1) -replace '\\\\', '\')
        }
    }
}

$readelfName = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    'llvm-readelf.exe'
} else {
    'llvm-readelf'
}
$readelf = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'ndk') `
        -Filter $readelfName -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if (!$readelf) {
    throw "llvm-readelf was not found below Android SDK: $AndroidSdk"
}

if ([string]::IsNullOrWhiteSpace($BundletoolJar) -or
    !(Test-Path -LiteralPath $BundletoolJar -PathType Leaf)) {
    throw "Pass -BundletoolJar with an official bundletool-all JAR."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path $artifactPath))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'xmo-aab-16kb-' + [Guid]::NewGuid().ToString('N')
)
$failures = [Collections.Generic.List[string]]::new()
$checked = 0

try {
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $nativeEntries = @(
        $archive.Entries |
            Where-Object { $_.FullName -match '^base/lib/([^/]+)/([^/]+\.so)$' }
    )

    $legacyOlm = @($nativeEntries | Where-Object { $_.Name -eq 'libolm.so' })
    if ($legacyOlm.Count -gt 0) {
        $failures.Add('AAB contains legacy libolm.so')
    }

    foreach ($abi in @('arm64-v8a', 'x86_64')) {
        $abiEntries = @(
            $nativeEntries | Where-Object { $_.FullName -like "base/lib/$abi/*" }
        )
        if (!($abiEntries | Where-Object {
                    $_.Name -eq 'libvodozemac_bindings_dart.so'
                })) {
            $failures.Add("$abi is missing libvodozemac_bindings_dart.so")
        }

        foreach ($entry in $abiEntries) {
            $abiDirectory = Join-Path $tempRoot $abi
            New-Item -ItemType Directory -Force -Path $abiDirectory | Out-Null
            $libraryPath = Join-Path $abiDirectory $entry.Name
            [IO.Compression.ZipFileExtensions]::ExtractToFile(
                $entry,
                $libraryPath,
                $true
            )

            $loadSegments = @(
                & $readelf -lW $libraryPath |
                    Where-Object { $_ -match '^\s*LOAD\s' }
            )
            if ($loadSegments.Count -eq 0) {
                $failures.Add("$abi/$($entry.Name) has no ELF LOAD segments")
                continue
            }

            foreach ($segment in $loadSegments) {
                $alignmentToken = ($segment -split '\s+')[-1]
                $alignment = [Convert]::ToInt64(
                    $alignmentToken.Substring(2),
                    16
                )
                if ($alignment -lt 0x4000) {
                    $failures.Add(
                        "$abi/$($entry.Name) has LOAD alignment $alignmentToken"
                    )
                }
            }
            $checked++
        }
    }
} finally {
    $archive.Dispose()
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

$bundleConfig = & java -jar $BundletoolJar dump config "--bundle=$artifactPath" 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "bundletool dump config failed: $($bundleConfig -join ' ')"
}
if (($bundleConfig -join "`n") -notmatch 'PAGE_ALIGNMENT_16K') {
    $failures.Add('BundleConfig does not request PAGE_ALIGNMENT_16K')
}

if ($failures.Count -gt 0) {
    throw "16 KB artifact gate failed:`n- $($failures -join "`n- ")"
}

Write-Host "PASS: $checked 64-bit ELF libraries use >=16 KB LOAD alignment."
Write-Host "PASS: Vodozemac is packaged, libolm.so is absent, and BundleConfig uses PAGE_ALIGNMENT_16K."
