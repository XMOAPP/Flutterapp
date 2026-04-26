# Clean Up Duplicate Matrix Rooms

You currently have 3 duplicate "kiranpeter" rooms. Here's how to clean them up:

## Option 1: From the App (Easiest)

Unfortunately, the current app doesn't have a "leave room" feature in the UI yet. We need to add it.

## Option 2: Using Matrix Admin API

### Step 1: Get your access token

1. Login to the app as @kiran
2. Add this debug code temporarily to see your token:

```dart
// In home_screen.dart, add to _XmoDrawer build method:
print('Access token: ${matrixProvider.service.client.accessToken}');
```

### Step 2: Leave the duplicate rooms

For each duplicate room ID, run:

```bash
# Get the room IDs first
curl -X GET "http://localhost:8008/_matrix/client/v3/joined_rooms" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# Leave each duplicate room
curl -X POST "http://localhost:8008/_matrix/client/v3/rooms/ROOM_ID/leave" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

## Option 3: Fresh Start (Nuclear Option)

If you want to start completely fresh:

```bash
# Stop Synapse
docker stop synapse
docker rm synapse

# Delete all data
cd ~/matrix-backend
rm -rf synapse-data/*

# Regenerate config (see matrix_local_backend_setup.md Phase 2)
# Then restart Synapse (see Phase 4)
# Recreate users (see Phase 6)
```

## Better Solution: Add Leave Room Feature

I can add a "Leave Room" button to the app. Would you like me to do that?
