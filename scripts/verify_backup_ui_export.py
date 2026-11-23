#!/usr/bin/env python3
"""Verify a native UI-test export against the isolated saved SQLite payload.

Reads only the UI-test database and an explicitly named synthetic Files fixture.
Requires the matching test's synthetic-profile marker. Never reads normal app
storage or prints the profile, database payload or machine-local paths.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--file-name', required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    if Path(args.file_name).name != args.file_name or not args.file_name.endswith('.json'):
        parser.error('Use a JSON basename, not a path')
    markers = re.findall(r'^BACKUP_EXPORT_EXPECTED_PROFILE\|(Export [A-Fa-f0-9]{6})\s*$',
                         args.log.read_text(), re.MULTILINE)
    if len(markers) != 1:
        parser.error('Expected exactly one synthetic export-profile marker')
    groups = dict(line.split('\t', 1) for line in subprocess.check_output([
        'xcrun', 'simctl', 'get_app_container', args.device,
        'com.apple.DocumentsApp', 'groups'], text=True,
        stderr=subprocess.PIPE).splitlines() if '\t' in line)
    storage = Path(groups['group.com.apple.FileProvider.LocalStorage']) / 'File Provider Storage'
    exported = (storage / 'CritiqueUITestBackups' / args.file_name).read_bytes()
    container = Path(subprocess.check_output([
        'xcrun', 'simctl', 'get_app_container', args.device,
        'com.dash1971.critiqueai2', 'data'], text=True, stderr=subprocess.PIPE).strip())
    database = container / 'Library/Application Support/CritiqueAI2/UITest-state.sqlite'
    with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as connection:
        row = connection.execute('SELECT payload FROM app_state WHERE id=1').fetchone()
    if row is None:
        parser.error('No isolated saved state exists')
    saved = row[0].encode('utf-8')
    exported_state, saved_state = json.loads(exported), json.loads(saved)
    if (exported != saved or exported_state != saved_state or exported_state.get('schema') != 1
            or exported_state.get('profile', {}).get('username') != markers[0]):
        parser.error('Export does not exactly match the synthetic saved state')
    print(json.dumps({'status': 'verified', 'bytes': len(exported),
                      'sha256': hashlib.sha256(exported).hexdigest(),
                      'saved_payload_bytes_match': True, 'schema': 1,
                      'synthetic_profile_matches': True, 'all_state_fields_match': True}))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, sqlite3.Error, subprocess.CalledProcessError):
        raise SystemExit('Backup UI export verification failed; check the local fixture and test log.') from None
