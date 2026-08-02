# XMO Invite Link Deployment

XMO invite links use this canonical form:

```text
https://xmo.dpdns.org/join/<opaque-token>
```

The installed Android app handles the HTTPS link. Browsers use a Netlify page
that shows a limited invite preview and offers **Open XMO** or **Download XMO**.
The user must confirm in XMO before joining or requesting access.

The current verified-link integration is Android-only. On iOS, desktop, and
other unsupported platforms, the same URL remains usable as a browser preview
and download page, but it does not join a room outside XMO. iOS Universal Links
require a separate Associated Domains and `apple-app-site-association`
deployment before they can be claimed as supported.

## 1. Backend configuration

Generate a dedicated secret on the VPS:

```bash
openssl rand -hex 32
```

Add these values to `/opt/xmo/auth.env` without committing the secret:

```text
XMO_INVITE_TOKEN_SECRET=<generated-value>
XMO_INVITE_WEB_BASE_URL=https://xmo.dpdns.org
XMO_INVITE_DATA_FILE=/app/data/invite_links.json
```

The existing `/opt/xmo/auth_data:/app/data` volume persists invite records.
Deploy these changed backend files together. Deploying only the invite handler
omits routing, health reporting, normalized rate limiting, and token-safe
request logging:

```text
auth_server/bin/server.dart
auth_server/lib/src/endpoint_modules.dart
auth_server/lib/src/health_status.dart
auth_server/lib/src/request_guard.dart
auth_server/lib/src/structured_logger.dart
auth_server/lib/src/handlers/invite_handler.dart
auth_server/lib/src/handlers/account_deletion_handler.dart
```

Then rebuild and restart:

```bash
cd /opt/xmo
docker compose build --no-cache xmo-auth
docker compose up -d xmo-auth
docker compose logs --tail=80 xmo-auth
curl -s https://xmo-matrix.centralindia.cloudapp.azure.com/health
```

The health response must include `inviteLinks: ready`. The current Caddy
`handle_path /auth/otp/*` route already exposes the invite endpoints.

Confirm the public preview route reaches XMO Auth without revealing a valid
token in terminal history:

```bash
curl -i https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp/invites/invalid-token/preview
```

An unavailable/invalid response from XMO Auth is expected. A Synapse HTML 404
means the Caddy route is wrong. Do not use a valid production invite for this
route check.

## 2. Prepare the Netlify files

In Google Play Console, open **Setup > App integrity > App signing key
certificate** and copy its SHA-256 fingerprint. Use the Google Play
app-signing certificate, not the upload certificate.

From the project root, generate a deployable bundle:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\prepare_netlify_invite.ps1 `
  -PlaySigningSha256 "AA:BB:...:FF"
```

The script validates the colon-separated fingerprint, writes the production
`.well-known/assetlinks.json`, and refuses to leave the placeholder in the
output. The generated files are placed in:

```text
build/netlify-invite
```

Merge the contents of that generated directory into the source directory of
the existing `xmo.dpdns.org` Netlify site. Do not replace unrelated site files
and do not deploy `.well-known/assetlinks.json.template` directly.

Deploy the site, then verify:

```text
https://xmo.dpdns.org/.well-known/assetlinks.json
https://xmo.dpdns.org/join/invalid-token
```

The first URL must return JSON with HTTP 200, content type `application/json`,
and no redirect. It must contain `com.xmo.xmo` and the Play app-signing
fingerprint, with no placeholder. The second URL should render the XMO
invalid-invite state.

## 3. Flutter production configuration

Include these values in release builds and CI:

```text
--dart-define=XMO_INVITE_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp
--dart-define=XMO_INVITE_WEB_BASE_URL=https://xmo.dpdns.org
```

In GitHub, open **Settings > Secrets and variables > Actions > Variables** and
create these repository variables:

```text
XMO_INVITE_SERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp
XMO_INVITE_WEB_BASE_URL=https://xmo.dpdns.org
```

The Android release workflow rejects a release build when either variable is
missing. These are public application endpoints, not secrets.

Rebuild and reinstall the app after the Android manifest change.

## 4. Verification

After installing a build signed with the certificate declared in
`assetlinks.json`, run:

```bash
adb shell pm verify-app-links --re-verify com.xmo.xmo
adb shell pm get-app-links com.xmo.xmo
adb shell am start -a android.intent.action.VIEW -d "https://xmo.dpdns.org/join/<valid-token>"
```

Verify all of these cases:

1. Installed app: the HTTPS link opens XMO directly and shows preview first.
2. App absent: the link opens the Netlify preview and APK download works.
3. Public group/channel: confirm joins, then opens the conversation.
4. Private group/channel: confirm sends a join request; it does not bypass approval.
5. Revoked, expired, exhausted, or malformed links show an unavailable state.
6. Resetting a link disables the old token and creates a different token.
7. Non-admin users cannot create, reset, or disable invite links.
8. Legacy `matrix.to` and `xmo://join` room links still open through the compatibility path.
9. Cold start: force-stop XMO, open the HTTPS link, and verify one preview is shown.
10. Warm start: leave XMO in the background, open the link, and verify the link is not lost.
11. Signed out: open the link, log in, and verify the same preview resumes once.
12. Open the same link repeatedly and verify no duplicate join or knock is sent.
13. Private invite browser previews show room type/name/count only and do not expose the topic.

The App Link test is not complete with a debug certificate unless that debug
fingerprint is also published. Production acceptance must use an internal-test
build signed through Google Play and the Play app-signing fingerprint deployed
in `assetlinks.json`.

## 5. Platform and security boundaries

- The browser page never joins a room. It provides a limited preview and opens
  or downloads XMO.
- The raw token is a bearer capability. Do not paste valid production tokens
  into tickets, logs, analytics, or screenshots.
- Public, unencrypted rooms use their existing direct-join policy.
- Private, encrypted rooms use the existing request-to-join flow. An invite
  link never disables encryption or grants posting power.
- Revocation, expiry, and usage limits are checked by the XMO backend before
  the app attempts membership.
- The current JSON repository is suitable for limited beta traffic only.
  Migrate invite records to PostgreSQL before multi-instance or high-volume
  deployment so final-use redemption can be transactional across processes.
