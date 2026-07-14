# Rate Limit Tomato · Product Specification

This document is the product’s single source of truth. `docs/CHANGES.md` records
intentional deviations, `docs/UI-SPEC.md` defines presentation, and
`docs/STATUS.md` records current evidence.

## 1. Product

Rate Limit Tomato is a local-first macOS menu-bar Pomodoro timer. It turns the
familiar feeling of an API rate limit into a healthy focus-and-rest rhythm:
one fictional “fast request” starts a focus session; HTTP `429` means it is
time to take a break.

The parody is an interface theme, not a service simulation. Timing,
persistence, notifications, statistics, and recovery must remain dependable.

### Positioning

- **Tagline:** When you hit 429, take five. · 让 429 替你喊停。
- **Default rhythm:** 25 minutes focus + 5 minutes cooldown.
- **Platform:** macOS 14 or later.
- **Audience:** people who enjoy API humor and want a lightweight menu-bar
  focus tool.
- **Language:** Simplified Chinese and English.

### Non-goals

- team time tracking, billing, accounts, cloud sync, or collaboration;
- a real API client or quota monitor;
- medical, workplace-compliance, or productivity scoring claims;
- reproducing any specific vendor’s product, logo, name, proprietary copy, or
  visual identity.

## 2. Non-negotiable red lines

These constraints override every other section:

1. The app must never initiate a real payment or open a purchase URL.
2. Shipped UI, notifications, bundle metadata, screenshots, and promotional
   copy must not use real AI-vendor names, logos, or trademarks.
3. Runtime code must not make network requests, send telemetry, create an
   account, or upload local data.
4. All quotas, headers, prices, plans, tokens, and usage values are fictional.
5. Every upgrade/pricing surface permanently shows the parody and no-charge
   disclaimer.
6. First launch blocks state-changing actions until the user acknowledges the
   same disclaimer.
7. The only upgrade CTA is `Send more messages with Pro →`; it triggers a
   fictional local response and never navigation or payment.

The privacy promise is enforced by implementation and tests; the current app
does not use App Sandbox as a network-denial boundary.

## 3. Core loop

```text
IDLE → SENDING → FOCUSING → COMPLETED → RATE_LIMITED → RESET → IDLE
                     └────→ ABORTED ────────┘
                              └─ three aborts in 30 min → TEAPOT → IDLE
```

| Phase | Duration / exit | Required behavior |
|---|---|---|
| `idle` | user starts | Shows remaining fictional daily requests. |
| `sending` | 1.5 seconds | Creates one session and consumes one request. |
| `focusing` | configured focus duration | Uses an injected wall clock; user may abort. |
| `completed` | 2 seconds | Finalizes and persists the completed session. |
| `rateLimited` | configured cooldown | Shows `429`, reset time, and skip action. |
| `aborted` | user chooses | Persists the aborted session; user may rest or skip. |
| `reset` | 2 seconds | Presents replenishment, then returns to idle. |
| `teapot` | user acknowledges | `418` easter egg after three aborts in 30 minutes. |

Timing uses wall-clock differences through `TomatoClock`; system sleep must not
pause the real elapsed time. A wake-up may cross several phases and must catch
up at each phase’s natural boundary. A structurally valid unfinished snapshot
remains recoverable after long dormancy (up to ten years). Clock rollback,
including rollback followed by restart, must not create a second daily quota or
display remaining time above the configured duration.

Session timing and daily quota settings are editable only while idle. Theme,
language, sound, and decorative switches may change at any phase.

## 4. Daily quota

- Default: 8 fictional requests per local calendar day.
- Supported settings UI range: 1–24.
- A request is consumed when `sendRequest` succeeds.
- Completed and aborted counts are tracked separately.
- A forward local-day change resets the quota without interrupting an active
  focus or cooldown.
- A backward system-date change does not grant a fresh quota.
- When the quota is exhausted, starting another session is disabled until the
  next forward day change.

## 5. Presentation and themes

Three neutral providers are available:

- **Provider A:** warm paper, serif display type, tomato-orange accent;
- **Provider B:** dark technical surface, cyan accent;
- **Provider C:** black terminal surface, green monospace type.

Provider letters are theme selectors only. They never imply a real service.
Common protocol terms such as `HTTP 429`, `408`, `418`, `503`, JSON, and generic
rate-limit headers are allowed parody material.

The app provides:

- menu-bar remaining count/countdown/status code;
- bilingual status and action copy from the i18n catalog;
- optional fictional logs, headers, token counts, and JSON responses;
- yearly activity grid and 24-hour completed/aborted distribution;
- system notifications, a configurable global shortcut, launch at login, and
  local `rlt://` commands in a packaged `.app`.

## 6. Settings

| Setting | Default | Product range |
|---|---:|---:|
| Focus duration | 25 min | 1–120 min |
| Cooldown duration | 5 min | 1–60 min |
| Daily quota | 8 | 1–24 |
| Theme | Provider A | A / B / C |
| Language | Simplified Chinese | zh-CN / en |
| Fictional logs | on | boolean |
| Fictional headers | on | boolean |
| Sound | on | boolean |

`longBreakMin` and `globalShortcut` remain in JSON schema v1 for compatibility;
the former is not active in v3.2.x and the latter is ignored in favor of the
shortcut library’s own storage.

## 7. Local data and recovery

Persistent data lives under:

```text
~/Library/Application Support/RateLimitTomato/
```

Files:

- `sessions.json`
- `quota.json`
- `settings.json`
- `engine.json`

Requirements:

- atomic replacement for each file;
- deterministic prefix write order with session history durable before later
  quota/settings/engine writes;
- startup reconciliation when a finalized snapshot exists but history is
  missing after an interrupted write;
- explicit degraded-persistence indicator if durable storage is unavailable or
  startup data is unreadable;
- first unreadable file retained as `*.corrupt.bak`;
- maximum 64 MiB per JSON payload, newest 100,000 sessions, text fields bounded
  by both characters and UTF-8 bytes, and bounded abort history;
- import is transactional and leaves cache/disk unchanged on failure;
- no silent fallback from production storage to an unnamed temporary folder.

The app must prohibit multiple packaged instances. Temporary files use unique
names so concurrent or interrupted writes do not share one fixed path.

## 8. Integrations

Packaged-app integrations:

- default global shortcut: `⌘⌥F`;
- launch at login toggle;
- interactive local notifications;
- URL scheme commands:
  - `rlt://startstop`
  - `rlt://send`
  - `rlt://abort`
  - `rlt://skip`
  - `rlt://usage`
  - `rlt://settings`

State-changing integrations obey the first-launch disclaimer gate. Read-only
usage/settings windows may open while the disclaimer is visible. Bare
`swift run` intentionally degrades packaged-app integrations to no-op where a
real bundle is required.

## 9. Internationalization and accessibility

- All shipped UI copy uses `L10n` keys; no user-facing hard-coded strings.
- Every catalog key has `zh-CN` and `en` values.
- Fixed legal copy remains complete in either selected language.
- Controls provide meaningful labels and values to assistive technologies.
- Reduced Motion disables nonessential animation.
- Color is not the only carrier of phase or status meaning.
- Empty chart buckets are hidden from accessibility traversal.

## 10. Distribution

Source code is MIT licensed. Locked third-party dependency notices are listed
in `THIRD_PARTY_NOTICES.md` and included in every packaged app.

A general-user binary may be advertised only after all of the following pass:

1. release build and full tests;
2. universal architecture and macOS 14 minimum-version checks;
3. Developer ID signing with hardened runtime;
4. Apple notarization and stapling;
5. Gatekeeper acceptance of the downloaded archive;
6. archive round-trip, checksums, manifest, and clean-machine launch smoke;
7. release notes that state privacy, parody, system requirements, and known
   limitations.

Until then, the public project is source-first and must not direct ordinary
users to an unnotarized binary or recommend bypassing Gatekeeper.

## 11. Definition of done

A change is releasable only when:

- behavior matches this specification and `docs/CHANGES.md`;
- business logic lives in `TomatoCore` and has deterministic tests;
- `bash scripts/verify.sh` passes;
- shell lint and syntax checks pass;
- packaged-app verification confirms resources, icon, notices, architectures,
  version, signature mode, red lines, and runtime paths;
- promotional claims have a direct code or test proof;
- no credential, private path, internal session record, or real vendor mark is
  present in the public tree or shipped artifacts.
