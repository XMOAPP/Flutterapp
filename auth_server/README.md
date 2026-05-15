# XMO Auth Server

Small Dart backend for XMO email OTP.

## Endpoints

- `GET /health`
- `POST /send` or `POST /auth/otp/send`
- `POST /verify` or `POST /auth/otp/verify`

## Environment

```bash
XMO_GMAIL=your-email@gmail.com
XMO_GMAIL_APP_PASSWORD=your-gmail-app-password
PORT=3000
```

The server generates OTPs, emails them, stores them in memory for 5 minutes,
and verifies them server-side.
