# XMO Google Play Release Remediation Plan

Date: 2026-07-15

Status: Implementation plan. This document does not mark XMO release-ready.

## Objective

Resolve the verified production-release blockers without breaking existing Matrix accounts, encrypted rooms, Element compatibility, media fallback, calls, or deployed backend services.

The work is deliberately ordered. Security and data migration phases must complete before release-build optimization or Play Console submission.

For the executable Play Console and internal-testing sequence after local
hardening, use [play_internal_testing_runbook.md](play_internal_testing_runbook.md).

## Release Gate

XMO can be called release-ready only when all of the following are true:

- No deterministic or client-derived account password remains reachable.
- Azure upload/download signing requires an authenticated Matrix user and enforces quotas.
- Account deletion removes Matrix and XMO-owned account data and has a working web request path.
- Matrix credentials, E2EE databases, and decrypted media are protected from Android backup.
- Flutter and backend format, analyze, and test jobs finish successfully within bounded time.
- A current signed AAB passes signing, bundle size, 64-bit, and 16 KB page-size checks.
- E2EE, calls, notifications, media, account deletion, and wallet flows pass real-device tests.
- Play declarations and the privacy policy match actual application behavior.

## Phase 0: Freeze and Reproducible Baseline

Goal: prevent unrelated changes from invalidating remediation evidence.

### Steps

1. Preserve the current four user-modified media files. Do not revert them.
2. Create a dedicated release-hardening branch from the reviewed commit.
3. Record Flutter, Dart, Java, Gradle, AGP, Kotlin, NDK, and bundletool versions in CI output.
4. Require committed `pubspec.lock` files for Flutter and `auth_server`.
5. Add a CI job that fails on an unexpectedly dirty generated release workspace.
6. Create a release evidence directory outside shipped app assets for reports only.
7. Define one canonical production configuration matrix. CI and local release builds must use the same required values.

### Acceptance Gate

- A clean checkout can run `flutter pub get` and backend `dart pub get` using the lockfiles.
- CI prints tool versions and configuration names without printing secret values.
- The release commit and build artifact can be traced to each other.

## Phase 1: Remove Deterministic Phone Credentials

Goal: eliminate the highest-risk account takeover path without locking out existing users.

Affected areas:

- `lib/services/matrix_service.dart`
- `lib/providers/matrix_provider.dart`
- Registration/login screens that invoke phone authentication
- Password reset backend and verified-email records

### 1A. Immediate Containment

1. Add a production-disabled feature gate around `loginOrRegisterWithPhone`.
2. Remove every UI route that can create or log in using `_phoneToPassword` in production builds.
3. Do not merely change the deterministic formula. Any client-derived password remains recoverable.
4. Add a server-side metric for legacy phone-login attempts without logging phone numbers.

### 1B. Existing Account Migration

1. Identify accounts created through the legacy phone flow using local/backend metadata, not by scanning or logging passwords.
2. Require those users to verify their registered email through the existing OTP flow.
3. After OTP verification, rotate the Matrix password through the authenticated reset backend to a user-chosen strong password or a server-generated random credential.
4. Revoke other Matrix sessions when rotation completes, with a clear user confirmation.
5. Delete locally stored legacy phone/password records after successful migration.
6. Provide a recovery route for users whose legacy account has no verified email; this requires a support/manual identity policy.

### 1C. Future Registration Design

1. Keep account creation server-mediated after OTP verification.
2. Prefer a user-chosen password. If an opaque credential is required, generate at least 256 random bits server-side.
3. Never persist a reusable plaintext password in Hive.
4. Use Matrix access/refresh tokens for sessions and store only what the Matrix SDK requires.
5. Rate-limit registration, OTP, password reset, and username enumeration independently.

### Tests

- Unit test that no phone number deterministically maps to a credential.
- Integration test for new registration, existing account login, migration, session revocation, and reset.
- Negative tests for invalid/expired/replayed OTP and mismatched account email.
- Search test ensuring no deterministic credential helper is reachable in release code.

### Acceptance Gate

- `_phoneToPassword` and its production call path are removed.
- Existing test users can migrate and log in again.
- No password value is written to Hive or logs.

## Phase 2: Secure Azure Chunk Signing and Media Authorization

Goal: stop anonymous SAS minting and ensure old media remains playable after a SAS expires.

Affected areas:

- `auth_server/lib/src/handlers/azure_blob_handler.dart`
- `auth_server/bin/server.dart`
- `lib/services/azure_blob_chunk_storage_service.dart`
- `lib/models/xmo_stream_manifest.dart`
- Backend deployment configuration

### 2A. Authenticate Signing Requests

1. Require `Authorization: Bearer <Matrix access token>` on upload and download-signing endpoints.
2. Validate the token against Synapse `/_matrix/client/v3/account/whoami`.
3. Derive user ID from the token. Never accept an owner user ID from the request body.
4. Keep global IP limiting, then add per-user limits and concurrent-upload limits.
5. Enforce maximum file size, chunk size, chunk count, MIME allowlist, and daily/user storage quota.
6. Return generic errors and structured logs containing request IDs, not SAS URLs or tokens.

### 2B. Replace Expiring URLs in Manifests

1. Do not store a 30-day SAS download URL as the permanent `xmo_stream` chunk URL.
2. Store an opaque blob identifier and storage provider in the manifest.
3. Add an authenticated `sign-download` endpoint that returns a short-lived read-only SAS when playback begins.
4. For private rooms, require `room_id` and verify the caller is currently joined before issuing the read SAS.
5. Bind blob ownership metadata to sender, room, event/transaction ID, chunk index, expected size, and ciphertext hash.
6. Make the endpoint idempotent and safe for retries.

### 2C. Secret Management

1. Rotate the Azure account key after the unauthenticated endpoint is removed.
2. Prefer Azure Managed Identity and user-delegation SAS over a long-lived account key when deployment supports it.
3. Keep upload SAS write-only and short-lived. Keep download SAS read-only and short-lived.
4. Add Azure lifecycle rules for abandoned uploads and unreferenced chunks.

### Tests

- Missing, invalid, expired, and wrong-user Matrix token tests.
- Non-member private-room download denial.
- Rate-limit, quota, MIME, size, and chunk-index boundary tests.
- SAS permissions/expiry assertions and log-redaction tests.
- Playback test after the original upload SAS and an earlier download SAS have expired.
- Matrix fallback test when Azure is unavailable.

### Acceptance Gate

- Anonymous `curl` cannot mint a SAS.
- A valid joined user can upload and play media.
- A non-member cannot obtain a private media URL.
- Old events remain playable through fresh signed download URLs.

## Phase 3: Complete Account and Data Deletion

Goal: satisfy Google Play deletion policy and delete all XMO-controlled account data.

Google requires an in-app deletion path and a functional web resource that works without reinstalling the app.

### 3A. Build an Idempotent Backend Deletion Orchestrator

1. Add an authenticated `POST /auth/account/delete` endpoint.
2. Verify the Matrix access token and require password/UIA where Synapse requires it.
3. Mark a deletion job pending before deleting data, so retries are safe.
4. Remove XMO user-directory records.
5. Remove email/OTP/password-reset account mappings and expired challenges.
6. Remove wallet-auth links, push tokens/pushers, donation profile references, and backend device records where present.
7. Remove or schedule deletion of Azure blobs owned solely by that account, subject to room/message retention rules.
8. Deactivate the Matrix account and request message erasure according to the selected option.
9. Clear local Matrix/Hive/cache/secure-storage data only after the server accepts the deletion request.
10. Return a deletion receipt ID and final/pending status without exposing internal identifiers.

### 3B. External Web Deletion Path

1. Add a public `https://xmo.dpdns.org/delete-account` page.
2. Allow a user to submit username and verified email without requiring the app.
3. Verify ownership using a short-lived email OTP.
4. Queue the same backend deletion orchestrator used by the app.
5. Clearly state what is deleted, expected completion time, and what federated servers or other users may retain.
6. Provide a support escalation path and deletion request status.

### 3C. Policy and Retention

1. Define retention for security logs, donation records, abuse records, backups, and federated messages.
2. Document lawful retention exceptions and deletion timelines in the privacy policy.
3. Do not call temporary deactivation complete account deletion.

### Tests

- App deletion, web deletion, retry, partial backend failure, and duplicate request tests.
- Verify directory search, login, reset, push, and wallet login fail after completion.
- Verify local data is removed and no automatic session restore occurs.
- Verify federated-message limitation text is shown before confirmation.

### Acceptance Gate

- Both in-app and web deletion invoke the same verified backend workflow.
- All XMO-owned records have documented deletion or retention behavior.
- The web link is public, stable, and entered in Play Console.

## Phase 4: Protect Local Credentials, Databases, Backups, and Temporary Media

Goal: prevent session, E2EE, and decrypted-media leakage from device storage or backup.

### 4A. Storage Inventory and Migration

1. Catalogue every Hive box, Matrix database, secure-storage key, SQLite database, cache, and external file path.
2. Classify access tokens, refresh tokens, passwords, recovery keys, crypto databases, decrypted media, and push tokens as sensitive.
3. Remove username/password maps from `xmo_auth`; retain only non-secret identifiers when necessary.
4. Store small session secrets in `flutter_secure_storage` backed by Android Keystore.
5. Perform a technical spike on encryption support in the current Matrix `HiveCollectionsDatabase`.
6. If supported, encrypt it with a random database key stored in secure storage. If unsupported, choose a supported encrypted Matrix database before migration.
7. Implement an atomic one-time migration with backup, validation, rollback, and post-success deletion of plaintext storage.

### 4B. Android Backup Rules

1. Add Android 12+ `dataExtractionRules` and pre-Android-12 `fullBackupContent` rules.
2. Exclude Matrix databases, Hive auth/settings containing sensitive state, secure-storage support files, decrypted chunks, media temp files, and recovery exports.
3. Decide explicitly whether harmless preferences may be backed up.
4. Test cloud backup and device-to-device transfer with `adb`/Android backup tooling.

### 4C. Temporary Media

1. Delete decrypted chunks immediately when the final player handle closes.
2. Keep startup/age cleanup as crash recovery, not the primary lifecycle.
3. Store decrypted content only under internal cache, never external files.
4. Ensure cancellation waits for file handles and HTTP responses to close before deletion.
5. Do not include event IDs or original filenames in cache directory names; use random opaque IDs.

### Acceptance Gate

- No reusable password exists in application storage.
- Sensitive stores are encrypted or excluded with an approved risk decision.
- Backup/restore tests prove excluded data does not move to another device.
- Closing playback removes decrypted files reliably.

## Phase 5: Harden Streaming Manifest and Local Range Proxy

Goal: retain chunk streaming while limiting local exposure, malformed-event attacks, and storage abuse.

### 5A. Local Proxy

1. Continue binding only to `127.0.0.1` on an ephemeral port.
2. Replace timestamp/counter paths with at least 128 bits from `Random.secure()`.
3. Validate method, path token, `Host`, range syntax, event/session ownership, and one active session per token.
4. Permit only `GET` and `HEAD`; return deterministic 4xx responses for invalid ranges.
5. Stop the server and close all streams when the player closes or app lifecycle invalidates playback.
6. Fix the failing cleanup test by awaiting client, response, handle, session, and server closure in order.

### 5B. Manifest Validation

1. Reject `http`; accept only `mxc` and `https`.
2. For Azure storage, accept only configured trusted storage hosts or opaque blob IDs.
3. Validate base64/base64url encoding and exact key, IV, and SHA-256 lengths.
4. Enforce version, MIME, quality count, chunk count, per-chunk size, total size, duration, and event-size limits.
5. Require contiguous unique indexes and verify total plaintext/ciphertext size consistency.
6. Reject duplicate URLs, repeated key+IV pairs, unknown required fields, and unsafe future versions.
7. Cap manifest size so multi-quality uploads cannot exceed practical Matrix event limits.
8. Define a version-2 sidecar-manifest design before v1 reaches its size ceiling.

### 5C. Retry and Data Use

1. Keep bounded exponential backoff with jitter.
2. Distinguish retryable network/5xx errors from permanent hash/auth/4xx failures.
3. Deduplicate in-flight chunk downloads by event, quality, and chunk index.
4. Prefetch only a small playback window, not every remaining chunk.
5. Stop prefetch immediately on close, network policy change, or quality switch.

### Acceptance Gate

- Proxy tests pass repeatedly on Windows CI and Android.
- Invalid manifests cannot allocate unbounded memory/storage or access arbitrary hosts.
- Seek, cancel, fallback, cache cleanup, and expired-SAS recovery pass integration tests.

## Phase 6: Android Components, Calls, and Permission Policy

Goal: comply with Android 13-16 behavior and Google Play call-notification policy.

### Current Implementation Status (`2026-07-20`)

Implemented and locally verified:

- `FileProvider` access is restricted to the dedicated `cacheDir/xmo_shared`
  export directory.
- Android 14+ full-screen-intent capability is checked before use, with a
  high-priority call-notification fallback and an explicit settings route.
- Unused foreground-service permissions were removed; camera and microphone
  hardware declarations are optional.
- Call and wallet deep-link inputs are allowlisted and covered by focused tests.
- The unified release verifier passes full Flutter analysis, all `147` Flutter
  tests, and the signed production AAB build with no automated blocking
  `FAIL`/`NOT VERIFIABLE` result. `jarsigner` also verifies the AAB successfully.

Still required before this phase can pass:

- Publish and verify `https://xmo.dpdns.org/.well-known/assetlinks.json`; it
  currently returns HTTP `404`.
- Run the Android 13-16 real-device call/notification matrix below.
- Upload the AAB to Play internal testing and review Play App Signing,
  pre-launch, SDK Index, permission, full-screen-intent, foreground-service,
  and 16 KB native-library results.
- Complete developer identity/contact verification and the applicable Play
  declarations.

### Steps

1. Inspect the generated release merged manifest and attribute every permission/component to source or dependency.
2. Narrow `FileProvider` paths to dedicated share/export directories instead of full cache/files roots.
3. Add `NotificationManager.canUseFullScreenIntent()` handling on Android 14+.
4. When unavailable, show a high-priority heads-up call notification and provide a settings route only after user explanation.
5. Keep answer, decline, and open `PendingIntent` mutability explicit and validate every identifier.
6. Verify camera/microphone foreground-service types, start timing, ongoing notification, and stop behavior.
7. Remove foreground-service permissions if no corresponding service is shipped.
8. Verify notification permission onboarding on Android 13+.
9. Validate `xmo://wallet`, `xmo://call`, and HTTPS call links; reject unexpected hosts, paths, IDs, and parameters.
10. Publish and verify `assetlinks.json` for the HTTPS domain.
11. Complete Play Console full-screen-intent and foreground-service declarations.

### Device Matrix

- Android 13, 14, 15, and 16.
- Foreground, background, recent apps, swiped away, locked screen, and permission denied.
- Normal phone call active, Bluetooth/wired/headset routes, Do Not Disturb, battery saver.

### Acceptance Gate

- Calls degrade safely when full-screen permission is unavailable.
- No undeclared or unjustified foreground service remains.
- Deep links and notification actions cannot open the wrong room/call.

## Phase 7: Restore Deterministic Quality Gates

Goal: make CI results authoritative before producing another release artifact.

### Steps

1. Apply formatting to `transfer_controller.dart` in a dedicated reviewed change.
2. Reproduce the Flutter analyzer hang with verbose/timeline output and a fixed timeout.
3. Analyze directories/files in batches to isolate the responsible source or analyzer/plugin.
4. Update analyzer/lints only after checking compatibility with the current Dart SDK.
5. Fix the local playback proxy cleanup test and run it repeatedly to detect flakiness.
6. Reproduce backend analyze/test hangs inside and outside Docker; inspect package resolution and generated snapshots.
7. Add explicit timeouts to CI so hangs fail with diagnostics.
8. Run backend tests in GitHub Actions; the current workflow only formats/analyzes backend code.
9. Add Android integration tests for auth, deletion, notifications, calls, permissions, media and E2EE setup.
10. Upload machine-readable test reports and logs with token/PII redaction.

### Acceptance Gate

- Format checks, Flutter analyze/test, backend analyze/test, and selected integration tests finish and pass in two consecutive clean CI runs.
- No analyzer/test process requires manual termination.

### Implementation Status - 2026-07-20

Implemented locally:

- Flutter and Java versions are pinned in Android CI.
- Flutter format, analyze, and test gates are bounded and always run for pushes and pull requests.
- Auth server format, analyze, and test gates are bounded and always run.
- Timeout failures terminate the process tree and return exit code `124`.
- Retained CI logs are redacted before artifact upload.
- Android emulator smoke and signed production AAB jobs are explicit workflow-dispatch gates.
- The Windows runner invokes Flutter tools directly through the bundled Dart SDK so timeout ownership is deterministic.
- Local timeout/redaction/launcher self-tests pass.
- The complete local gate passes all six checks; report: `build/quality_gate/quality_gate_report.md`.

External acceptance still required:

1. Run the GitHub Actions quality and backend jobs successfully on two consecutive clean commits/runs.
2. Run the opt-in Android emulator smoke job and retain its redacted logs.
3. Keep calls, push lifecycle, E2EE interoperability, and real media playback in the real-device release checklist; one emulator smoke test cannot validate those systems.

## Phase 8: Dependency and Native SDK Hardening

Goal: reduce maintenance and Play SDK/native compatibility risk without a destabilizing bulk upgrade.

### Steps

1. Use Play SDK Index in Play Console for all Android SDKs; this cannot be proven from `pub outdated` alone.
2. Remove or upgrade the discontinued transitive `js` dependency through its owning package.
3. Upgrade patch/minor Firebase, camera, notifications, WebRTC, audio, and path-provider packages in separate batches.
4. Treat Matrix `0.25.13` to `8.x` as a dedicated migration project, not a routine dependency bump.
5. Treat `file_picker`, `local_auth`, `record`, secure storage, and other major upgrades independently with platform tests.
6. Generate an SBOM and run a recognized dependency vulnerability scanner in CI.
7. For every native upgrade, rerun ABI, 16 KB, permissions, startup, media, calls, and wallet tests.

### Acceptance Gate

- No discontinued direct/transitive dependency remains without a documented exception.
- Play SDK Index shows no blocking SDK issue.
- Dependency updates do not regress Matrix compatibility or native builds.

## Phase 9: E2EE Production Evidence
f
Goal: validate claims rather than changing Matrix encryption semantics late in the release.

### Steps

1. Keep public rooms explicitly unencrypted and private-room type immutable after creation.
2. Test encrypted text, image, video, audio, file, reaction, reply, edit, redact, and pagination between two XMO devices.
3. Repeat private-room tests between XMO and current Element Android/Desktop.
4. Test SSSS setup, generated recovery key, passphrase path if supported, cross-signing, key backup, reinstall restore, and verified-device key requests.
5. Test unverified/new-device behavior and withheld keys.
6. Verify old Matrix fallback media remains accessible when `xmo_stream` is ignored or fails.
7. Record device versions, account IDs in redacted form, event IDs in redacted form, expected result, actual result, and screenshots/log bundles.
8. Do not use "production E2EE" marketing until every mandatory scenario passes.

### Acceptance Gate

- The approved E2EE checklist has repeatable XMO-XMO and XMO-Element evidence.
- Recovery after reinstall works without relying on the old device's local cache.

## Phase 10: Production Configuration and Signed AAB

Goal: produce one traceable artifact that cannot silently use development configuration.

### Steps

1. Add startup/build validation for every required production value.
2. Production builds must fail for localhost, emulator IPs, HTTP URLs, empty required URLs, and placeholder IDs.
3. Pass all production values explicitly in GitHub Actions, even when a production-looking source default exists.
4. Keep public client identifiers separate from secrets; restrict Firebase/Reown/Thirdweb identifiers in their provider consoles.
5. Validate signing secrets without printing them and securely delete temporary keystore files after the job.
6. Increment version code and confirm it is unused in Play Console.
7. Build `flutter build appbundle --release` from the exact reviewed commit.
8. Verify AAB signing and record certificate fingerprints without exposing key material.
9. Use bundletool to inspect manifest, delivered permissions, modules, ABIs, and per-device compressed size.
10. Test every packaged `.so` for 16 KB ELF alignment and generated APK ZIP alignment.
11. Report largest assets. Optimize large GIFs/audio and remove debug/native symbols from delivered modules when safe.
12. Enable R8/resource shrinking only in a separate experiment, add required keep rules, and prove wallet, Firebase, Matrix, WebRTC, notifications and method channels in an internal build.

### Acceptance Gate

- Current AAB is signed, traceable, API compliant, 64-bit, 16 KB compatible, and installable through Play internal testing.
- Per-device download size is measured, not inferred from the universal APK.

## Phase 11: Privacy, Data Safety, and Financial Declarations

Goal: align policy documents and Play declarations with actual code and infrastructure.

### Steps

1. Finalize a data inventory for Matrix/Synapse, federation, Firebase Auth/FCM/Crashlytics, Azure, Brevo/Gmail, Reown, Thirdweb, wallet addresses, donations, contacts, stories, calls, media, IPs and diagnostics.
2. Decide Play "collected" and "shared" answers using Google definitions, including user-directed Matrix federation.
3. Document purpose, required/optional status, retention, encryption in transit, E2EE scope, and deletion behavior for every data type.
4. Update the public privacy policy to name XMO and every relevant processor/service.
5. State clearly that public rooms are not E2EE and that federated copies may remain after deletion.
6. Complete Financial Features accurately. XMO connects to external wallets and supports donations; it does not collect seed phrases/private keys.
7. Verify whether donations provide any digital entitlement. If they do, obtain policy/legal review for Play Billing.
8. Complete ads, app access, audience, content rating, full-screen intent, foreground service, country and crypto declarations.

### Acceptance Gate

- Privacy policy, Data Safety, account deletion, financial declarations, and app behavior are consistent.
- Public URLs are accessible, non-geofenced, and stable.

## Phase 12: Internal Testing, Rollout, and Monitoring

Goal: catch production-only failures before broad distribution.

### Steps

1. Upload only the Phase 10 AAB to Play internal testing.
2. Run the complete device regression matrix for auth, deletion, E2EE, media, calls, push, permissions, wallet and upgrades.
3. Review Play pre-launch report, SDK warnings, policy declarations and Android Vitals.
4. Verify Crashlytics initializes before release-critical asynchronous work and does not collect in debug builds.
5. Redact tokens, SAS URLs, room/event IDs, emails, phone numbers and stack traces from routine production logs.
6. Begin closed testing with a small controlled cohort.
7. Use staged production rollout: 5%, 20%, 50%, then 100%, with explicit crash/ANR/login/message/call thresholds.
8. Maintain rollback instructions and keep the previous compliant AAB available in Play Console.

### Final Go/No-Go Gate

Release only when:

- All BLOCKER and HIGH findings are closed with evidence.
- Two consecutive CI runs pass from clean checkouts.
- Play internal/closed tests show no blocker regression.
- Account deletion and privacy URLs are live.
- E2EE evidence is approved.
- Play Console reports no unresolved policy, SDK, signing, permission or pre-launch issue.

## Recommended Pull Request Order

1. Disable deterministic phone auth.
2. Authenticate/redesign Azure signing and rotate credentials.
3. Add complete backend/web account deletion.
4. Remove plaintext credentials and add encrypted storage/backup exclusions.
5. Harden proxy, manifest, cache lifecycle, and fix its tests.
6. Correct Android call/permission/deep-link/FileProvider behavior.
7. Fix analyzer/backend hangs and enforce CI quality gates.
8. Upgrade dependencies in controlled batches.
9. Complete E2EE evidence and compatibility testing.
10. Harden production configuration and generate the signed AAB.
11. Complete privacy/Play declarations.
12. Internal test and staged rollout.

Do not combine these into one large pull request. Each security-sensitive PR needs focused tests, a migration/rollback note, and independent review.

## Official References

- Google Play account deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- Google Play Data Safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Full-screen intent and foreground services: https://support.google.com/googleplay/android-developer/answer/13392821
- Android backup security: https://developer.android.com/privacy-and-security/risks/backup-best-practices
- Android 16 KB page sizes: https://developer.android.com/guide/practices/page-sizes
- R8 and resource shrinking: https://developer.android.com/topic/performance/app-optimization/enable-app-optimization
- Target API requirements: https://support.google.com/googleplay/android-developer/answer/11926878
