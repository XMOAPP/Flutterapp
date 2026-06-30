# Phase 3 E2EE Verification Checklist

Do not mark XMO E2EE as production-ready until every blocking scenario below has a dated PASS result with evidence.

## Test Matrix

Required clients:
- XMO Android device A, fresh install or clean logged-in state.
- XMO Android device B, separate physical device or emulator.
- Element client, Android or desktop, logged into an account on the same homeserver.

Record before testing:
- Date:
- Homeserver URL:
- XMO commit/build:
- Device A user ID/device ID:
- Device B user ID/device ID:
- Element user ID/device ID/version:

## Blocking Scenarios

### 1. XMO to XMO encrypted text

Steps:
1. Device A creates a private encrypted direct room with Device B.
2. Confirm the room has an `m.room.encryption` state event before test messages.
3. A sends text to B.
4. B replies with text to A.
5. Restart both apps and reopen the room.

PASS evidence:
- Room ID:
- A to B event ID:
- B to A event ID:
- Screenshot/log showing both messages decrypted on both devices after restart.

### 2. XMO to XMO encrypted media

Steps:
1. In the same encrypted room, send image, video, audio, and file from A to B.
2. Send at least one image or file from B to A.
3. Preview, open, and download every attachment on the opposite device.
4. Inspect event content for encrypted media structure.

PASS evidence:
- Event IDs for each media type.
- Event content contains `file` or `thumbnail_file` for encrypted attachments.
- Event content does not expose plaintext Matrix media URL as the only media pointer.
- Screenshot/log showing each attachment decrypts and opens.

### 3. XMO to Element encrypted text and media

Steps:
1. Create or join an encrypted room containing XMO device A and Element.
2. Confirm encryption is enabled before new test messages.
3. XMO sends text and media to Element.
4. Element sends text and media to XMO.
5. Restart XMO and Element, then reopen the room.

PASS evidence:
- Element app/version/platform:
- Room ID:
- Event IDs for XMO text/media and Element text/media.
- Screenshot/log showing both clients decrypt all events after restart.

### 4. Recovery setup and key backup

Steps:
1. On XMO device A, open Settings > Security.
2. Run Set up recovery and key backup.
3. Store the displayed recovery key or passphrase.
4. Reload the Security screen.

PASS evidence:
- Recovery setup completed without error.
- Cross-signing shows Ready.
- Key backup shows Ready.
- Recovery key ID is present.

### 5. Backup restore after reinstall

Steps:
1. Ensure encrypted text and media exist before reinstall.
2. Uninstall XMO or clear app data on device B.
3. Reinstall, log in, and unlock recovery with the saved key/passphrase.
4. Open the encrypted room from before reinstall.
5. Decrypt old text and media without resending them.

PASS evidence:
- Old text event ID decrypted:
- Old media event ID decrypted:
- Recovery unlock completed after reinstall:
- Screenshot/log showing old content visible after restore.

### 6. Cross-signing reliability

Steps:
1. Verify/trust device B from device A or complete the app-supported verification path.
2. Restart both apps.
3. Confirm verified/trusted state persists.
4. Send new encrypted text and media.

PASS evidence:
- Before/after trust state for device A and B.
- No unexpected unverified-device warning for the verified session.
- New encrypted events decrypt on both devices.

### 7. Verified-device key requests

Steps:
1. Create a missing-key condition on device B by logging in after encrypted history already exists.
2. Keep device A online and verified.
3. On B, use Request keys from verified devices.
4. Reopen the previously undecryptable event.

PASS evidence:
- Event ID that was undecryptable before request:
- Request action timestamp:
- Event decrypts after request without rejoin or resend.

## Release Decision

Production E2EE can be claimed only when:
- All seven blocking scenarios above have PASS evidence.
- Evidence includes room IDs, event IDs, device IDs, and screenshots or logs.
- Failures are fixed and re-tested from a clean install where relevant.

Until then, describe the feature as implemented but still under verification.
