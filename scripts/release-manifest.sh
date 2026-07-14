#!/bin/bash
# Generate traceability metadata and SHA256SUMS for a packaged app/archive.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

ROOT=$(rlt_repo_root)
APP=""
ARCHIVE=""
SIGN_MODE="auto"
OUTPUT=""

usage() {
  cat <<'EOF'
Usage: scripts/release-manifest.sh --app PATH [options]

Options:
  --archive PATH
  --sign auto|none|adhoc|developer-id
  --output PATH       Default: next to the app as release-manifest.json
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || rlt_die "--app requires a path"; APP="$2"; shift 2 ;;
    --archive) [ "$#" -ge 2 ] || rlt_die "--archive requires a path"; ARCHIVE="$2"; shift 2 ;;
    --sign) [ "$#" -ge 2 ] || rlt_die "--sign requires a value"; SIGN_MODE="$2"; shift 2 ;;
    --output) [ "$#" -ge 2 ] || rlt_die "--output requires a path"; OUTPUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) rlt_die "unknown option: $1" ;;
  esac
done

[ -n "$APP" ] || rlt_die "--app is required"
[ -d "$APP" ] || rlt_die "app not found: $APP"
if [ -n "$ARCHIVE" ]; then [ -f "$ARCHIVE" ] || rlt_die "archive not found: $ARCHIVE"; fi
if [ "$SIGN_MODE" = "auto" ]; then SIGN_MODE=$(rlt_detect_sign_mode "$APP"); fi
case "$SIGN_MODE" in none|adhoc|developer-id) ;; *) rlt_die "invalid sign mode: $SIGN_MODE" ;; esac

VERSION=$(rlt_read_version "$ROOT")
BINARY="$APP/Contents/MacOS/RateLimitTomato"
PLIST="$APP/Contents/Info.plist"
[ -x "$BINARY" ] || rlt_die "main executable missing"
[ -f "$PLIST" ] || rlt_die "Info.plist missing"

if [ -z "$OUTPUT" ]; then OUTPUT="$(dirname "$APP")/release-manifest.json"; fi
mkdir -p "$(dirname "$OUTPUT")"
OUTPUT=$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")
SUMS="$(dirname "$OUTPUT")/SHA256SUMS"
[ "$OUTPUT" != "$SUMS" ] || rlt_die "manifest output must not be named SHA256SUMS"

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

COMMIT=$(/usr/bin/git -C "$ROOT" rev-parse HEAD)
SOURCE_EPOCH=$(/usr/bin/git -C "$ROOT" show -s --format=%ct HEAD)
if /usr/bin/git -C "$ROOT" diff --quiet \
  && /usr/bin/git -C "$ROOT" diff --cached --quiet \
  && [ -z "$(/usr/bin/git -C "$ROOT" ls-files --others --exclude-standard)" ]; then
  DIRTY=false
else
  DIRTY=true
fi
ARCHS=$(/usr/bin/lipo -archs "$BINARY")
ARCHS_JSON=""
for arch in $ARCHS; do
  if [ -n "$ARCHS_JSON" ]; then ARCHS_JSON="$ARCHS_JSON, "; fi
  ARCHS_JSON="$ARCHS_JSON\"$(json_escape "$arch")\""
done
PACKAGE_SHA=$(rlt_sha256 "$ROOT/Package.resolved")
SWIFT_VERSION=$(/usr/bin/swift --version 2>&1 | /usr/bin/head -n 1)
XCODE_VERSION=$(/usr/bin/xcodebuild -version | /usr/bin/paste -sd ';' -)
MACOS_VERSION=$(/usr/bin/sw_vers -productVersion)
BUILT_AT=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')
BUILD_CONFIGURATION=${RLT_BUILD_CONFIGURATION:-}
if [ -z "$BUILD_CONFIGURATION" ]; then
  BUILD_CONFIGURATION=$(/usr/libexec/PlistBuddy -c 'Print :RLTBuildConfiguration' "$PLIST" 2>/dev/null || printf 'unknown')
fi

CDHASH=""
TEAM_ID=""
if [ "$SIGN_MODE" != "none" ]; then
  SIGN_DETAILS=$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1)
  CDHASH=$(printf '%s\n' "$SIGN_DETAILS" | /usr/bin/awk -F= '/^CDHash=/{print $2; exit}')
  TEAM_ID=$(printf '%s\n' "$SIGN_DETAILS" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')
fi
NOTARIZED=false
if [ "$SIGN_MODE" = "developer-id" ] \
  && /usr/bin/xcrun stapler validate "$APP" >/dev/null 2>&1; then
  NOTARIZED=true
fi

ARCHIVE_JSON=null
ARCHIVE_SHA_JSON=null
if [ -n "$ARCHIVE" ]; then
  ARCHIVE_JSON="\"$(json_escape "$(basename "$ARCHIVE")")\""
  ARCHIVE_SHA_JSON="\"$(rlt_sha256 "$ARCHIVE")\""
fi
CDHASH_JSON=null
TEAM_ID_JSON=null
if [ -n "$CDHASH" ]; then CDHASH_JSON="\"$(json_escape "$CDHASH")\""; fi
if [ -n "$TEAM_ID" ] && [ "$TEAM_ID" != "not set" ]; then TEAM_ID_JSON="\"$(json_escape "$TEAM_ID")\""; fi

TRANSACTION_DIR=$(mktemp -d "$(dirname "$OUTPUT")/.release-manifest.XXXXXX")
RAW_MANIFEST="$TRANSACTION_DIR/raw-release-manifest.json"
STAGED_OUTPUT="$TRANSACTION_DIR/staged-release-manifest.json"
STAGED_SUMS="$TRANSACTION_DIR/staged-SHA256SUMS"
BACKUP_OUTPUT="$TRANSACTION_DIR/previous-release-manifest.json"
BACKUP_SUMS="$TRANSACTION_DIR/previous-SHA256SUMS"
PROMOTION_STARTED=0
PROMOTION_COMPLETE=0
RESTORE_FAILED=0

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

rollback_artifact() {
  local final_path="$1"
  local staged_path="$2"
  local backup_path="$3"

  if path_exists "$backup_path"; then
    if ! rm -rf "$final_path"; then
      printf 'error: failed to remove incomplete release metadata: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
      return
    fi
    if path_exists "$final_path"; then
      printf 'error: incomplete release metadata still exists after removal: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
      return
    fi
    if ! mv "$backup_path" "$final_path"; then
      printf 'error: failed to restore release metadata; recovery data kept at %s\n' "$TRANSACTION_DIR" >&2
      RESTORE_FAILED=1
    fi
  elif ! path_exists "$staged_path" && path_exists "$final_path"; then
    if ! rm -rf "$final_path"; then
      printf 'error: failed to remove incomplete release metadata: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
    elif path_exists "$final_path"; then
      printf 'error: incomplete release metadata still exists after removal: %s\n' "$final_path" >&2
      RESTORE_FAILED=1
    fi
  fi
}

cleanup_transaction() {
  local status="$1"
  trap - EXIT HUP INT TERM
  set +e
  if [ "$status" -ne 0 ] && [ "$PROMOTION_STARTED" -eq 1 ] && [ "$PROMOTION_COMPLETE" -eq 0 ]; then
    rollback_artifact "$SUMS" "$STAGED_SUMS" "$BACKUP_SUMS"
    rollback_artifact "$OUTPUT" "$STAGED_OUTPUT" "$BACKUP_OUTPUT"
  fi
  if [ "$RESTORE_FAILED" -eq 0 ]; then
    if ! rm -rf "$TRANSACTION_DIR" || path_exists "$TRANSACTION_DIR"; then
      printf 'error: failed to remove release metadata transaction directory: %s\n' "$TRANSACTION_DIR" >&2
      status=1
    fi
  else
    printf 'error: release metadata transaction retained for manual recovery: %s\n' "$TRANSACTION_DIR" >&2
    status=1
  fi
  exit "$status"
}
trap 'cleanup_transaction $?' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

cat > "$RAW_MANIFEST" <<JSON
{
  "schemaVersion": 1,
  "product": "RateLimitTomato",
  "version": "$(json_escape "$VERSION")",
  "bundleIdentifier": "local.rlt.RateLimitTomato",
  "commit": "$(json_escape "$COMMIT")",
  "sourceDateEpoch": $SOURCE_EPOCH,
  "dirty": $DIRTY,
  "builtAtUTC": "$(json_escape "$BUILT_AT")",
  "configuration": "$(json_escape "$BUILD_CONFIGURATION")",
  "architectures": [$ARCHS_JSON],
  "signMode": "$(json_escape "$SIGN_MODE")",
  "codeDirectoryHash": $CDHASH_JSON,
  "teamIdentifier": $TEAM_ID_JSON,
  "notarized": $NOTARIZED,
  "packageResolvedSHA256": "$(json_escape "$PACKAGE_SHA")",
  "swift": "$(json_escape "$SWIFT_VERSION")",
  "xcode": "$(json_escape "$XCODE_VERSION")",
  "macOS": "$(json_escape "$MACOS_VERSION")",
  "archive": $ARCHIVE_JSON,
  "archiveSHA256": $ARCHIVE_SHA_JSON
}
JSON
/usr/bin/plutil -convert json -r -o "$STAGED_OUTPUT" "$RAW_MANIFEST"

printf '%s  %s\n' "$(rlt_sha256 "$BINARY")" 'RateLimitTomato.app/Contents/MacOS/RateLimitTomato' >> "$STAGED_SUMS"
printf '%s  %s\n' "$(rlt_sha256 "$PLIST")" 'RateLimitTomato.app/Contents/Info.plist' >> "$STAGED_SUMS"
if [ -n "$ARCHIVE" ]; then
  printf '%s  %s\n' "$(rlt_sha256 "$ARCHIVE")" "$(basename "$ARCHIVE")" >> "$STAGED_SUMS"
fi
printf '%s  %s\n' "$(rlt_sha256 "$STAGED_OUTPUT")" "$(basename "$OUTPUT")" >> "$STAGED_SUMS"

PROMOTION_STARTED=1
if path_exists "$OUTPUT"; then
  mv "$OUTPUT" "$BACKUP_OUTPUT"
fi
if path_exists "$SUMS"; then
  mv "$SUMS" "$BACKUP_SUMS"
fi
mv "$STAGED_OUTPUT" "$OUTPUT"
mv "$STAGED_SUMS" "$SUMS"
PROMOTION_COMPLETE=1

rlt_note "release manifest: $OUTPUT"
rlt_note "checksums: $SUMS"
