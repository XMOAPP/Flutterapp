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
3. Create recovery key backup, reinstall one device, unlock recovery, and decrypt old encrypted text and attachments.
4. Verify notification navigation for text, media, direct calls, and group calls in foreground, background, recent-apps, and lock-screen states.
5. Answer, decline, leave, and host-end direct and group calls.
6. Exercise group permission changes, transfers, retries, and cancellation.

Android force-stop from Settings intentionally prevents FCM delivery until the user opens the app again.
