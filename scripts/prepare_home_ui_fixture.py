#!/usr/bin/env python3
"""Exclusively create synthetic Home UI data. Never replace an existing store.

Stop the test app first. Proposal text is a UI fixture, not model-quality evidence.
The normal database and the other UI fixture databases are never opened.
"""
import argparse
import datetime as dt
import json
from pathlib import Path
import sqlite3
import subprocess
import uuid


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    raw = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', args.device,
                                   'com.dash1971.critiqueai2', 'data'], text=True, timeout=20)
    target = Path(raw.strip()) / 'Library/Application Support/CritiqueAI2/UITest-home-state.sqlite'
    target.parent.mkdir(parents=True, exist_ok=True)
    today = dt.date.today()

    def stamp(days=0, minute=0):
        local = dt.datetime.combine(today + dt.timedelta(days=days), dt.time()) + dt.timedelta(minutes=minute)
        return local.astimezone(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')

    def identifier():
        return str(uuid.uuid4()).upper()

    state = {key: [] for key in ['habits', 'routines', 'workouts', 'foods', 'meals', 'water', 'goals', 'focus', 'screenTime', 'coach']}
    state.update(schema=1, profile={'username': 'Sample', 'isPrivate': True},
                 settings={'theme': 'Dark', 'notifications': [], 'summaryMinute': 1200, 'waterTarget': 2000,
                           'focusMinutes': 25, 'breakMinutes': 5, 'backendURL': '', 'coachConsent': False})
    for index, title in enumerate(['Read a chapter', 'Review tomorrow\u2019s priorities', 'Evening reflection']):
        state['habits'].append({'id': identifier(), 'title': title, 'category': 'Routine', 'weekdays': list(range(1, 8)),
                                'created': stamp(-7), 'reminderMinute': [480, 1080, 1260][index],
                                'completed': [(today + dt.timedelta(days=n)).isoformat() for n in range(-6, 1) if (n + index) % 3 == 0]})
    state['workouts'] = [{'id': identifier(), 'title': 'Sample workout', 'date': stamp(0, 600), 'minutes': 30, 'exercises': [], 'notes': ''}]
    state['focus'] = [{'id': identifier(), 'started': stamp(0, 540), 'ended': stamp(0, 565), 'kind': 'Work'}]
    state['goals'] = [{'id': identifier(), 'title': title, 'detail': '', 'category': 'Personal', 'cadence': 'Weekly',
                        'created': stamp(-7), 'deadline': stamp(2, 1200), 'target': 3,
                        'updates': [{'id': identifier(), 'date': stamp(0, 600), 'value': value}]}
                       for title, value in [('Finish a book', 1), ('Practice sessions', 3)]]
    state['dailyRoutine'] = {'day': today.isoformat(), 'timezone': 'Asia/Tokyo', 'generatedAt': stamp(0, 600),
                             'suggestions': [{'id': identifier(), 'title': 'Try a short planning session.', 'proposedMinutes': 10},
                                             {'id': identifier(), 'title': 'Choose a comfortable reading break.', 'proposedMinutes': 15}]}
    # O_EXCL is the preservation boundary. Never truncate an existing fixture.
    try:
        with target.open('xb'):
            pass
    except FileExistsError:
        parser.error('Fixture already exists; preserve it. Do not overwrite or reset.')
    with sqlite3.connect(target) as database:
        database.executescript('CREATE TABLE app_state (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL);'
                               'CREATE TABLE recovery (id INTEGER PRIMARY KEY, payload TEXT NOT NULL);')
        database.execute('INSERT INTO app_state VALUES (1, ?)', (json.dumps(state),))
    print('Created exclusive synthetic Home fixture; proposals are UI fixtures, not AI evaluation.')


if __name__ == '__main__':
    main()
