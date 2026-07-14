#!/bin/bash
# Create, re-extract, and verify a distributable zip before locked promotion.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

ROOT=$(rlt_repo_root)
APP=""
LABEL="auto"
OUTPUT_DIR="$ROOT/dist"

usage() {
  cat <<'EOF'
Usage: scripts/archive-app.sh --app PATH [options]

Options:
  --label auto|unsigned|adhoc|developer-id|notarized
  --output-dir PATH
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || rlt_die "--app requires a path"; APP="$2"; shift 2 ;;
    --label) [ "$#" -ge 2 ] || rlt_die "--label requires a value"; LABEL="$2"; shift 2 ;;
    --output-dir) [ "$#" -ge 2 ] || rlt_die "--output-dir requires a path"; OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) rlt_die "unknown option: $1" ;;
  esac
done

[ -n "$APP" ] || rlt_die "--app is required"
[ -d "$APP" ] || rlt_die "app not found: $APP"
case "$LABEL" in auto|unsigned|adhoc|developer-id|notarized) ;; *) rlt_die "invalid label: $LABEL" ;; esac

SIGN_MODE=$(rlt_detect_sign_mode "$APP")
case "$SIGN_MODE" in none|adhoc|developer-id) ;; *) rlt_die "unsupported app signature" ;; esac
if [ "$LABEL" = "auto" ]; then
  case "$SIGN_MODE" in none) LABEL=unsigned ;; *) LABEL="$SIGN_MODE" ;; esac
fi
case "$LABEL:$SIGN_MODE" in
  unsigned:none|adhoc:adhoc|developer-id:developer-id|notarized:developer-id) ;;
  *) rlt_die "archive label $LABEL does not match app signature $SIGN_MODE" ;;
esac
if [ "$LABEL" = "notarized" ]; then
  /usr/bin/xcrun stapler validate "$APP" >/dev/null \
    || rlt_die "notarized label requires a valid stapled ticket"
fi

VERSION=$(rlt_read_version "$ROOT")
ARCH_LABEL=$(rlt_arch_label "$APP/Contents/MacOS/RateLimitTomato")
case "$OUTPUT_DIR" in /*) ;; *) OUTPUT_DIR="$ROOT/$OUTPUT_DIR" ;; esac
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
FINAL_ARCHIVE="$OUTPUT_DIR/RateLimitTomato-v$VERSION-macOS-$ARCH_LABEL-$LABEL.zip"
WORK_DIR=$(mktemp -d "$OUTPUT_DIR/.rlt-archive.XXXXXX")
STAGED_ARCHIVE="$WORK_DIR/$(basename "$FINAL_ARCHIVE")"
EXTRACT_DIR="$WORK_DIR/extracted"
STAGED_MANIFEST="$WORK_DIR/release-manifest.json"
STAGED_SUMS="$WORK_DIR/SHA256SUMS"
FINAL_MANIFEST="$OUTPUT_DIR/release-manifest.json"
FINAL_SUMS="$OUTPUT_DIR/SHA256SUMS"
BACKUP_ARCHIVE="$WORK_DIR/previous-$(basename "$FINAL_ARCHIVE")"
BACKUP_MANIFEST="$WORK_DIR/previous-release-manifest.json"
BACKUP_SUMS="$WORK_DIR/previous-SHA256SUMS"
LOCK_DIR="$OUTPUT_DIR/.rlt-release.lock"
LOCK_HELD=0
PROMOTION_STARTED=0
PROMOTION_COMPLETE=0
RESTORE_FAILED=0

rollback_artifact() {
  local final_path="$1"
  local staged_path="$2"
  local backup_path="$3"

  if [ -e "$backup_path" ]; then
    if ! rm -rf "$final_path"; then
      printf 'error: failed to remove incomplete release artifact: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
      return
    fi
    if [ -e "$final_path" ] || [ -L "$final_path" ]; then
      printf 'error: incomplete release artifact still exists after removal: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
      return
    fi
    if ! mv "$backup_path" "$final_path"; then
      printf 'error: failed to restore release artifact; recovery data kept at %s\n' "$WORK_DIR" >&2
      RESTORE_FAILED=1
    fi
  elif [ ! -e "$staged_path" ] && [ -e "$final_path" ]; then
    if ! rm -rf "$final_path"; then
      printf 'error: failed to remove incomplete release artifact: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
    elif [ -e "$final_path" ] || [ -L "$final_path" ]; then
      printf 'error: incomplete release artifact still exists after removal: %s\n' "$final_path" >&2
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
    rollback_artifact "$FINAL_ARCHIVE" "$STAGED_ARCHIVE" "$BACKUP_ARCHIVE"
  fi
  if [ "$RESTORE_FAILED" -eq 0 ]; then
    if ! rm -rf "$WORK_DIR"; then
      printf 'error: failed to remove release work directory: %s\n' "$WORK_DIR" >&2
      status=1
    elif [ -e "$WORK_DIR" ] || [ -L "$WORK_DIR" ]; then
      printf 'error: release work directory still exists after removal: %s\n' "$WORK_DIR" >&2
      status=1
    fi
    if [ "$LOCK_HELD" -eq 1 ]; then
      if ! rm -rf "$LOCK_DIR"; then
        printf 'error: failed to remove release lock: %s\n' "$LOCK_DIR" >&2
        status=1
      elif [ -e "$LOCK_DIR" ] || [ -L "$LOCK_DIR" ]; then
        printf 'error: release lock still exists after removal: %s\n' "$LOCK_DIR" >&2
        status=1
      fi
    fi
  else
    printf 'error: release lock retained for manual recovery: %s\n' "$LOCK_DIR" >&2
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

verify_archive_app() {
  local target_app="$1"
  if [ "$LABEL" = "developer-id" ] || [ "$LABEL" = "notarized" ]; then
    "$SCRIPT_DIR/verify-app.sh" \
      --app "$target_app" \
      --sign "$SIGN_MODE" \
      --arch "$ARCH_LABEL" \
      --require-release
  else
    "$SCRIPT_DIR/verify-app.sh" \
      --app "$target_app" \
      --sign "$SIGN_MODE" \
      --arch "$ARCH_LABEL"
  fi
}

verify_archive_app "$APP"
rlt_note "creating staged archive"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGED_ARCHIVE"
/usr/bin/unzip -tq "$STAGED_ARCHIVE" >/dev/null
mkdir -p "$EXTRACT_DIR"
/usr/bin/ditto -x -k "$STAGED_ARCHIVE" "$EXTRACT_DIR"
verify_archive_app "$EXTRACT_DIR/RateLimitTomato.app"
if [ "$LABEL" = "notarized" ]; then
  /usr/bin/xcrun stapler validate "$EXTRACT_DIR/RateLimitTomato.app" >/dev/null \
    || rlt_die "stapled ticket did not survive archive round-trip"
fi
"$SCRIPT_DIR/check-version.sh" --app "$APP" --archive "$STAGED_ARCHIVE"
"$SCRIPT_DIR/release-manifest.sh" \
  --app "$APP" \
  --archive "$STAGED_ARCHIVE" \
  --sign "$SIGN_MODE" \
  --output "$STAGED_MANIFEST"

PROMOTION_STARTED=1
if [ -e "$FINAL_ARCHIVE" ]; then
  mv "$FINAL_ARCHIVE" "$BACKUP_ARCHIVE"
fi
if [ -e "$FINAL_MANIFEST" ]; then
  mv "$FINAL_MANIFEST" "$BACKUP_MANIFEST"
fi
if [ -e "$FINAL_SUMS" ]; then
  mv "$FINAL_SUMS" "$BACKUP_SUMS"
fi
mv "$STAGED_ARCHIVE" "$FINAL_ARCHIVE"
mv "$STAGED_MANIFEST" "$FINAL_MANIFEST"
mv "$STAGED_SUMS" "$FINAL_SUMS"
PROMOTION_COMPLETE=1
rm -f "$BACKUP_ARCHIVE" "$BACKUP_MANIFEST" "$BACKUP_SUMS"
rlt_note "verified archive: $FINAL_ARCHIVE"
