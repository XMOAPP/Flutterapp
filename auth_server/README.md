# XMO Auth Server

Small Dart backend for XMO email OTP, donation checkout creation, and Matrix
push notification forwarding to Firebase Cloud Messaging.

## Endpoints

- `GET /health`
- `POST /send`, `POST /auth/otp/send`, `POST /auth/send-otp`, or `POST /auth/resend-otp`
- `POST /verify` or `POST /auth/otp/verify`
- `POST /password/link-email`, `POST /password/reset/start`, and `POST /password/reset/complete`
- `POST /donations/create`, `POST /auth/donations/create`, or `POST /auth/otp/donations/create`
- `POST /wallet/nonce` or `POST /auth/wallet/nonce`
- `POST /wallet/verify` or `POST /auth/wallet/verify`
- `POST /auth/media/chunks/azure/sign-upload` (authenticated encrypted chunk upload signing)
- `GET /auth/media/chunks/azure/download?ref=...` (authenticated short-lived chunk download)
- `POST /users/upsert`, `POST /auth/users/upsert`, or `POST /auth/otp/users/upsert`
- `POST /users/search`, `POST /auth/users/search`, or `POST /auth/otp/users/search`
- `POST /reports/submit`, `POST /auth/reports/submit`, or `POST /auth/otp/reports/submit`
- `POST /reports/review/list` and `POST /reports/review/update` (with the same `/auth` aliases)
- `POST /account/delete-data` (authenticated XMO-owned data cleanup)
- `GET /account-deletion` (external account deletion page)
- `POST /account-deletion/request` and `POST /account-deletion/confirm`
- `POST /invites/create`, `POST /invites/list`, and `POST /invites/revoke` (authenticated room admins)
- `GET /invites/{token}/preview` (public limited preview)
- `POST /invites/{token}/redeem` (authenticated join or join-request redemption)
- `POST /_matrix/push/v1/notify` for Matrix push gateway delivery
- `POST /push` or `POST /auth/otp/push` for manual/internal tests only

## Environment

```bash
EMAIL_PROVIDER=brevo
BREVO_API_KEY=your-brevo-api-key
MAIL_FROM=noreply@xmo.dpdns.org
MAIL_FROM_NAME=XMO
MAIL_REPLY_TO=support@xmo.dpdns.org
EMAIL_USER=xmomessenger@gmail.com
EMAIL_APP_PASSWORD=your-gmail-app-password
XMO_THIRDWEB_SECRET_KEY=your-rotated-thirdweb-secret-key
XMO_DONATION_RECIPIENT_ADDRESS=0x...
XMO_WALLET_AUTH_SECRET=your-random-32-byte-or-longer-wallet-auth-secret
XMO_WALLET_AUTH_DOMAIN=xmo-matrix.centralindia.cloudapp.azure.com
XMO_WALLET_AUTH_URI=https://xmo-matrix.centralindia.cloudapp.azure.com
XMO_HOMESERVER_URL=http://synapse:8008
XMO_MATRIX_SERVER_NAME=xmo-matrix.centralindia.cloudapp.azure.com
XMO_SYNAPSE_ADMIN_TOKEN=your-synapse-admin-access-token
XMO_AUTH_DATA_FILE=/app/data/auth_data.json
# Optional; defaults beside XMO_AUTH_DATA_FILE as reports.json:
XMO_REPORT_DATA_FILE=/app/data/reports.json
# Optional; defaults beside XMO_AUTH_DATA_FILE as user_directory.json:
XMO_USER_DIRECTORY_DATA_FILE=/app/data/user_directory.json
# Recommended in production; generate independently from other secrets:
XMO_CHANNEL_ANALYTICS_SECRET=your-random-32-byte-or-longer-analytics-secret
# Optional; defaults beside XMO_AUTH_DATA_FILE:
XMO_CHANNEL_ANALYTICS_DATA_FILE=/app/data/channel_analytics.json
# Required for branded group/channel invite links. Generate an independent
# 32-byte secret, for example with: openssl rand -hex 32
XMO_INVITE_TOKEN_SECRET=your-random-32-byte-invite-secret
XMO_INVITE_WEB_BASE_URL=https://xmo.dpdns.org
# Optional; defaults beside XMO_AUTH_DATA_FILE:
XMO_INVITE_DATA_FILE=/app/data/invite_links.json
XMO_FIREBASE_SERVICE_ACCOUNT_FILE=/run/secrets/firebase-service-account.json
# Or use one of these instead of the file path:
# XMO_FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
# XMO_FIREBASE_SERVICE_ACCOUNT_BASE64=base64-encoded-service-account-json
# Optional if the service account JSON has project_id:
# XMO_FIREBASE_PROJECT_ID=xmoapp-6ef05
XMO_AZURE_BLOB_ACCOUNT=your-storage-account
XMO_AZURE_BLOB_CONTAINER=your-private-container
XMO_AZURE_BLOB_ACCOUNT_KEY=your-rotated-storage-account-key
# Public HTTPS origin of this backend. Falls back to XMO_WALLET_AUTH_URI.
XMO_PUBLIC_BASE_URL=https://xmo-matrix.centralindia.cloudapp.azure.com
# Optional, defaults shown:
XMO_AZURE_BLOB_UPLOAD_TTL_MINUTES=15
XMO_AZURE_BLOB_DOWNLOAD_TTL_MINUTES=10
XMO_AZURE_BLOB_MAX_CHUNK_BYTES=8388608
PORT=3000
```

Azure chunk signing requires a valid Matrix access token and verifies that the
caller is currently joined to the requested room. The permanent Matrix event
contains a signed opaque backend reference, not an Azure SAS URL. Playback uses
that reference to obtain a short-lived, read-only SAS through the authenticated
download endpoint. Upload SAS values are write-only and short-lived. Keep the
Azure container private, never expose the account key to Flutter, and rotate
the account key after upgrading from the older anonymous signing endpoint.

The reverse proxy must route both Azure paths to this backend:

```caddy
handle /auth/media/* {
    reverse_proxy xmo-auth:3000
}
```

Brevo is the production email provider. `EMAIL_USER` and
`EMAIL_APP_PASSWORD` are only for Gmail SMTP fallback or local development.
Legacy `XMO_GMAIL` and `XMO_GMAIL_APP_PASSWORD` values are still accepted as
fallbacks, but new deployments should use the `EMAIL_*` names. Never put email
credentials or Brevo API keys in the Flutter app.

The server generates OTPs, emails them, stores them in memory for 1 minute,
and verifies them server-side.

Password reset is OTP-backed. After successful app registration, Flutter calls
`/password/link-email` so the backend can attach the verified email to the
Matrix account. Reset then requires the same username and email before sending a
reset code, and `/password/reset/complete` uses the Synapse admin reset-password
API. `XMO_SYNAPSE_ADMIN_TOKEN` must belong to a Synapse admin user and must
never be exposed to Flutter.

User directory search stores only users who publish XMO account visibility from
the app. `/users/upsert` requires the user's Matrix access token and verifies it
with `/account/whoami` before updating the record. `/users/search` is intended
for exact `@username` lookup and only returns records marked public.

Reports are authenticated with the reporting user's Matrix access token. The
report store contains target identifiers, a reason code, optional user-entered
details, and review state; it does not copy decrypted message bodies or media.
Message reports are also forwarded to Matrix's standard event-report endpoint.
Room moderators with power level 50 or higher can review group and channel
reports for their room. A Synapse server admin can review the global queue,
including direct-chat and user reports. Global review uses
`XMO_SYNAPSE_ADMIN_TOKEN` only inside this backend; never expose that token to
Flutter.

Account deletion has two supported paths. The app calls
`/account/delete-data` with the current Matrix access token before using the
Matrix account-deactivation API. The external `/account-deletion` page verifies
the account's linked recovery email with a short-lived code, then uses the
backend-only Synapse admin deactivation endpoint with `erase: true`. Both paths
remove the XMO directory entry, linked recovery email, pending OTP/reset and
wallet challenges, reports associated with the user, and media uploaded to the
local Synapse media repository. Matrix events and media already delivered to
other users, federated servers, or external media repositories cannot be
guaranteed deleted.

The reverse proxy must expose the external page without exposing the Synapse
Admin API:

```caddy
handle /account-deletion* {
    reverse_proxy xmo-auth:3000
}
```

Invite endpoints also accept the `/auth/otp` prefix used by the Flutter app.
Invite previews intentionally omit the internal room ID. Redeeming a public
unencrypted-room invite returns a join action; redeeming an encrypted private
room invite returns a join-request action and does not bypass room approval.

Donation checkout creation is server-side only because Thirdweb requires a
secret key for `/v1/bridge/payments`. Do not put the Thirdweb secret key in the
Flutter app.

Wallet authentication uses WalletConnect/Reown in the Flutter app and verifies
the signed message on this backend. EVM wallets are verified with
`personal_sign`; Solana wallets are verified with `solana_signMessage`.
Bitcoin-only, custodial, or non-WalletConnect wallets are not supported unless
they expose a compatible message-signing method. `XMO_WALLET_AUTH_SECRET` is
used to derive the Matrix account password after signature verification, so it
must be stable across restarts and must never be exposed to Flutter.

Matrix push forwarding receives Synapse push payloads and sends high-priority
FCM data messages to Android devices. Calls are marked as call pushes, while
messages include text/media/file/audio labels when Synapse provides that event
content. Encrypted messages may only show a generic encrypted-message label
because the server cannot read encrypted content.

Synapse validates HTTP pusher URLs and requires the public path to be exactly
`/_matrix/push/v1/notify`. If this server is behind a reverse proxy, route that
path to the auth server before the normal Synapse catch-all route.
