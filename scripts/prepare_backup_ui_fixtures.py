#!/usr/bin/env python3
"""Create synthetic backup files in a disposable simulator's local Files provider.

Creates a new fixture directory, or adds an exclusive newer-schema file to an
existing synthetic fixture directory. Existing files and app databases are never
opened or replaced.
"""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='Booted simulator UUID')
    parser.add_argument('--newer-schema', action='store_true',
                        help='Add only a new unsupported-version JSON to existing synthetic fixtures')
    args = parser.parse_args()
    devices = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'booted', '--json'], text=True))
    if not any(d['udid'] == args.device for group in devices['devices'].values() for d in group):
        parser.error('The specified simulator must be booted')
    groups = subprocess.check_output([
        'xcrun', 'simctl', 'get_app_container', args.device,
        'com.apple.DocumentsApp', 'groups'], text=True)
    locations = dict(line.split('\t', 1) for line in groups.splitlines() if '\t' in line)
    provider = locations.get('group.com.apple.FileProvider.LocalStorage')
    if not provider:
        parser.error('Local Files provider is unavailable')
    storage = Path(provider) / 'File Provider Storage'
    if not storage.is_dir():
        parser.error('Local Files storage is unavailable')
    target = storage / 'CritiqueUITestBackups'
    if args.newer_schema:
        if not target.is_dir():
            parser.error('Prepare the base synthetic fixture directory first')
    else:
        try:
            target.mkdir()
        except FileExistsError:
            parser.error('Fixture directory exists; preserve it and use a fresh disposable installation')
    state = {key: [] for key in ['habits', 'routines', 'workouts', 'foods',
                                'meals', 'water', 'goals', 'focus', 'screenTime', 'coach']}
    state.update(schema=1, profile={'username': 'Imported fixture', 'isPrivate': True},
                 settings={'theme': 'Dark', 'notifications': [], 'summaryMinute': 1200,
                           'waterTarget': 2000, 'focusMinutes': 25, 'breakMinutes': 5,
                           'backendURL': '', 'coachConsent': False})
    fixtures = {'Critique Valid Backup.json': json.dumps(state),
                'Critique Invalid Backup.json': 'synthetic invalid JSON'}
    if args.newer_schema:
        state['schema'] = 2
        fixtures = {'Critique Newer Schema Backup.json': json.dumps(state)}
    for name, contents in fixtures.items():
        with (target / name).open('x') as fixture:
            fixture.write(contents)
    print('Created synthetic files in On My iPhone / CritiqueUITestBackups; app stores unchanged.')


if __name__ == '__main__':
    main()
