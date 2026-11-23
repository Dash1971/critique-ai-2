#!/usr/bin/env python3
"""Create a disposable failed-load fixture in an installed simulator app.

Run before the matching isolated failed-load UI test. Never opens the
normal database or overwrites an existing fixture. Keep the application stopped
while preparing it. Generated data remains in the simulator, not the repository.
"""
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True, help='Booted simulator UUID')
    parser.add_argument('--scenario', choices=['previous-save', 'backup-import'],
                        default='previous-save')
    args = parser.parse_args()
    devices = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'booted', '--json'], text=True))
    if not any(d['udid'] == args.device for group in devices['devices'].values() for d in group):
        parser.error('The specified simulator must be booted')
    container = Path(subprocess.check_output([
        'xcrun', 'simctl', 'get_app_container', args.device,
        'com.dash1971.critiqueai2', 'data'], text=True).strip())
    filename = ('UITest-backup-import-state.sqlite' if args.scenario == 'backup-import'
                else 'UITest-recovery-state.sqlite')
    target = container / 'Library/Application Support/CritiqueAI2' / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    # Exclusive creation: a prior test's database and evidence must survive.
    try:
        with target.open('xb'):
            pass
    except FileExistsError:
        parser.error('Fixture already exists; preserve it and use a fresh disposable installation')
    state = {key: [] for key in ['habits', 'routines', 'workouts', 'foods',
                                'meals', 'water', 'goals', 'focus', 'screenTime', 'coach']}
    state.update(schema=1, profile={'username': 'Recovered fixture', 'isPrivate': True},
                 settings={'theme': 'Dark', 'notifications': [], 'summaryMinute': 1200,
                           'waterTarget': 2000, 'focusMinutes': 25, 'breakMinutes': 5,
                           'backendURL': '', 'coachConsent': False})
    with sqlite3.connect(target) as database:
        database.executescript('''
            CREATE TABLE app_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL);
            CREATE TABLE recovery (id INTEGER PRIMARY KEY, payload TEXT NOT NULL);
            INSERT INTO app_state VALUES (1, 'synthetic invalid JSON');
        ''')
        database.execute('INSERT INTO recovery VALUES (1, ?)', (json.dumps(state),))
    print('Created isolated failed-load fixture; normal and existing UI-test stores unchanged.')


if __name__ == '__main__':
    main()
