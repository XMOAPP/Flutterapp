# Streaming Release Verification Checklist

Use this checklist before shipping a build with media streaming enabled.

## Build Configuration

- Build/run with production Matrix values:
  - `XMO_HOMESERVER_URL=https://xmo-matrix.centralindia.cloudapp.azure.com`
  - `XMO_MATRIX_SERVER_NAME=xmo-matrix.centralindia.cloudapp.azure.com`
- If Azure chunk storage is enabled, include both:
  - `XMO_STREAM_CHUNK_STORAGE=azure`
  - `XMO_AZURE_CHUNK_SIGN_URL=https://xmo-matrix.centralindia.cloudapp.azure.com/auth/media/chunks/azure/sign-upload`
- Confirm the backend health endpoint reports `azureBlob:"ready"` before testing Azure chunk uploads.

## Required Playback Paths

| Scenario | Expected path | Expected wording |
| --- | --- | --- |
| Public group/channel unencrypted video | Direct Matrix authenticated URL stream | `Loading video...` |
| Public group/channel unencrypted audio | Direct Matrix authenticated URL stream | No full-file download prompt |
| Private encrypted video with valid `xmo_stream` | Local loopback secure stream | `Preparing secure video...` |
| Private encrypted video without `xmo_stream` | Existing Matrix decrypt-to-temp-file fallback | `Opening...` |
| Files/PDFs/unsupported media | Existing open/download behavior | `Opening...` or explicit download wording |
| Any streaming failure | Existing Matrix fallback | No crash, no stuck snackbar |

## Device Regression Tests

Test on a real Android device:

- Public channel video opens quickly and seek works.
- Public group video opens quickly and seek works.
- Private encrypted small video still opens through fallback.
- Private encrypted large video with `xmo_stream` starts before the full file is downloaded.
- Seek forward/backward in an encrypted streamed video.
- Close the player while streaming; temporary chunks are cleaned later.
- Start the same video twice; duplicate downloads should be avoided.
- Turn network off mid-playback; the player should fail gracefully or retry, then fall back when needed.
- Send and open a PDF/file; it must not use video streaming.

## Security Checks

- Matrix access tokens must be sent only in HTTP headers, never URL query strings.
- Local playback proxy must bind only to `127.0.0.1`.
- Local playback URLs must include an unguessable token.
- The proxy must support `GET`, `HEAD`, `Range`, `206`, and invalid-range `416`.
- Decrypted chunks must stay in temporary app storage and be cleaned by cache expiry.
- Azure stores encrypted chunk bytes only; Azure account keys stay backend-only.
- Normal Matrix media fields remain present for Element and old XMO compatibility.
