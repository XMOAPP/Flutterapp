# XMO Auth Server

Small Dart backend for XMO email OTP, donation checkout creation, and Matrix
push notification forwarding to Firebase Cloud Messaging.

## Endpoints

- `GET /health`
- `POST /send` or `POST /auth/otp/send`
- `POST /verify` or `POST /auth/otp/verify`
- `POST /donations/create`, `POST /auth/donations/create`, or `POST /auth/otp/donations/create`
- `POST /_matrix/push/v1/notify` for Matrix push gateway delivery
- `POST /push` or `POST /auth/otp/push` for manual/internal tests only

## Environment

```bash
XMO_GMAIL=your-email@gmail.com
XMO_GMAIL_APP_PASSWORD=your-gmail-app-password
XMO_THIRDWEB_SECRET_KEY=your-rotated-thirdweb-secret-key
XMO_DONATION_RECIPIENT_ADDRESS=0x...
XMO_FIREBASE_SERVICE_ACCOUNT_FILE=/run/secrets/firebase-service-account.json
# Or use one of these instead of the file path:
# XMO_FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
# XMO_FIREBASE_SERVICE_ACCOUNT_BASE64=base64-encoded-service-account-json
# Optional if the service account JSON has project_id:
# XMO_FIREBASE_PROJECT_ID=xmoapp-6ef05
PORT=3000
```

The server generates OTPs, emails them, stores them in memory for 5 minutes,
and verifies them server-side.

Donation checkout creation is server-side only because Thirdweb requires a
secret key for `/v1/bridge/payments`. Do not put the Thirdweb secret key in the
Flutter app.

Matrix push forwarding receives Synapse push payloads and sends high-priority
FCM data messages to Android devices. Calls are marked as call pushes, while
messages include text/media/file/audio labels when Synapse provides that event
content. Encrypted messages may only show a generic encrypted-message label
because the server cannot read encrypted content.

Synapse validates HTTP pusher URLs and requires the public path to be exactly
`/_matrix/push/v1/notify`. If this server is behind a reverse proxy, route that
path to the auth server before the normal Synapse catch-all route.
