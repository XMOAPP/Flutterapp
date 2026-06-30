# Phase 8 Product Polish QA Checklist

Phase 8 is beta-ready only after every blocking item below has real evidence.
Automated tests protect basic rendering and checklist gating, but physical-device
passes are still required for the Android-specific surfaces.

## Test Matrix

- Small phone: 320-360 px logical width.
- Normal phone: 390-430 px logical width.
- Landscape: physical Android device.
- Split screen: Android multi-window at the narrowest supported width.
- Room types: encrypted private room and unencrypted room where applicable.

## Reaction Details

- Create a message and have at least two users react with the same emoji.
- Tap the reaction chip.
- Confirm the details sheet lists each reacting user with display name/avatar.
- Confirm the current user's row can remove their own reaction.
- Confirm long display names truncate and do not overflow.

Evidence:
- Room ID, message event ID, reaction event IDs.
- Screenshot of the reaction details sheet.

## Polls

- Create a poll with a long question and long answer labels.
- Vote from two different accounts.
- Restart the app and reopen the room.
- Confirm counts persist and each voter has only one active vote.
- Repeat at 320 px width and in split screen.

Evidence:
- Poll event ID and vote event IDs.
- Screenshots before and after voting.

## Stickers

- Send and receive a sticker in an encrypted private room.
- Send and receive a sticker in an unencrypted room.
- Confirm image, sender label, and timestamp render.
- Confirm a missing or broken sticker media URL shows a fallback state.
- Confirm sticker bubble does not overflow at narrow width.

Evidence:
- Sticker event IDs.
- Screenshot of loaded and fallback states.

## Link Previews

- Send a plain URL with title, description, and image metadata.
- Send a URL without preview image metadata.
- Confirm title, description, host/site label, and message body render.
- Tap the preview and confirm the expected URL opens externally.
- Repeat at narrow width and split screen.

Evidence:
- Message event IDs.
- Screenshot of image and no-image preview variants.

## Stories, Replies, And Reactions

- Create text, image, and video stories.
- View another user's story and verify viewed state persists after restart.
- Send a story text reply.
- Send a story emoji reaction.
- Confirm both arrive as direct messages.
- Delete your own story and confirm it disappears for viewers.

Evidence:
- Story IDs and direct-message event IDs.
- Screenshots of story list, viewer, reply, and reaction message.

## App Lock

- Enable PIN lock.
- Unlock with the correct PIN.
- Attempt failed PINs until temporary blocking appears.
- Verify timeout lock after backgrounding.
- Verify lock-now behavior.
- Enable biometric unlock on a supported device.
- Disable app lock.
- Sign in as a different user and confirm settings are scoped separately.

Evidence:
- Device model, Android version, timeout value.
- Screenshots of enabled, locked, blocked, and disabled states.

## Device And Session Management

- Open device/session management with at least two logged-in devices.
- Confirm current device is sorted first and labeled correctly.
- Confirm verified state matches Matrix device keys.
- Rename a device and confirm it persists after refresh.
- Delete another device.
- Confirm reauthentication prompt appears when the server requires it.

Evidence:
- User ID, current device ID, deleted device ID.
- Screenshot before and after refresh.

## Responsive Pass

- Check chat, settings, stories, calls, media preview, app lock, and device sessions.
- Confirm no primary controls are clipped or unreachable.
- Confirm text truncates cleanly rather than overlapping adjacent controls.
- Confirm bottom sheets leave controls above system navigation areas.
- Confirm landscape and split-screen layouts remain usable.

Evidence:
- Screenshot set for each screen at small, landscape, and split-screen sizes.
