$ErrorActionPreference = 'Stop'
$FlutterArguments = @($args)
$toolchainRoot = 'C:\tmp\xmo-toolchain-links'
$projectRoot = Join-Path $toolchainRoot 'project'
$flutter = Join-Path $toolchainRoot 'flutter\bin\flutter.bat'

foreach ($requiredPath in @($projectRoot, $flutter)) {
    if (!(Test-Path -LiteralPath $requiredPath)) {
        throw "Short-path toolchain link is missing: $requiredPath"
    }
}

$env:PUB_CACHE = Join-Path $toolchainRoot 'pub'
$env:ANDROID_HOME = Join-Path $toolchainRoot 'android'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:DART_DISABLE_ANALYTICS = 'true'

$rustupHome = 'C:\tmp\xmo-rustup'
if (Test-Path -LiteralPath $rustupHome) {
    $env:RUSTUP_HOME = $rustupHome
    Remove-Item Env:CARGO_HOME -ErrorAction SilentlyContinue
    $cargoBin = Join-Path $env:USERPROFILE '.cargo\bin'
    $env:PATH = "$cargoBin;$env:PATH"
}

Push-Location $projectRoot
try {
    & $flutter @FlutterArguments
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
