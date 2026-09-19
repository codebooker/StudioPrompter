#!/usr/bin/env python3
"""Promote a signature-verified stable or explicitly selected tester release."""
import argparse
import json
import pathlib
import plistlib
import re
import subprocess
import tempfile
from update_feed import REPOSITORY, inspect_feed


def run(*args):
    return subprocess.check_output(args, text=True)


def validate_release_channel(release, *, tester=False):
    if release['isDraft']:
        raise ValueError('Draft releases cannot enter an update feed')
    if release['isPrerelease'] != tester:
        raise ValueError('Tester feed requires a prerelease; stable feed requires a stable release')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tag')
    parser.add_argument('--tester', action='store_true', help='Use the separate non-notarized tester feed')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', args.tag):
        raise ValueError('Use a numeric release tag such as 0.1.1 (without a v prefix)')
    release = json.loads(run('gh', 'release', 'view', args.tag, '--repo', REPOSITORY,
                             '--json', 'isDraft,isPrerelease,tagName,assets'))
    validate_release_channel(release, tester=args.tester)
    feed_name = 'tester-appcast.xml' if args.tester else 'appcast.xml'
    with tempfile.TemporaryDirectory(prefix='studioprompter-update-') as temporary:
        folder = pathlib.Path(temporary)
        run('gh', 'release', 'download', args.tag, '--repo', REPOSITORY,
            '--pattern', feed_name, '--dir', str(folder))
        feed = (folder / feed_name).read_bytes()
        current = pathlib.Path('updates') / feed_name
        if current.read_bytes() == feed:
            print('This release is already in the update feed.')
            return
        info = inspect_feed(feed, tag=args.tag, previous=current.read_bytes())
        asset = next((asset for asset in release['assets'] if asset['name'] == info['archive']), None)
        if asset is None or asset['size'] != info['size']:
            raise ValueError('Published archive is missing or differs from the appcast byte count')
        run('gh', 'release', 'download', args.tag, '--repo', REPOSITORY,
            '--pattern', info['archive'], '--dir', str(folder))
        archive = folder / info['archive']
        print(run('swift', 'scripts/verify-update.swift', 'scripts/Info.plist', str(folder / feed_name), str(archive)))
        extracted = folder / 'unpacked'
        run('ditto', '-x', '-k', str(archive), str(extracted))
        app = extracted / 'Prompter.app'
        with (app / 'Contents/Info.plist').open('rb') as source:
            bundle = plistlib.load(source)
        with pathlib.Path('scripts/Info.plist').open('rb') as source:
            expected = plistlib.load(source)
        if (bundle['CFBundleIdentifier'] != expected['CFBundleIdentifier'] or
                bundle['CFBundleShortVersionString'] != info['version'] or
                int(bundle['CFBundleVersion']) != info['build'] or
                bundle.get('SUPublicEDKey') != expected['SUPublicEDKey'] or
                bundle.get('SUFeedURL') != f'https://raw.githubusercontent.com/{REPOSITORY}/main/updates/{feed_name}'):
            raise ValueError('Bundle identity, versions, or update configuration do not match')
        run('codesign', '--verify', '--deep', '--strict', str(app))
        if not args.tester:
            run('xcrun', 'stapler', 'validate', str(app))
            run('spctl', '--assess', '--type', 'execute', str(app))
        # Atomic replacement; never expose a partial or unverified feed.
        staged = current.with_suffix('.xml.tmp')
        staged.write_bytes(feed)
        staged.replace(current)
        print(f"Ready to publish update feed for {info['version']} (build {info['build']}).")


if __name__ == '__main__':
    main()
