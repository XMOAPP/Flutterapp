# Matrix Backend — Complete Local Setup Guide
> Flutter frontend ready. This guide sets up everything backend side, locally, step by step.

---

## What You Are Building

```
Flutter App (your phone / emulator)
        │
        │  matrix dart SDK  (http)
        ▼
Synapse Homeserver  (Docker → localhost:8008)
        │
        ▼
SQLite  (auto-created inside Docker volume)
```

No VPS needed. No domain needed. No SSL needed. Just Docker on your machine.

---

## Prerequisites

- **Docker** already installed ✅
- **Flutter** already set up ✅
- ~4 GB free disk space
- Internet connection (to pull Docker images)

Quick check — confirm Docker is running:
```bash
docker --version
docker ps
```

Both commands should work without errors before proceeding.

---

## PHASE 1 — Create Your Project Folder

Open Terminal (or PowerShell on Windows) and run:

```bash
# Go to your home directory
cd ~

# Create a folder for your Matrix backend
mkdir matrix-backend
cd matrix-backend

# Create a folder where Synapse will store its data
mkdir synapse-data
```

Your structure now:
```
~/matrix-backend/
    synapse-data/    ← empty for now
```

---

## PHASE 2 — Generate Synapse Configuration

This command runs Synapse once just to create the config file. It will NOT start the server permanently.

### macOS / Linux:
```bash
docker run -it --rm \
  -v $(pwd)/synapse-data:/data \
  -e SYNAPSE_SERVER_NAME=localhost \
  -e SYNAPSE_REPORT_STATS=no \
  matrixdotorg/synapse:latest generate
```

### Windows (PowerShell):
```powershell
docker run -it --rm `
  -v ${PWD}/synapse-data:/data `
  -e SYNAPSE_SERVER_NAME=localhost `
  -e SYNAPSE_REPORT_STATS=no `
  matrixdotorg/synapse:latest generate
```

### What this does:
- Downloads the official Synapse Docker image (first time takes 2-3 min)
- Generates `homeserver.yaml` inside your `synapse-data/` folder
- Generates a signing key file
- Exits automatically

After it finishes, check:
```bash
ls synapse-data/
# You should see:
# homeserver.yaml
# localhost.log.config
# localhost.signing.key
```

---

## PHASE 3 — Edit homeserver.yaml

Open `synapse-data/homeserver.yaml` in any text editor (VS Code, Notepad, nano, etc.)

Find and change these settings:

### 4a — Allow user registration (REQUIRED for local dev)

Find this line:
```yaml
#enable_registration: false
```

Replace with:
```yaml
enable_registration: true
enable_registration_without_verification: true
```

### 4b — Check your server name (should already be set)

```yaml
server_name: "localhost"
```

### 4c — Database (leave as-is for local dev)

The default is SQLite. This is fine for local development. You will see something like:
```yaml
database:
  name: sqlite3
  args:
    database: /data/homeserver.db
```

Leave this alone. SQLite is automatically created when Synapse starts.

### 4d — Disable federation (optional but recommended for private local dev)

Scroll down and find or add:
```yaml
federation_domain_whitelist: []
```

Or just leave federation as-is. It doesn't matter much for local dev since you're on localhost anyway.

---

### Final homeserver.yaml — Key Lines Summary

Your file is long. These are the only lines you actually changed:
```yaml
server_name: "localhost"
enable_registration: true
enable_registration_without_verification: true
```

Everything else is auto-configured.

---

## PHASE 4 — Start Synapse Server

### macOS / Linux:
```bash
docker run -d \
  --name synapse \
  -v $(pwd)/synapse-data:/data \
  -p 8008:8008 \
  matrixdotorg/synapse:latest
```

### Windows (PowerShell):
```powershell
docker run -d `
  --name synapse `
  -v ${PWD}/synapse-data:/data `
  -p 8008:8008 `
  matrixdotorg/synapse:latest
```

### Flags explained:
| Flag | Meaning |
|------|---------|
| `-d` | Run in background (detached) |
| `--name synapse` | Give container a name so you can reference it |
| `-v $(pwd)/synapse-data:/data` | Mount your local folder into container |
| `-p 8008:8008` | Expose port 8008 to your machine |

---

## PHASE 5 — Verify Synapse is Running

### Check container status:
```bash
docker ps
```

You should see synapse in the list with status `Up`.

### Check logs (if something is wrong):
```bash
docker logs synapse
```

Look for a line like:
```
synapse.app.homeserver - INFO - ... Synapse now listening on ...
```

### Test in browser:

Open: `http://localhost:8008`

You should see:
```json
{
  "errcode": "M_UNRECOGNIZED",
  "error": "Unrecognized request"
}
```

**This is correct and expected.** It means Synapse is running and responding. The error just means you hit the root URL which isn't a valid Matrix endpoint.

### Test the Matrix well-known endpoint:
Open: `http://localhost:8008/_matrix/client/versions`

You should see a JSON response listing Matrix spec versions. ✅

---

## PHASE 6 — Create Users

You need at least an admin user and a test user.

### Create Admin User:
```bash
docker exec -it synapse register_new_matrix_user \
  http://localhost:8008 \
  -c /data/homeserver.yaml \
  -u admin \
  -p yourpassword123 \
  --admin
```

### Create Test User 1:
```bash
docker exec -it synapse register_new_matrix_user \
  http://localhost:8008 \
  -c /data/homeserver.yaml \
  -u alice \
  -p alice123 \
  --no-admin
```

### Create Test User 2:
```bash
docker exec -it synapse register_new_matrix_user \
  http://localhost:8008 \
  -c /data/homeserver.yaml \
  -u bob \
  -p bob123 \
  --no-admin
```

You now have 3 users: admin, alice, bob.

---

## PHASE 7 — Test Login via curl

This confirms your server works before touching Flutter.

```bash
curl -X POST http://localhost:8008/_matrix/client/v3/login \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "identifier": {
      "type": "m.id.user",
      "user": "alice"
    },
    "password": "alice123"
  }'
```

Expected response:
```json
{
  "access_token": "syt_...",
  "device_id": "...",
  "home_server": "localhost",
  "user_id": "@alice:localhost"
}
```

Copy that `access_token`. You are now logged in as alice. ✅

---

## PHASE 8 — Test Create a Room via curl

Using alice's access token from above:

```bash
curl -X POST http://localhost:8008/_matrix/client/v3/createRoom \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN_HERE" \
  -d '{
    "name": "Test Room",
    "topic": "Testing Matrix",
    "preset": "public_chat"
  }'
```

Expected response:
```json
{
  "room_id": "!abc123:localhost"
}
```

Save the `room_id`. ✅

---

## PHASE 9 — Test Send a Message via curl

```bash
curl -X PUT \
  "http://localhost:8008/_matrix/client/v3/rooms/YOUR_ROOM_ID/send/m.room.message/1" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN_HERE" \
  -d '{
    "msgtype": "m.text",
    "body": "Hello from curl! 🎉"
  }'
```

Expected response:
```json
{
  "event_id": "$abc123..."
}
```

Your Matrix server is fully working. ✅✅

---

## PHASE 10 — Connect Flutter App

### 11a — Add matrix package to pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter
  matrix: ^0.25.0
  hive_flutter: ^1.1.0
  path_provider: ^2.1.0
```

Run:
```bash
flutter pub get
```

---

### 11b — Determine the correct server URL for your device

| Device | URL to use |
|--------|-----------|
| Android Emulator | `http://10.0.2.2:8008` |
| iOS Simulator | `http://localhost:8008` |
| Physical Android (same WiFi) | `http://YOUR_MACHINE_IP:8008` |
| Physical iPhone (same WiFi) | `http://YOUR_MACHINE_IP:8008` |

**Find your machine's local IP:**
- macOS: `ipconfig getifaddr en0`
- Linux: `ip addr show` or `hostname -I`
- Windows: `ipconfig` → look for IPv4 Address

---

### 11c — Initialize the Matrix Client

```dart
import 'package:matrix/matrix.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

Future<Client> initMatrixClient() async {
  await Hive.initFlutter();

  final client = Client(
    'MyAppName',
    databaseBuilder: (_) async {
      final dir = await getApplicationSupportDirectory();
      final db = HiveCollectionsDatabase('matrix_client', dir.path);
      await db.open();
      return db;
    },
  );

  await client.init();
  return client;
}
```

---

### 11d — Check Homeserver and Login

```dart
Future<void> loginUser(Client client) async {
  // Step 1: Point client to your local server
  await client.checkHomeserver(
    Uri.parse('http://10.0.2.2:8008'),  // Android emulator
    // Uri.parse('http://localhost:8008'),    // iOS simulator
    // Uri.parse('http://192.168.1.x:8008'), // physical device
  );

  // Step 2: Login
  final response = await client.login(
    LoginType.mLoginPassword,
    identifier: AuthenticationUserIdentifier(user: 'alice'),
    password: 'alice123',
  );

  print('Logged in as: ${response.userId}');
  print('Access token: ${response.accessToken}');
}
```

---

### 11e — Register a New User from Flutter

```dart
Future<void> registerUser(Client client, String username, String password) async {
  try {
    await client.register(
      username: username,
      password: password,
    );
    print('Registered: @$username:localhost');
  } catch (e) {
    print('Registration error: $e');
  }
}
```

---

### 11f — Create a Room

```dart
Future<String> createRoom(Client client, String roomName) async {
  final roomId = await client.createRoom(
    name: roomName,
    topic: 'Created from Flutter',
    preset: CreateRoomPreset.publicChat,
  );
  print('Room created: $roomId');
  return roomId;
}
```

---

### 11g — Join an Existing Room

```dart
Future<void> joinRoom(Client client, String roomId) async {
  await client.joinRoom(roomId);
  print('Joined room: $roomId');
}
```

---

### 11h — Send a Text Message

```dart
Future<void> sendMessage(Client client, String roomId, String message) async {
  final room = client.getRoomById(roomId);
  if (room == null) {
    print('Room not found');
    return;
  }
  await room.sendTextEvent(message);
  print('Message sent!');
}
```

---

### 11i — Listen for New Messages (Real-time Sync)

```dart
void listenForMessages(Client client) {
  client.onEvent.stream.listen((eventUpdate) {
    final event = eventUpdate.content;
    if (event['type'] == 'm.room.message') {
      final body = event['content']['body'];
      final sender = event['sender'];
      print('[$sender]: $body');
    }
  });

  // Start sync (keeps connection alive)
  client.sync();
}
```

---

### 11j — Get All Rooms for the Logged-in User

```dart
List<Room> getUserRooms(Client client) {
  final rooms = client.rooms;
  for (final room in rooms) {
    print('Room: ${room.displayname} | ID: ${room.id}');
  }
  return rooms;
}
```

---

### 11k — Get Message History for a Room

```dart
Future<void> getMessageHistory(Client client, String roomId) async {
  final room = client.getRoomById(roomId);
  if (room == null) return;

  final timeline = await room.getTimeline();
  final events = timeline.events;

  for (final event in events) {
    if (event.type == EventTypes.Message) {
      print('[${event.senderId}]: ${event.body}');
    }
  }
}
```

---

### 11l — Send a File / Image

```dart
import 'dart:io';

Future<void> sendImage(Client client, String roomId, File imageFile) async {
  final room = client.getRoomById(roomId);
  if (room == null) return;

  final bytes = await imageFile.readAsBytes();
  final mimeType = 'image/jpeg'; // or detect dynamically

  await room.sendFileEvent(
    MatrixFile(bytes: bytes, name: imageFile.path.split('/').last),
    msgType: MessageTypes.Image,
  );
  print('Image sent!');
}
```

---

### 11m — Logout

```dart
Future<void> logoutUser(Client client) async {
  await client.logout();
  print('Logged out');
}
```

---

## PHASE 11 — Enable Android Cleartext HTTP (Important!)

By default Android blocks HTTP (non-HTTPS) traffic. Since localhost uses HTTP, you need to allow it.

Open `android/app/src/main/AndroidManifest.xml` and add:

```xml
<application
  android:usesCleartextTraffic="true"   <!-- ADD THIS LINE -->
  ...
>
```

For production (VPS with HTTPS) you will remove this line.

---

## PHASE 12 — Useful Docker Commands

```bash
# See running containers
docker ps

# See all containers (including stopped)
docker ps -a

# Stop synapse
docker stop synapse

# Start synapse again
docker start synapse

# Restart synapse
docker restart synapse

# View live logs
docker logs -f synapse

# View last 50 lines of logs
docker logs --tail 50 synapse

# Open a shell inside synapse container
docker exec -it synapse bash

# Remove container (data is safe in synapse-data/ folder)
docker rm synapse

# Remove container AND image (full cleanup)
docker rm synapse
docker rmi matrixdotorg/synapse
```

---

## PHASE 13 — What to Test End-to-End

Work through this checklist in order:

- [ ] `docker ps` shows synapse as `Up`
- [ ] `http://localhost:8008` returns JSON response in browser
- [ ] `http://localhost:8008/_matrix/client/versions` shows spec versions
- [ ] curl login returns an `access_token`
- [ ] curl createRoom returns a `room_id`
- [ ] curl sendMessage returns an `event_id`
- [ ] Flutter app initializes without crash
- [ ] Flutter `checkHomeserver()` succeeds without error
- [ ] Flutter `login()` succeeds and returns userId
- [ ] Flutter `createRoom()` returns a roomId
- [ ] Flutter `sendTextEvent()` sends a message
- [ ] Alice sends a message, Bob receives it in real-time

---

## PHASE 14 — Troubleshooting

### "Connection refused" in Flutter
- Make sure synapse container is running: `docker ps`
- Make sure you're using the right URL for your device (see Phase 11b)
- Make sure `usesCleartextTraffic="true"` is set in AndroidManifest.xml

### "Registration is disabled"
- Make sure `enable_registration: true` is set in homeserver.yaml
- Restart synapse: `docker restart synapse`

### "docker: command not found" on Linux
- Run `sudo apt install docker.io` again
- Or add docker to PATH: `export PATH=$PATH:/usr/bin`

### Synapse crashes on startup
- Check logs: `docker logs synapse`
- Most common cause: syntax error in homeserver.yaml
- Open homeserver.yaml and check for incorrect indentation

### Flutter build error after adding matrix package
- Run `flutter pub get` again
- Clean build: `flutter clean && flutter pub get`
- Check minSdkVersion in android/app/build.gradle — must be at least 21

### Port 8008 already in use
- Find what's using it: `lsof -i :8008` (Mac/Linux) or `netstat -ano | findstr :8008` (Windows)
- Stop that process, then start synapse again

---

## Summary — Your Local Stack

```
Flutter App
    │
    │  matrix dart SDK
    │  http://10.0.2.2:8008 (Android)
    │  http://localhost:8008 (iOS)
    ▼
Docker Container: synapse
    │
    │  Matrix Client-Server API (/_matrix/client/...)
    ▼
SQLite database (auto-managed by Synapse)
    stored in ~/matrix-backend/synapse-data/homeserver.db
```

---

## What Comes Next (VPS Phase)

When you're ready to go live:
1. Rent a VPS (DigitalOcean, Hetzner, AWS)
2. Buy a domain and point DNS to VPS
3. Install Docker on VPS (same commands as above)
4. Add Nginx as reverse proxy (SSL termination)
5. Get SSL certificate via Certbot (free, Let's Encrypt)
6. Switch SQLite → PostgreSQL in homeserver.yaml
7. Update Flutter URL from localhost → your domain
8. Add FCM push notifications (Firebase)
9. Set up backups for PostgreSQL

Everything you build locally transfers directly. Same code, same config structure, just a new URL.
