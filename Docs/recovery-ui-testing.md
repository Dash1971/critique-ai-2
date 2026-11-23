# Recovery UI tests

Use a disposable, booted iOS simulator with the Debug app installed. Normal
application data is never a fixture. `--ui-testing` selects a separate persistent
store; `--ui-testing-recovery-fixture` selects an additional isolated store only
when combined with `--ui-testing`.

With the simulator application stopped, prepare the failed-load fixture:

```sh
python3 scripts/prepare_recovery_ui_fixture.py --device SIMULATOR_UUID
```

The script creates `UITest-recovery-state.sqlite` exclusively. It refuses to
overwrite an earlier fixture. Preserve prior results and use a fresh disposable
installation when another fixture is needed.

Run `TrackerUITests/TrackerUITests/testFailedLoadRecoveryPreservesDataUntilConfirmed` with
`xcodebuild test -only-testing:` on that simulator. It checks failed-load retry,
file-picker cancellation, recovery cancellation, explicit confirmation and
relaunch persistence. A valid recovery snapshot is synthetic; the current row
is deliberately unreadable JSON. No normal-store corruption is involved.

`testPreviousSaveRecoveryConfirmsAndPersistsAcrossRelaunch` separately exercises
two successful saves and one-level recovery using the regular UI-test store.
Confirmation popovers may expose an outside-dismiss region instead of Cancel;
both dismissal paths must preserve the saved data.
