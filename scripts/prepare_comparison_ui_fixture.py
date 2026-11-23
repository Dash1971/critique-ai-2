#!/usr/bin/env python3
"""Exclusively create a synthetic comparison database; never open normal data.

Keep the simulator app stopped during preparation. Existing fixtures are never
replaced. Dates use the host local calendar day, which must match the simulator.
"""
import argparse
import datetime
import json
from pathlib import Path
import sqlite3
import subprocess
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json'], text=True))
    if not any(d['udid'] == args.device for group in devices['devices'].values() for d in group):
        parser.error('The specified simulator must be booted')
    container = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.device,
                                            'com.dash1971.critiqueai2', 'data'], text=True).strip())
    target = container / 'Library/Application Support/CritiqueAI2/UITest-comparison-state.sqlite'
    target.parent.mkdir(parents=True, exist_ok=True)
    today = datetime.date.today()

    def date_string(days, minutes=0):
        day = today + datetime.timedelta(days=days)
        local = datetime.datetime.combine(day, datetime.time()) + datetime.timedelta(minutes=minutes)
        return local.astimezone(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')

    def identifier():
        return str(uuid.uuid4()).upper()

    state = {key: [] for key in ['habits', 'routines', 'workouts', 'foods', 'meals', 'water', 'goals', 'focus', 'screenTime', 'coach']}
    state.update(schema=1, profile={'username': 'Comparison fixture', 'isPrivate': True},
                 settings={'theme': 'Dark', 'notifications': [], 'summaryMinute': 1200, 'waterTarget': 2000,
                           'focusMinutes': 25, 'breakMinutes': 5, 'backendURL': '', 'coachConsent': False})
    state['habits'] = [{'id': identifier(), 'title': 'Synthetic habit', 'category': 'Routine', 'weekdays': list(range(1, 8)),
                        'created': date_string(-30), 'completed': [(today + datetime.timedelta(days=n)).isoformat() for n in [-2, -10, -20]]}]
    state['workouts'] = [{'id': identifier(), 'title': 'Synthetic workout', 'date': date_string(day, 720),
                          'minutes': minutes, 'exercises': [], 'notes': ''}
                         for day, minutes in [(-2, 30), (-10, 45), (-20, 60), (0, 100)]]
    state['focus'] = [{'id': identifier(), 'started': start, 'ended': end, 'kind': 'Work'} for start, end in
                      [(date_string(-7, -5), date_string(-7, 10)), (date_string(-1, 720), date_string(-1, 745)),
                       (date_string(-9, 720), date_string(-9, 740)), (date_string(0, 720), date_string(0, 780))]]
    try:
        with target.open('xb'):
            pass
    except FileExistsError:
        parser.error('Fixture already exists; preserve it and use a fresh disposable installation')
    with sqlite3.connect(target) as database:
        database.executescript('CREATE TABLE app_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL);'
                               'CREATE TABLE recovery (id INTEGER PRIMARY KEY, payload TEXT NOT NULL);')
        database.execute('INSERT INTO app_state VALUES (1, ?)', (json.dumps(state),))
    print('Created isolated synthetic comparison fixture; existing and normal stores untouched.')


if __name__ == '__main__':
    main()
