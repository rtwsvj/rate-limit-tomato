#!/bin/bash

# Shared helpers for release scripts. Keep this file compatible with macOS's
# system Bash (3.2); do not use associative arrays or Bash 4-only features.

rlt_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

rlt_note() {
  printf '==> %s\n' "$*"
}

rlt_repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

rlt_require_command() {
  command -v "$1" >/dev/null 2>&1 || rlt_die "required command not found: $1"
}

rlt_read_version() {
  local root="$1"
  local version

  [ -f "$root/VERSION" ] || rlt_die "VERSION file not found at $root/VERSION"
  version=$(<"$root/VERSION")
  printf '%s\n' "$version" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || rlt_die "VERSION must match MAJOR.MINOR.PATCH, got: $version"
  [ "$(/usr/bin/awk 'END { print NR }' "$root/VERSION")" -eq 1 ] \
    || rlt_die "VERSION must contain exactly one line"
  printf '%s\n' "$version"
}

rlt_sha256() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

rlt_detect_sign_mode() {
  local app="$1"
  local details

  if [ ! -f "$app/Contents/_CodeSignature/CodeResources" ]; then
    printf 'none\n'
    return
  fi

  details=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1) \
    || rlt_die "cannot inspect signature: $app"
  if printf '%s\n' "$details" | /usr/bin/grep -q '^Signature=adhoc$'; then
    printf 'adhoc\n'
  elif printf '%s\n' "$details" | /usr/bin/grep -q '^Authority=Developer ID Application:'; then
    printf 'developer-id\n'
  else
    printf 'unknown\n'
  fi
}

rlt_arch_label() {
  local binary="$1"
  local archs

  archs=$(/usr/bin/lipo -archs "$binary") || rlt_die "cannot inspect architectures: $binary"
  if printf '%s\n' "$archs" | /usr/bin/grep -Eq '(^| )arm64( |$)' \
    && printf '%s\n' "$archs" | /usr/bin/grep -Eq '(^| )x86_64( |$)'; then
    printf 'universal\n'
  elif [ "$archs" = "arm64" ]; then
    printf 'arm64\n'
  elif [ "$archs" = "x86_64" ]; then
    printf 'x86_64\n'
  else
    printf '%s\n' "$archs" | /usr/bin/tr ' ' '-'
  fi
}
