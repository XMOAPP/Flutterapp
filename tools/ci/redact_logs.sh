#!/usr/bin/env bash
set -euo pipefail

for log_file in "$@"; do
  [[ -f "$log_file" ]] || continue
  sed -E -i \
    -e 's/(access[_-]?token|authorization|api[_-]?key|password|secret)([[:space:]]*[=:][[:space:]]*)[^[:space:],;"}]+/\1\2<redacted>/Ig' \
    -e 's/syt_[A-Za-z0-9._~-]+/<redacted-matrix-token>/g' \
    "$log_file"
done
