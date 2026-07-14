# Contributing to Rate Limit Tomato

Thanks for helping improve Rate Limit Tomato. This project is a local-only macOS menu-bar Pomodoro app built with Swift. Please keep changes focused, reviewable, and consistent with the product specification in `docs/SPEC.md`.

## Before you start

- Use macOS 14 or later and Swift 5.9 or later.
- Search existing issues before opening a new one.
- For a security vulnerability, follow `SECURITY.md` instead of opening a detailed public issue.
- Discuss large product or architecture changes in an issue before investing in an implementation.

## Build and test

```bash
swift build
swift test
bash scripts/verify.sh
```

Run the development app with:

```bash
swift run RateLimitTomato
```

Before submitting a pull request, run the verification script and any focused tests relevant to the change. Packaging changes should also be checked with the applicable scripts under `scripts/`.

## Architecture and code rules

- Put platform-neutral business logic in `Sources/TomatoCore/` and add XCTest coverage in `Tests/TomatoCoreTests/`.
- Keep SwiftUI views and macOS services in `Sources/RateLimitTomatoUI/`.
- Keep `Sources/RateLimitTomato/` as the minimal `@main` application shell.
- Inject time through `TomatoClock`; do not make business logic depend directly on the system clock.
- Route user-facing UI text through i18n keys. Do not hard-code display copy in views.
- Do not remove the resource-bundle copy logic from `scripts/make-app.sh`; packaged apps require it.
- Preserve Swift 5 language mode and the macOS 14 deployment target unless a separately reviewed compatibility change updates the specification.

## Non-negotiable product boundaries

Every contribution must preserve these rules:

1. No runtime network requests, telemetry, accounts, or cloud sync.
2. No real payment integration and no links to real purchase or upgrade pages.
3. No real vendor trademarks, logos, copied product assets, or vendor-specific upgrade wording.
4. All user data remains local.
5. The parody disclaimer remains visible where required, and first launch requires acknowledgement.

Build-time dependency downloads are distinct from runtime behavior, but new dependencies still require a clear rationale and license review.

## Documentation

`docs/SPEC.md` is the product source of truth. If behavior changes, update the specification and `docs/CHANGES.md` in the same pull request. Keep documentation factual and free of private development-session details, local machine paths, credentials, or personal data.

## Pull requests

Keep each pull request to one coherent change. Include:

- the problem and the chosen solution;
- tests run and their results;
- screenshots for visible UI changes;
- documentation changes or a short explanation of why none are needed;
- any packaging, persistence, accessibility, privacy, or migration impact.

Do not commit generated build output, local application data, signing material, credentials, or unrelated workspace changes.

By contributing, you agree that your contribution is licensed under the repository's license.
