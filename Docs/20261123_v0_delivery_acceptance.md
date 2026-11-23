# Delivery acceptance ledger — 2026-11-23

This is an unfinished independent application, not a TestFlight delivery.
The confirmed physical target is iPhone 13. This ledger distinguishes
implemented paths, observed evidence, and requirements not yet fulfilled.

## Verified checkpoints

- Core storage: SQLite/WAL persistence, validation before atomic save, recovery
  snapshot and validated JSON backup. The 33-test core suite passed.
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
- Current complete-core source passes 33 tests. A build is not a substitute for
  exercising every feature or testing physical-device resources.

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
| Profile/settings | Local nickname/photo/theme; backup export/restore/reset controls | Photo, file-picker, confirmation, restore and theme UI validation |
| Notifications | Per-type settings, permission request, real local queue, foreground delegate | Permission/delivery/deadline/streak/timer behavior on real devices |
| AI coach | Actual bounded saved data, checked facts/proposals, history, local diagnostics | Full quality/held-out corpus, missing workout detail/long-term comparison, physical resource and lifecycle gates |
| Friends/challenges | No fake profiles, scores or decorative controls | Optional social/privacy/sharing and weekly leaderboard implementation/integration |
| Synchronization | Local-only state, explicit backup/restore | CloudKit/account/container/conflict and multi-device integration |
| Desktop | Adaptive sidebar design in shared native UI | Desktop runtime target, compile and actual desktop verification |
| Distribution | Unsigned development builds only | App registration, reviewed signing configuration, archive/bundle audit and TestFlight processing/tester access |

## Release-blocking evidence

Small raw models produced false personal facts and unsuitable advice. Protected
format checks, app-owned statistics and capability boundaries reduce specific
failure modes; they do not certify arbitrary advice. The larger comparison is
not a demonstrated upgrade. No cloud key or exposed Mac-mini service is used.

No physical iPhone timing, certified peak memory, sustained battery/heat or
repeated lifecycle result exists yet. Simulator timing is not phone timing.
The standalone evaluation app's earlier no-result smoke remains retained as a
failed attempt; a later main-tracker integration smoke passed separately.

## Evidence locations

All generated outputs stay under ignored build/verification; model weights and
pinned vendor sources stay under ignored local/. The dated evaluation checkpoint
and trial manifests map exact model/source/policy/validator revisions. Do not
replace old failure evidence or label routed out-of-scope cases as model passes.
