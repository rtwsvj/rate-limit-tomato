# Specification Decision Log

Changes to locked product decisions in `docs/SPEC.md` are recorded here.

| ID | Date | Decision | Reason |
|---|---|---|---|
| C1 | 2026-07-08 | The upgrade CTA is fixed to `Send more messages with Pro →`; no real vendor name is allowed. | Product red lines override parody fidelity. |
| C2 | 2026-07-08 | Persistence uses atomic local JSON files instead of a database framework. | Keeps the app inspectable, dependency-light, and compatible with JSON export/import. |
| C3 | 2026-07-08 | The 24-hour distribution is implemented in native SwiftUI rather than a chart framework. | The small fixed chart does not justify another runtime dependency. |
| C4 | 2026-07-08 | UI code is isolated in `RateLimitTomatoUI`; the executable target remains an app shell. | Enables deterministic rendering and keeps business logic testable. |
| C5 | 2026-07-08 | The full bilingual parody/no-charge disclaimer is used on every legal surface. | A shortened translation must not weaken a red line. |
| C6 | 2026-07-08 | Secondary bilingual lines follow the selected language rather than a separate setting. | Avoids a redundant schema field while preserving readability. |
| C7 | 2026-07-08 | The fictional five-hour window is displayed at minute precision. | A 12× mapped seconds value looks like a broken timer; the real menu-bar countdown remains precise. |
| C8 | 2026-07-08 | Three locked Swift packages provide shortcut recording, launch at login, and menu-panel access. | These system integrations benefit from mature, narrowly scoped implementations. |
| C9 | 2026-07-08 | Packaged builds support local notifications and six `rlt://` commands. | Restores useful system integration while keeping the app offline. |
| C10 | 2026-07-13 | Shipped UI, metadata, screenshots, README, and launch copy are vendor-neutral. | Keeps the parody identifiable through generic protocol language without implying affiliation. |
| C11 | 2026-07-13 | `longBreakMin` and `globalShortcut` remain decode-compatible but are inactive/ignored in v3.2.x. | Avoids breaking schema v1 while retaining one shortcut source of truth. |
| C12 | 2026-07-13 | UI interaction ranges are narrower than defensive Core decode ranges. | Normal settings stay usable while older or hand-edited data can be safely clamped. |
| C13 | 2026-07-14 | The first-launch disclaimer gate covers timer actions, settings, permissions, and third-party controls. | Merely guarding view-model actions did not prevent side effects in embedded system controls. |
| C14 | 2026-07-14 | A cross-day snapshot may restore the session phase but cannot overwrite the live day quota. | Prevents a second reset and preserves an active session across midnight. |
| C15 | 2026-07-14 | Shortcut defaults and handlers are installed only after disclaimer acknowledgement. | Constructing a shortcut default can itself write preferences. |
| C16 | 2026-07-14 | Session rhythm and quota settings are locked outside idle. | Mid-session edits could otherwise shorten/extend the active timer and reinterpret consumed quota. |
| C17 | 2026-07-14 | Catch-up transitions execute at natural phase boundaries; structurally valid unfinished sessions remain recoverable after long dormancy. | Preserves correct cooldown progress and prevents a long shutdown from discarding an unfinished focus session. |
| C18 | 2026-07-14 | Startup storage is bounded and keeps the first unreadable payload as `*.corrupt.bak`. | Prevents local-file resource exhaustion and avoids destroying the only recovery copy. |
| C19 | 2026-07-14 | Finalized session history writes precede runtime snapshots and startup reconciles missing history. | A process interruption between independent files must not permanently lose a completed session. |
| C20 | 2026-07-14 | Public distribution is source-first until a notarized, stapled build passes Gatekeeper. | Developer ID signing without notarization is not a safe general-user installation path. |
| C21 | 2026-07-14 | A persisted quota date later than the live system date is preserved across restart. | Clock rollback must not grant another daily quota when the clock returns to the same date. |
| C22 | 2026-07-14 | Finalized history is synchronously bounded by count and encoded bytes, retaining the newest records; session writes form a durability barrier before engine snapshots. | Prevents near-capacity or partial cross-file writes from losing the newest completed session and its recovery point. |
| C23 | 2026-07-14 | Structurally valid unfinished sessions remain recoverable for up to ten years. | A long shutdown must not silently discard a focus session that was still represented by a valid local snapshot. |
| C24 | 2026-07-14 | Persisted text has both character and UTF-8 byte limits. | Extended grapheme clusters can contain unbounded scalars despite a small user-perceived character count. |
