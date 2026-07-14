# Rate Limit Tomato Release Checklist

This document is the operational release gate. `docs/SPEC.md` remains the
product truth; `VERSION` is the only semantic version source. A release tag is
not required while developing or building a candidate.

## 1. Release invariants

- `VERSION` contains exactly one stable `MAJOR.MINOR.PATCH` line.
- `CFBundleShortVersionString`, `CFBundleVersion`, archive name, release notes,
  and final tag are derived from that value.
- `Package.resolved` is committed and all build/test commands use
  `--only-use-versions-from-resolved-file`.
- `*.bundle` resources from SwiftPM are present in the packaged app.
- The app icon, project license, and `THIRD_PARTY_NOTICES.md` are present in
  the packaged app resources.
- `LSMultipleInstancesProhibited` is enabled to prevent competing writers.
- An ad-hoc artifact is labeled `adhoc` and is never described as a public
  release.
- A public artifact is universal, Developer ID signed with hardened runtime,
  notarized, stapled, and accepted by Gatekeeper.
- The release scripts never fall back from Developer ID to ad-hoc signing and
  never fall back from universal to a thin binary.

“Reproducible” here means a clean checkout can rebuild from locked inputs and
the resulting artifact is traceable through `release-manifest.json` and
`SHA256SUMS`. Secure timestamps and Apple notarization tickets are external
inputs, so a notarized zip is not expected to be byte-for-byte reproducible.

## 2. Development gate (no tag required)

```bash
rtk bash scripts/verify.sh
rtk bash scripts/check-version.sh
```

The gate runs the locked build and complete test suite, rejects warnings from
owned `Sources/` and `Tests/`, checks `git diff --check`, validates the source
version contract, and scans the immutable no-network/no-payment/no-vendor red
lines.

SwiftPM applies `-Xswiftc` flags to dependency checkouts too. For that reason,
the canonical gate parses compiler diagnostics and treats only warnings from
this repository as errors; third-party warnings remain visible without making
the release depend on an upstream package's warning policy.

## 3. Internal candidate

Current architecture:

```bash
rtk bash scripts/make-app.sh \
  --configuration release \
  --arch current \
  --sign adhoc
rtk bash scripts/smoke-app.sh --app dist/RateLimitTomato.app
rtk bash scripts/archive-app.sh \
  --app dist/RateLimitTomato.app \
  --label adhoc
```

Universal candidate:

```bash
rtk bash scripts/make-app.sh \
  --configuration release \
  --arch universal \
  --sign adhoc
```

If either arm64 or x86_64 cannot compile, universal mode stops. A thin
`current` build may still be used for local QA but cannot pass the public
release gate.

Expected candidate outputs:

- `dist/RateLimitTomato.app`
- `dist/RateLimitTomato-v<VERSION>-macOS-<ARCH>-adhoc.zip`
- `dist/release-manifest.json`
- `dist/SHA256SUMS`

## 4. Developer ID candidate

List identities and select the exact Developer ID Application identity; do not
select an Apple Development identity:

```bash
rtk security find-identity -v -p codesigning
```

Then build and sign:

```bash
RLT_SIGN_IDENTITY='Developer ID Application: NAME (TEAMID)' \
  rtk bash scripts/make-app.sh \
    --configuration release \
    --arch universal \
    --sign developer-id
rtk bash scripts/verify-app.sh \
  --app dist/RateLimitTomato.app \
  --arch universal \
  --sign developer-id
```

Using the private signing key can trigger a Keychain authorization prompt. It
is an explicit release action, not part of ordinary CI.

## 5. Notarization

Create a Keychain profile once, interactively. Never put the Apple password or
API key in the repository, command history, or a manifest:

```bash
rtk xcrun notarytool store-credentials RLT-notary
```

Submit, wait, staple, validate, and run Gatekeeper assessment:

```bash
rtk bash scripts/notarize-app.sh \
  --app dist/RateLimitTomato.app \
  --keychain-profile RLT-notary
```

The script stores the submission response/log by submission id under `dist/`.
It modifies the candidate app only after Apple returns `Accepted`.

Archive the stapled app, not the pre-staple app:

```bash
rtk bash scripts/archive-app.sh \
  --app dist/RateLimitTomato.app \
  --label notarized
```

Final mechanical evidence:

```bash
rtk codesign --verify --deep --strict --verbose=2 dist/RateLimitTomato.app
rtk xcrun stapler validate dist/RateLimitTomato.app
rtk spctl --assess --type execute --verbose=4 dist/RateLimitTomato.app
rtk lipo -archs dist/RateLimitTomato.app/Contents/MacOS/RateLimitTomato
rtk shasum -a 256 -c dist/SHA256SUMS
```

The `SHA256SUMS` executable and plist paths are relative to `dist/`; run its
check from the artifact directory if verifying every line. The archive hash
may also be compared directly with its recorded line.

## 6. Human app acceptance

Complete every item in `docs/APP-SMOKE-CHECKLIST.md` on a clean macOS test
account or VM. Do not use a maintainer's production account for URL registration,
notification authorization, shortcut, or Launch at Login acceptance.

## 7. Version cut and tag

Only after all code fixes and the complete gate are green:

1. Update `VERSION` and ensure `docs/releases/v<VERSION>.md` is final.
2. Run `rtk bash scripts/check-version.sh --release --clean` before tagging.
3. Build, sign, notarize, archive, and complete app acceptance.
4. Create the local annotated tag `v<VERSION>`.
5. Run `rtk bash scripts/check-version.sh --release --require-tag --clean`.
6. Push/tag/publish only after reviewing `release-manifest.json`,
   `SHA256SUMS`, and the notarization response.

Tagging, pushing, publishing a release, using the private signing key, and
submitting to Apple are external state changes and must remain visible actions.

## 8. Rollback

- Source/CI/script changes are split into reviewable commits and reverted with
  `git revert`; never reset or overwrite unrelated user work.
- Packaging uses a staging directory and promotes only a verified app/archive.
- Failed staging directories are removed; an existing artifact is restored if
  promotion fails.
- `make-app.sh`, `archive-app.sh`, and `notarize-app.sh` share
  `dist/.rlt-release.lock` so only one release mutation can run per output
  directory. After SIGKILL or power loss, inspect any `.rlt-*` work directory,
  restore its `previous-*` files if present, and only then remove the stale
  lock. Multi-file promotion does not claim power-loss atomicity.
- A notarization submission does not publish the app. On rejection, retain its
  log, fix the cause, and create a new candidate.
- Before push, a bad local tag can be removed and recreated. After push or
  publication, unpublish/delete operations require a separate explicit review.
