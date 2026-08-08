# XMO Synapse SSO Branding

These files customize Synapse browser pages used during SSO. They do not change
Matrix login, encryption, rooms, media, or OIDC token handling.

## Install

On the VM:

```bash
cd /opt/xmo
sudo mkdir -p /opt/xmo/synapse/templates
sudo cp /path/to/sso_redirect_confirm.html /opt/xmo/synapse/templates/sso_redirect_confirm.html
```

In `/opt/xmo/synapse/homeserver.yaml`, add or merge:

```yaml
templates:
  custom_template_directory: /data/templates

sso:
  client_whitelist:
    - https://xmo.dpdns.org/auth/callback
  update_profile_information: true
```

Restart Synapse:

```bash
cd /opt/xmo
docker compose restart synapse
```

The template uses the public website logo and chat pattern from
`https://xmo.dpdns.org/`.

For the XMO mobile app, `client_whitelist` should skip the Synapse confirmation
page entirely. The template remains useful for fallback/browser flows and keeps
the page branded as XMO instead of Matrix.
