# Open-source readiness audit — 2026-07-14

## Conclusion

Rate Limit Tomato is ready for a **source-first public release**.

- Release-blocking findings: **0 P0 / 0 P1**
- Full automated suite: **261 tests passed**
- Public-tree, product-redline, version, whitespace, and locked-dependency gates: **passed**
- Release arm64 App packaging, ad-hoc signature verification, isolated launch, zero-socket probe, and ZIP round-trip verification: **passed**
- Public binary status: **not released**; Apple notarization and clean-system Gatekeeper acceptance remain separate future gates

## Adversarial review scope

The review exercised the state machine, clock changes, crash recovery, persistence failures, corrupted or oversized local data, import safety, quota reset behavior, disclaimer enforcement, notification and URL entry points, localization, snapshot rendering, packaging, signing, bundled resources, and the immutable privacy/parody constraints.

The public repository tree was also checked for private workspace records, machine-specific paths, private-key material, mutable GitHub Actions references, real AI-vendor marks, real payment links, and missing community or license files.

## Release-blocking fixes completed

- Finalized sessions are reconciled after interruption and the recovery snapshot is only cleared after history is durably written.
- Persistence writes use a strict ordering barrier so a failed history write cannot be masked by later state writes.
- Corrupt and oversized local files degrade safely instead of crashing or exhausting memory.
- Session history and user-controlled strings have bounded storage behavior; newest valid history is retained when pruning is required.
- Clock rollback no longer grants duplicate quota, while long sleep and cold-start catch-up retain normal focus/cooldown behavior.
- Non-finite numeric inputs and extreme timestamps are sanitized before conversion or persistence.
- Settings that define the active rhythm are locked during a session; appearance and language remain editable.
- Packaged Apps now include the icon, project license, third-party notices, required SwiftPM resource bundles, and single-instance declaration.
- Public documentation, runtime copy, screenshots, and launch artwork are vendor-neutral and contain fictional data only.

## Verification evidence

Executed from the repository root:

```bash
bash scripts/verify.sh
bash scripts/make-app.sh --configuration release --arch current --sign adhoc --output-dir dist/public-audit
bash scripts/verify-app.sh --app dist/public-audit/RateLimitTomato.app --arch current --sign adhoc --require-release
bash scripts/smoke-app.sh --app dist/public-audit/RateLimitTomato.app --duration 4
bash scripts/archive-app.sh --app dist/public-audit/RateLimitTomato.app --label adhoc --output-dir dist/public-audit
```

Observed results:

- Debug build and all 261 XCTest/snapshot tests passed.
- Release arm64 build completed with dependency revisions locked by `Package.resolved`.
- Code-signature, architecture, minimum macOS, version, resources, runtime paths, and product redlines passed verification.
- The isolated packaged process stayed healthy for four seconds, opened zero network sockets, did not modify production data, and left no temporary LaunchServices registration.
- The archive was extracted and independently reverified.

## Public-release boundary

This audit authorizes publishing the source repository, not advertising an unsigned or unnotarized download. A future public binary still requires Developer ID signing, hardened runtime, notarization, stapling, quarantine-aware Gatekeeper acceptance, and clean-system manual checks documented in [the release checklist](../RELEASE-CHECKLIST.md).

One deliberately deferred, non-blocking performance concern remains: a history file near the documented storage ceiling may briefly stall the menu-bar UI while it is encoded and atomically written. It does not compromise persisted-data correctness and is outside the source-release gate.
