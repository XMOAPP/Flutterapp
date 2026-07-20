# Phase 7: Deterministic Quality Gates

## Local Gate

Run from the Flutter project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_quality_gates.ps1
```

This runs non-mutating format checks, analysis, and tests for both Flutter and
`auth_server`. Every command has a fixed timeout. A timeout terminates the
process tree and is recorded as exit code `124`.

The report and redacted logs are written below:

```text
build/quality_gate/quality_gate_report.md
build/quality_gate/*.log
```

Test the timeout runner itself with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\test_quality_gate_common.ps1 -IncludeFlutter
```

## CI Gates

`.github/workflows/android.yml` always runs these jobs on pull requests and
pushes to `main`:

1. Flutter dependency resolution, format check, analysis, and tests.
2. Auth server dependency resolution, format check, analysis, and tests.
3. Log redaction and retained diagnostic artifacts, including failed runs.

Manual workflow dispatch exposes two additional gates:

- `run_android_integration`: starts an Android 35 emulator and runs the chat
  input smoke test after the source and backend gates pass.
- `build_release`: validates signing/configuration inputs, builds the signed
  production AAB, removes temporary signing files, and retains the AAB and
  redacted build logs.

## Production Configuration

The release workflow requires all of these repository variables:

```text
XMO_HOMESERVER_URL
XMO_MATRIX_SERVER_NAME
XMO_WALLET_AUTH_SERVER_URL
XMO_STREAM_CHUNK_STORAGE
XMO_AZURE_CHUNK_SIGN_URL
XMO_ACCOUNT_DELETION_SERVER_URL
XMO_ACCOUNT_DELETION_WEB_URL
```

Signing values remain GitHub secrets and are never retained as artifacts.

## Current Evidence

Local verification on 2026-07-20 passed:

- Flutter format check
- Flutter analysis
- Flutter tests: 154 passed
- Auth server format check
- Auth server analysis
- Auth server tests
- Timeout, redaction, batch-launch, and Flutter-tool launcher self-tests

## Remaining Acceptance

Phase 7 implementation is complete locally. Release acceptance still requires
two consecutive clean hosted CI runs and one successful opt-in emulator smoke
run. Real-device calls, push lifecycle, E2EE interoperability, and media
playback remain separate production verification gates.
