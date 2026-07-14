#!/bin/bash
# Canonical local/CI quality gate. Dependencies are locked to Package.resolved.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

ROOT=$(rlt_repo_root)
cd "$ROOT"

rlt_require_command swift
rlt_require_command rg

run_and_reject_owned_warnings() {
  local label="$1"
  shift
  local log
  local warning_pattern='(^|[/ ])(Sources|Tests)/[^:]+:[0-9]+:[0-9]+: warning:'

  log=$(mktemp "${TMPDIR:-/tmp}/rlt-${label}.XXXXXX")
  if ! "$@" 2>&1 | /usr/bin/tee "$log"; then
    rm -f "$log"
    rlt_die "$label failed"
  fi

  # SwiftPM's -Xswiftc applies to dependency checkouts too. Treat diagnostics
  # from this repository as errors while leaving third-party warning policy to
  # their owners, so a dependency warning cannot make this gate flaky.
  if /usr/bin/grep -E "$warning_pattern" "$log" >/dev/null; then
    /usr/bin/grep -E "$warning_pattern" "$log" >&2 || true
    rm -f "$log"
    rlt_die "$label emitted warnings in owned Sources/ or Tests/"
  fi
  rm -f "$log"
}

rlt_note "checking source version contract"
"$SCRIPT_DIR/check-version.sh"

rlt_note "checking immutable product red lines"
"$SCRIPT_DIR/check-redlines.sh"

rlt_note "checking public repository tree"
"$SCRIPT_DIR/check-public-tree.sh"

rlt_note "checking patch whitespace"
/usr/bin/git diff --check

rlt_note "building with locked dependency revisions"
run_and_reject_owned_warnings build \
  /usr/bin/swift build --only-use-versions-from-resolved-file

TEST_COMMAND=(/usr/bin/swift test --only-use-versions-from-resolved-file)
if [ "${RLT_SKIP_SNAPSHOT_TESTS:-0}" = "1" ]; then
  # ImageRenderer may enter Metal on headless Intel runners and abort before
  # XCTest can report a result. The full suite still runs on arm64; Intel keeps
  # proving the source and non-rendering tests on the second architecture.
  TEST_COMMAND+=(--skip RLTSnapshotTests)
  rlt_note "running non-rendering test suite with locked dependency revisions"
else
  rlt_note "running full test suite with locked dependency revisions"
fi
run_and_reject_owned_warnings test \
  "${TEST_COMMAND[@]}"

rlt_note "quality gate passed"
