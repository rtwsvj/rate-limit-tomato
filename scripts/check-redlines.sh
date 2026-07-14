#!/bin/bash
# Enforce the immutable product red lines against runtime source and an optional app.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

ROOT=$(rlt_repo_root)
APP=""

usage() {
  cat <<'EOF'
Usage: scripts/check-redlines.sh [--app PATH]

Checks runtime source for networking/payment APIs and real vendor marks. When an
app is supplied, also scans user-visible strings in the final executable.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      [ "$#" -ge 2 ] || rlt_die "--app requires a path"
      APP="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) rlt_die "unknown option: $1" ;;
  esac
done

rlt_require_command rg

scan_runtime_source() {
  local label="$1"
  local pattern="$2"
  local matches

  matches=$(rg -n -i "$pattern" "$ROOT/Sources" \
    | /usr/bin/awk '
      {
        text=$0
        sub(/^[^:]+:[0-9]+:/, "", text)
        if (text !~ /^[[:space:]]*\/\//) print $0
      }
    ' || true)
  if [ -n "$matches" ]; then
    printf '%s\n' "$matches" >&2
    rlt_die "$label red-line scan failed"
  fi
}

scan_runtime_source "networking" \
  'URLSession|URLRequest|NWConnection|NWPathMonitor|WebSocket|CFNetwork|import[[:space:]]+Network|https?://'
scan_runtime_source "payment" \
  'import[[:space:]]+StoreKit|SKPayment|Product\.purchase|Stripe|PayPal|checkout\.session|paymentIntent'
scan_runtime_source "vendor mark" \
  'Claude|Anthropic|OpenAI|ChatGPT|Codex'

rg -q '"error\.parody_disclaimer"' "$ROOT/Sources/TomatoCore/I18n/L10n.swift" \
  || rlt_die "permanent disclaimer key is missing from L10n"
rg -q 'L10n\.t\("error\.parody_disclaimer"' "$ROOT/Sources/RateLimitTomatoUI/Views/Sheets.swift" \
  || rlt_die "upgrade/disclaimer surfaces no longer render the permanent disclaimer"

if [ -n "$APP" ]; then
  BINARY="$APP/Contents/MacOS/RateLimitTomato"
  [ -x "$BINARY" ] || rlt_die "app executable missing: $BINARY"
  STRINGS_FILE=$(mktemp "${TMPDIR:-/tmp}/rlt-strings.XXXXXX")
  trap 'rm -f "$STRINGS_FILE"' EXIT HUP INT TERM
  /usr/bin/strings "$BINARY" > "$STRINGS_FILE"
  if /usr/bin/grep -Eqi 'Claude|Anthropic|OpenAI|ChatGPT|Codex' "$STRINGS_FILE"; then
    /usr/bin/grep -Ein 'Claude|Anthropic|OpenAI|ChatGPT|Codex' "$STRINGS_FILE" >&2 || true
    rlt_die "final executable contains a real vendor mark"
  fi
  if /usr/bin/grep -Eqi 'https?://(buy|checkout|pay|billing)' "$STRINGS_FILE"; then
    /usr/bin/grep -Ein 'https?://(buy|checkout|pay|billing)' "$STRINGS_FILE" >&2 || true
    rlt_die "final executable contains a payment URL"
  fi
fi

rlt_note "product red lines OK"

