#!/bin/bash
# Safe packaged-app smoke test: isolated data, no notification permission prompt,
# no login-item mutation, and no persistent LaunchServices registration.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

APP=""
DURATION=4

usage() {
  cat <<'EOF'
Usage: scripts/smoke-app.sh --app PATH [--duration SECONDS]

The complete signed app is copied into a temporary runtime so its Developer ID
signature remains valid. RLT_DISABLE_GLOBAL_INTEGRATIONS=1 suppresses notification,
shortcut, and URL integrations while still proving that the packaged app launches
and stays alive. macOS may discover the temporary bundle even on a direct binary
launch, so this script unregisters that exact temporary path before cleanup. Full
LaunchServices/UI checks remain manual release checks.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || rlt_die "--app requires a path"; APP="$2"; shift 2 ;;
    --duration) [ "$#" -ge 2 ] || rlt_die "--duration requires seconds"; DURATION="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) rlt_die "unknown option: $1" ;;
  esac
done

[ -n "$APP" ] || rlt_die "--app is required"
[ -d "$APP" ] || rlt_die "app not found: $APP"
printf '%s\n' "$DURATION" | /usr/bin/grep -Eq '^[1-9][0-9]*$' \
  || rlt_die "duration must be a positive integer"

SIGN_MODE=$(rlt_detect_sign_mode "$APP")
ARCH_MODE=$(rlt_arch_label "$APP/Contents/MacOS/RateLimitTomato")
"$SCRIPT_DIR/verify-app.sh" --app "$APP" --sign "$SIGN_MODE" --arch "$ARCH_MODE"

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rlt-safe-smoke.XXXXXX")
# LaunchServices canonicalizes /var to /private/var. Use the physical path so the
# exact-path verification below cannot miss a registration because of that alias.
WORK_DIR=$(cd "$WORK_DIR" && pwd -P)
RUNTIME_APP="$WORK_DIR/RateLimitTomato.app"
RUNTIME_BINARY="$RUNTIME_APP/Contents/MacOS/RateLimitTomato"
RUNTIME_TMP="$WORK_DIR/tmp"
RUNTIME_HOME="$WORK_DIR/home"
LOG="$WORK_DIR/process.log"
BEFORE="$WORK_DIR/production-before.txt"
AFTER="$WORK_DIR/production-after.txt"
LS_DUMP="$WORK_DIR/launchservices-after.txt"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PID=""
RUNTIME_UNREGISTERED=0
UNREGISTER_FAILED=0

snapshot_production_data() {
  local destination="$1"
  local production="$HOME/Library/Application Support/RateLimitTomato"
  if [ -d "$production" ]; then
    /usr/bin/find "$production" -type f -exec /usr/bin/shasum -a 256 {} \; \
      | LC_ALL=C /usr/bin/sort > "$destination"
  else
    printf 'ABSENT\n' > "$destination"
  fi
}

unregister_runtime_app() {
  local unregister_status=0

  if [ ! -x "$LSREGISTER" ]; then
    printf 'LaunchServices tool is unavailable: %s\n' "$LSREGISTER" >&2
    return 1
  fi

  "$LSREGISTER" -u "$RUNTIME_APP" >/dev/null 2>&1 || unregister_status=$?
  if ! "$LSREGISTER" -dump > "$LS_DUMP"; then
    printf 'could not inspect LaunchServices after unregistering: %s\n' "$RUNTIME_APP" >&2
    return 1
  fi
  if /usr/bin/awk -v target="$RUNTIME_APP" '
      index($0, target) { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$LS_DUMP"; then
    printf 'temporary app is still registered with LaunchServices: %s\n' "$RUNTIME_APP" >&2
    return 1
  fi
  if [ "$unregister_status" -ne 0 ]; then
    rlt_note "LaunchServices unregister returned ${unregister_status}, but the exact temporary path is absent"
  fi
}

cleanup() {
  local status="$1"
  trap - EXIT HUP INT TERM
  set +e
  if [ -n "$PID" ] && /bin/kill -0 "$PID" >/dev/null 2>&1; then
    /bin/kill -TERM "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
  if [ "$RUNTIME_UNREGISTERED" -eq 0 ] && [ "$UNREGISTER_FAILED" -eq 0 ] \
     && [ -d "$RUNTIME_APP" ]; then
    if unregister_runtime_app; then
      RUNTIME_UNREGISTERED=1
    else
      UNREGISTER_FAILED=1
      status=1
    fi
  fi
  if [ "$status" -ne 0 ] && [ -f "$LOG" ]; then
    printf '%s\n' '--- smoke process log ---' >&2
    /bin/cat "$LOG" >&2
  fi
  if [ "$UNREGISTER_FAILED" -ne 0 ]; then
    printf 'temporary runtime preserved for exact-path recovery: %s\n' "$RUNTIME_APP" >&2
  else
    if ! rm -rf "$WORK_DIR"; then
      printf 'could not remove temporary smoke directory: %s\n' "$WORK_DIR" >&2
      status=1
    elif [ -e "$WORK_DIR" ] || [ -L "$WORK_DIR" ]; then
      printf 'temporary smoke directory still exists after removal: %s\n' "$WORK_DIR" >&2
      status=1
    fi
  fi
  exit "$status"
}
trap 'cleanup $?' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$RUNTIME_TMP" "$RUNTIME_HOME"
/usr/bin/ditto "$APP" "$RUNTIME_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$RUNTIME_APP"
snapshot_production_data "$BEFORE"

rlt_note "launching isolated packaged binary for ${DURATION}s"
HOME="$RUNTIME_HOME" \
TMPDIR="$RUNTIME_TMP" \
RLT_TIME_SCALE=600 \
RLT_DISABLE_GLOBAL_INTEGRATIONS=1 \
  "$RUNTIME_BINARY" > "$LOG" 2>&1 &
PID=$!

ELAPSED=0
while [ "$ELAPSED" -lt "$DURATION" ]; do
  /bin/sleep 1
  if ! /bin/kill -0 "$PID" >/dev/null 2>&1; then
    wait "$PID" || true
    rlt_die "packaged binary exited before the smoke window completed"
  fi
  ELAPSED=$((ELAPSED + 1))
done

if /usr/sbin/lsof -a -p "$PID" -i -n -P 2>/dev/null | /usr/bin/grep -v '^COMMAND' >/dev/null; then
  /usr/sbin/lsof -a -p "$PID" -i -n -P >&2 || true
  rlt_die "packaged binary opened a network socket during smoke test"
fi

/bin/kill -TERM "$PID"
wait "$PID" >/dev/null 2>&1 || true
PID=""
snapshot_production_data "$AFTER"
/usr/bin/cmp -s "$BEFORE" "$AFTER" || rlt_die "production data changed during isolated smoke test"

if ! unregister_runtime_app; then
  UNREGISTER_FAILED=1
  rlt_die "could not remove the temporary LaunchServices registration"
fi
RUNTIME_UNREGISTERED=1

rlt_note "safe smoke passed: process health, zero sockets, production data unchanged, temporary LaunchServices path removed"
