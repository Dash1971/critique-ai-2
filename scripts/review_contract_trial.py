#!/usr/bin/env python3
"""Check a completed synthetic trial with the actual Swift output contract.

Structural acceptance is not semantic/model approval. Preserve the exact Swift
validator sources and binary hash beside each report for reproducibility.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import re

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trial')
    parser.add_argument('--review-name', default='contract-review')
    args = parser.parse_args()
    trial = (ROOT / 'build/verification/trials' / args.trial).resolve()
    if trial.parent != (ROOT / 'build/verification/trials').resolve():
        parser.error('Use a trial directory name, not a path')
    manifest = json.loads((trial / 'trial.json').read_text())
    if manifest['status'] != 'generation_completed':
        parser.error('Wait for this trial to complete before checking it')
    rows = [json.loads(line) for line in (trial / 'answers.jsonl').read_text().splitlines() if line.strip()]
    ids = [row['id'] for row in rows]
    if ids != manifest['case_ids']:
        raise RuntimeError('Missing, duplicate or reordered responses')
    if not re.fullmatch(r'contract-review(?:-v[0-9]+)?', args.review_name):
        parser.error('Use contract-review or contract-review-vN')
    destination = trial / args.review_name
    destination.mkdir(exist_ok=False)
    hashes = {}
    paths = list((ROOT / 'Sources/CritiqueCore').glob('*.swift'))
    paths += [ROOT / 'Tools/CoachFixtureExporter/main.swift', ROOT / 'Package.swift']
    before = {str(path.relative_to(ROOT)): digest(path) for path in paths}
    with (destination / 'validator-build.log').open('w') as log:
        subprocess.run(['swift', 'build', '-j', '2', '--product', 'critique-coach-fixtures'],
                       cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    if before != {str(path.relative_to(ROOT)): digest(path) for path in paths}:
        raise RuntimeError('Validator sources changed during its build; preserve this attempt and start a new review revision')
    for path in paths:
        relative = path.relative_to(ROOT)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        hashes[str(relative)] = digest(path)
    binary = ROOT / '.build/debug/critique-coach-fixtures'
    result = subprocess.run([str(binary), '--validate', str(trial / 'inputs/cases.json'),
                             str(trial / 'answers.jsonl')], check=True, capture_output=True, text=True)
    report = json.loads(result.stdout)
    report.update(validator_binary_sha256=digest(binary), validator_source_sha256=hashes,
                  model_approved=False, physical_device_benchmark=False)
    (destination / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['checked', 'contract_accepted', 'semantic_quality_review']}))


if __name__ == '__main__':
    main()
