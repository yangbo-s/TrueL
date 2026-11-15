#!/usr/bin/env python3
"""Write the app's version and public update configuration from one release file."""
import json
from pathlib import Path
import plistlib
import sys

config = json.loads(Path('Config/release.json').read_text())
info = {
    'CFBundleExecutable': 'TrueL', 'CFBundleIdentifier': 'com.truel.prototype',
    'CFBundleName': 'TrueL', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': config['version'], 'CFBundleVersion': config['build'],
    'LSMinimumSystemVersion': config['minimumSystemVersion'], 'NSHighResolutionCapable': True,
    'SUFeedURL': config['feedURL'], 'SUPublicEDKey': config['publicEDKey'],
    'SURequireSignedFeed': True,
    'SUVerifyUpdateBeforeExtraction': True,
    'SUSignedFeedFailureExpirationInterval': 0,
    'SUEnableAutomaticChecks': True,
    'SUAutomaticallyUpdate': False,
}
Path(sys.argv[1]).write_bytes(plistlib.dumps(info))
