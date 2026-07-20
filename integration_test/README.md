# Android integration testing

Run the deterministic Android smoke test on an emulator or a connected phone:

```powershell
flutter test integration_test/chat_input_smoke_test.dart -d <device-id> `
  --dart-define=XMO_HOMESERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com `
  --dart-define=XMO_MATRIX_SERVER_NAME=xmo-matrix.centralindia.cloudapp.azure.com
```

The smoke test deliberately avoids a real Matrix account. Run this manual release checklist on two Android devices before each beta:

1. Login, register, and wallet authentication.
2. Logout and confirm account-scoped cache data is not shown for the next account.
3. Complete the Phase 3 E2EE evidence checklist in `docs/e2ee_verification_checklist.md`.
4. Verify notification navigation for text, media, direct calls, and group calls in foreground, background, recent-apps, and lock-screen states.
5. Answer, decline, leave, and host-end direct and group calls.
6. Exercise group permission changes, transfers, retries, and cancellation.

Android force-stop from Settings intentionally prevents FCM delivery until the user opens the app again.

## Real Matrix account smoke

Run this only against a disposable Matrix account:

```powershell
flutter test integration_test/real_matrix_auth_e2ee_test.dart -d <device-id> `
  --dart-define=XMO_HOMESERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com `
  --dart-define=XMO_MATRIX_SERVER_NAME=xmo-matrix.centralindia.cloudapp.azure.com `
  --dart-define=XMO_TEST_USERNAME=<matrix-username> `
  --dart-define=XMO_TEST_PASSWORD=<matrix-password> `
  --dart-define=XMO_TEST_REQUIRE_E2EE=true
```

If `XMO_TEST_USERNAME` or `XMO_TEST_PASSWORD` is missing, the test skips itself so CI can keep running the deterministic widget integration test without secrets.

## GitHub Actions gate

The `Android CI` workflow always runs bounded Flutter and auth-server format,
analysis, and test gates. To run the Android emulator smoke test, open the
workflow in GitHub Actions, select **Run workflow**, and enable
`run_android_integration`. The emulator gate is deliberately opt-in because it
is slower than the deterministic host tests.

The emulator job runs only `chat_input_smoke_test.dart`; it does not claim to
verify live Matrix, E2EE interoperability, calls, FCM delivery, or locked-screen
behavior. Run the disposable-account and real-device checklists above before a
beta release.
