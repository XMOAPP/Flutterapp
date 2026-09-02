# XMO - Flutter Messaging App

A modern Flutter messaging application with Matrix backend integration, wallet authentication, and OTP verification.

## 🎯 Features

- **Matrix-based Messaging** - Real-time chat using Matrix protocol
- **Direct Messaging** - One-on-one conversations
- **Group Chats** - Multi-user rooms
- **Wallet Authentication** - Login with MetaMask, Brave Wallet, Coinbase Wallet
- **Email OTP Verification** - Secure phone-based registration
- **User Search** - Find and message other users
- **Real-time Sync** - Instant message delivery and updates

## 📋 Prerequisites

Before you begin, ensure you have the following installed:

- **Flutter** (3.0.0 or higher) - [Install Flutter](https://flutter.dev/docs/get-started/install)
- **Dart** (included with Flutter)
- **Docker** - [Install Docker](https://docs.docker.com/get-docker/)
- **Git**
- **Node.js** (for email server) - [Install Node.js](https://nodejs.org/)

### Verify Installation

```bash
flutter --version
dart --version
docker --version
node --version
```

## 🚀 Quick Start

### Step 1: Clone the Repository

```bash
git clone https://github.com/XMOAPP/Flutterapp.git
cd Flutterapp/xmo
```

### Step 2: Install Flutter Dependencies

```bash
flutter pub get
```

### Step 3: Set Up Matrix Backend (Synapse)

The app requires a local Matrix homeserver. Follow these steps:

#### 3a. Create Matrix Backend Directory

```bash
# Go to your home directory
cd ~

# Create backend folder
mkdir matrix-backend
cd matrix-backend
mkdir synapse-data
```

#### 3b. Generate Synapse Configuration

**macOS / Linux:**
```bash
docker run -it --rm \
  -v $(pwd)/synapse-data:/data \
  -e SYNAPSE_SERVER_NAME=localhost \
  -e SYNAPSE_REPORT_STATS=no \
  matrixdotorg/synapse:latest generate
```

**Windows (PowerShell):**
```powershell
docker run -it --rm `
  -v ${PWD}/synapse-data:/data `
  -e SYNAPSE_SERVER_NAME=localhost `
  -e SYNAPSE_REPORT_STATS=no `
  matrixdotorg/synapse:latest generate
```

#### 3c. Configure homeserver.yaml

Edit `~/matrix-backend/synapse-data/homeserver.yaml`:

Find and update these settings:

```yaml
server_name: "localhost"
enable_registration: true
enable_registration_without_verification: true
```

#### 3d. Start Synapse Server

**macOS / Linux:**
```bash
cd ~/matrix-backend
docker run -d \
  --name synapse \
  -v $(pwd)/synapse-data:/data \
  -p 8008:8008 \
  matrixdotorg/synapse:latest
```

**Windows (PowerShell):**
```powershell
cd ~/matrix-backend
docker run -d `
  --name synapse `
  -v ${PWD}/synapse-data:/data `
  -p 8008:8008 `
  matrixdotorg/synapse:latest
```

#### 3e. Verify Synapse is Running

```bash
# Check container status
docker ps

# Test the server
curl http://localhost:8008/_matrix/client/versions
```

You should see a JSON response with Matrix spec versions.

#### 3f. Create Test Users

```bash
# Create admin user
docker exec -it synapse register_new_matrix_user \
  http://localhost:8008 \
  -c /data/homeserver.yaml \
  -u admin \
  -p admin123 \
  --admin

# Create test user 1
docker exec -it synapse register_new_matrix_user \
  http://localhost:8008 \
  -c /data/homeserver.yaml \
  -u alice \
  -p alice123 \
  --no-admin

# Create test user 2
docker exec -it synapse register_new_matrix_user \
  http://localhost:8008 \
  -c /data/homeserver.yaml \
  -u bob \
  -p bob123 \
  --no-admin
```

### Step 4: Set Up Email Server (Optional - for OTP)

The email server sends OTP codes via Gmail. To enable it:

#### 4a. Get Gmail App Password

1. Go to [Google Account Security](https://myaccount.google.com/security)
2. Enable 2-Factor Authentication
3. Generate an App Password for "Mail"
4. Copy the 16-character password

#### 4b. Configure Email Server

Edit `xmo/email_server.dart`:

```dart
const String myGmail = 'your-email@gmail.com';
const String myAppPassword = 'your-16-char-app-password';
```

#### 4c. Run Email Server

```bash
cd xmo
dart email_server.dart
```

The server will start on `http://localhost:3000`

### Step 5: Run the Flutter App

#### For Web (Chrome)

```bash
flutter run -d chrome
```

#### For Android Emulator

```bash
# First, start Android emulator
flutter emulators --launch <emulator-name>

# Then run the app
flutter run
```

#### For iOS Simulator

```bash
flutter run -d ios
```

### Step 6: Test the App

1. **Create Account:**
   - Choose authentication method (Email OTP or Wallet)
   - For Email: Enter phone number, verify OTP
   - For Wallet: Connect MetaMask/Brave/Coinbase wallet

2. **Search Users:**
   - Tap the green chat button
   - Search for another user (e.g., "alice", "bob")
   - Tap to start chatting

3. **Send Messages:**
   - Type a message
   - Tap send button
   - Message appears in real-time

## 🔧 Configuration

### Matrix Server URL

The app connects to `http://localhost:8008` by default.

To change it, edit `lib/services/matrix_service.dart`:

```dart
static const String homeserverUrl = 'http://localhost:8008';
```

### Android Cleartext Traffic

For Android, HTTP traffic is allowed locally. Edit `android/app/src/main/AndroidManifest.xml`:

```xml
<application
  android:usesCleartextTraffic="true"
  ...
>
```

**Remove this for production with HTTPS!**

## 📁 Project Structure

```
xmo/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── theme.dart                # UI theme
│   ├── providers/
│   │   ├── matrix_provider.dart  # Matrix state management
│   │   └── chat_filter_provider.dart
│   ├── services/
│   │   ├── matrix_service.dart   # Matrix SDK wrapper
│   │   ├── otp_service.dart      # OTP handling
│   │   └── wallet_service.dart   # Wallet auth
│   ├── screens/
│   │   ├── splash_screen.dart
│   │   ├── login_screen.dart
│   │   ├── auth_choice_screen.dart
│   │   ├── otp_screen.dart
│   │   ├── wallet_auth_screen.dart
│   │   ├── home_screen.dart
│   │   ├── user_search_screen.dart
│   │   ├── matrix_chat_screen.dart
│   │   └── ...
│   └── widgets/
│       ├── avatar_widget.dart
│       └── chat_tile.dart
├── android/                      # Android native code
├── ios/                          # iOS native code
├── web/                          # Web assets
├── pubspec.yaml                  # Dependencies
├── email_server.dart             # Email OTP server
└── README.md                     # This file
```

## 🐛 Troubleshooting

### "Connection refused" Error

**Problem:** App can't connect to Matrix server

**Solution:**
```bash
# Check if Synapse is running
docker ps

# If not running, start it
docker start synapse

# Check logs
docker logs synapse
```

### "Registration is disabled" Error

**Problem:** Can't create new accounts

**Solution:**
Edit `~/matrix-backend/synapse-data/homeserver.yaml`:
```yaml
enable_registration: true
enable_registration_without_verification: true
```

Then restart Synapse:
```bash
docker restart synapse
```

### "No users found" in Search

**Problem:** User search returns no results

**Solution:**
The app automatically tries direct Matrix ID lookup. Try:
- Search for exact username: `alice`
- Or full Matrix ID: `@alice:localhost`

### Port 8008 Already in Use

**Problem:** Synapse won't start because port is in use

**Solution:**
```bash
# Find what's using port 8008
lsof -i :8008  # macOS/Linux
netstat -ano | findstr :8008  # Windows

# Kill the process or use a different port
docker run -d --name synapse -p 8009:8008 ...
```

### Flutter Build Errors

**Problem:** Build fails after adding dependencies

**Solution:**
```bash
flutter clean
flutter pub get
flutter run
```

## 📚 API Documentation

### Matrix Client Methods

```dart
// Login
await matrixProvider.login(username, password);

// Register
await matrixProvider.register(username, password);

// Search users
final users = await matrixProvider.searchUsers(query);

// Start direct chat
final roomId = await matrixProvider.startDirectChat(userId);

// Send message
await matrixProvider.sendMessage(roomId, message);

// Logout
await matrixProvider.logout();
```

## 🔐 Security Notes

- **Local Development Only:** This setup uses HTTP and unencrypted storage
- **Production:** Use HTTPS, secure credential storage, and proper encryption
- **Credentials:** Never commit credentials to Git
- **Email Passwords:** Use app-specific passwords, not your main password

## 📦 Dependencies

Key packages used:

- `matrix: ^0.25.0` - Matrix SDK
- `provider: ^6.1.1` - State management
- `hive_flutter: ^1.1.0` - Local storage
- `firebase_auth: ^6.4.0` - Firebase authentication
- `google_fonts: ^6.1.0` - Custom fonts
- `mailer: ^7.1.0` - Email sending

See `pubspec.yaml` for complete list.

## 🚀 Deployment

### To VPS (Production)

1. Get a domain and SSL certificate
2. Install Docker on VPS
3. Set up Synapse with PostgreSQL (not SQLite)
4. Use Nginx as reverse proxy with SSL
5. Update Flutter app URL to your domain
6. Build and deploy

## 🏭 Production handbook

This section is the single operational source of truth for the project. The
application is a Flutter client backed by a Matrix homeserver (Synapse), an
XMO Dart authentication/API server, Authentik for OIDC credentials, Firebase
Cloud Messaging for push delivery, and optional Azure Blob Storage for large
encrypted media chunks.

### Production architecture

```text
Flutter Android/iOS client
  ├─ Matrix Client-Server API ──> Synapse homeserver
  ├─ OIDC login ────────────────> Authentik
  ├─ OTP, wallet, deletion, media signing ──> XMO auth server
  ├─ Push registration ─────────> Firebase Cloud Messaging
  └─ Encrypted large-media chunks ─────────> Azure Blob Storage
```

The client uses Provider-based state management, Matrix Dart, Olm-compatible
E2EE services, local encrypted storage, repository/service boundaries, native
Android call and notification integrations, and Flutter screens/widgets for
presentation. Synapse stores Matrix identities, room state, events, devices,
and encrypted media metadata. The XMO backend must never receive plaintext
room keys or plaintext message content.

### Production endpoints and configuration

Use production values only in release builds or authorized staging tests:

```text
XMO_HOMESERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com
XMO_MATRIX_SERVER_NAME=xmo-matrix.centralindia.cloudapp.azure.com
XMO_STREAM_CHUNK_STORAGE=azure
XMO_AZURE_CHUNK_SIGN_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/media/chunks/azure/sign-upload
```

Never commit passwords, signing secrets, Azure keys, JWT secrets, OTP
credentials, or production tokens. Supply them through deployment secrets or
dart-defines. Release builds must use HTTPS, production signing, the intended
application ID, privacy URLs, backup rules, and the real Matrix server name.

### Authentication and account lifecycle

Authentik is the credential authority for the normal OIDC flow. Registration
uses email OTP, creates the linked identity, and hands the user to Authentik;
login uses Authentik credentials and optional TOTP; recovery changes the
Authentik credential through the verified recovery flow. Synapse provides the
Matrix session but does not become the source of usable local passwords.

Wallet-only accounts are a separate path. The user connects a wallet, selects
an available username for a new account or signs a fresh challenge for an
existing account, receives a short-lived JWT, and then receives a Synapse
device session. Wallet authentication must validate nonce, signature, wallet
address, username ownership, expiry, and replay protection server-side.

Account deletion must be idempotent and available both in-app and through the
public deletion route. It must remove or schedule removal of XMO account data,
linked Authentik identity data, local session/cache data, and documented
external data while retaining only legally required records.

### Matrix, E2EE, and device recovery

XMO uses Matrix Olm/Megolm, cross-signing, SAS device verification, Secure
Secret Storage, and Matrix key backup. Recovery is Matrix-native: no custom
recovery PIN, plaintext recovery key, backend key escrow, or decrypted room-key
upload is permitted.

Required production workflows are:

1. First-device setup creates cross-signing and secure recovery material.
2. A second device authenticates, verifies through SAS or an already trusted
   device, and restores the encrypted key backup.
3. Recovery without the old device uses the user’s protected recovery key or
   passphrase and then re-verifies the new device.
4. Logout, reinstall, backup restore, historical-event decryption, encrypted
   media, cross-signing, and verified-device key requests are tested before
   release.

The E2EE release gate requires successful XMO-to-XMO text and media tests,
XMO-to-Element interoperability, recovery setup, reinstall restore,
cross-signing reliability, and verified-device key-request handling on two
independent devices. Automated tests do not replace physical-device evidence.

### Groups, channels, and invite links

Invite links use:

```text
https://xmo.dpdns.org/join/<opaque-token>
```

The backend supports authenticated create, list, revoke, preview, and redeem
operations. Raw tokens must not be logged or stored as lookup keys. One active
primary link per room is supported; resetting a link invalidates the previous
token. Public unencrypted rooms may join directly. Private encrypted rooms
must retain the approval/knock flow and must never be made public or
unencrypted by an invite.

Android App Links open the installed app. Netlify provides a browser preview,
Open XMO action, and download fallback. iOS and unsupported platforms remain
browser-only until Universal Links are separately configured. Synapse enforces
the final membership limits: groups allow up to 50 joined members and channels
up to 100 joined subscribers, regardless of which client performs the join.

### Media, streaming, and calls

Small media follows Matrix encrypted-media handling. Large media may use
chunked upload/download with Azure Blob Storage. Signing endpoints must require
Matrix authentication and room membership, use short-lived authorized URLs,
avoid secrets in manifests, validate manifests and ranges, and support retry,
resume, cancellation, and bounded local storage.

Before shipping streaming, verify text, image, audio, and video paths; upload,
download, resume, cancellation, background/foreground transitions, offline
behavior, expired URLs, unauthorized-room access, large files, encrypted media,
and Android physical-device playback. Confirm the backend reports
`azureBlob:"ready"` when Azure storage is enabled.

Calls require notification, microphone, camera, background, lock-screen,
recent-apps, direct-call, and group-call regression coverage. Validate Android
permissions, notification actions, incoming-call handling, and cleanup after
hang-up or process termination.

### Deployment runbook

#### Auth server

Deploy the Dart service with HTTPS and protected environment secrets. Verify
health, OTP send/verify and resend, password recovery, wallet nonce/verify,
username availability, donation creation, invite operations, account deletion,
and Azure chunk-signing authorization. Review logs for token, password, OTP,
wallet signature, and media-secret leakage.

Password-reset challenges are stored in PostgreSQL, so an auth-server restart
does not invalidate a code that has already been emailed. Configure
`XMO_PASSWORD_RESET_CODE_SECRET` with a distinct random secret of at least 32
characters. The reset store accepts dedicated `XMO_PASSWORD_RESET_DB_*`
settings; when they are not present it uses the existing `XMO_WALLET_DB_*`
connection settings. The database user needs permission to create and use the
`xmo_password_reset_challenges` table. The reset-code secret is mandatory and
never falls back to `XMO_WALLET_JWT_SECRET`. Never log or persist raw reset
codes.

Registration and external account-deletion codes are also stored in
PostgreSQL. Configure `XMO_EMAIL_OTP_CODE_SECRET` with a different random
secret of at least 32 characters. Optional `XMO_EMAIL_OTP_DB_*` settings take
precedence over `XMO_PASSWORD_RESET_DB_*` and `XMO_WALLET_DB_*`; only database
connection settings fall back. The database user needs permission to create
and use `xmo_email_otp_challenges` and `xmo_email_otp_rate_limits`. Stored
subjects, client addresses, and codes are keyed digests rather than plaintext.

For an existing wallet-account deployment, add both independent code secrets
before deploying this auth-server version:

```bash
openssl rand -hex 32
# Add the generated value to /opt/xmo/auth.env as:
XMO_PASSWORD_RESET_CODE_SECRET=<generated value>
openssl rand -hex 32
# Add the second generated value as:
XMO_EMAIL_OTP_CODE_SECRET=<different generated value>
```

After deployment, `xmo-auth` must log `password_reset_store_ready` and
`email_otp_store_ready`. Request each type of code, restart only `xmo-auth`,
then complete the corresponding operation with that same code to verify the
operational paths. Codes are single-use, enforce completion-attempt limits,
and use durable per-target and per-client-address request quotas.

New and reset passwords must be 15-256 characters. Existing passwords remain
valid until changed. Mirror this policy in every Authentik enrollment,
password-change, and recovery prompt; its API-created users are still checked
by the auth server.

Set `XMO_ALLOWED_CORS_ORIGINS` to the comma-separated exact browser origins
that may access the auth server (production: `https://xmo.dpdns.org`). Do not
use `*`. The legacy loopback email helper permits browser access only when its
separate `XMO_LOCAL_EMAIL_ALLOWED_CORS_ORIGINS` setting is explicitly set.

#### Synapse

Deploy homeserver configuration, OIDC integration, templates, and the room
capacity module. The capacity module is the final enforcement point for
direct joins, invites, public joins, join-request approvals, tracked invite
links, Element, and other clients. Verify group and channel boundary cases,
including attempts made by unauthorized clients.

#### Authentik and Android links

Configure the XMO brand, production domain, default application, OIDC client,
redirect URIs, logout URIs, optional TOTP policy, and secure cookie/session
settings. Verify Android App Links using the production domain and asset
links. Confirm browser fallback behavior for unsupported platforms.

#### Wallet accounts

Provision the wallet account database with restricted permissions, configure
the auth-server database connection and JWT secret, enable the Synapse JWT
login module, and test new-wallet registration, existing-wallet login,
username collision, nonce expiry, replay, invalid signature, logout, and
device-session creation.

Wallet sign-in is fail-closed. Configure these exact production values in the
auth-server secret environment; do not rely on defaults and do not put any of
these values in Flutter dart-defines:

```text
XMO_WALLET_AUTH_DOMAIN=xmo.dpdns.org
XMO_WALLET_AUTH_URI=https://xmo.dpdns.org
XMO_WALLET_JWT_SECRET=<one random secret shared with Synapse>
XMO_WALLET_JWT_ISSUER=xmo-wallet-auth
XMO_WALLET_JWT_AUDIENCE=xmo-matrix
XMO_PUBLIC_BASE_URL=https://xmo-matrix.centralindia.cloudapp.azure.com
```

The auth server and Synapse must use identical JWT secret, issuer, and
audience settings. Compare redacted SHA-256 digests during deployment and
record only `match` or `mismatch`; never print their values. Wallet prompts
must show `xmo.dpdns.org`, never an Azure or container hostname.

`XMO_PUBLIC_BASE_URL` is the externally reachable auth/media API origin, not
the wallet-signing domain. It must be a hostname that the reverse proxy
actually serves for `/auth/media/*`; the current deployment uses the Matrix
hostname for that route.

Donations use Thirdweb as the payment gateway. For in-app Base USDC payments,
Reown connects the user's wallet and submits only the short-lived transaction
plan prepared by Thirdweb. Browser checkout remains available for other payment
methods. Configure a distinct `XMO_THIRDWEB_WEBHOOK_SECRET` of at least 32
characters from Thirdweb Bridge > Webhooks, pointing to
`https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp/donations/thirdweb/webhook`.
This uses the auth route already forwarded by the production Caddy config.
Donation records use `XMO_DONATION_DB_*`,
falling back to `XMO_WALLET_DB_*` when omitted. The webhook secret must differ
from `XMO_THIRDWEB_SECRET_KEY`. The service must log both
`donation_store_ready` and `thirdweb_webhook_ready` before in-app checkout is
enabled.

`XMO_DONATION_RECIPIENT_ADDRESS` is mandatory server configuration. It has no
compiled fallback and must not be supplied as a Flutter dart-define. Confirm
the configured address out of band before deployment without exposing any
secret values.

XMO reports a donation as completed only after Thirdweb status matches the
stored payment ID, random donation ID, wallet, recipient, Base chain, USDC
token, and amount. Matrix user IDs are not sent as Thirdweb purchase metadata.
Webhooks are HMAC verified, timestamp limited, and deduplicated. Do not grant
donation benefits unless that confirmed state is used idempotently on the
server.

### Deterministic quality gates

Run from the Flutter project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\run_quality_gates.ps1
```

The gate must run formatting checks, static analysis, Flutter tests, auth-server
tests, and fixed-timeout checks without mutating source files. CI must repeat
the same checks with the exact production configuration contract. Keep the
generated report and redacted logs as release evidence.

### Release and Play testing

The release candidate is not production-ready until all of the following are
true:

- A reproducible commit is built with production dart-defines and release
  signing.
- No deterministic phone-derived credentials remain as a security shortcut.
- Azure chunk signing is authenticated, authorized, secret-managed, and
  tested with real encrypted media.
- Account deletion, Android backup exclusions, temporary-media cleanup, and
  local credential protection are verified.
- Native libraries, Android components, permissions, calls, and 16 KB page
  size compatibility pass on supported devices.
- E2EE evidence, privacy policy, data-safety declarations, financial
  declarations, store listing, and public account-deletion URLs are complete.
- Internal testing covers authentication, messaging, E2EE, media, calls,
  notifications, upgrade, storage, logout, reinstall, and failure recovery.

Retain privately: commit SHA, signed AAB checksum, build configuration, test
device IDs, E2EE evidence, backend health output, Azure rotation evidence,
Play Console reports, crash/ANR results, and the final go/no-go decision.

### Production QA matrix

Test a small phone (320–360 logical pixels), normal phone (390–430 pixels),
landscape, split-screen, a physical Android device, an encrypted private room,
and an applicable unencrypted room. Cover reactions, polls, stickers, link
previews, stories, replies, app lock, device/session management, search,
attachments, notifications, calls, and account switching. Every blocking item
needs dated evidence; a green automated test alone is insufficient.

### Privacy and service rules

XMO processes account identifiers, profiles, Matrix events, rooms, media,
device/session information, calls, usage data, OTP information, wallet
addresses, donation metadata, and permission-related data as required to run
the service. E2EE protects eligible content in transit and at rest, but
metadata, recipients, homeserver storage, local caches, notifications, and
third-party services may still expose operational information.

Users control sessions, app lock, device verification, recovery material,
message deletion/redaction where supported, and account deletion. Third-party
providers—including Authentik, Matrix/Synapse infrastructure, email delivery,
Firebase, Azure, wallet providers, blockchain networks, and app stores—have
separate terms and policies. Keep public privacy and terms URLs synchronized
with the deployed behavior and review them whenever data flows change.

### Project maintenance rule

This README intentionally replaces the former scattered Markdown guides. Keep
production architecture, deployment commands, security constraints, release
gates, and operator evidence requirements here. Do not create a second project
guide without merging its useful content into this file.

## 📝 License

This project is part of the XMO messaging platform.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📞 Support

For issues and questions:
- Open an issue on GitHub
- Check existing documentation
- Review troubleshooting section above

## 🎓 Learning Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Matrix Protocol](https://matrix.org/docs/spec)
- [Matrix Dart SDK](https://pub.dev/packages/matrix)
- [Docker Documentation](https://docs.docker.com/)

---

**Happy Messaging! 🎉**
