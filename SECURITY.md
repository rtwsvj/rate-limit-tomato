# Security Policy

Rate Limit Tomato is a local-only macOS application. Security reports are welcome, especially for issues involving local data integrity, malformed persistence files, URL-scheme or notification actions, disclaimer and permission boundaries, packaging, or dependency supply-chain risk.

## Supported code

Security fixes target the current `main` branch and, when practical, the latest published release. Older releases may not receive fixes; verify a report against the newest available version first.

## Reporting a vulnerability

Do not disclose sensitive vulnerability details in a public issue or pull request.

If GitHub Private Vulnerability Reporting is enabled for this repository, open the repository's **Security** tab and choose **Report a vulnerability**. Include:

- affected version or commit;
- macOS version and installation method;
- minimal reproduction steps or a proof of concept;
- expected and actual behavior;
- security impact and any known mitigation;
- only the logs or sample data needed to reproduce the issue.

Remove credentials, personal data, signing identities, and unrelated local files from the report.

If private vulnerability reporting is not available, open a minimal public issue asking maintainers to enable a private reporting channel. Do not include exploit details in that issue. This project does not publish or invent an email address as a security contact.

Maintainers will coordinate validation, remediation, and disclosure through the private report. Response and release timing depends on severity and maintainer availability; no fixed service-level deadline is promised.

## Project security boundaries

The following are product invariants and should be reported if violated:

- no runtime network access or telemetry;
- no account or cloud-sync behavior;
- no real payment flow or purchase URL;
- no use of real vendor trademarks or copied proprietary assets;
- local data must fail safely when malformed or partially written;
- state-changing URL, notification, and shortcut actions must respect the disclaimer gate.

The app's local JSON files are writable by the same macOS user and are not an authorization or anti-tampering boundary. Reports about crashes, resource exhaustion, or data loss caused by malformed local files are still in scope.

Please test in good faith, avoid accessing other people's data, and stop if testing could cause lasting data loss or system disruption.
