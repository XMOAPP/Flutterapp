# XMO Account 2FA Deployment

## Scope

XMO's existing password login goes directly to Synapse. A Flutter-only code
prompt would not protect the account because another Matrix client could submit
the password directly. Account two-factor authentication must therefore be
enforced by the homeserver's sign-in provider.

The app includes an opt-in Synapse SSO client flow. It is disabled by default
and does not change current password, wallet, email OTP, App Lock, device
session, encryption, or recovery behavior.

## Recommended provider

Deploy [Authentik](https://goauthentik.io/) at a dedicated HTTPS origin such as
`https://auth.xmo.example`. Enable its password, TOTP authenticator, recovery
codes, and optionally passkeys/WebAuthn. Authentik is self-hosted software; it
does not charge per OTP. It still needs a backed-up database, CPU/RAM, TLS, and
ongoing updates.

Use the official Authentik Docker installation instructions. Do not add the
Authentik database or secrets to this repository.

## Synapse configuration

Configure an OIDC provider in the real VPS `homeserver.yaml`. Values below are
examples and must be replaced with deployment secrets:

```yaml
oidc_providers:
  - idp_id: authentik
    idp_name: XMO secure sign-in
    discover: true
    issuer: "https://auth.xmo.example/application/o/xmo/"
    client_id: "replace-with-authentik-client-id"
    client_secret: "replace-with-authentik-client-secret"
    scopes: ["openid", "profile", "email"]
    allow_existing_users: true
    user_profile_method: userinfo_endpoint
    user_mapping_provider:
      config:
        subject_claim: sub
        localpart_template: "{{ user.preferred_username }}"
        display_name_template: "{{ user.name|default(user.preferred_username) }}"
        email_template: "{{ user.email }}"
```

In Authentik, set the redirect URI exactly to:

```text
https://xmo-matrix.centralindia.cloudapp.azure.com/_synapse/client/oidc/callback
```

The `preferred_username` of each existing Authentik account must equal its
existing Matrix localpart. For example, Matrix user `@hunter:server` must map
to Authentik `hunter`. Test this mapping with one non-admin account before
enabling it for production users.

## Automatic secure sign-in provisioning

For new XMO registrations, `xmo-auth` can create the matching Authentik user
after Matrix registration succeeds. This lets new users register once in XMO
and then use **Continue with secure sign-in** without manual admin work.

Create an Authentik API token for a service account with permission to manage
users. Add these values to `/opt/xmo/auth.env` on the VM:

```dotenv
XMO_AUTHENTIK_BASE_URL=https://auth.xmo.dpdns.org
XMO_AUTHENTIK_API_TOKEN=replace-with-authentik-service-token
XMO_AUTHENTIK_USER_PATH=users
```

Then rebuild/restart only the auth service:

```bash
cd /opt/xmo
docker compose build xmo-auth
docker compose up -d xmo-auth
docker compose logs --tail=80 xmo-auth
```

After email OTP verification, the backend returns a short-lived, one-use
enrollment proof. The app calls `/auth/otp/users/provision-secure-login` after
Matrix registration and submits that proof. The backend verifies the Matrix
access token with Synapse, binds the proof to the verified email, and consumes
it before creating or updating the Authentik account. Passwords are never sent
through the public profile or user-directory upsert endpoint.

If Authentik is temporarily unavailable, Matrix registration still completes
and the app offers Retry or Continue for now. A transient provider failure
restores the unexpired proof so Retry is safe.

Password resets also update the Authentik password best-effort. Account
deletion deactivates the Authentik user best-effort.

## Safe rollout

1. Back up the Synapse PostgreSQL database and `homeserver.yaml`.
2. Deploy Authentik, create the OIDC application, and require TOTP plus
   recovery-code enrollment in its login flow.
3. Add the OIDC configuration to a staging Synapse first. Verify SSO on a
   clean XMO install and another Matrix client.
4. Add the production Synapse OIDC config, restart Synapse, and confirm
   `GET /_matrix/client/v3/login` advertises `m.login.sso`.
5. Build XMO with the flags below. Existing password sign-in remains available
   during migration.
6. Configure automatic secure sign-in provisioning for new registrations.
7. Migrate existing users one at a time. Verify each account can sign in
   through the secure flow and has stored recovery codes.
8. Only after every active user has migrated, disable local password login in
   Synapse:

```yaml
password_config:
  enabled: false
  localdb_enabled: false
```

Do not disable password login before validating an administrator recovery path.
Keep a break-glass admin procedure documented outside this repository.

## XMO build flags

After Synapse OIDC works, add these to XMO builds:

```powershell
--dart-define=XMO_ENABLE_SSO_LOGIN=true `
--dart-define=XMO_SSO_IDP_ID=oidc-authentik `
--dart-define=XMO_SSO_CALLBACK_URL=https://xmo.dpdns.org/auth/callback `
--dart-define=XMO_MFA_SETUP_URL=https://auth.xmo.dpdns.org/if/flow/xmo-totp-setup/
```

Use the exact identity-provider ID advertised by
`GET /_matrix/client/v3/login`. In the current deployment that ID is
`oidc-authentik`.

XMO opens Synapse's SSO redirect in the browser. On success it accepts only the
verified `https://xmo.dpdns.org/auth/callback` Android App Link with its
matching one-time state value, then exchanges the returned Matrix `loginToken`
through `m.login.token`. The legacy `xmo://auth/callback` is disabled unless a
temporary build explicitly sets `XMO_ENABLE_LEGACY_SSO_CALLBACK=true`.

Add the callback to Synapse before distributing the new app:

```yaml
sso:
  client_whitelist:
    - "https://xmo.dpdns.org/auth/callback"
  update_profile_information: true
```

Publish `/.well-known/assetlinks.json` on `xmo.dpdns.org` with the Google Play
**app-signing** SHA-256 fingerprint, not the local upload-key fingerprint:

```powershell
.\tools\prepare_netlify_invite.ps1 `
  -PlaySigningSha256 "AA:BB:...:FF"
```

Deploy the generated `build/netlify-invite` contents to the root of the XMO
website and verify both URLs return HTTP 200:

```text
https://xmo.dpdns.org/.well-known/assetlinks.json
https://xmo.dpdns.org/auth/callback
```

The Security screen also exposes a branded **Set up authenticator** action.
By default it opens:

```powershell
--dart-define=XMO_MFA_SETUP_URL=https://auth.xmo.dpdns.org/if/flow/xmo-totp-setup/
```

Create an Authentik flow with slug `xmo-totp-setup` and bind a TOTP
Authenticator Setup stage to it. A setup stage only enrolls TOTP; also bind an
Authenticator Validation stage into the login flow to enforce the six-digit
code during secure sign-in. Until the setup flow exists, temporarily point
`XMO_MFA_SETUP_URL` at `https://auth.xmo.dpdns.org/if/user/`.

## Verification checklist

1. Login with correct password but no TOTP code: provider must reject it.
2. Login with correct TOTP: XMO must return to the app and create a new Matrix
   session.
3. Cancel browser login: XMO must not create a session.
4. Alter callback state or token: XMO must reject it.
5. Test recovery codes once, then rotate them.
6. Test a second Matrix client after the final password-login shutdown.
7. Confirm an existing user retains rooms, encryption keys, and device history.
8. Verify Android App Links on a Play-installed build; a sideloaded build uses
   a different signing certificate and is not proof of Play association.
