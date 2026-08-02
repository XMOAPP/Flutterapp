# XMO Play Internal Testing and Compliance Runbook

Last updated: 2026-07-21

This runbook covers the remaining work after local release hardening. It does
not replace `play_store_release_remediation_plan.md`; it turns the remaining
release gates into an executable order.

## Current Starting Point

- Deterministic phone-derived passwords are disabled by default.
- Azure chunk upload/download endpoints require Matrix authentication and room
  membership. An authorized end-to-end production test and Azure key rotation
  are still required.
- Account deletion exists in-app and at the public `/account-deletion` route.
- Android backup exclusions are configured.
- Local Flutter/backend quality gates and a signed AAB build have passed.
- Android app label is `XMO`.
- Hosted CI must still prove the exact release commit.
- Play Console identity/contact verification, declarations, internal testing,
  and real-device acceptance remain external gates.

## Stage 0: Finish Developer Account Verification

Owner: Play Console account owner

1. In Play Console, complete **Verify your identity** using an unedited,
   accepted identity document.
2. Wait for approval.
3. Complete **Verify your contact phone number**.
4. Verify the developer email and developer website shown in the account.
5. Save screenshots of the completed verification statuses in the private
   release evidence folder. Do not commit identity documents.

Gate:

- Developer identity and contact verification both show completed.
- Do not create a production rollout while account verification is pending.

## Stage 1: Freeze the Release Candidate

Owner: developer

1. Stop feature work on the release branch.
2. Review the worktree:

   ```powershell
   cd "C:\Users\sangeeth karunakaran\Desktop\xmoapp\xmo"
   git status --short
   git diff --check
   ```

3. Review every changed file. Exclude local logs, generated APK/AAB files,
   keystores, `key.properties`, secrets, and temporary artifacts.
4. Increment `version` in `pubspec.yaml`. The part after `+` is Android's
   `versionCode` and must be greater than every previously uploaded build.
5. Run the complete local gate:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\verify_play_release.ps1 -BuildAab -FullChecks
   ```

6. Confirm the generated report has no blocking result:

   ```text
   build/release_verification/play_release_verification.md
   ```

7. Commit the reviewed release candidate and push it to `main`.

Gate:

- The worktree contains no accidental secret/generated-file changes.
- Local format, analyze, tests, backend checks, and signed AAB build pass.
- The release commit and version code are recorded.

## Stage 2: Prove the Exact Commit in GitHub Actions

Owner: repository administrator

1. Open **GitHub > Actions > Android CI**.
2. Confirm the automatic `main` run passes both:
   - Flutter format, analyze, and test
   - Auth server format, analyze, and test
3. Run **Android CI > Run workflow** with:
   - `run_android_integration = true`
   - `build_release = true`
4. Do not rerun from an unreviewed/newer commit. Record the workflow commit SHA.
5. Confirm these jobs pass:
   - quality
   - backend
   - Android emulator smoke
   - Signed production app bundle
6. Download and retain:
   - `xmo-release-aab`
   - `release-build-logs`
   - `android-integration-logs`
7. Verify the AAB came from the same recorded commit SHA.

Gate:

- All four jobs pass for the exact release commit.
- Retained logs contain no token, SAS URL, email, phone number, or key material.
- The AAB used below is the CI artifact, not an unrelated local build.

## Stage 3: Rotate Azure Credentials and Test Secure Streaming

Owner: Azure/backend administrator

1. Rotate the Azure Storage account key that was previously exposed during
   development.
2. Update only the VPS/backend secret configuration. Never put the account key
   in Flutter, GitHub repository variables, source control, or Play Console.
3. Rebuild/restart `xmo-auth` and verify `/health` reports `azureBlob: ready`.
4. Confirm an unauthenticated signing request returns HTTP 401.
5. From the internal app build, perform an authenticated encrypted large-video
   upload in a private room.
6. From another room member, stream and seek through the video.
7. From a non-member account, verify download authorization is denied.
8. Leave the room and verify a new download authorization is denied.
9. Configure Azure lifecycle deletion for abandoned/unreferenced encrypted
   chunks according to the documented retention period.
10. Review backend logs and confirm bearer tokens and signed URLs are redacted.

Gate:

- Upload, playback, seek, expiry refresh, and Matrix fallback work.
- Non-members cannot obtain upload/download access.
- The old Azure key is invalid and lifecycle cleanup is active.

## Stage 4: Create the Play Console App

Owner: Play Console account owner

1. Select **Create app**.
2. Use:
   - App name: `XMO`
   - Default language: the primary supported store language
   - App type: App
   - Pricing: Free, unless the business decision explicitly changes
3. Enter the public support email and website.
4. Accept the required policy/export declarations and Play App Signing terms.
5. Confirm the package detected from the AAB is `com.xmo.xmo`.
6. Enable Play App Signing. Preserve the existing upload key separately; it is
   not the same as Google's app-signing key.

Gate:

- Package name, app name, support identity, and signing setup are correct.
- Never create a second Play app to work around a package/signing mistake.

## Stage 5: Prepare Store Listing and Public Policy URLs

Owner: product/policy owner

1. Complete the main store listing: short description, full description, app
   icon, feature graphic, phone screenshots, category, support email, and
   website.
2. Publish a privacy policy that:
   - names XMO and the developer identity shown in Play Console;
   - explains Matrix/Synapse and federation;
   - distinguishes private E2EE rooms from public unencrypted rooms;
   - explains Firebase/FCM/Crashlytics, Azure, email OTP, wallet connections,
     donations, contacts, stories, calls, media, diagnostics, and retention;
   - explains account deletion and federated-message retention.
3. Verify the privacy-policy URL is public, HTTPS, mobile readable, and does not
   require login.
4. Verify the external deletion page:

   ```text
   https://xmo.dpdns.org/account-deletion
   ```

5. Submit a test deletion request and confirm the complete operational path,
   including backend records and Matrix deactivation policy.
6. Record the final privacy-policy and deletion URLs used in Play Console.

Gate:

- Both URLs return HTTP 200 without authentication and match actual behavior.
- The deletion request has a documented response/retention process.

## Stage 6: Complete App Content and Compliance Declarations

Owner: product/policy owner with developer review

Complete each Play Console section using the actual app behavior:

1. **Privacy policy**: enter the verified public URL.
2. **Data Safety**: declare every off-device transmission by XMO and included
   SDKs. Cover account/profile data, email/phone, contacts, messages/media,
   calls, device identifiers/push tokens, wallet address/signatures, IP/logs,
   diagnostics, and user-generated content.
3. **Account deletion**: declare both the in-app path and public web URL.
4. **Ads**: declare no ads only if no advertising SDK/behavior exists in the
   uploaded AAB.
5. **App access**: provide stable reviewer credentials and precise steps for
   login, OTP, E2EE chat, calls, wallet connection, and deletion. Never provide
   administrator secrets.
6. **Target audience and content**: choose the actual intended age groups.
7. **Content rating**: answer for messaging, user-generated content, calls,
   wallet connectivity, and donations.
8. **Financial features**: declare external-wallet connection, wallet
   authentication, and donations accurately. XMO must not claim custody if it
   does not store seed phrases/private keys.
9. **Full-screen intent**: declare that the permitted core use is incoming
   voice/video calls. Ensure the app still works with permission denied.
10. **Foreground service**: declare only service types actually present in the
    uploaded manifest and explain their user-visible purpose.
11. Complete country/region availability and any applicable crypto policy
    requirements.

Gate:

- No declaration contradicts the AAB, privacy policy, or server behavior.
- Any Play warning requiring a declaration is resolved before rollout.

## Stage 7: Upload to Internal Testing

Owner: release manager

1. Go to **Test and release > Testing > Internal testing**.
2. Create an email tester list. Internal testing supports up to 100 testers.
3. Add a feedback email or URL.
4. Create a release and upload the CI-produced `app-release.aab`.
5. Confirm Play reports the expected:
   - package `com.xmo.xmo`
   - version name/version code
   - upload certificate
   - target API
   - ABIs
   - permissions
6. Add release notes describing this as a private validation build.
7. Resolve blocking App content/permission alerts.
8. Start rollout to internal testing and share the opt-in link only with the
   approved testers.

Gate:

- Testers install XMO from Google Play, not by sideloading.
- The installed build version matches the release candidate.

## Stage 8: Run the Internal-Test Regression Matrix

Owner: QA/testers

Test on at least Android 13, 14, 15, and 16 where devices are available.

### Account and Authentication

- Register using email OTP.
- Login/logout and session restoration.
- Password reset.
- Wallet login with MetaMask and at least one other supported wallet.
- Delete account in-app.
- Submit deletion through the web page.
- Verify legacy phone-derived password login remains disabled.

### Messaging and E2EE

- XMO-to-XMO private text, photo, video, audio, file, reply, reaction, edit,
  redact, receipt, mention, forward, contact, and pagination.
- XMO-to-Element private message/media compatibility.
- Public group/channel messages are visibly identified as unencrypted.
- New device, unverified device, SSSS/recovery key, cross-signing, key backup,
  reinstall, and restore.

### Media

- Public direct URL streaming.
- Private small encrypted media fallback.
- Private large `xmo_stream` playback, seek, cancel, retry, expired URL refresh,
  cache cleanup, and Azure unavailable fallback.
- Portrait/landscape and 240p/480p/source quality behavior.

### Calls and Notifications

- Incoming audio/video call while foreground, background, swiped away, and
  locked.
- Full-screen intent allowed and denied.
- Answer/decline/open actions.
- Android notification permission denied.
- Normal cellular call active, speaker, Bluetooth/headset, DND, and battery
  saver.
- Encrypted and public message notifications for text and media types.

### Upgrade and Storage

- Upgrade over the previously distributed build without data loss.
- Confirm drafts/settings/session behavior.
- Confirm decrypted media and recovery material are excluded from backup.
- Exercise cache expiry and low-storage behavior.

For every failure record: app version, device/Android version, exact steps,
expected/actual result, redacted logs, and screenshot/video.

Gate:

- No BLOCKER/HIGH failure remains.
- E2EE restore and account deletion have repeatable evidence.
- Calls degrade safely if special permissions are denied.

## Stage 9: Review Play-Generated Reports

Owner: release manager/developer

1. Review the pre-launch report for crashes, ANRs, accessibility, security, and
   compatibility findings.
2. Review **App Bundle Explorer** for delivered permissions, device support,
   per-device download size, and native libraries.
3. Review **SDK Index** warnings.
4. Confirm all required 64-bit ABIs and 16 KB page-size compatibility.
5. Review Android Vitals after testers have exercised the build.
6. Fix findings in a new version code; never replace an already-uploaded
   version code.

Gate:

- No unresolved Play blocker, native compatibility failure, crash, or ANR.

## Stage 10: Closed Test and Production Decision

Owner: release owner

1. For a personal developer account created after 2023-11-13, follow the
   closed-testing requirement shown by Play Console before requesting
   production access. Internal testing alone may not satisfy that requirement.
2. Promote a proven build or upload a higher version-code fix to closed testing.
3. Maintain the required tester count/duration displayed in Play Console.
4. Collect tester feedback and resolve production blockers.
5. Request production access only after every gate in this runbook passes.
6. Use staged production rollout: 5%, 20%, 50%, then 100%, with explicit stop
   thresholds for crashes, ANRs, login, messaging, calls, deletion, and media.
7. Keep the previous compliant release available for rollback.

Final release gate:

- Exact release commit passes local and hosted checks.
- Play internal/closed tests pass.
- Identity and declarations are complete.
- Privacy and deletion URLs are live.
- Azure key rotation and lifecycle cleanup are complete.
- E2EE, calls, notifications, media, wallet, and deletion are proven on the
  Play-installed build.
- Play Console shows no unresolved blocking issue.

## Evidence to Retain Privately

- Release commit SHA and version code.
- GitHub Actions run URL and downloaded artifact checksums.
- AAB signing/upload certificate fingerprints.
- Play release ID and tester list name.
- Completed declaration screenshots.
- Pre-launch, SDK Index, 16 KB, and Android Vitals results.
- Redacted regression test results.
- Azure key-rotation date and lifecycle policy evidence.
- Account-deletion and E2EE recovery acceptance evidence.

Never retain identity documents, keystores, passwords, access tokens, Azure
keys, Matrix tokens, SAS URLs, Firebase service accounts, or recovery keys in
the repository or release evidence bundle.
