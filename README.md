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

See `matrix_local_backend_setup.md` for detailed VPS setup guide.

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
