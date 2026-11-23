#!/usr/bin/env python3
"""Read-only unsigned iPhone packaging check; not Apple/release approval."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MODEL_SHA = 'bb741ebb106d543e9de114b843a3d3d73d51c74b5801e69da2abde821a0cb3e1'
MODEL_BYTES = 695755488


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Preserve existing audits; choose a new revision')
    app = args.app.resolve()
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.dash1971.critiqueai2'
    assert info['DTPlatformName'] == 'iphoneos' and info['UIDeviceFamily'] == [1, 2]
    binary = app / info['CFBundleExecutable']
    architectures = subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).split()
    assert architectures == ['arm64']
    model = json.loads((app / 'EvaluationModel.json').read_text())
    assert Path(model['filename']).name == model['filename']
    weights = app / model['filename']
    assert model['sha256'] == MODEL_SHA and model['bytes'] == MODEL_BYTES
    assert weights.stat().st_size == MODEL_BYTES and digest(weights) == MODEL_SHA
    assert digest(app / 'CoachPolicy.txt') == digest(ROOT / 'Resources/CoachPolicy.txt')
    assert (app / 'Assets.car').is_file()
    assert info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] == 'AppIcon'
    required_licenses = ['LFM-Open-LICENSE.txt', 'llama.cpp-LICENSE.txt', 'nlohmann-json-LICENSE.txt']
    license_hashes = {}
    for name in required_licenses:
        bundled = app / 'ThirdParty' / name
        assert bundled.is_file() and bundled.stat().st_size > 100
        assert digest(bundled) == digest(ROOT / 'Resources/ThirdParty' / name)
        license_hashes[name] = digest(bundled)
    report = {
        'packaging_check': 'passed',
        'measured_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'bundle_id': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
        'build': info['CFBundleVersion'], 'minimum_os': info['MinimumOSVersion'],
        'device_families': info['UIDeviceFamily'], 'architectures': architectures,
        'executable_sha256': digest(binary), 'model_bytes': MODEL_BYTES,
        'model_sha256': MODEL_SHA, 'coach_policy_sha256': digest(app / 'CoachPolicy.txt'),
        'required_license_sha256': license_hashes, 'app_icon_asset_present': True,
        'signing_verified': False, 'apple_validation': False, 'testflight_upload': False,
        'physical_device_acceptance': False, 'model_quality_approved': False,
        'note': 'Packaging of the local unsigned development build only. Not a release audit or distribution approval.'
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['packaging_check', 'version', 'build', 'model_bytes', 'testflight_upload']}))


if __name__ == '__main__':
    main()
