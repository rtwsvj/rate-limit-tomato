# Dependency Record

Rate Limit Tomato has three direct runtime dependencies. Swift Package Manager
locks the exact versions and revisions in `Package.resolved`; builds and tests
use `--only-use-versions-from-resolved-file`.

| Package | Purpose | Locked version | Locked revision | License |
|---|---|---:|---|---|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global shortcut recording and handling | 2.4.0 | `1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27` | MIT |
| [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) | Launch-at-login integration | 1.1.0 | `a04ec1c363be3627734f6dad757d82f5d4fa8fcc` | MIT |
| [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) | Menu-bar panel access | 1.3.0 | `33bb0e4b1e407feac791e047dcaaf9c69b25fd26` | MIT |

The project does not intentionally include analytics, networking, account,
payment, advertising, or crash-reporting SDKs. Package source URLs are used by
SwiftPM at build time; the application itself makes no runtime network request.

Full copyright and license text is preserved in
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) and copied into every
packaged app.

## Updating dependencies

1. Review upstream release notes, source changes, license, and package graph.
2. Update one dependency at a time and commit the resulting `Package.resolved`.
3. Run `bash scripts/verify.sh` and the packaged-app verification gate.
4. Update this file and `THIRD_PARTY_NOTICES.md` when a version, revision,
   source, copyright notice, or license changes.
