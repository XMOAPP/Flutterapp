#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: run_with_timeout.sh <seconds> <log-file> <command> [args...]" >&2
  exit 64
fi

timeout_seconds="$1"
log_file="$2"
shift 2

mkdir -p "$(dirname "$log_file")"
set +e
timeout --signal=TERM --kill-after=30s "$timeout_seconds" "$@" 2>&1 | tee "$log_file"
status=${PIPESTATUS[0]}
set -e

if [[ $status -eq 124 || $status -eq 137 ]]; then
  echo "TIMEOUT: command exceeded ${timeout_seconds}s" | tee -a "$log_file" >&2
  ps -ef | grep -E '[d]art|[f]lutter|[g]radle|[j]ava' | tee -a "$log_file" || true
fi

exit "$status"
