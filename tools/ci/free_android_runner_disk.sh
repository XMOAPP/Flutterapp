#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_ACTIONS:-}" != "true" || "${RUNNER_OS:-}" != "Linux" ]]; then
  echo "Refusing to clean disk outside a GitHub-hosted Linux runner." >&2
  exit 1
fi

echo "Disk usage before Android runner cleanup:"
df -h /

# These large SDKs are preinstalled on ubuntu-latest but are unrelated to XMO.
sudo rm -rf -- /usr/share/dotnet /opt/ghc /usr/local/share/boost

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -n "$sdk_root" && "$sdk_root" == /usr/local/lib/android/sdk ]]; then
  # Keep Android command-line tools, while replacing bulky images and NDKs with
  # the exact versions selected by Flutter and the smoke-test workflow.
  sudo rm -rf -- "$sdk_root/ndk" "$sdk_root/system-images"
fi

sudo apt-get clean
docker system prune --all --force >/dev/null 2>&1 || true

echo "Disk usage after Android runner cleanup:"
df -h /

