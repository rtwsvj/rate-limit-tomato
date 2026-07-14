#!/bin/bash
# Assemble a verified RateLimitTomato.app from locked SwiftPM inputs.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

ROOT=$(rlt_repo_root)
CONFIGURATION="release"
ARCH_MODE="current"
SIGN_MODE=""
SIGN_IDENTITY=${RLT_SIGN_IDENTITY:-}
OUTPUT_DIR="$ROOT/dist"

usage() {
  cat <<'EOF'
Usage: scripts/make-app.sh --sign MODE [options]

Required:
  --sign none|adhoc|developer-id

Options:
  --configuration debug|release       Default: release
  --arch current|arm64|x86_64|universal
                                       Default: current
  --identity NAME_OR_SHA               Required for developer-id unless
                                       RLT_SIGN_IDENTITY is set
  --output-dir PATH                    Default: dist
  -h, --help

Universal mode builds arm64 and x86_64 independently and fails rather than
silently producing a thin binary if either slice cannot be built.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --configuration)
      [ "$#" -ge 2 ] || rlt_die "--configuration requires a value"
      CONFIGURATION="$2"
      shift 2
      ;;
    --arch)
      [ "$#" -ge 2 ] || rlt_die "--arch requires a value"
      ARCH_MODE="$2"
      shift 2
      ;;
    --sign)
      [ "$#" -ge 2 ] || rlt_die "--sign requires a value"
      SIGN_MODE="$2"
      shift 2
      ;;
    --identity)
      [ "$#" -ge 2 ] || rlt_die "--identity requires a value"
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --output-dir)
      [ "$#" -ge 2 ] || rlt_die "--output-dir requires a path"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) rlt_die "unknown option: $1" ;;
  esac
done

case "$CONFIGURATION" in debug|release) ;; *) rlt_die "invalid configuration: $CONFIGURATION" ;; esac
case "$ARCH_MODE" in current|arm64|x86_64|universal) ;; *) rlt_die "invalid architecture mode: $ARCH_MODE" ;; esac
case "$SIGN_MODE" in none|adhoc|developer-id) ;; '') rlt_die "--sign is required" ;; *) rlt_die "invalid sign mode: $SIGN_MODE" ;; esac
if [ "$SIGN_MODE" = "developer-id" ] && [ -z "$SIGN_IDENTITY" ]; then
  rlt_die "developer-id signing requires --identity or RLT_SIGN_IDENTITY"
fi
if [ "$SIGN_MODE" = "developer-id" ] && [ "$CONFIGURATION" != "release" ]; then
  rlt_die "Developer ID distribution builds must use --configuration release"
fi

rlt_require_command swift
rlt_require_command lipo
rlt_require_command codesign

VERSION=$(rlt_read_version "$ROOT")
case "$OUTPUT_DIR" in /*) ;; *) OUTPUT_DIR="$ROOT/$OUTPUT_DIR" ;; esac
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
cd "$ROOT"

WORK_DIR=$(mktemp -d "$OUTPUT_DIR/.rlt-package.XXXXXX")
STAGED_APP="$WORK_DIR/RateLimitTomato.app"
FINAL_APP="$OUTPUT_DIR/RateLimitTomato.app"
STAGED_MANIFEST="$WORK_DIR/release-manifest.json"
STAGED_SUMS="$WORK_DIR/SHA256SUMS"
FINAL_MANIFEST="$OUTPUT_DIR/release-manifest.json"
FINAL_SUMS="$OUTPUT_DIR/SHA256SUMS"
BACKUP_APP="$WORK_DIR/previous-RateLimitTomato.app"
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
    # No previous artifact existed and the staged path has already been moved.
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
    rollback_artifact "$FINAL_APP" "$STAGED_APP" "$BACKUP_APP"
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

build_slice() {
  local arch="$1"
  local scratch="$2"

  rlt_note "building $CONFIGURATION slice: $arch"
  /usr/bin/swift build \
    --configuration "$CONFIGURATION" \
    --arch "$arch" \
    --scratch-path "$scratch" \
    --only-use-versions-from-resolved-file
  SLICE_BIN_DIR=$(/usr/bin/swift build \
    --configuration "$CONFIGURATION" \
    --arch "$arch" \
    --scratch-path "$scratch" \
    --only-use-versions-from-resolved-file \
    --show-bin-path)
  [ -x "$SLICE_BIN_DIR/RateLimitTomato" ] || rlt_die "built executable missing for $arch"
}

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

RESOURCE_BIN_DIR=""
case "$ARCH_MODE" in
  current)
    CURRENT_ARCH=$(/usr/bin/uname -m)
    case "$CURRENT_ARCH" in arm64|x86_64) ;; *) rlt_die "unsupported host architecture: $CURRENT_ARCH" ;; esac
    build_slice "$CURRENT_ARCH" "$WORK_DIR/build-$CURRENT_ARCH"
    BIN_DIR="$SLICE_BIN_DIR"
    cp "$BIN_DIR/RateLimitTomato" "$STAGED_APP/Contents/MacOS/RateLimitTomato"
    RESOURCE_BIN_DIR="$BIN_DIR"
    ;;
  arm64|x86_64)
    build_slice "$ARCH_MODE" "$WORK_DIR/build-$ARCH_MODE"
    BIN_DIR="$SLICE_BIN_DIR"
    cp "$BIN_DIR/RateLimitTomato" "$STAGED_APP/Contents/MacOS/RateLimitTomato"
    RESOURCE_BIN_DIR="$BIN_DIR"
    ;;
  universal)
    build_slice arm64 "$WORK_DIR/build-arm64"
    ARM_BIN_DIR="$SLICE_BIN_DIR"
    build_slice x86_64 "$WORK_DIR/build-x86_64"
    INTEL_BIN_DIR="$SLICE_BIN_DIR"
    /usr/bin/lipo -create \
      "$ARM_BIN_DIR/RateLimitTomato" \
      "$INTEL_BIN_DIR/RateLimitTomato" \
      -output "$STAGED_APP/Contents/MacOS/RateLimitTomato"
    RESOURCE_BIN_DIR="$ARM_BIN_DIR"
    ;;
esac

chmod 755 "$STAGED_APP/Contents/MacOS/RateLimitTomato"

# SPM dependency resource bundles (notably KeyboardShortcuts) are mandatory:
# Bundle.module fatalErrors at runtime when these *.bundle directories are absent.
BUNDLE_COUNT=0
for b in "$RESOURCE_BIN_DIR"/*.bundle; do
  if [ -e "$b" ]; then
    cp -R "$b" "$STAGED_APP/Contents/Resources/"
    BUNDLE_COUNT=$((BUNDLE_COUNT + 1))
  fi
done
[ "$BUNDLE_COUNT" -gt 0 ] || rlt_die "no SwiftPM resource bundles were produced"
[ -f "$ROOT/LICENSE" ] || rlt_die "project LICENSE is missing"
[ -f "$ROOT/THIRD_PARTY_NOTICES.md" ] || rlt_die "THIRD_PARTY_NOTICES.md is missing"
[ -f "$ROOT/Sources/RateLimitTomato/Resources/AppIcon.icns" ] || rlt_die "AppIcon.icns is missing"
cp "$ROOT/LICENSE" "$STAGED_APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGED_APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT/Sources/RateLimitTomato/Resources/AppIcon.icns" \
  "$STAGED_APP/Contents/Resources/AppIcon.icns"

cat > "$STAGED_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.rlt.RateLimitTomato</string>
    <key>CFBundleName</key><string>RateLimitTomato</string>
    <key>CFBundleDisplayName</key><string>Rate Limit Tomato</string>
    <key>CFBundleExecutable</key><string>RateLimitTomato</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>RLTBuildConfiguration</key><string>${CONFIGURATION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>local.rlt.RateLimitTomato.url</string>
            <key>CFBundleURLSchemes</key><array><string>rlt</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$STAGED_APP/Contents/Info.plist" >/dev/null

case "$SIGN_MODE" in
  none)
    rlt_note "leaving app explicitly unsigned"
    ;;
  adhoc)
    rlt_note "applying ad-hoc signature"
    /usr/bin/codesign --force --sign - "$STAGED_APP"
    ;;
  developer-id)
    rlt_note "applying Developer ID signature with hardened runtime"
    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$SIGN_IDENTITY" \
      "$STAGED_APP"
    ;;
esac

rlt_note "verifying staged app before promotion"
if [ "$SIGN_MODE" = "developer-id" ]; then
  "$SCRIPT_DIR/verify-app.sh" \
    --app "$STAGED_APP" \
    --sign "$SIGN_MODE" \
    --arch "$ARCH_MODE" \
    --require-release
else
  "$SCRIPT_DIR/verify-app.sh" \
    --app "$STAGED_APP" \
    --sign "$SIGN_MODE" \
    --arch "$ARCH_MODE"
fi

RLT_BUILD_CONFIGURATION="$CONFIGURATION" \
  "$SCRIPT_DIR/release-manifest.sh" \
  --app "$STAGED_APP" \
  --sign "$SIGN_MODE" \
  --output "$STAGED_MANIFEST"

PROMOTION_STARTED=1
if [ -e "$FINAL_APP" ]; then
  mv "$FINAL_APP" "$BACKUP_APP"
fi
if [ -e "$FINAL_MANIFEST" ]; then
  mv "$FINAL_MANIFEST" "$BACKUP_MANIFEST"
fi
if [ -e "$FINAL_SUMS" ]; then
  mv "$FINAL_SUMS" "$BACKUP_SUMS"
fi
mv "$STAGED_APP" "$FINAL_APP"
mv "$STAGED_MANIFEST" "$FINAL_MANIFEST"
mv "$STAGED_SUMS" "$FINAL_SUMS"
PROMOTION_COMPLETE=1
rm -rf "$BACKUP_APP"
rm -f "$BACKUP_MANIFEST" "$BACKUP_SUMS"

rlt_note "packaged app: $FINAL_APP"
