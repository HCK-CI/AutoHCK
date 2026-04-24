#!/usr/bin/env bash
# Example AutoHCK external notification hook.
# Environment: AUTOHCK_NOTIFICATION_HOOK and one variable per Ruby argument,
# e.g. AUTOHCK_NOTIFICATION_PROJECT holds JSON for the Project snapshot.

set -euo pipefail

log_default="${TMPDIR:-/tmp}/autohck_external_notification.log"
log_path="${AUTOHCK_NOTIFICATION_LOG_PATH:-$log_default}"

{
  printf '%s\n' "=== $(date -Iseconds 2>/dev/null || date) ==="
  env | LC_ALL=C sort | grep '^AUTOHCK_NOTIFICATION_' || true
  printf '\n'
} >>"$log_path"

exit 0
