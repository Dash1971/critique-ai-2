# Home

Home is a dark, routine-first dashboard backed by the local tracker store.

- The greeting uses the saved profile and current local date.
- Daily progress is completed scheduled habits divided by today's scheduled habits.
  No scheduled habits means 0%, with an explicit empty state.
- Generate routine proposals on-device from the current saved-record snapshot.
  Generation is user-initiated; there is no cloud fallback. Rejected or cancelled
  generation does not create habits or substitute canned advice.
- Review each proposal's name, time and repeating weekdays before adding it.
  Scheduling creates an uncompleted habit; proposals earn no XP. Deleting a
  scheduled habit does not silently recreate it from its proposal.
- Suggestions are date/timezone-bound. Scheduled habits remain after suggestions
  expire or are refreshed. Existing backup files without plans remain readable.
- Upcoming activities are saved habit/routine times today and unfinished goal
  deadlines within seven days. Untimed habits stay in the routine list.
- Focus and workout totals reflect today's saved entries. Goals show all saved
  completions and today's new completions. Weekly bars show scheduled-habit
  completion for the last seven days using current schedules, not historical
  schedule reconstruction. XP and levels use the tracker calculation.
- State changes, foreground activation and a periodic clock refresh keep the
  dashboard current. Backgrounding cancels routine generation.

The local model remains experimental. Format validation does not establish
semantic quality. Physical-device performance, notification delivery and full
accessibility acceptance require separate verification.

`prepare_home_ui_fixture.py --device UUID` exclusively creates a separate synthetic
UI-test store. Run with `--ui-testing --ui-testing-home-fixture`. Its proposal text
is a fixture, not evidence of successful model generation. Existing stores must
not be overwritten.
