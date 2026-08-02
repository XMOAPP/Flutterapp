# Vodozemac Migration

## Current State

XMO currently uses Matrix Dart and its `olm` API. The application also pins a
local `flutter_olm` package that supplies `libolm.so` on Android. Matrix Dart
uses that API for:

- Olm account and one-to-one sessions
- Megolm group sessions
- room-key sharing and key requests
- device verification and SAS
- cross-signing
- key backup and recovery

Vodozemac is not ABI-compatible with `libolm.so` and does not implement the
Dart `olm` package API. Replacing the native library alone would break E2EE.

## Migration Decision

Use Matrix Rust SDK crypto, backed by vodozemac, behind an XMO-owned adapter.
Do not attempt a binary swap and do not remove the working Matrix Dart crypto
path until the Rust path passes the complete acceptance suite.

The production release gate is:

```powershell
powershell -ExecutionPolicy Bypass -File tools/verify_no_legacy_olm.ps1
```

The gate must pass against the signed release AAB before uploading a
vodozemac-based build to Google Play.

## State Migration Policy

XMO currently has no production users, so the first Rust-crypto build uses a
clean-state migration instead of translating libolm databases:

1. Stop sync and log out the old client.
2. Delete only the old local Matrix/Olm database and crypto cache.
3. Preserve non-credential user preferences where safe.
4. Start the Rust crypto store.
5. Require a fresh login and device verification.
6. Restore historical room keys from key backup or another verified device
   when available.

This policy intentionally does not promise access to locally stored keys that
were never backed up.

## Implementation Stages

### Stage 1: Rust Crypto Adapter

Create an isolated Flutter plugin backed by the official Matrix Rust SDK:

- Android builds use NDK r28 or newer.
- Rust targets are `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
- The adapter owns the Rust crypto store and never exposes private keys to
  Dart.
- Dart receives serializable Matrix requests and decrypted event results only.
- Secrets and decrypted payloads must not be logged.

Required adapter operations:

- open and close a crypto store
- receive sync encryption data
- decrypt room events
- encrypt room events
- publish device keys and one-time keys
- process to-device events
- return outgoing key/query/claim/backup requests
- acknowledge completed outgoing requests
- expose verification, cross-signing, backup, and recovery operations

### Stage 2: Matrix Sync Integration

Integrate the adapter at the Matrix sync boundary:

1. Feed device-list changes, one-time-key counts, to-device events, and room
   encryption events into the Rust crypto machine.
2. Send every outgoing request produced by Rust through the existing
   authenticated Matrix HTTP transport.
3. Acknowledge responses back to Rust.
4. Store only opaque Rust store data outside Dart.
5. Keep encrypted events pending when required keys are unavailable and retry
   after key arrival.

### Stage 3: Message and Media Integration

Route encrypted room messages through the adapter while retaining XMO's
existing Matrix event and media behavior:

- text, replies, edits, reactions, polls, contacts, and stories
- encrypted image, video, audio, voice, and file attachments
- room-key requests and forwarded room keys
- retry after undecryptable events
- encrypted media fallback and streamed-media manifests

### Stage 4: Account Security

Complete and test:

- device verification and SAS
- cross-signing bootstrap and status
- secret storage
- key backup creation, restore, and version changes
- recovery passphrase and recovery key
- verified-device key requests
- logout, account deletion, and device removal

### Stage 5: Controlled Cutover

Use a compile-time engine selection during development:

- `legacy` keeps the current Matrix Dart/Olm path.
- `rust` enables the new adapter.

The flag is temporary and must not create two crypto writers for one account
or database. After the Rust acceptance suite passes:

1. Make `rust` the only release engine.
2. Remove `flutter_olm` and the transitive Dart `olm` runtime path.
3. Regenerate `pubspec.lock`.
4. Build the signed production AAB.
5. Run `tools/verify_no_legacy_olm.ps1`.
6. Confirm Google Play reports 16 KB page-size support.
7. Remove the temporary legacy engine and migration flag.

## Acceptance Suite

The migration is not complete until all of these pass on two physical Android
devices and an Element client:

- new encrypted direct room
- new encrypted group
- decrypt messages sent while offline
- text, reply, edit, reaction, redaction, and mention interoperability
- encrypted image, video, audio, voice, and file attachments
- room-key request from a new device
- SAS verification with XMO and Element
- cross-signing bootstrap and verified-device state
- key backup create, upload, restore, and recovery
- logout and fresh login
- app restart during sync and during key requests
- corrupted or missing crypto-store handling
- no plaintext, access tokens, keys, or recovery material in logs
- signed AAB contains no `libolm.so`
- Play Console reports no 16 KB native-library blocker

## Rollback

Rollback is allowed only during testing and requires clearing the local crypto
store before switching engines. Never open the same crypto store with both
engines and never silently downgrade a production account from Rust crypto to
legacy libolm.

## Completion Status

The migration contract and release gate are implemented. Runtime migration is
not complete until the Rust adapter and Matrix sync integration above are
implemented and pass the acceptance suite.
