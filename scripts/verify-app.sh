#!/bin/bash
# Structural, architecture, red-line, and signature verification for an app.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

APP=""
SIGN_MODE="auto"
ARCH_MODE="current"
REQUIRE_RELEASE=0

usage() {
  cat <<'EOF'
Usage: scripts/verify-app.sh --app PATH [options]

Options:
  --sign auto|none|adhoc|developer-id   Default: auto
  --arch current|arm64|x86_64|universal
                                       Default: current
  --require-release                    Require RLTBuildConfiguration=release
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app) [ "$#" -ge 2 ] || rlt_die "--app requires a path"; APP="$2"; shift 2 ;;
    --sign) [ "$#" -ge 2 ] || rlt_die "--sign requires a value"; SIGN_MODE="$2"; shift 2 ;;
    --arch) [ "$#" -ge 2 ] || rlt_die "--arch requires a value"; ARCH_MODE="$2"; shift 2 ;;
    --require-release) REQUIRE_RELEASE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) rlt_die "unknown option: $1" ;;
  esac
done

[ -n "$APP" ] || rlt_die "--app is required"
[ -d "$APP" ] || rlt_die "app not found: $APP"
case "$SIGN_MODE" in auto|none|adhoc|developer-id) ;; *) rlt_die "invalid sign mode: $SIGN_MODE" ;; esac
case "$ARCH_MODE" in current|arm64|x86_64|universal) ;; *) rlt_die "invalid architecture mode: $ARCH_MODE" ;; esac

PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/RateLimitTomato"
[ -f "$PLIST" ] || rlt_die "Info.plist missing"
[ -x "$BINARY" ] || rlt_die "main executable missing or not executable"
/usr/bin/plutil -lint "$PLIST" >/dev/null

DISPLAY_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST")
PACKAGE_TYPE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$PLIST")
MINIMUM_OS=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$PLIST")
LSUIELEMENT=$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$PLIST")
MULTIPLE_INSTANCES_PROHIBITED=$(/usr/libexec/PlistBuddy -c 'Print :LSMultipleInstancesProhibited' "$PLIST")
URL_SCHEME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$PLIST")
BUILD_CONFIGURATION=$(/usr/libexec/PlistBuddy -c 'Print :RLTBuildConfiguration' "$PLIST")
ICON_FILE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")
[ "$DISPLAY_NAME" = "Rate Limit Tomato" ] || rlt_die "unexpected display name: $DISPLAY_NAME"
[ "$PACKAGE_TYPE" = "APPL" ] || rlt_die "unexpected package type: $PACKAGE_TYPE"
[ "$MINIMUM_OS" = "14.0" ] || rlt_die "unexpected minimum macOS: $MINIMUM_OS"
[ "$LSUIELEMENT" = "true" ] || rlt_die "LSUIElement must be true"
[ "$MULTIPLE_INSTANCES_PROHIBITED" = "true" ] \
  || rlt_die "LSMultipleInstancesProhibited must be true"
[ "$URL_SCHEME" = "rlt" ] || rlt_die "rlt URL scheme is missing"
[ "$ICON_FILE" = "AppIcon" ] || rlt_die "unexpected app icon declaration: $ICON_FILE"
[ -f "$APP/Contents/Resources/AppIcon.icns" ] || rlt_die "AppIcon.icns is missing from app"
case "$BUILD_CONFIGURATION" in debug|release) ;; *) rlt_die "invalid build configuration: $BUILD_CONFIGURATION" ;; esac
if [ "$REQUIRE_RELEASE" -eq 1 ] && [ "$BUILD_CONFIGURATION" != "release" ]; then
  rlt_die "distribution verification requires a release build"
fi

BUNDLE_COUNT=0
for bundle in "$APP/Contents/Resources"/*.bundle; do
  if [ -d "$bundle" ]; then
    BUNDLE_COUNT=$((BUNDLE_COUNT + 1))
  fi
done
[ "$BUNDLE_COUNT" -gt 0 ] || rlt_die "required SwiftPM resource bundles are missing"
REQUIRED_KEYBOARD_SHORTCUTS_BUNDLE="$APP/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle"
[ -d "$REQUIRED_KEYBOARD_SHORTCUTS_BUNDLE" ] \
  || rlt_die "required KeyboardShortcuts resource bundle is missing"
[ -f "$APP/Contents/Resources/LICENSE.txt" ] || rlt_die "project LICENSE is missing from app"
[ -f "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md" ] \
  || rlt_die "third-party notices are missing from app"

ACTUAL_ARCHS=$(/usr/bin/lipo -archs "$BINARY")
case "$ARCH_MODE" in
  current) EXPECTED_ARCH=$(/usr/bin/uname -m) ;;
  arm64) EXPECTED_ARCH=arm64 ;;
  x86_64) EXPECTED_ARCH=x86_64 ;;
  universal) EXPECTED_ARCH=universal ;;
esac
if [ "$EXPECTED_ARCH" = "universal" ]; then
  printf '%s\n' "$ACTUAL_ARCHS" | /usr/bin/grep -Eq '(^| )arm64( |$)' \
    || rlt_die "universal app is missing arm64: $ACTUAL_ARCHS"
  printf '%s\n' "$ACTUAL_ARCHS" | /usr/bin/grep -Eq '(^| )x86_64( |$)' \
    || rlt_die "universal app is missing x86_64: $ACTUAL_ARCHS"
  [ "$(printf '%s\n' "$ACTUAL_ARCHS" | /usr/bin/wc -w | /usr/bin/tr -d ' ')" -eq 2 ] \
    || rlt_die "universal app has unexpected architecture set: $ACTUAL_ARCHS"
else
  [ "$ACTUAL_ARCHS" = "$EXPECTED_ARCH" ] \
    || rlt_die "expected $EXPECTED_ARCH app, got: $ACTUAL_ARCHS"
fi

BUILD_INFO=$(/usr/bin/vtool -show-build "$BINARY")
MINIMUM_VERSIONS=$(printf '%s\n' "$BUILD_INFO" | /usr/bin/awk '$1 == "minos" { print $2 }')
EXPECTED_SLICE_COUNT=$(printf '%s\n' "$ACTUAL_ARCHS" | /usr/bin/wc -w | /usr/bin/tr -d ' ')
ACTUAL_MINIMUM_COUNT=$(printf '%s\n' "$MINIMUM_VERSIONS" | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }')
[ "$ACTUAL_MINIMUM_COUNT" -eq "$EXPECTED_SLICE_COUNT" ] \
  || rlt_die "could not determine the minimum OS for every architecture slice"
while IFS= read -r minimum; do
  [ -z "$minimum" ] && continue
  [ "$minimum" = "14.0" ] || rlt_die "Mach-O minimum macOS must be 14.0, got: $minimum"
done <<EOF
$MINIMUM_VERSIONS
EOF

if [ "$SIGN_MODE" = "auto" ]; then
  SIGN_MODE=$(rlt_detect_sign_mode "$APP")
fi
case "$SIGN_MODE" in
  none)
    [ ! -f "$APP/Contents/_CodeSignature/CodeResources" ] \
      || rlt_die "app was expected to be unsigned but has a bundle signature"
    ;;
  adhoc)
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
    SIGN_DETAILS=$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1)
    printf '%s\n' "$SIGN_DETAILS" | /usr/bin/grep -q '^Signature=adhoc$' \
      || rlt_die "app is not ad-hoc signed"
    ;;
  developer-id)
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
    SIGN_DETAILS=$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1)
    printf '%s\n' "$SIGN_DETAILS" | /usr/bin/grep -q '^Authority=Developer ID Application:' \
      || rlt_die "Developer ID authority is missing"
    printf '%s\n' "$SIGN_DETAILS" | /usr/bin/grep -Eq '^TeamIdentifier=.+$' \
      || rlt_die "Developer ID TeamIdentifier is missing"
    printf '%s\n' "$SIGN_DETAILS" | /usr/bin/grep -Eq '^CodeDirectory .*flags=.*\(runtime\)' \
      || rlt_die "hardened runtime flag is missing"
    ;;
  *) rlt_die "unable to classify signature" ;;
esac

# Universal Mach-O output repeats an unindented local binary header for each
# architecture. Only indented rows are actual linked-library entries.
LINKS=$(/usr/bin/otool -L "$BINARY" | /usr/bin/awk '/^[[:space:]]/ { print }')
if printf '%s\n' "$LINKS" | /usr/bin/grep -E '/Users/|/private/tmp/|/\.build/|/DerivedData/' >/dev/null; then
  printf '%s\n' "$LINKS" >&2
  rlt_die "binary contains a build-machine dynamic library path"
fi
RPATHS=$(/usr/bin/otool -l "$BINARY" | /usr/bin/awk '
  $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
  in_rpath && $1 == "path" { print $2; in_rpath = 0 }
')
if printf '%s\n' "$RPATHS" | /usr/bin/grep -E '/Users/|/private/tmp/|/\.build/|/DerivedData/' >/dev/null; then
  printf '%s\n' "$RPATHS" >&2
  rlt_die "binary contains a workspace-specific runtime search path"
fi

"$SCRIPT_DIR/check-version.sh" --app "$APP"
"$SCRIPT_DIR/check-redlines.sh" --app "$APP"
rlt_note "app verification passed (archs=$ACTUAL_ARCHS, sign=$SIGN_MODE)"
