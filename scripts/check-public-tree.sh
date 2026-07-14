#!/bin/bash
# Enforce the repository contract for source that is safe to publish.
# Keep this compatible with the system Bash 3.2 shipped by macOS.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/release-common.sh
. "$SCRIPT_DIR/lib/release-common.sh"

ROOT=$(rlt_repo_root)
FAILURES=0

rlt_require_command git
rlt_require_command rg

record_failure() {
  printf 'error: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}

require_tracked_file() {
  local relative_path="$1"

  if [ ! -s "$ROOT/$relative_path" ]; then
    record_failure "required public file is missing or empty: $relative_path"
    return
  fi
  if ! /usr/bin/git -C "$ROOT" ls-files --error-unmatch -- "$relative_path" \
    >/dev/null 2>&1; then
    record_failure "required public file is not tracked: $relative_path"
  fi
}

require_one_tracked_file() {
  local label="$1"
  shift
  local candidate

  for candidate in "$@"; do
    if [ -s "$ROOT/$candidate" ] \
      && /usr/bin/git -C "$ROOT" ls-files --error-unmatch -- "$candidate" \
        >/dev/null 2>&1; then
      return
    fi
  done
  record_failure "required $label is missing, empty, or untracked"
}

rlt_note "checking forbidden internal tracked paths"
FORBIDDEN_PATH_FOUND=0
while IFS= read -r -d '' tracked_path; do
  case "$tracked_path" in
    .zcode|.zcode/*|docs/codex|docs/codex/*|CLAUDE.md)
      printf 'forbidden tracked path: %s\n' "$tracked_path" >&2
      FORBIDDEN_PATH_FOUND=1
      ;;
  esac
done < <(/usr/bin/git -C "$ROOT" ls-files -z)
if [ "$FORBIDDEN_PATH_FOUND" -ne 0 ]; then
  record_failure "internal planning/agent files must not be tracked"
fi

rlt_note "checking required community, license, and brand files"
for required_file in \
  README.md \
  LICENSE \
  THIRD_PARTY_NOTICES.md \
  SECURITY.md \
  CONTRIBUTING.md \
  CODE_OF_CONDUCT.md \
  Sources/RateLimitTomato/Resources/AppIcon.icns \
  docs/assets/brand/app-icon-source.png \
  docs/assets/social-preview.png; do
  require_tracked_file "$required_file"
done

require_one_tracked_file "bug-report issue template" \
  .github/ISSUE_TEMPLATE/bug_report.yml \
  .github/ISSUE_TEMPLATE/bug_report.yaml \
  .github/ISSUE_TEMPLATE/bug_report.md \
  .github/ISSUE_TEMPLATE/bug-report.yml \
  .github/ISSUE_TEMPLATE/bug-report.yaml \
  .github/ISSUE_TEMPLATE/bug-report.md
require_one_tracked_file "feature-request issue template" \
  .github/ISSUE_TEMPLATE/feature_request.yml \
  .github/ISSUE_TEMPLATE/feature_request.yaml \
  .github/ISSUE_TEMPLATE/feature_request.md \
  .github/ISSUE_TEMPLATE/feature-request.yml \
  .github/ISSUE_TEMPLATE/feature-request.yaml \
  .github/ISSUE_TEMPLATE/feature-request.md
require_one_tracked_file "pull-request template" \
  .github/pull_request_template.md \
  .github/PULL_REQUEST_TEMPLATE.md \
  .github/PULL_REQUEST_TEMPLATE/default.md

TRACKED_SCREENSHOT=""
while IFS= read -r -d '' screenshot; do
  if [ -s "$ROOT/$screenshot" ]; then
    TRACKED_SCREENSHOT="$screenshot"
    break
  fi
done < <(/usr/bin/git -C "$ROOT" ls-files -z -- 'docs/assets/screenshots/*.png')
if [ -z "$TRACKED_SCREENSHOT" ]; then
  record_failure "at least one non-empty tracked PNG is required under docs/assets/screenshots/"
fi

rlt_note "checking tracked text for private machine paths"
# Require a concrete macOS user component so the defensive '/Users/' matcher in
# verify-app.sh does not flag itself as a leaked absolute path.
ABSOLUTE_USER_PATH_PATTERN='/U[s]ers/[[:alnum:]_.-]+([^[:alnum:]_.-]|$)'
PATH_MATCHES=$(/usr/bin/git -C "$ROOT" grep -n -I -E \
  "$ABSOLUTE_USER_PATH_PATTERN" -- . || true)
if [ -n "$PATH_MATCHES" ]; then
  printf '%s\n' "$PATH_MATCHES" >&2
  record_failure "tracked text contains a concrete macOS user path"
fi

rlt_note "checking public copy and source for real AI vendor marks"
# Tests deliberately contain forbidden words to prove the runtime red-line
# checker. Restrict this public-copy rule to the surfaces that will be read or
# rendered as project/product material; scripts likewise contain the patterns
# that implement the gate and are intentionally outside this scan.
UNAMBIGUOUS_VENDOR_PATTERN='Claude|Anthropic|OpenAI|ChatGPT|Codex|GitHub[[:space:]]+Copilot|Windsurf|DeepSeek|Qwen|Mistral|Cohere|Midjourney|Stable[[:space:]]+Diffusion|通义千问|豆包|文心一言'
AMBIGUOUS_VENDOR_PATTERN='Opus|Copilot|Cursor|Gemini|Grok|xAI|Kimi|Llama|Perplexity'
VENDOR_MATCHES=$(
  /usr/bin/git -C "$ROOT" grep -n -I -i -E \
    "$UNAMBIGUOUS_VENDOR_PATTERN" -- README.md docs Sources || true
  /usr/bin/git -C "$ROOT" grep -n -I -E \
    "$AMBIGUOUS_VENDOR_PATTERN" -- README.md docs Sources || true
)
if [ -n "$VENDOR_MATCHES" ]; then
  printf '%s\n' "$VENDOR_MATCHES" >&2
  record_failure "public README/docs/Sources contain a real AI vendor name or mark"
fi

rlt_note "checking tracked tree for private-key headers"
PRIVATE_KEY_PATTERN='-----BEGIN[[:space:]]+((RSA|DSA|EC|OPENSSH|ENCRYPTED)[[:space:]]+)?PRIVATE[[:space:]]+KEY-----|-----BEGIN[[:space:]]+PGP[[:space:]]+PRIVATE[[:space:]]+KEY[[:space:]]+BLOCK-----'
KEY_MATCHES=$(/usr/bin/git -C "$ROOT" grep -n -I -E \
  -e "$PRIVATE_KEY_PATTERN" -- . || true)
if [ -n "$KEY_MATCHES" ]; then
  printf '%s\n' "$KEY_MATCHES" >&2
  record_failure "tracked tree contains a private-key header"
fi

rlt_note "checking GitHub Actions references for immutable revisions"
ACTION_LINES=$(rg -n --no-heading --with-filename \
  '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*' \
  "$ROOT/.github/workflows" -g '*.yml' -g '*.yaml' || true)
if [ -n "$ACTION_LINES" ]; then
  while IFS= read -r action_line; do
    source_line=${action_line#*:*:}
    action_ref=${source_line#*uses:}
    action_ref=${action_ref%%#*}
    action_ref=$(printf '%s\n' "$action_ref" \
      | /usr/bin/awk '{$1=$1; print}')
    case "$action_ref" in
      \"*\") action_ref=${action_ref#\"}; action_ref=${action_ref%\"} ;;
      \'*\') action_ref=${action_ref#\'}; action_ref=${action_ref%\'} ;;
    esac

    case "$action_ref" in
      ./*)
        # Local actions and reusable workflows are part of this same tree.
        ;;
      *)
        if ! [[ "$action_ref" =~ ^[^[:space:]@]+/[^[:space:]@]+@[0-9a-fA-F]{40}$ ]]; then
          printf '%s\n' "$action_line" >&2
          record_failure "remote GitHub Action must use a full 40-character commit SHA"
        fi
        ;;
    esac
  done <<< "$ACTION_LINES"
fi

if [ "$FAILURES" -ne 0 ]; then
  rlt_die "public tree check failed with $FAILURES violation(s)"
fi

rlt_note "public tree OK"
