#!/bin/bash
# Submit a Developer ID app to Apple's notary service and staple the ticket.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

ROOT=$(rlt_repo_root)
APP=""
PROFILE=""
OUTPUT_DIR="$ROOT/dist"

usage() {
  cat <<'EOF'
Usage: scripts/notarize-app.sh --app PATH --keychain-profile NAME [options]

The profile must already exist in Keychain (created with notarytool
store-credentials). This script never accepts or stores raw Apple secrets.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || rlt_die "--app requires a path"; APP="$2"; shift 2 ;;
    --keychain-profile) [ "$#" -ge 2 ] || rlt_die "--keychain-profile requires a value"; PROFILE="$2"; shift 2 ;;
    --output-dir) [ "$#" -ge 2 ] || rlt_die "--output-dir requires a path"; OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) rlt_die "unknown option: $1" ;;
  esac
done

[ -n "$APP" ] || rlt_die "--app is required"
[ -n "$PROFILE" ] || rlt_die "--keychain-profile is required"
[ -d "$APP" ] || rlt_die "app not found: $APP"
APP=$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")
case "$OUTPUT_DIR" in /*) ;; *) OUTPUT_DIR="$ROOT/$OUTPUT_DIR" ;; esac
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
[ "$(/usr/bin/stat -f '%d' "$APP")" = "$(/usr/bin/stat -f '%d' "$OUTPUT_DIR")" ] \
  || rlt_die "--app and --output-dir must be on the same volume for transactional notarization"
LOCK_DIR="$OUTPUT_DIR/.rlt-release.lock"
LOCK_HELD=0
WORK_DIR=""
STAGED_APP=""
STAGED_MANIFEST=""
STAGED_SUMS=""
FINAL_APP="$APP"
FINAL_MANIFEST="$OUTPUT_DIR/release-manifest.json"
FINAL_SUMS="$OUTPUT_DIR/SHA256SUMS"
BACKUP_APP=""
BACKUP_MANIFEST=""
BACKUP_SUMS=""
PROMOTION_STARTED=0
PROMOTION_COMPLETE=0
RESTORE_FAILED=0
PRESERVE_WORK_DIR=0

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

rollback_artifact() {
  local final_path="$1"
  local staged_path="$2"
  local backup_path="$3"

  if path_exists "$backup_path"; then
    if ! rm -rf "$final_path"; then
      printf 'error: failed to remove incomplete notarized artifact: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
      return
    fi
    if path_exists "$final_path"; then
      printf 'error: incomplete notarized artifact still exists after removal: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
      return
    fi
    if ! mv "$backup_path" "$final_path"; then
      printf 'error: failed to restore pre-notarization artifact; recovery data kept at %s\n' "$WORK_DIR" >&2
      RESTORE_FAILED=1
    fi
  elif ! path_exists "$staged_path" && path_exists "$final_path"; then
    if ! rm -rf "$final_path"; then
      printf 'error: failed to remove incomplete notarized artifact: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
    elif path_exists "$final_path"; then
      printf 'error: incomplete notarized artifact still exists after removal: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
    fi
  fi
}

cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  set +e
  if [ "$status" -ne 0 ] && [ "$PROMOTION_STARTED" -eq 1 ] && [ "$PROMOTION_COMPLETE" -eq 0 ]; then
    rollback_artifact "$FINAL_SUMS" "$STAGED_SUMS" "$BACKUP_SUMS"
    rollback_artifact "$FINAL_MANIFEST" "$STAGED_MANIFEST" "$BACKUP_MANIFEST"
    rollback_artifact "$FINAL_APP" "$STAGED_APP" "$BACKUP_APP"
  fi
  if [ "$RESTORE_FAILED" -eq 0 ]; then
    if [ -n "$WORK_DIR" ] && [ "$PRESERVE_WORK_DIR" -eq 0 ]; then
      if ! rm -rf "$WORK_DIR"; then
        printf 'error: failed to remove notary work directory: %s\n' "$WORK_DIR" >&2
        status=1
      elif path_exists "$WORK_DIR"; then
        printf 'error: notary work directory still exists after removal: %s\n' "$WORK_DIR" >&2
        status=1
      fi
    elif [ -n "$WORK_DIR" ] && [ "$PRESERVE_WORK_DIR" -eq 1 ]; then
      printf 'note: notary diagnostics retained at %s\n' "$WORK_DIR" >&2
      if [ "$status" -eq 0 ]; then
        printf 'error: refusing a successful exit while notary recovery data is retained\n' >&2
        status=1
      fi
    fi
    if [ "$LOCK_HELD" -eq 1 ]; then
      if ! rm -rf "$LOCK_DIR"; then
        printf 'error: failed to remove release lock: %s\n' "$LOCK_DIR" >&2
        status=1
      elif path_exists "$LOCK_DIR"; then
        printf 'error: release lock still exists after removal: %s\n' "$LOCK_DIR" >&2
        status=1
      fi
    fi
  else
    printf 'error: release lock retained for manual recovery: %s\n' "$LOCK_DIR" >&2
    printf 'error: notary recovery data retained at %s\n' "$WORK_DIR" >&2
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! mkdir "$LOCK_DIR"; then
  rlt_die "another release operation is active (or stale lock exists): $LOCK_DIR"
fi
LOCK_HELD=1
printf '%s\n' "$$" > "$LOCK_DIR/pid"

"$SCRIPT_DIR/verify-app.sh" \
  --app "$APP" \
  --sign developer-id \
  --arch "$(rlt_arch_label "$APP/Contents/MacOS/RateLimitTomato")" \
  --require-release

WORK_DIR=$(mktemp -d "$OUTPUT_DIR/.rlt-notary.XXXXXX")
STAGED_APP="$WORK_DIR/RateLimitTomato.app"
SUBMISSION_ZIP="$WORK_DIR/RateLimitTomato-notary.zip"
RESPONSE="$WORK_DIR/notary-response.json"
STAGED_MANIFEST="$WORK_DIR/release-manifest.json"
STAGED_SUMS="$WORK_DIR/SHA256SUMS"
BACKUP_APP="$WORK_DIR/previous-RateLimitTomato.app"
BACKUP_MANIFEST="$WORK_DIR/previous-release-manifest.json"
BACKUP_SUMS="$WORK_DIR/previous-SHA256SUMS"

rlt_note "copying app into the notarization transaction"
/usr/bin/ditto "$APP" "$STAGED_APP"
STAGED_ARCH=$(rlt_arch_label "$STAGED_APP/Contents/MacOS/RateLimitTomato")
"$SCRIPT_DIR/verify-app.sh" \
  --app "$STAGED_APP" \
  --sign developer-id \
  --arch "$STAGED_ARCH" \
  --require-release

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$SUBMISSION_ZIP"
PRESERVE_WORK_DIR=1
rlt_note "submitting app to Apple notary service"
if ! /usr/bin/xcrun notarytool submit \
  --keychain-profile "$PROFILE" \
  --wait \
  --output-format json \
  "$SUBMISSION_ZIP" > "$RESPONSE"; then
  rlt_die "notary submission failed; diagnostics retained at $WORK_DIR"
fi

STATUS=$(/usr/bin/plutil -extract status raw -o - "$RESPONSE")
SUBMISSION_ID=$(/usr/bin/plutil -extract id raw -o - "$RESPONSE")
DIAGNOSTIC_RESPONSE="$OUTPUT_DIR/notarization-$SUBMISSION_ID.json"
mv "$RESPONSE" "$DIAGNOSTIC_RESPONSE"
if [ "$STATUS" != "Accepted" ]; then
  STAGED_LOG="$WORK_DIR/notarization-$SUBMISSION_ID.log.json"
  FINAL_LOG="$OUTPUT_DIR/notarization-$SUBMISSION_ID.log.json"
  if /usr/bin/xcrun notarytool log \
    --keychain-profile "$PROFILE" \
    "$SUBMISSION_ID" \
    "$STAGED_LOG"; then
    mv "$STAGED_LOG" "$FINAL_LOG"
    PRESERVE_WORK_DIR=0
  else
    printf 'warning: failed to retrieve notary log; diagnostics retained at %s\n' "$WORK_DIR" >&2
  fi
  rlt_die "notarization status is $STATUS (submission $SUBMISSION_ID)"
fi

rlt_note "stapling accepted ticket into staged app"
/usr/bin/xcrun stapler staple "$STAGED_APP"
/usr/bin/xcrun stapler validate "$STAGED_APP"
/usr/sbin/spctl --assess --type execute --verbose=4 "$STAGED_APP"
"$SCRIPT_DIR/verify-app.sh" \
  --app "$STAGED_APP" \
  --sign developer-id \
  --arch "$STAGED_ARCH" \
  --require-release
"$SCRIPT_DIR/release-manifest.sh" \
  --app "$STAGED_APP" \
  --sign developer-id \
  --output "$STAGED_MANIFEST"

PROMOTION_STARTED=1
if path_exists "$FINAL_APP"; then
  mv "$FINAL_APP" "$BACKUP_APP"
fi
if path_exists "$FINAL_MANIFEST"; then
  mv "$FINAL_MANIFEST" "$BACKUP_MANIFEST"
fi
if path_exists "$FINAL_SUMS"; then
  mv "$FINAL_SUMS" "$BACKUP_SUMS"
fi
mv "$STAGED_APP" "$FINAL_APP"
mv "$STAGED_MANIFEST" "$FINAL_MANIFEST"
mv "$STAGED_SUMS" "$FINAL_SUMS"
PROMOTION_COMPLETE=1
PRESERVE_WORK_DIR=0
rlt_note "notarization accepted and stapled (submission $SUBMISSION_ID)"
