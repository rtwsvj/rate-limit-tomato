## Summary

Describe the problem and the outcome of this change.

## Validation

List the commands and manual checks performed, with results.

```text
swift build
swift test
bash scripts/verify.sh
```

## Project boundaries

- [ ] No runtime networking, telemetry, account, or cloud-sync behavior was added.
- [ ] No real payment integration or purchase URL was added.
- [ ] No real vendor trademark, logo, copied asset, or vendor-specific upgrade wording was added.
- [ ] Local-data and first-launch disclaimer behavior remain intact.
- [ ] New business logic is in `TomatoCore` with tests, or the pull request explains why this is not applicable.
- [ ] User-facing UI text uses i18n keys, or the pull request explains why this is not applicable.

## Review notes

- Documentation updated, or reason not needed:
- Persistence or migration impact:
- Packaging or signing impact:
- Accessibility impact:
- New dependency and license impact:

## Visual changes

Attach before/after screenshots for UI changes. Do not include personal data or third-party proprietary assets.
