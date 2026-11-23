#!/usr/bin/env python3
"""Verify the actual native pipeline on an owned simulator, never a real phone.

Main-app checks use only its separate UI-test store. Exported receipts/metrics
exclude prompts, answers and account information. This is not phone performance
acceptance, model-quality approval, signing or a TestFlight upload.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import sqlite3
import subprocess
import time
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
ALLOWED = {'com.dash1971.critiqueai2', 'com.dash1971.critiqueai2.evaluation'}


def command(*args, check=True):
    return subprocess.run(list(args), check=check, capture_output=True, text=True)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def history_count(database):
    if not database.exists():
        return 0
    uri = 'file:' + urllib.parse.quote(str(database)) + '?mode=ro'
    with sqlite3.connect(uri, uri=True) as connection:
        row = connection.execute('SELECT payload FROM app_state WHERE id=1').fetchone()
    return len(json.loads(row[0]).get('coach', [])) if row else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trial')
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--timeout', type=int, default=240)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,79}', args.trial) or not 30 <= args.timeout <= 600:
        parser.error('Use a unique lowercase label and a bounded timeout')
    app = args.app.resolve()
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    bundle = info['CFBundleIdentifier']
    if bundle not in ALLOWED or info.get('DTPlatformName') != 'iphonesimulator':
        parser.error('Only this project’s simulator app bundles are allowed')
    inventory = json.loads(command('xcrun', 'simctl', 'list', 'devices', '-j').stdout)
    device = next((d for rows in inventory['devices'].values() for d in rows if d['udid'] == args.device), None)
    if not device or device['state'] != 'Booted' or not device['name'].startswith('Critique '):
        parser.error('Boot the owned Critique test simulator first; do not target another device')
    destination = ROOT / 'build/verification/native-smoke' / args.trial
    destination.mkdir(parents=True, exist_ok=False)
    model = json.loads((app / 'EvaluationModel.json').read_text())
    if Path(model['filename']).name != model['filename']:
        raise RuntimeError('Invalid model filename')
    artifact = app / model['filename']
    if artifact.stat().st_size != model['bytes'] or digest(artifact) != model['sha256']:
        raise RuntimeError('Bundled model integrity failed')
    expected_policy = digest(app / 'CoachPolicy.txt')
    command('xcrun', 'simctl', 'install', args.device, str(app))
    container = Path(command('xcrun', 'simctl', 'get_app_container', args.device, bundle, 'data').stdout.strip())
    database = container / 'Library/Application Support/CritiqueAI2/UITest-state.sqlite'
    is_main = bundle == 'com.dash1971.critiqueai2'
    baseline = history_count(database) if is_main else None
    receipt = {'state': 'running', 'model': model['name'], 'model_sha256': model['sha256'],
               'policy_sha256': expected_policy, 'model_verified_in_bundle': True,
               'main_app_saved_test_records': is_main, 'physical_device_acceptance': False,
               'testflight_upload': False, 'note': 'Simulator compatibility only; not iPhone speed or memory acceptance.'}
    report = destination / 'receipt.json'
    report.write_text(json.dumps(receipt, indent=2) + '\n')
    started = time.time()
    launch = ['xcrun', 'simctl', 'launch', '--terminate-running-process', args.device, bundle]
    if is_main:
        launch.append('--ui-testing')
    launch.append('--local-coach-smoke')
    command(*launch)
    print('Native checked generation started on the owned simulator', flush=True)
    try:
        next_update = started + 20
        while time.time() - started < args.timeout:
            outcome_path = container / 'tmp/local-coach-smoke-outcome.json'
            if outcome_path.exists() and outcome_path.stat().st_mtime >= started:
                outcome = json.loads(outcome_path.read_text())
                if outcome['outcome'] in {'cancelled', 'rejected'}:
                    receipt.update(state=outcome['outcome'], reason=outcome.get('reason', 'Native request cancelled'))
                    raise RuntimeError(receipt['reason'])
            for candidate in (container / 'tmp').glob('*_v0_local_coach_metrics.json'):
                if candidate.stat().st_mtime < started:
                    continue
                metrics = json.loads(candidate.read_text())
                if metrics.get('model_sha256') != model['sha256'] or metrics.get('coach_policy_sha256') != expected_policy:
                    continue
                if metrics.get('constrained_json') is not True or metrics.get('max_output_tokens') != 256:
                    raise RuntimeError('Native generation did not use the expected constrained pipeline')
                if is_main and metrics.get('test_store') is not True:
                    raise RuntimeError('Main-app check did not use the isolated test store')
                if is_main and history_count(database) < baseline + 2:
                    continue
                shutil.copyfile(candidate, destination / '20261123_v0_native_metrics.json')
                receipt.update(state='accepted', checked_generation=True, history_saved=is_main,
                               started_at_utc=datetime.datetime.fromtimestamp(started, datetime.timezone.utc).isoformat())
                report.write_text(json.dumps(receipt, indent=2) + '\n')
                print(json.dumps(receipt), flush=True)
                return
            if time.time() >= next_update:
                print('Awaiting native outcome; seconds elapsed', int(time.time() - started), flush=True)
                next_update += 20
            time.sleep(2)
        receipt.update(state='timed_out', reason='No complete checked result within the bounded native test')
        raise RuntimeError(receipt['reason'])
    finally:
        report.write_text(json.dumps(receipt, indent=2) + '\n')
        command('xcrun', 'simctl', 'io', args.device, 'screenshot', str(destination / '20261123_v0_native_screen.png'), check=False)
        command('xcrun', 'simctl', 'terminate', args.device, bundle, check=False)


if __name__ == '__main__':
    main()
