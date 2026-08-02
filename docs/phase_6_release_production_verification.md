# Phase 6: Release / Production Verification

This phase proves the current XMO build is safe to send to Google Play internal
testing. It should not add new product features.

## Why This Phase Exists

Google Play release readiness is not the same as `flutter run` working. The app
must be verified with production dart-defines, release signing, Android manifest
policy requirements, native-library compatibility, privacy URLs, and real-device
regression coverage.

Current external requirements to keep in mind:

- Google Play requires recent target API levels. Starting 31 August 2026, new
  apps and updates must target Android 16 / API 36 or higher unless an exception
  applies.
- Apps using native code and targeting Android 15+ must support 16 KB page sizes
  for Google Play submissions from 1 November 2025.
- New apps must use Play App Signing.

## Automated Verification

Run this from the project root:

```powershell
cd "C:\Users\sangeeth karunakaran\Desktop\xmoapp\xmo"
powershell -ExecutionPolicy Bypass -File .\tools\verify_play_release.ps1
```

This checks:

- Android application ID and namespace.
- `pubspec.yaml` version format.
- Release signing guard.
- `.gitignore` protection for signing secrets.
- Android backup exclusion configuration.
- Required production dart-defines.
- Obvious local/insecure production configuration mistakes.
- Manifest permission inventory.
- Full-screen intent policy warning.
- R8/resource shrinking status.
- Focused release-critical `flutter analyze`.
- Focused streaming/release-media tests.

If analyzer/test tooling is hanging and you need only the static Play-release
configuration report first, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\verify_play_release.ps1 -SkipAnalyze -SkipTests
```

This does not prove release readiness. It only confirms the static checks and
marks analyzer/tests as not verifiable.

Run the full project checks before final upload:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\verify_play_release.ps1 -FullChecks
```

If full project analysis hangs, treat that as a release-tooling issue and record
it in the generated report. Do not call the release clean until either the full
check passes or the hang has a documented root cause and workaround.

The script writes:

```text
build/release_verification/play_release_verification.md
```

## Signed AAB Verification

Only run this after local signing is configured:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\verify_play_release.ps1 -BuildAab -FullChecks
```

Expected output:

```text
build/app/outputs/bundle/release/app-release.aab
```

Upload this AAB to **Internal testing** first. Do not upload directly to
production.

## Current Local Verification Result

Last verified on `2026-07-20` with production dart-defines:

- `flutter analyze --no-pub`: passed with no issues in `18.8s`.
- `flutter test`: passed, `147` tests.
- Unified `verify_play_release.ps1 -BuildAab -FullChecks`: passed with no
  automated blocking `FAIL` or `NOT VERIFIABLE` items.
- Clean signed release AAB: passed with the exact production configuration.
- Artifact: `build/app/outputs/bundle/release/app-release.aab`.
- Artifact size: `136,329,165` bytes (`130.01 MiB`).
- `jarsigner -verify`: passed with exit code `0` and `jar verified`.
- Signing certificate expiry reported by `jarsigner`: `2053-11-05`.

The release-only `IntegrationTestPlugin` stub is intentional. Flutter `3.41.x`
generated a release registrant reference to the development-only integration
test plugin even though Gradle excluded the plugin implementation. The stub
only satisfies that invalid release reference and contains no test behavior.

`jarsigner` also reports that a packaged Reown AppKit warning SVG is signed in
`JarFile` but not in `JarInputStream`. The AAB still verifies successfully. This
is recorded as a non-blocking bundle-tool warning, not treated as a signature
failure.

The earlier failed report was stale after code fixes. Local compile, analyzer,
unit-test, artifact, and signature checks now pass. Phase 6 is still open
because the remaining blockers require real devices, the production website,
or Play Console evidence.

The verifier can run static/build-only checks with `-SkipAnalyze` and
`-SkipTests`, but those switches correctly mark the skipped checks as not
verifiable. The final unified run completed successfully. The direct commands
below remain useful for isolating a future failure:

```powershell
flutter analyze
flutter test
cd android
.\gradlew.bat :app:bundleRelease -Pdart-defines=<base64 production dart-defines>
```

The project remains pinned to Android Gradle Plugin `8.9.1`, Gradle `8.12`, and
Kotlin `2.3.0`. Android's compatibility table associates Kotlin `2.3` with AGP
`8.13.2` and newer R8. Both a full AGP/Gradle upgrade and an isolated R8 override
were tested locally, but each made the release build remain CPU-bound beyond 20
minutes. They were reverted rather than replacing a reproducible signed build
with an unverified toolchain. Resolve this as a controlled Phase 8 dependency
and native-toolchain upgrade before production rollout.

## Production Dart-Defines

The release verifier uses these production values by default:

```powershell
--dart-define=XMO_HOMESERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com
--dart-define=XMO_MATRIX_SERVER_NAME=xmo-matrix.centralindia.cloudapp.azure.com
--dart-define=XMO_WALLET_AUTH_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/wallet
--dart-define=XMO_STREAM_CHUNK_STORAGE=azure
--dart-define=XMO_AZURE_CHUNK_SIGN_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/media/chunks/azure/sign-upload
--dart-define=XMO_ACCOUNT_DELETION_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp
--dart-define=XMO_ACCOUNT_DELETION_WEB_URL=https://xmo.dpdns.org/account-deletion
```

If production hosts change, pass replacements through `-DartDefine`.

## Real-Device Streaming Verification

Run the app with the same production dart-defines, then complete
`docs/streaming_release_verification_checklist.md`.

Minimum required tests:

1. Public channel video opens with direct streaming.
2. Public group video opens with direct streaming.
3. Private encrypted old video still opens through fallback.
4. New large private encrypted video opens through `xmo_stream` when present.
5. Seek forward and backward.
6. Close while loading and verify no stuck transfer.
7. Open PDF/file and confirm normal file flow remains.
8. Repeat on low network and after app restart.

## Manual Play Console Gates

These cannot be proven locally and must be verified in Play Console:

- Developer identity verification approved.
- Contact phone verification approved.
- Play App Signing enabled.
- Version code unused.
- Privacy policy URL live.
- Account deletion URL live.
- Data Safety completed.
- Content rating completed.
- Full-screen intent and foreground-service declarations completed.
- Financial Features declaration completed for wallet connection/donations.
- SDK Index / pre-launch report reviewed.

The production App Links file is currently a blocker:

```text
https://xmo.dpdns.org/.well-known/assetlinks.json -> HTTP 404
```

Publish an `assetlinks.json` entry containing the Google Play **app-signing**
certificate SHA-256 fingerprint. The local upload/sideload certificate may be
added as a second fingerprint, but it cannot replace the Play app-signing
certificate for Play-installed builds.

## Native Library / 16 KB Page-Size Gate

XMO uses native dependencies such as Matrix/Olm, WebRTC, media, Firebase, and
wallet libraries. Before release:

1. Build the signed AAB.
2. Upload to internal testing.
3. Review Play Console native library warnings.
4. Verify no 16 KB page-size warning remains.
5. If Play flags a dependency, upgrade that dependency and rebuild.

Do not claim final Play readiness until this gate is clean.

## Acceptance Gate

Phase 6 is complete only when:

- `tools/verify_play_release.ps1 -BuildAab` completes without blocker failures.
- Streaming real-device checklist passes.
- Play Console account verification is approved.
- Internal testing upload succeeds.
- Play pre-launch report shows no blocker issues.
- Privacy/account deletion URLs are reachable.
- No release artifact uses localhost, emulator IPs, HTTP, test accounts, or
  placeholder configuration.

Current status: **not fully complete**. The local implementation and build gates
pass; the real-device, App Links, Play Console, internal-testing, pre-launch,
and 16 KB native-library gates remain.
