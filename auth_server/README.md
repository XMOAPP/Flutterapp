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
- `POST /users/upsert`, `POST /auth/users/upsert`, or `POST /auth/otp/users/upsert`
- `POST /users/search`, `POST /auth/users/search`, or `POST /auth/otp/users/search`
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
# Optional; defaults beside XMO_AUTH_DATA_FILE as user_directory.json:
XMO_USER_DIRECTORY_DATA_FILE=/app/data/user_directory.json
XMO_FIREBASE_SERVICE_ACCOUNT_FILE=/run/secrets/firebase-service-account.json
# Or use one of these instead of the file path:
# XMO_FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
# XMO_FIREBASE_SERVICE_ACCOUNT_BASE64=base64-encoded-service-account-json
# Optional if the service account JSON has project_id:
# XMO_FIREBASE_PROJECT_ID=xmoapp-6ef05
PORT=3000
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
