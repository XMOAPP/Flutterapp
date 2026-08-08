# XMO Authentik Branding

Use `xmo-brand.css` in Authentik's Brand settings to make the secure sign-in
pages look like XMO and reduce visible Authentik branding.

## Install

In Authentik admin:

1. Open **System -> Brands**.
2. Edit the brand for `auth.xmo.dpdns.org`.
3. Set:
   - **Branding title**: `XMO`
   - **Domain**: `auth.xmo.dpdns.org`
   - **Default application**: `XMO`
4. Upload/select the same XMO logo used by the website:
   `https://xmo.dpdns.org/img/cropped_circle_image%281%29%281%29.png`
5. Use the website favicon:
   `https://xmo.dpdns.org/favicon.png`
6. Paste `xmo-brand.css` into **Custom CSS**.
7. Save and test in a private browser window.

Also edit the XMO application:

1. Open **Applications -> Applications -> XMO**.
2. Set **Launch URL** to `https://xmo.dpdns.org/`.
3. Keep the provider as the existing XMO Matrix OIDC provider.
