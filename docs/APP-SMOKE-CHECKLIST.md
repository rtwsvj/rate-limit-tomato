# Packaged App Smoke Checklist

## Safe automated smoke

The default smoke intentionally does **not** launch through LaunchServices. It
copies the complete signed app to a temporary runtime, then launches with an
isolated `HOME`, `TMPDIR`, `RLT_TIME_SCALE`, and
`RLT_DISABLE_GLOBAL_INTEGRATIONS=1`. Keeping the full bundle preserves the
Developer ID resource seal. macOS may still discover a directly launched app,
so cleanup unregisters only this run's exact temporary bundle path and verifies
that it is absent before deleting the temporary directory.

```bash
rtk bash scripts/smoke-app.sh --app dist/RateLimitTomato.app
```

It verifies:

- the packaged app first passes `verify-app.sh`;
- the executable remains alive for the smoke window;
- no network socket is opened;
- NotificationService, global shortcuts, and URL handlers stay disabled by the
  explicit smoke-only environment gate, so they cannot mutate system state;
- QA storage stays under the temporary directory;
- the maintainer's real `Application Support/RateLimitTomato` tree is byte-for-byte
  unchanged before and after the run;
- no Launch at Login setting, global shortcut preference, or URL handler is
  changed, and no temporary LaunchServices registration remains after cleanup.

If exact-path unregistration or verification fails, the smoke exits non-zero
and preserves the temporary app path printed in the error. It never rebuilds or
clears the global LaunchServices database.

This probe is safe for local development and CI, but it is not a substitute for
full system integration acceptance.

## Full `.app` acceptance environment

Use a clean macOS test user or disposable VM. The exact signed candidate uses
the production bundle id, so launching it can register `rlt://`, request
notification authorization, and expose a Launch at Login toggle. Do not run
these steps in a maintainer's main account unless those state changes are explicitly
approved and their original state is recorded.

Record before starting:

- macOS version and architecture;
- candidate zip SHA-256;
- whether Rosetta is installed when testing x86_64 on Apple silicon;
- existing notification, shortcut, and login-item state for the test account.

## Mechanical checks after extraction

- [ ] Zip extracts without warnings or path traversal.
- [ ] App version and build version equal `VERSION`.
- [ ] `lipo -archs` reports exactly `arm64 x86_64` in either order.
- [ ] `codesign --verify --deep --strict` passes.
- [ ] `stapler validate` passes.
- [ ] `spctl --assess --type execute` reports accepted.
- [ ] App opens from a quarantined copy without bypassing Gatekeeper.
- [ ] No Dock icon appears; the menu bar item appears once.

## First launch and hard red lines

- [ ] First launch blocks product actions behind the disclaimer.
- [ ] Declining/closing cannot start a focus via UI, global shortcut, or URL.
- [ ] Accepting persists across a normal quit/relaunch.
- [ ] Upgrade surface always shows the permanent parody/no-charge disclaimer.
- [ ] Upgrade action stays local and opens no browser/payment flow.
- [ ] No real vendor name or logo is visible.
- [ ] Network observation remains empty for the complete session.

## Core menu-bar flow

- [ ] IDLE → SENDING → FOCUSING → COMPLETED → RATE_LIMITED → RESET → IDLE.
- [ ] Menu-bar countdown advances while the panel is closed.
- [ ] Abort, skip cooldown, exhausted quota, and 418 paths behave correctly.
- [ ] Provider A/B/C preserve layout and readable contrast.
- [ ] Settings and Usage windows open, refresh, close, and reopen.
- [ ] Native controls in Settings are visible and have full expected hit areas.
- [ ] Usage populated and empty states render correctly.

Use a scaled QA run only in the disposable account when speeding up the full
cycle. Confirm afterward that no QA directory is mistaken for production data.

## System integrations

- [ ] `rlt://send`, `rlt://startstop`, `rlt://usage`, and `rlt://settings` route
      to the already-running candidate.
- [ ] Cold-start URL routing replays the pending command exactly once.
- [ ] Default global shortcut works and does not fire twice.
- [ ] Shortcut conflict/reassignment is understandable and persists.
- [ ] Notification request appears only when expected.
- [ ] Completion/reset banners use the chosen language.
- [ ] Notification body click opens the panel.
- [ ] Notification actions perform skip/start exactly once.
- [ ] Launch at Login can be enabled, survives logout/login, and can be disabled.
- [ ] Restore the original login-item, shortcut, and notification state before
      leaving the test account.

## Persistence, sleep, and architecture

- [ ] Quit during focus, relaunch, and confirm phase/time/session restoration.
- [ ] Completion is persisted exactly once after relaunch.
- [ ] Midnight reset does not interrupt an active focus.
- [ ] Sleep/wake catches up by wall clock without replaying a full cooldown.
- [ ] Native arm64 launch passes.
- [ ] x86_64/Rosetta launch passes on Apple silicon, or a native Intel launch
      passes on the CI/test Mac.

Actual sleep, login/logout, notification authorization, and Launch at Login
modify system state. They must remain manual, visible steps; automation must not
invoke `pmset sleepnow` or toggle login items.

## Closeout evidence

- [ ] Save screenshots of all nine primary states and Settings/Usage surfaces.
- [ ] Record any OS-specific visual differences.
- [ ] Attach `release-manifest.json`, `SHA256SUMS`, notarization response, and
      the completed checklist to the release record.
- [ ] Verify the final uploaded asset hash still matches the local final zip.
