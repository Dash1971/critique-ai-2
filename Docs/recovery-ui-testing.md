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

For `testFailedLoadBackupImportRequiresConfirmationAndPersists`, prepare an
independent store without replacing the previous-save fixture:

```sh
python3 scripts/prepare_recovery_ui_fixture.py --device SIMULATOR_UUID \
  --scenario backup-import
```

This exclusively creates `UITest-backup-import-state.sqlite`. The test combines
`--ui-testing` and `--ui-testing-backup-import-fixture`; without `--ui-testing`,
fixture flags never select a test database. It checks cancelled import across a
failed-load relaunch, then confirmed native JSON import and restored-profile
relaunch persistence. The focused regression passed; the older synthetic stores
and exported backup were independently checked for preservation.

Run `TrackerUITests/TrackerUITests/testFailedLoadRecoveryPreservesDataUntilConfirmed` with
`xcodebuild test -only-testing:` on that simulator. It checks failed-load retry,
file-picker cancellation, recovery cancellation, explicit confirmation and
relaunch persistence. A valid recovery snapshot is synthetic; the current row
is deliberately unreadable JSON. No normal-store corruption is involved.

`testPreviousSaveRecoveryConfirmsAndPersistsAcrossRelaunch` separately exercises
two successful saves and one-level recovery using the regular UI-test store.
Confirmation popovers may expose an outside-dismiss region instead of Cancel;
both dismissal paths must preserve the saved data.

`testBackupExportCancellationPreservesSavedProfile` opens the native export
picker from Settings, cancels it, and verifies that no save-error alert appears
and the saved profile survives relaunch. It uses only the separate UI-test store.
This cancellation check does not establish successful file export or import.

For native import checks, create a new synthetic Files-provider directory:

```sh
python3 scripts/prepare_backup_ui_fixtures.py --device SIMULATOR_UUID
```

The helper exclusively creates `On My iPhone / CritiqueUITestBackups` with valid
and malformed JSON files. It refuses to reuse an existing directory and never
opens an app database. This setup depends on the simulator's local Files-provider
layout; it is not a physical-device provisioning procedure.

`testValidBackupImportRequiresConfirmationAndPersistsAcrossRelaunch` selects the
valid JSON through the native picker, cancels the replacement confirmation,
checks that the saved profile is unchanged, then confirms a second selection and
checks the restored profile after relaunch. Run this test independently from the
failed-load fixture check.

The focused valid-backup import check passed from Settings, including
confirmation cancellation and confirmed restoration across relaunch.
`testInvalidBackupShowsErrorWithoutReplacingSavedData` also passed: malformed
JSON produces a visible error, no replacement confirmation and no profile change
after relaunch. File import from a separate failed-load fixture also passed.
Newer-schema/semantic-invalid backup UI remains open. Fixture preparation alone
does not establish restore acceptance.

Synchronize import checks on the picker-owned Search field before querying its
folders. A Cancel button can belong to the underlying Settings sheet and is not
a picker-readiness signal. Allow the native folder accessibility subtree to
attach before attempting location navigation.

`testBackupExportWritesNativeJSONDocument` passed together with a byte-for-byte
comparison against the isolated saved state. The export picker exposes its
current folder as an Actions Menu button and
commits with Save in `FullDocumentManagerViewControllerNavigationBar`; do not
match the Settings Save button. A dismissed picker alone is insufficient:
compare the new exported JSON with the isolated saved state before recording an
export pass. Refuse existing output filenames and preserve prior files.

After a fresh native export, verify the real file without reading normal app
storage or printing its contents:

```sh
python3 scripts/verify_backup_ui_export.py --device SIMULATOR_UUID \
  --file-name EXPORTED_JSON_BASENAME --log TEST_LOG
```

The verifier requires the matching test's synthetic profile marker and compares
all exported bytes and decoded fields to `UITest-state.sqlite`, opened read-only.
Its result contains only byte count, checksum and verification flags. The test
log, exported backup and generated verification output remain local.
