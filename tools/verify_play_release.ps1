param(
    [switch]$BuildAab,
    [switch]$SkipAnalyze,
    [switch]$SkipTests,
    [switch]$SkipCrashlyticsUpload,
    [switch]$FullChecks,
    [int]$CommandTimeoutSeconds = 300,
    [string]$ReportPath = "build/release_verification/play_release_verification.md",
    [string[]]$DartDefine = @(
        "XMO_HOMESERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com",
        "XMO_MATRIX_SERVER_NAME=xmo-matrix.centralindia.cloudapp.azure.com",
        "XMO_WALLET_AUTH_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/wallet",
        "XMO_STREAM_CHUNK_STORAGE=azure",
        "XMO_AZURE_CHUNK_SIGN_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/media/chunks/azure/sign-upload",
        "XMO_ACCOUNT_DELETION_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp",
        "XMO_ACCOUNT_DELETION_WEB_URL=https://xmo.dpdns.org/account-deletion",
        "XMO_INVITE_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp",
        "XMO_INVITE_WEB_BASE_URL=https://xmo.dpdns.org",
        "XMO_ENABLE_SSO_LOGIN=true",
        "XMO_SSO_IDP_ID=oidc-authentik",
        "XMO_SSO_CALLBACK_URL=https://xmo.dpdns.org/auth/callback",
        "XMO_MFA_SETUP_URL=https://auth.xmo.dpdns.org/if/flow/xmo-totp-setup/"
    )
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "quality_gate_common.ps1")

function Add-Result {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [string]$Section,
        [string]$Check,
        [string]$Status,
        [string]$Severity,
        [string]$Evidence,
        [string]$Action
    )

    $Results.Add([pscustomobject]@{
        Section = $Section
        Check = $Check
        Status = $Status
        Severity = $Severity
        Evidence = $Evidence
        Action = $Action
    }) | Out-Null
}

function Invoke-CheckedCommand {
    param(
        [string]$Name,
        [string[]]$Command,
        [int]$TimeoutSeconds = $CommandTimeoutSeconds
    )

    $bounded = Invoke-BoundedCommand `
        -Name $Name `
        -Command $Command `
        -TimeoutSeconds $TimeoutSeconds `
        -LogDirectory $reportDir

    return [pscustomobject]@{
        Name = $Name
        ExitCode = $bounded.ExitCode
        TimedOut = $bounded.TimedOut
        ElapsedSeconds = $bounded.ElapsedSeconds
        Output = "Logs: $($bounded.StdoutPath), $($bounded.StderrPath); timeout=$($bounded.TimedOut); duration=$($bounded.ElapsedSeconds)s"
    }
}

function Test-FileContains {
    param(
        [string]$Path,
        [string]$Pattern
    )

    if (!(Test-Path $Path)) {
        return $false
    }
    return [bool](Select-String -Path $Path -Pattern $Pattern -Quiet)
}

function Get-RegexValue {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern)
    if ($match.Success -and $match.Groups.Count -gt 1) {
        return $match.Groups[1].Value
    }
    return ""
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

$results = [System.Collections.Generic.List[object]]::new()
$commands = [System.Collections.Generic.List[object]]::new()
$reportFullPath = Join-Path $projectRoot $ReportPath
$reportDir = Split-Path $reportFullPath -Parent
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

$buildGradlePath = "android/app/build.gradle.kts"
$manifestPath = "android/app/src/main/AndroidManifest.xml"
$pubspecPath = "pubspec.yaml"
$gitignorePath = ".gitignore"
$backupRulesPath = "android/app/src/main/res/xml/backup_rules.xml"
$dataExtractionRulesPath = "android/app/src/main/res/xml/data_extraction_rules.xml"
$appConfigPath = "lib/config/app_config.dart"

$buildGradle = if (Test-Path $buildGradlePath) { Get-Content $buildGradlePath -Raw } else { "" }
$manifest = if (Test-Path $manifestPath) { Get-Content $manifestPath -Raw } else { "" }
$pubspec = if (Test-Path $pubspecPath) { Get-Content $pubspecPath -Raw } else { "" }
$gitignore = if (Test-Path $gitignorePath) { Get-Content $gitignorePath -Raw } else { "" }
$appConfig = if (Test-Path $appConfigPath) { Get-Content $appConfigPath -Raw } else { "" }

$applicationId = Get-RegexValue $buildGradle 'applicationId\s*=\s*"([^"]+)"'
$namespace = Get-RegexValue $buildGradle 'namespace\s*=\s*"([^"]+)"'
$version = Get-RegexValue $pubspec '(?m)^version:\s*([^\r\n]+)'
$androidLabel = Get-RegexValue $manifest 'android:label="([^"]+)"'

if ($applicationId -and $applicationId -notmatch '^com\.example\.') {
    Add-Result $results "Application identity" "applicationId" "PASS" "BLOCKER" "$buildGradlePath uses $applicationId" "None"
} else {
    Add-Result $results "Application identity" "applicationId" "FAIL" "BLOCKER" "$buildGradlePath applicationId is missing or placeholder" "Set a permanent production applicationId."
}

if ($namespace -and $namespace -eq $applicationId) {
    Add-Result $results "Application identity" "namespace matches applicationId" "PASS" "MEDIUM" "$buildGradlePath namespace=$namespace" "None"
} else {
    Add-Result $results "Application identity" "namespace matches applicationId" "NEEDS ATTENTION" "MEDIUM" "$buildGradlePath namespace=$namespace applicationId=$applicationId" "Keep namespace and package naming intentional."
}

if ($version -match '^\d+\.\d+\.\d+\+\d+$') {
    Add-Result $results "Application identity" "pubspec version format" "PASS" "HIGH" "$pubspecPath version=$version" "Before Play upload, confirm this versionCode is unused in Play Console."
} else {
    Add-Result $results "Application identity" "pubspec version format" "FAIL" "HIGH" "$pubspecPath version=$version" "Use versionName+versionCode, for example 1.0.1+2."
}

if ($androidLabel -eq "XMO") {
    Add-Result $results "Application identity" "Android app label" "PASS" "HIGH" "$manifestPath android:label=$androidLabel" "None"
} else {
    Add-Result $results "Application identity" "Android app label" "FAIL" "HIGH" "$manifestPath android:label=$androidLabel" "Set the release launcher label to XMO."
}

if ($buildGradle -match 'throw GradleException\(\s*"Missing android/key\.properties' -and $buildGradle -match 'signingConfig\s*=\s*signingConfigs\.getByName\("release"\)') {
    Add-Result $results "Signing" "release signing guard" "PASS" "BLOCKER" "$buildGradlePath fails release builds when android/key.properties is missing" "None"
} else {
    Add-Result $results "Signing" "release signing guard" "FAIL" "BLOCKER" "$buildGradlePath may allow unsigned/debug-signed release output" "Keep release signing mandatory and fail if key.properties is missing."
}

if ($gitignore -match 'key\.properties' -and $gitignore -match '\*\.jks') {
    Add-Result $results "Signing" "secret file ignore rules" "PASS" "BLOCKER" "$gitignorePath ignores key.properties and .jks" "Never commit keystores or passwords."
} else {
    Add-Result $results "Signing" "secret file ignore rules" "FAIL" "BLOCKER" "$gitignorePath does not cover release signing secrets" "Ignore key.properties, .jks, .keystore, .pem, and environment files."
}

if (Test-Path "android/key.properties") {
    Add-Result $results "Signing" "local key.properties exists" "PASS" "HIGH" "android/key.properties exists locally; values were not printed" "Use only for local signed release builds."
} else {
    Add-Result $results "Signing" "local key.properties exists" "NOT VERIFIABLE" "HIGH" "android/key.properties is not present in this checkout" "Create it locally or use CI secrets before building a signed AAB."
}

if ($manifest -match 'android:fullBackupContent="@xml/backup_rules"' -and $manifest -match 'android:dataExtractionRules="@xml/data_extraction_rules"' -and (Test-Path $backupRulesPath) -and (Test-Path $dataExtractionRulesPath)) {
    Add-Result $results "Storage security" "Android backup exclusions configured" "PASS" "BLOCKER" "$manifestPath references backup rules and data extraction rules" "Device backup behavior still needs real-device verification."
} else {
    Add-Result $results "Storage security" "Android backup exclusions configured" "FAIL" "BLOCKER" "$manifestPath must reference backup exclusions for Matrix/E2EE/cache data" "Add fullBackupContent and dataExtractionRules XML files."
}

$requiredDefines = @(
    "XMO_HOMESERVER_URL",
    "XMO_MATRIX_SERVER_NAME",
    "XMO_WALLET_AUTH_SERVER_URL",
    "XMO_STREAM_CHUNK_STORAGE",
    "XMO_AZURE_CHUNK_SIGN_URL",
    "XMO_ACCOUNT_DELETION_SERVER_URL",
    "XMO_ACCOUNT_DELETION_WEB_URL",
    "XMO_INVITE_SERVER_URL",
    "XMO_INVITE_WEB_BASE_URL"
)

$providedDefineNames = @{}
foreach ($define in $DartDefine) {
    $name = ($define -split '=', 2)[0]
    $providedDefineNames[$name] = $true
}

$missingDefines = @($requiredDefines | Where-Object { !$providedDefineNames.ContainsKey($_) })
if ($missingDefines.Count -eq 0) {
    Add-Result $results "Production config" "required release dart-defines supplied" "PASS" "BLOCKER" ($requiredDefines -join ", ") "None"
} else {
    Add-Result $results "Production config" "required release dart-defines supplied" "FAIL" "BLOCKER" ("Missing: " + ($missingDefines -join ", ")) "Pass every required production dart-define to build/run."
}

$badDefineValues = @($DartDefine | Where-Object {
    $_ -match 'localhost|127\.0\.0\.1|10\.0\.2\.2|http://'
})
if ($badDefineValues.Count -eq 0) {
    Add-Result $results "Production config" "release dart-defines use production HTTPS hosts" "PASS" "BLOCKER" "No localhost/emulator/http values in supplied dart-defines" "None"
} else {
    Add-Result $results "Production config" "release dart-defines use production HTTPS hosts" "FAIL" "BLOCKER" "One or more supplied values use local or insecure endpoints; values redacted" "Replace with production HTTPS endpoints."
}

if ($appConfig -match "defaultValue: 'http://localhost:8008'" -or $appConfig -match "defaultValue: 'localhost'") {
    Add-Result $results "Production config" "development defaults cannot be used silently" "NEEDS ATTENTION" "HIGH" "$appConfigPath keeps development defaults for local builds" "Release builds must pass explicit production dart-defines and should be checked by this script/CI."
} else {
    Add-Result $results "Production config" "development defaults cannot be used silently" "PASS" "HIGH" "$appConfigPath has no localhost defaults" "None"
}

$permissions = [regex]::Matches($manifest, '<uses-permission\s+android:name="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
if ($permissions.Count -gt 0) {
    Add-Result $results "Manifest" "permissions inventory" "NEEDS ATTENTION" "HIGH" ($permissions -join ", ") "Map each permission to a Play disclosure and app feature before upload."
} else {
    Add-Result $results "Manifest" "permissions inventory" "FAIL" "HIGH" "No permissions found; manifest may not have been read" "Inspect merged release manifest."
}

if ($manifest -match 'USE_FULL_SCREEN_INTENT') {
    Add-Result $results "Manifest" "full-screen intent policy" "NEEDS ATTENTION" "HIGH" "$manifestPath declares USE_FULL_SCREEN_INTENT" "In Play Console, declare qualifying incoming-call use and verify degraded behavior if unavailable."
}

if ($buildGradle -match 'minifyEnabled|isMinifyEnabled|shrinkResources|isShrinkResources') {
    Add-Result $results "Build config" "R8/resource shrinking configured" "NEEDS ATTENTION" "MEDIUM" "$buildGradlePath contains shrinking configuration" "Verify wallet/Firebase/Matrix/WebRTC release behavior after shrinking."
} else {
    Add-Result $results "Build config" "R8/resource shrinking configured" "NEEDS ATTENTION" "MEDIUM" "$buildGradlePath does not enable minification/resource shrinking" "Not a blocker; measure size first, then test a separate minified build before release use."
}

if (!$SkipAnalyze) {
    $analyzeCommand = if ($FullChecks) {
        @("flutter", "analyze")
    } else {
        @(
            "flutter",
            "analyze",
            "lib/config/app_config.dart",
            "lib/models/xmo_stream_manifest.dart",
            "lib/services/local_playback_proxy_service.dart",
            "lib/services/streaming_playback_decision_service.dart",
            "test/streaming_playback_decision_service_test.dart"
        )
    }

    $analyze = Invoke-CheckedCommand "flutter analyze" $analyzeCommand
    $commands.Add($analyze) | Out-Null
    if ($analyze.ExitCode -eq 0) {
        $scope = if ($FullChecks) { "full project" } else { "focused release-critical files" }
        Add-Result $results "Tooling" "flutter analyze" "PASS" "BLOCKER" "flutter analyze exited 0 ($scope)" "Run with -FullChecks before final upload."
    } else {
        Add-Result $results "Tooling" "flutter analyze" "FAIL" "BLOCKER" "flutter analyze exited $($analyze.ExitCode)" "Fix analyzer errors before release."
    }
} else {
    Add-Result $results "Tooling" "flutter analyze" "NOT VERIFIABLE" "BLOCKER" "Skipped by -SkipAnalyze" "Run flutter analyze before release. If it hangs, treat that as a release-tooling blocker until isolated."
}

if (!$SkipTests) {
    $testCommand = if ($FullChecks) {
        @("flutter", "test")
    } else {
        @(
            "flutter",
            "test",
            "test/streaming_playback_decision_service_test.dart",
            "test/xmo_stream_manifest_test.dart",
            "test/local_playback_proxy_service_test.dart",
            "test/xmo_media_compatibility_test.dart"
        )
    }

    $tests = Invoke-CheckedCommand "flutter test" $testCommand
    $commands.Add($tests) | Out-Null
    if ($tests.ExitCode -eq 0) {
        $scope = if ($FullChecks) { "full project" } else { "focused streaming/release media tests" }
        Add-Result $results "Tooling" "flutter test" "PASS" "BLOCKER" "flutter test exited 0 ($scope)" "Run with -FullChecks before final upload."
    } else {
        Add-Result $results "Tooling" "flutter test" "FAIL" "BLOCKER" "flutter test exited $($tests.ExitCode)" "Fix failing tests before release."
    }
} else {
    Add-Result $results "Tooling" "flutter test" "NOT VERIFIABLE" "BLOCKER" "Skipped by -SkipTests" "Run tests before release."
}

if ($BuildAab) {
    $aabPath = "build/app/outputs/bundle/release/app-release.aab"
    $aabBuildStartedAt = Get-Date
    $versionMatch = [regex]::Match($version, '^(?<name>\d+\.\d+\.\d+)\+(?<code>\d+)$')
    if (!$versionMatch.Success) {
        throw "Cannot build AAB: invalid pubspec version '$version'."
    }
    $flutterVersionName = $versionMatch.Groups['name'].Value
    $flutterVersionCode = $versionMatch.Groups['code'].Value
    $localPropertiesPath = "android/local.properties"
    if (!(Test-Path $localPropertiesPath)) {
        throw "Cannot build AAB: $localPropertiesPath is missing. Run flutter pub get first."
    }
    $localProperties = Get-Content $localPropertiesPath -Raw
    foreach ($entry in @{
            'flutter.versionName' = $flutterVersionName
            'flutter.versionCode' = $flutterVersionCode
        }.GetEnumerator()) {
        $pattern = "(?m)^$([regex]::Escape($entry.Key))=.*$"
        $replacement = "$($entry.Key)=$($entry.Value)"
        if ($localProperties -match $pattern) {
            $localProperties = [regex]::Replace(
                $localProperties,
                $pattern,
                $replacement
            )
        } else {
            $localProperties = $localProperties.TrimEnd() +
                [Environment]::NewLine + $replacement +
                [Environment]::NewLine
        }
    }
    Set-Content -Path $localPropertiesPath -Value $localProperties -NoNewline
    $encodedDartDefines = @()
    foreach ($define in $DartDefine) {
        $encodedDartDefines += [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($define))
    }
    $aabCommand = @(
        "android/gradlew.bat",
        "-p",
        "android",
        ":app:bundleRelease",
        "-Pflutter.versionName=$flutterVersionName",
        "-Pflutter.versionCode=$flutterVersionCode",
        "-Pdart-defines=$($encodedDartDefines -join ',')"
    )
    if ($SkipCrashlyticsUpload) {
        $aabCommand += @(
            "-x",
            ":app:uploadCrashlyticsMappingFileRelease"
        )
    }
    $aab = Invoke-CheckedCommand "Gradle bundleRelease" $aabCommand -TimeoutSeconds ([math]::Max($CommandTimeoutSeconds, 900))
    $commands.Add($aab) | Out-Null
    if ($aab.ExitCode -eq 0 -and (Test-Path $aabPath)) {
        $aabItem = Get-Item $aabPath
        if ($aabItem.LastWriteTime -ge $aabBuildStartedAt.AddSeconds(-5)) {
            Add-Result $results "Signed AAB" "release app bundle build" "PASS" "BLOCKER" "AAB built at $aabPath ($([math]::Round($aabItem.Length / 1MB, 2)) MiB)" "Upload this only to internal testing first."
        } else {
            Add-Result $results "Signed AAB" "release app bundle build" "FAIL" "BLOCKER" "Gradle exited $($aab.ExitCode), but $aabPath was not freshly generated in this run" "Fix release build and rerun; do not rely on stale AAB artifacts."
        }
    } else {
        Add-Result $results "Signed AAB" "release app bundle build" "FAIL" "BLOCKER" "Gradle bundleRelease exited $($aab.ExitCode)" "Fix release build before Play upload."
    }
} else {
    Add-Result $results "Signed AAB" "release app bundle build" "NOT VERIFIABLE" "BLOCKER" "Skipped by default" "Run this script with -BuildAab before Play internal testing."
}

$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# XMO Play Release Verification Report") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("Generated: $now") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("## Result Table") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("| Section | Check | Status | Severity | Evidence | Required action |") | Out-Null
$lines.Add("|---|---|---|---|---|---|") | Out-Null
foreach ($result in $results) {
    $evidence = ($result.Evidence -replace '\|', '/' -replace "`r?`n", " ")
    $action = ($result.Action -replace '\|', '/' -replace "`r?`n", " ")
    $lines.Add("| $($result.Section) | $($result.Check) | $($result.Status) | $($result.Severity) | $evidence | $action |") | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## Commands") | Out-Null
$lines.Add("") | Out-Null
foreach ($command in $commands) {
    $lines.Add("- $($command.Name): exit $($command.ExitCode)") | Out-Null
}

$lines.Add("") | Out-Null
$lines.Add("## Manual Gates Still Required") | Out-Null
$lines.Add("") | Out-Null
$lines.Add("- Confirm Play Console developer identity and contact verification are approved.") | Out-Null
$lines.Add("- Confirm versionCode is unused in Play Console before upload.") | Out-Null
$lines.Add("- Upload the AAB to internal testing before production.") | Out-Null
$lines.Add("- Inspect Play pre-launch report, SDK Index warnings, permissions, Data Safety, content rating, and financial declarations.") | Out-Null
$lines.Add("- Run the real-device streaming checks in the Production handbook section of README.md.") | Out-Null
$lines.Add("- Verify 16 KB page-size compatibility for native libraries using Android Studio/Play report or bundletool extraction.") | Out-Null

Set-Content -Path $reportFullPath -Value $lines -Encoding UTF8

Write-Host ""
Write-Host "Release verification report written to $ReportPath"
Write-Host ""
$blockingFailures = @($results | Where-Object { $_.Severity -eq "BLOCKER" -and ($_.Status -eq "FAIL" -or $_.Status -eq "NOT VERIFIABLE") })
if ($blockingFailures.Count -gt 0) {
    Write-Host "Release gate is not complete. Blocking items remain: $($blockingFailures.Count)"
    exit 2
}

Write-Host "No blocking FAIL/NOT VERIFIABLE items found by automated checks."
exit 0
