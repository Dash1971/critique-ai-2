# Delivery acceptance ledger — 2026-11-23

This is an unfinished independent application, not a TestFlight delivery.
Physical-device acceptance remains open. This ledger distinguishes
implemented paths, observed evidence, and requirements not yet fulfilled.

## Verified checkpoints

- Core storage: SQLite/WAL persistence, validation before atomic save, recovery
  snapshot and validated JSON backup. The updated 38-test core suite passed,
  including five recovery cases: absent snapshot, restore/undo across reopen,
  corrupt current data, invalid/newer snapshot and transaction rollback on write
  failure. All fixtures are disposable synthetic databases.
- Tracker UI: habit/meal/focus relaunch persistence and goal/workout/calendar
  flows passed. A missing editor error alert was reproduced, fixed and its
  negative regression passed. Other CRUD paths are implemented but not all
  exercised end-to-end. The profile/settings navigation, save and relaunch
  regression also passed after fixing draft reinitialization.
- Runtime: 30 checks passed, including real inference, context overflow,
  cancellation, chat framing, reasoning suppression and constrained generation.
- Main coach: simulator build and native pipeline smoke passed using saved
  tracker test records. Checked output and two conversation messages persisted.
  Raw output is not presented as checked advice. The model is not release-approved.
- Current complete-core source passes 38 tests. A build is not a substitute for
  exercising every feature or testing physical-device resources.
- Previous-save UI recovery: cancellation preserves the latest profile;
  confirming restores the preceding profile and persists across relaunch. The
  focused simulator regression passed. A compact-popover selector failure was
  corrected in the test; it was not an observed application data-loss failure.
- Failed-load UI recovery: a separate corrupt-data fixture passed retry without
  reset, backup-picker cancellation, recovery cancellation, explicit recovery,
  restored profile across relaunch and disabling an unreadable recovery row.
- Failed-load backup-file import: a separate unreadable-store fixture passed
  native JSON selection, cancellation preserving the failed state across
  relaunch, confirmed replacement and imported-profile relaunch persistence.
  Read-only checks confirmed the earlier synthetic stores and export survived.
- Backup export cancellation: the native export picker opens from Settings;
  cancellation shows no save-error alert and preserves the saved profile across
  relaunch. The focused simulator regression passed. No file was exported.
- Valid backup import: native JSON selection from Settings, cancellation of the
  replacement confirmation without changing the saved profile, confirmed import
  and the imported profile after relaunch passed a focused simulator regression.
- Malformed JSON import: native file selection shows a validation-error alert,
  offers no replacement confirmation and preserves the saved profile across
  relaunch. The focused simulator regression passed. Newer-schema and
  semantically invalid backup UI cases are not covered by this check.
- Native JSON export: a new file saved through the native picker matched the
  isolated synthetic SQLite payload byte-for-byte, including schema, profile
  and collection fields. The focused UI regression and separate read-only file
  verifier passed. This is a synthetic-state check, not physical-device approval.

## Implementation and outstanding gates

| Area | Present locally | Still required before claiming complete |
| --- | --- | --- |
| Independent identity/storage | Own app ID/source/store; original icon retained; public MIT-licensed source mirror | Separate Apple release setup and distribution acceptance |
| Dashboard | Computed daily tracker facts, completion chart, XP/badges | Full chart/layout/accessibility review and broader streak/progress presentation |
| Habits | Create/edit/delete, weekdays, completion history/streaks, reminders | Full edit/delete/schedule UI coverage |
| Workouts | Routines, weekdays, exercises/sets/reps/kg/duration, history/chart/PR | Full routine/edit/delete and timer interoperability checks |
| Nutrition | Editable custom foods/meals/macros/water and day history | Complete CRUD/category/history UI coverage |
| Goals | Cadences, target/progress/deadline, history/completion | Deadline/cadence/edit/delete UI coverage and broader history presentation |
| Focus/calendar | Persistent work/break/rest timers, session history, dated activity | Background/lifecycle boundaries and expanded date/layout checks |
| Screen time | Clearly marked manual journal | Automatic collection/reporting requires native permission/entitlement integration; not implemented |
| Profile/settings | Local nickname/photo/theme; backup export/restore/reset controls; atomic previous-save restore; failed-load retry/restore and backup-file import; valid JSON import confirmation/cancellation/relaunch, malformed JSON rejection and native export bytes verified | Photo, newer-schema/semantic-invalid backup UI and theme validation |
| Notifications | Per-type settings, permission request, real local queue, foreground delegate | Permission/delivery/deadline/streak/timer behavior on real devices |
| AI coach | Actual bounded saved data, checked facts/proposals, history, local diagnostics | Full quality/held-out corpus, missing workout detail/long-term comparison, physical resource and lifecycle gates |
| Friends/challenges | No fake profiles, scores or decorative controls | Optional social/privacy/sharing and weekly leaderboard implementation/integration |
| Synchronization | Local-only state, explicit backup/restore | CloudKit/account/container/conflict and multi-device integration |
| Desktop | Adaptive sidebar design in shared native UI | Desktop runtime target, compile and actual desktop verification |
| Distribution | Unsigned development builds only | App registration, reviewed signing configuration, archive/bundle audit and TestFlight processing/tester access |

## Release-blocking evidence

The 60-case wording-robustness batch reused seven synthetic saved histories.
The unchanged Swift contract accepted 53 responses and rejected seven: three
incomplete generations and four with no surviving suggestion or question.
Manual review of every case found eight adequate bounded suggestions and 45
accepted responses with relevance or grounding concerns. These qualitative
assessments are not a release score or an unseen-history evaluation. Common
problems include generic advice that does not answer the question, assumed
goal progress, weak rest-day handling and unsolicited health-related cautions.
The model remains provisional; structural acceptance is not coaching approval.

Small raw models produced false personal facts and unsuitable advice. Protected
format checks, app-owned statistics and capability boundaries reduce specific
failure modes; they do not certify arbitrary advice. The larger comparison is
not a demonstrated upgrade. No cloud key or exposed Mac-mini service is used.

No physical iPhone timing, certified peak memory, sustained battery/heat or
repeated lifecycle result exists yet. Simulator timing is not phone timing.
The standalone evaluation app's earlier no-result smoke remains retained as a
failed attempt; a later main-tracker integration smoke passed separately.

## Backup and recovery behavior

- A JSON import is decoded and validated before a replacement confirmation is
  offered. Confirming it writes atomically; a rejected import or failed write
  does not install partial data. Cancelling does not replace records.
- “Restore previous save” restores only the immediately preceding committed
  version. It validates that snapshot while holding the write transaction. The
  replaced payload becomes the recovery row until the next successful save;
  an unreadable payload is not offered as a valid recovery candidate. This is
  one-level recovery, not a dated archive. Ordinary saves, including timer
  settlement, advance it. Export backups separately for long-term retention.
- When current data cannot be decoded, the screen offers retry, previous-save
  recovery (only if valid), and backup import. No restore is automatic and no
  blank-state reset is performed. If SQLite itself cannot be opened, retry must
  succeed before any restore can write; physical-file corruption repair is not
  implemented. Backups contain profile/activity data and should be kept private.

## Evidence locations

All generated outputs stay under ignored build/verification; model weights and
pinned vendor sources stay under ignored local/. The dated evaluation checkpoint
and trial manifests map exact model/source/policy/validator revisions. Do not
replace old failure evidence or label routed out-of-scope cases as model passes.
