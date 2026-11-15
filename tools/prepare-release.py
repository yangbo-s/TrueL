#!/usr/bin/env python3
"""Build a signed installer and appcast. Publishing is a separate, explicit step."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def run(*args, capture=False):
    return subprocess.run(args, cwd=ROOT, text=True, check=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    config = json.loads((ROOT / 'Config/release.json').read_text())
    run('./tools/fetch-sparkle.sh')
    tools = ROOT / '.build/sparkle-tools/bin'
    key = run(str(tools / 'generate_keys'), '--account', config['sparkleKeyAccount'], '-p', capture=True).strip()
    if key != config['publicEDKey']:
        raise SystemExit('The local update key does not match the app public key.')
    if not args.skip_build:
        run('./build.sh')
    run('./tools/package-dmg.sh', '--skip-build')
    destination = ROOT / 'build/releases' / config['version']
    destination.mkdir(parents=True, exist_ok=True)
    name = f"TrueL-{config['version']}-arm64.dmg"
    archive = destination / name
    shutil.copy2(ROOT / 'build/TrueL.dmg', archive)
    notes = (ROOT / 'CHANGELOG.md').read_text().split('## ', 1)[1].split('\n', 1)[1].split('\n## ', 1)[0].strip()
    archive.with_suffix('.md').write_text(notes + '\n')
    existing = ROOT / 'updates/appcast.xml'
    if existing.exists():
        namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
        if any(item.findtext(namespace + 'version') == config['build'] for item in ET.parse(existing).findall('./channel/item')):
            raise SystemExit('This build number is already published; increment it before preparing another release.')
        shutil.copy2(existing, destination / 'appcast.xml')
    elif (destination / 'appcast.xml').exists():
        (destination / 'appcast.xml').unlink()
    run(str(tools / 'generate_appcast'), '--account', config['sparkleKeyAccount'],
        '--download-url-prefix', f"https://github.com/yangbo-s/TrueL/releases/download/v{config['version']}/",
        '--embed-release-notes', '--maximum-deltas', '0', str(destination))
    feed = destination / 'appcast.xml'
    ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    items = ET.parse(feed).findall('./channel/item')
    item = next(item for item in items if item.findtext('sparkle:version', namespaces=ns) == config['build'])
    enclosure = item.find('enclosure')
    assert enclosure is not None
    assert int(enclosure.attrib['length']) == archive.stat().st_size
    signature = enclosure.attrib['{'+ns['sparkle']+'}edSignature']
    verifier = ROOT / '.build/verify-update'
    run('swiftc', '-module-cache-path', str(ROOT / '.build/modules'),
        str(ROOT / 'tools/verify-update.swift'), '-o', str(verifier))
    run(str(verifier), config['publicEDKey'], str(archive), signature)
    run(str(verifier), config['publicEDKey'], str(feed))
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / 'SHA256SUMS').write_text(f'{digest}  {name}\n')
    print(f'Release prepared: {destination}')


if __name__ == '__main__':
    main()
