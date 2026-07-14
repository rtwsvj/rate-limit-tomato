#!/bin/bash
# Validate the source version contract and, optionally, a packaged app/archive.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

ROOT=$(rlt_repo_root)
APP=""
ARCHIVE=""
REQUIRE_RELEASE=0
REQUIRE_TAG=0
REQUIRE_CLEAN=0

usage() {
  cat <<'EOF'
Usage: scripts/check-version.sh [options]

Options:
  --app PATH          Verify the packaged app's version and bundle identifier.
  --archive PATH      Verify that the archive filename carries the source version.
  --release           Require docs/releases/vVERSION.md to exist.
  --require-tag       Require tag vVERSION to point at HEAD.
  --clean             Require a completely clean tracked/untracked worktree.
  -h, --help          Show this help.

No tag is required by default, so this check is safe during development.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      [ "$#" -ge 2 ] || rlt_die "--app requires a path"
      APP="$2"
      shift 2
      ;;
    --archive)
      [ "$#" -ge 2 ] || rlt_die "--archive requires a path"
      ARCHIVE="$2"
      shift 2
      ;;
    --release) REQUIRE_RELEASE=1; shift ;;
    --require-tag) REQUIRE_TAG=1; shift ;;
    --clean) REQUIRE_CLEAN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) rlt_die "unknown option: $1" ;;
  esac
done

VERSION=$(rlt_read_version "$ROOT")
EXPECTED_TAG="v$VERSION"

[ -s "$ROOT/Package.resolved" ] || rlt_die "Package.resolved is missing or empty"

if [ "$REQUIRE_RELEASE" -eq 1 ]; then
  RELEASE_NOTES="$ROOT/docs/releases/v$VERSION.md"
  [ -s "$RELEASE_NOTES" ] \
    || rlt_die "release notes missing: docs/releases/v$VERSION.md"
  if /usr/bin/grep -Eiq '(^|[^[:alpha:]])(pending|unreleased)([^[:alpha:]]|$)' "$RELEASE_NOTES"; then
    rlt_die "release notes still contain pending or unreleased evidence"
  fi
  [ -s "$ROOT/CHANGELOG.md" ] || rlt_die "CHANGELOG.md is missing or empty"
  CHANGELOG_HEADER=$(/usr/bin/grep -F "## [$VERSION] - " "$ROOT/CHANGELOG.md" | /usr/bin/head -n 1 || true)
  [ -n "$CHANGELOG_HEADER" ] || rlt_die "CHANGELOG.md has no $VERSION release entry"
  if printf '%s\n' "$CHANGELOG_HEADER" | /usr/bin/grep -Eiq 'unreleased|pending'; then
    rlt_die "CHANGELOG.md still marks $VERSION as unreleased"
  fi
fi

if [ "$REQUIRE_TAG" -eq 1 ]; then
  /usr/bin/git -C "$ROOT" rev-parse -q --verify "refs/tags/$EXPECTED_TAG" >/dev/null \
    || rlt_die "required tag does not exist: $EXPECTED_TAG"
  TAG_COMMIT=$(/usr/bin/git -C "$ROOT" rev-list -n 1 "$EXPECTED_TAG")
  HEAD_COMMIT=$(/usr/bin/git -C "$ROOT" rev-parse HEAD)
  [ "$TAG_COMMIT" = "$HEAD_COMMIT" ] \
    || rlt_die "$EXPECTED_TAG points to $TAG_COMMIT, not HEAD $HEAD_COMMIT"
fi

POINTING_TAGS=$(/usr/bin/git -C "$ROOT" tag --points-at HEAD --list 'v*' || true)
if [ -n "$POINTING_TAGS" ]; then
  while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    [ "$tag" = "$EXPECTED_TAG" ] \
      || rlt_die "HEAD has mismatched version tag $tag (expected $EXPECTED_TAG)"
  done <<EOF
$POINTING_TAGS
EOF
fi

if [ "$REQUIRE_CLEAN" -eq 1 ]; then
  DIRTY=$(/usr/bin/git -C "$ROOT" status --porcelain --untracked-files=all)
  [ -z "$DIRTY" ] || {
    printf '%s\n' "$DIRTY" >&2
    rlt_die "release worktree is not clean"
  }
fi

if [ -n "$APP" ]; then
  [ -d "$APP" ] || rlt_die "app not found: $APP"
  PLIST="$APP/Contents/Info.plist"
  [ -f "$PLIST" ] || rlt_die "Info.plist not found: $PLIST"
  /usr/bin/plutil -lint "$PLIST" >/dev/null
  APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
  BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")
  [ "$APP_VERSION" = "$VERSION" ] \
    || rlt_die "app version $APP_VERSION does not match VERSION $VERSION"
  [ "$BUILD_VERSION" = "$VERSION" ] \
    || rlt_die "app build version $BUILD_VERSION does not match deterministic version $VERSION"
  [ "$BUNDLE_ID" = "local.rlt.RateLimitTomato" ] \
    || rlt_die "unexpected bundle identifier: $BUNDLE_ID"
fi

if [ -n "$ARCHIVE" ]; then
  [ -f "$ARCHIVE" ] || rlt_die "archive not found: $ARCHIVE"
  case "$(basename "$ARCHIVE")" in
    RateLimitTomato-v"$VERSION"-macOS-*.zip) ;;
    *) rlt_die "archive filename does not carry version $VERSION: $(basename "$ARCHIVE")" ;;
  esac
fi

rlt_note "version contract OK (VERSION=$VERSION, tag requirement=$REQUIRE_TAG)"
