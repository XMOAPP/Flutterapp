# XMO Group and Channel Invite Links: Implementation Plan

## Current Implementation Status

The beta architecture described below is implemented with these boundaries:

- Branded `https://xmo.dpdns.org/join/<token>` links, Android App Links, a
  Netlify browser fallback, QR sharing, and legacy `xmo://join` and
  `matrix.to` compatibility are implemented.
- The backend implements authenticated create, list, revoke, preview, and
  redeem endpoints. Raw tokens are not stored as lookup keys or logged.
- One active primary link per room is supported. Resetting creates a new token
  and invalidates the previous one.
- Public unencrypted rooms use direct join. Private encrypted rooms use the
  existing approval/knock flow and never become public or unencrypted.
- Signed-out users can log in and resume the pending invite in memory.
- Invite records currently use the serialized JSON auth-data store. PostgreSQL
  remains required before high-volume production use.
- Multiple named links, per-link policy overrides, targeted direct invites,
  and a moderator approval-management screen remain future work.
- Android cold-start and warm-start link delivery are implemented. iOS
  Universal Links and desktop deep-link handlers are not implemented.
- Browser previews intentionally omit private-room topics and internal room
  identifiers. A browser can preview/open/download XMO, but membership changes
  happen only inside an authenticated XMO client.

The remaining deployment requirements are a Google Play app-signing SHA-256
fingerprint, deployment of the generated Netlify bundle, backend environment
configuration, and real-device verification. These are release acceptance
steps and cannot be proven by source tests alone.

## 1. Objective

Replace the current room-ID-based invite links with server-validated,
revocable XMO invite tokens while preserving existing room membership,
encryption, public discovery, QR sharing, and legacy-link compatibility.

The completed feature must provide:

- One simple primary invite link for every group or channel.
- Optional additional links with a name, expiry, and usage limit.
- Direct join, administrator approval, or invite-only behavior.
- Effective reset and revocation.
- Branded HTTPS links that open XMO when installed and a web fallback when not.
- Correct behavior for permanent public/private and encrypted/unencrypted rooms.
- Compatibility with existing XMO clients and standard Matrix clients.

## 2. Current Implementation and Gaps

### Existing behavior

- `MatrixService.buildXmoInviteLink` embeds the room ID and link ID in a
  Base64URL payload under `xmo://join/...`.
- `generateTrackedInviteLink` creates a link ID from the current timestamp.
- Invite records are stored in the room state event `u.xmo.invite_links`.
- The group and channel screens share `InviteLinkView` for QR, copy,
  regenerate, and revoke actions.
- `InviteLinkService` opens joined rooms and searches the public room directory
  for rooms the user has not joined.
- Group and channel controls already map XMO membership modes to Matrix
  `public`, `knock`, and `invite` join rules.

### Production gaps

- Base64URL encoding is not encryption or authorization.
- Timestamp-derived link IDs are predictable and are not bearer secrets.
- Link opening extracts only the room ID; the link ID is not validated.
- Revocation and expiry are not enforced during redemption.
- Usage counts are not incremented or protected against concurrent requests.
- A private-room link cannot securely authorize an uninvited user to join.
- Invite records in room state are unsuitable for secret validation and
  server-side abuse controls.
- `xmo://` links have no browser, install, or unsupported-device fallback.
- The current Share Link action copies the URL instead of opening the native
  sharing sheet.
- Rewriting a complete room-state list risks lost updates and unbounded state.

## 3. Product Rules to Freeze Before Coding

These rules are part of the security model and must remain consistent across
the app, backend, and room controls.

1. Room privacy is permanent.
   - A private encrypted room remains private and encrypted.
   - A public unencrypted room remains public and unencrypted.
   - Creating or redeeming an invite never changes room privacy or encryption.

2. Room type is permanent.
   - A group invite grants normal group membership.
   - A channel invite grants subscriber membership.
   - Channel posting remains controlled by existing Matrix power levels.

3. Membership mode is room-wide in the first release.
   - `direct`: a valid link can authorize immediate membership.
   - `approval`: a valid link creates or exposes a join request using the
     existing Matrix knock flow.
   - `invite_only`: only explicitly invited accounts can join.
   - Per-link approval overrides are deferred until room-wide behavior is
     stable.

4. A reset revokes the old primary link and creates a new one.
   - Reset does not remove existing members.
   - Revoked tokens must fail immediately at the backend.

5. Public discovery and invite links are separate capabilities.
   - Public rooms remain searchable when public discovery is enabled.
   - A tracked invite can still be expired or revoked independently.

## 4. Target Architecture

### Canonical link

```text
https://xmo.dpdns.org/join/<opaque-token>
```

The token must contain at least 128 bits of cryptographically secure random
entropy. The URL must not contain a room ID, user ID, creator ID, or room name.

### Request flow

```text
User opens HTTPS link
  -> Android App Link opens XMO, or website shows fallback
  -> XMO requests a minimal invite preview
  -> user logs in if required
  -> XMO redeems the token with a Matrix access token
  -> backend validates token, account, room, and membership policy
  -> backend performs or authorizes the Matrix membership transition
  -> XMO syncs and opens the room or pending-request screen
```

### Trust boundaries

- Flutter may display and submit a raw token but cannot decide whether it is
  valid.
- The XMO backend is the authority for token status, expiry, and limits.
- Synapse remains the authority for room membership, bans, join rules, and
  power levels.
- Only a token hash is persisted by the backend.
- Tokens and Matrix access tokens must never appear in logs or analytics.

## 5. Backend Data Model

Add a versioned invite record:

```text
id                  internal stable identifier
token_hash          SHA-256 hash of the raw token; unique
room_id             Matrix room ID
room_kind           group | channel
created_by          Matrix user ID
title               optional administrator-only label
created_at          UTC timestamp
expires_at          optional UTC timestamp
max_uses             optional positive integer
use_count            non-negative integer
requires_approval   boolean snapshot/setting
is_primary           boolean
revoked_at           optional UTC timestamp
last_used_at         optional UTC timestamp
version              schema/behavior version
```

Constraints:

- One active primary link per room.
- `token_hash` is unique.
- `max_uses` is null or greater than zero.
- `use_count` cannot exceed `max_uses` after a successful atomic redemption.
- Revoked and expired records are immutable except for administrative cleanup.

### Initial persistence

Use the existing `XMO_AUTH_DATA_FILE` persistence abstraction only for a
limited beta if writes are serialized and atomic. Before broad production,
move invite records to PostgreSQL so concurrent redemptions can use a database
transaction and row lock.

Do not store raw tokens inside Matrix room state. A non-secret state event may
later expose administrative summaries, but the backend remains authoritative.

## 6. Backend API Contract

### Public preview

`GET /invites/{token}/preview`

Returns only safe fields:

```json
{
  "status": "available",
  "roomKind": "group",
  "name": "Example group",
  "avatarUrl": null,
  "memberCount": 12,
  "requiresApproval": false
}
```

Rules:

- Return the same generic unavailable response for malformed, unknown,
  revoked, and expired tokens where practical.
- Do not expose member lists, creator IDs, room IDs, encryption keys, or
  private descriptions before authentication.
- Apply per-IP and per-token rate limits.

### Authenticated redemption

`POST /auth/invites/{token}/redeem`

Headers:

```text
Authorization: Bearer <Matrix access token>
```

Possible results:

```text
joined              membership was granted or already exists
approval_required   a knock/request exists or was created
invited             an explicit invite was created; client must sync/join
unavailable         invalid, revoked, expired, or exhausted
forbidden           banned, blocked, or room policy prevents joining
```

Redemption must be idempotent. Opening the same link again as an existing
member must not consume another use.

### Administrator endpoints

```text
POST   /auth/rooms/{roomId}/invites
GET    /auth/rooms/{roomId}/invites
PATCH  /auth/rooms/{roomId}/invites/{id}
POST   /auth/rooms/{roomId}/invites/{id}/revoke
POST   /auth/rooms/{roomId}/invites/primary/reset
```

Every management request must:

- Validate the Matrix bearer token with `/_matrix/client/v3/account/whoami`.
- Fetch room state/power levels and verify invite-management permission.
- Reject requests from former, banned, or insufficiently privileged members.
- Return raw tokens only once, immediately after creation or reset.

## 7. Matrix Membership Integration

### Existing member

- Return `joined` without changing counters.
- Sync and open the local room.

### Direct mode

- Backend validates the token and authenticated user.
- Backend creates an invite using a narrowly scoped service/admin credential.
- Client accepts the invite or joins after sync.
- Increment use count only after the membership action succeeds.

### Approval mode

- Keep the room join rule as `knock`.
- Client submits a Matrix knock after successful token validation.
- Existing group/channel administrator approval UI handles the request.
- Count policy must be explicit: recommended first release counts a use only
  when the request is approved and membership becomes `join`.

### Invite-only mode

- A general link must not bypass invite-only policy.
- It may show a safe preview and explain that an administrator invitation is
  required.
- A future single-use targeted invite can be designed separately.

### Ban and history behavior

- Banned users always fail even with a valid token.
- Kicked users follow current room policy unless explicitly banned.
- Verify `m.room.history_visibility` for every room type so joining through a
  link does not reveal more history than intended.

## 8. Flutter Implementation

### Configuration

Add production configuration values in `AppConfig`:

```text
XMO_INVITE_API_BASE_URL
XMO_INVITE_WEB_BASE_URL=https://xmo.dpdns.org
```

CI and release scripts must require production HTTPS values.

### Models

Replace the current UI-oriented link model with separate models:

- `InviteLinkSummary`: administrator list data without raw token.
- `CreatedInviteLink`: one-time raw URL plus summary.
- `InvitePreview`: safe recipient preview.
- `InviteRedemptionResult`: joined, pending, invited, or unavailable.

### Services

Add `invite_api_service.dart` with:

- `createInvite`
- `listInvites`
- `resetPrimaryInvite`
- `revokeInvite`
- `previewInvite`
- `redeemInvite`

Keep navigation orchestration in `InviteLinkService`, but remove security
decisions from it. It should call the backend before room lookup or joining.

### Authentication continuation

- Store a pending token in memory while navigating to login.
- After successful login, resume preview/redemption exactly once.
- Do not persist raw invite tokens in Hive, secure storage, crash reports, or
  analytics unless a short-lived encrypted continuation is proven necessary.
- Clear pending tokens after success, failure, logout, or timeout.

### Recipient screens

Add a compact invite preview screen with:

- Group/channel avatar and name.
- Group or Channel label.
- Member/subscriber count when safe.
- Join, Request to Join, Open, or unavailable action.
- Login action when signed out.
- Clear states for expired, revoked, full, banned, and network failure without
  exposing internal identifiers.

### Administrator screens

Primary screen:

- Compact room identity.
- Smaller QR code.
- Branded shortened invite URL.
- Copy and native Share actions.
- Manage Links action.
- Fixed first-viewport layout where practical; only the advanced list scrolls.

Manage Links screen:

- Primary link and additional links.
- Name, status, expiry, usage, and pending-request count.
- Create, edit, revoke, and reset actions.
- Confirmation before reset/revoke.

Use `share_plus` or the existing sharing abstraction for Share Link. Do not
route Share Link to clipboard copy.

## 9. HTTPS App Links and Web Fallback

### Android

- Add an HTTPS intent filter for `https://xmo.dpdns.org/join/*`.
- Keep the custom `xmo://join/...` filter during migration.
- Host `/.well-known/assetlinks.json` with the production package name and Play
  App Signing certificate fingerprint.
- Validate installed-release behavior with `adb shell pm get-app-links`.

### Website

Create `/join/<token>` that:

- Does not log or expose the token beyond what is necessary.
- Attempts to open the verified app link.
- Offers Download XMO when the app is not installed.
- Displays only a minimal non-sensitive preview, or no preview until the
  backend endpoint is ready.
- Uses `Referrer-Policy: no-referrer` and prevents third-party analytics from
  receiving the token URL.

## 10. Compatibility and Migration

### New clients

- Generate only branded HTTPS token links.
- Redeem only after backend validation.

### Existing `xmo://` links

- Continue parsing them during a defined migration period.
- Joined users may open the room normally.
- Public rooms may open through public discovery with a Legacy link warning.
- Legacy links must not grant access to private rooms.

### Existing `matrix.to` links

- Continue supporting standard public-room navigation for interoperability.
- Do not treat `matrix.to` as a revocable XMO private invite.

### Old XMO clients

- Normal Matrix room events and memberships remain unchanged.
- They can use public discovery or existing Matrix invitations.
- Advanced XMO link management is unavailable but must not break chat access.

## 11. Security Requirements

- Use `Random.secure()` or OS cryptographic randomness for at least 128 bits.
- Encode tokens with unpadded Base64URL or an equivalent URL-safe format.
- Compare token hashes in constant time where practical.
- Store only SHA-256 token hashes.
- Never put tokens in room state, push payloads, logs, exception messages, or
  analytics.
- Redact URL paths in backend request logging for `/invites/*`.
- Rate-limit preview, redemption, creation, and reset endpoints.
- Use HTTPS only.
- Verify administrator power at request time, not only at link creation.
- Make use-count checks and increments atomic.
- Set maximum expiry and usage limits to prevent abusive values.
- Limit active links per room and clean expired/revoked records.
- Revoke all room links when a room is deleted or invite management is reset.
- Rotate any backend credential that was exposed during development.

## 12. Delivery Phases

### Phase 0: Decisions and contracts

- Freeze product rules in Section 3.
- Define API request/response schemas and error codes.
- Decide beta persistence and production PostgreSQL migration point.
- Define use counting for approval links.

Exit gate: product and backend/client contracts are reviewed and versioned.

### Phase 1: Backend model and validation

- Add invite configuration and persistence repository.
- Add secure token generation and hashing.
- Add model validation, expiry, revoke, and limit logic.
- Add redacted request logging and rate-limit hooks.
- Add unit tests for token and record behavior.

Exit gate: tokens cannot be recovered from storage and invalid states are
rejected by tests.

### Phase 2: Backend management and redemption APIs

- Add `InviteEndpointModule` and server routing.
- Add health readiness reporting.
- Implement whoami and room-power authorization.
- Implement create/list/edit/reset/revoke.
- Implement preview and idempotent redemption.
- Integrate invite/knock membership paths.
- Add concurrency tests for final permitted use.

Exit gate: revoked, expired, exhausted, and unauthorized links cannot grant
membership.

### Phase 3: Flutter service and recipient flow

- Add API configuration, models, and service.
- Parse branded links and preserve login continuation.
- Add preview, join, approval, unavailable, and retry states.
- Sync and open only after successful backend redemption.
- Add widget and service tests.

Exit gate: private links cannot open by room ID without token validation.

### Phase 4: Administrator UI

- Update the shared group/channel invite screen.
- Add native sharing and compact QR/link layout.
- Add Manage Links and advanced-link creation.
- Preserve existing permission checks and room settings.

Exit gate: an administrator can create, share, inspect, reset, and revoke links
without exposing internal Matrix identifiers.

### Phase 5: App Links and website

- Add Android verified App Links.
- Publish `assetlinks.json`.
- Add the Netlify/web join fallback.
- Test installed, uninstalled, logged-out, and QR paths.

Exit gate: the same HTTPS URL works from browsers, QR scanners, messaging apps,
and an installed production-signed XMO build.

### Phase 6: Legacy migration

- Keep safe parsing of existing custom and `matrix.to` links.
- Stop generating room-ID-based links.
- Add telemetry using link type only, never token or room ID.
- Define and document the legacy support removal date.

Exit gate: old clients retain normal room compatibility and legacy links cannot
bypass private-room controls.

### Phase 7: Production verification

- Run backend format, analyze, compile, and tests in Docker.
- Run Flutter format checks, analyze, tests, and signed release build.
- Deploy to a staging homeserver and backend first.
- Run the complete acceptance matrix in Section 13.
- Roll out through Play Internal Testing before production.

Exit gate: all security and membership cases pass on at least two Android
devices and an Element compatibility client.

## 13. Required Test Matrix

### Link state

- Active primary link succeeds.
- Active additional link succeeds.
- Unknown, malformed, revoked, expired, and exhausted links fail.
- Reset invalidates the previous primary link immediately.
- Two simultaneous requests for the final use cannot both consume it.
- Reopening as an existing member is idempotent.

### Room behavior

- Public group direct join.
- Public group approval request.
- Private encrypted group direct invite/join.
- Private encrypted group approval request if supported.
- Public channel subscriber join.
- Private channel subscriber invite/join.
- Invite-only room refuses general-link bypass.
- Channel subscribers cannot gain posting power.
- A link never changes encryption, visibility, or room type.

### Account state

- Logged-in user.
- Logged-out user followed by successful login continuation.
- Existing member.
- Invited member.
- Kicked user.
- Banned user.
- Deactivated account.
- Creator who later loses administrator power.

### Navigation

- HTTPS link with XMO installed.
- HTTPS link without XMO installed.
- Link opened from browser, SMS, another messenger, and QR scanner.
- App cold start, background, and foreground.
- Network loss during preview and redemption.
- Repeated taps do not create duplicate navigation or membership requests.

### Compatibility and privacy

- Existing XMO client continues receiving room messages.
- Element can join through the resulting standard Matrix invitation where
  applicable.
- E2EE remains enabled for private rooms.
- Room history visibility matches policy after joining.
- Backend logs contain no raw token or access token.
- Crash reports and analytics contain no invite URL.

## 14. Rollout and Rollback

### Rollout

1. Deploy backend schema and inactive endpoints.
2. Verify Docker health and endpoint tests.
3. Publish website fallback and App Links metadata.
4. Release Flutter build to internal testers.
5. Enable new-link generation for test administrators.
6. Observe redemption errors, latency, and abuse rates without logging tokens.
7. Expand to beta, then production.

### Rollback

- Feature-flag new invite creation and redemption independently.
- If redemption fails broadly, disable new-link creation while preserving
  normal Matrix invitations and public discovery.
- Do not fall back from a failed private token to room-ID joining.
- Keep revoked tokens revoked across rollback and redeployment.

## 15. Expected Code Areas

### Flutter changes

- `lib/config/app_config.dart`
- `lib/models/invite_link_models.dart`
- `lib/services/invite_link_service.dart`
- `lib/services/invite_api_service.dart` (new)
- `lib/screens/shared/invite_link_view.dart`
- `lib/screens/group/invite_links_screen.dart`
- `lib/screens/channel/channel_invite_screen.dart`
- `lib/services/matrix_service.dart`
- `android/app/src/main/AndroidManifest.xml`
- release dart-define and CI configuration

### Backend changes

- `auth_server/bin/server.dart`
- `auth_server/lib/src/endpoint_modules.dart`
- `auth_server/lib/src/health_status.dart`
- `auth_server/lib/src/handlers/invite_handler.dart` (new)
- `auth_server/lib/src/invite_repository.dart` (new)
- `auth_server/test/invite_*_test.dart` (new)
- `auth_server/README.md` and environment examples

### Website and infrastructure

- Netlify `/join/:token` route/page
- `/.well-known/assetlinks.json`
- Caddy route for `/auth/invites/*` and public `/invites/*` where required
- PostgreSQL migration before broad production scale

## 16. Definition of Done

The invite-link feature is complete only when:

- New links contain no room identifier.
- Tokens are random, hashed at rest, and redacted from logs.
- Revocation, reset, expiry, and limits are enforced by the backend.
- Private membership cannot be obtained by decoding or editing a URL.
- Administrator authorization is checked against current room power levels.
- Direct and approval membership paths work for groups and channels.
- Branded HTTPS links open the installed app and provide a safe web fallback.
- Native sharing, copy, and QR flows work.
- Legacy links cannot bypass private-room rules.
- All tests in Section 13 pass on signed internal-test builds.
- Existing Matrix messaging, E2EE, room discovery, and old-client behavior remain
  operational.
