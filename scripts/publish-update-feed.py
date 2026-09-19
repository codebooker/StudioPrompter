#!/usr/bin/env python3
"""Promote a verified appcast from an already-published stable GitHub release.

This script never publishes a release. It only writes updates/appcast.xml after
checking the archive's signature, size, Apple signing, notarization and versions.
"""
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('tag')
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', args.tag):
        raise ValueError('Use a stable release tag such as 0.1.1 (without a v prefix)')
    release = json.loads(run('gh', 'release', 'view', args.tag, '--repo', REPOSITORY,
                             '--json', 'isDraft,isPrerelease,tagName,assets'))
    if release['isDraft'] or release['isPrerelease']:
        raise ValueError('Drafts and prereleases cannot enter the stable update feed')
    with tempfile.TemporaryDirectory(prefix='studioprompter-update-') as temporary:
        folder = pathlib.Path(temporary)
        run('gh', 'release', 'download', args.tag, '--repo', REPOSITORY,
            '--pattern', 'appcast.xml', '--dir', str(folder))
        feed = (folder / 'appcast.xml').read_bytes()
        current = pathlib.Path('updates/appcast.xml')
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
        print(run('swift', 'scripts/verify-update.swift', 'scripts/Info.plist', str(folder / 'appcast.xml'), str(archive)))
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
                bundle.get('SUFeedURL') != expected['SUFeedURL']):
            raise ValueError('Bundle identity, versions, or update configuration do not match')
        run('codesign', '--verify', '--deep', '--strict', str(app))
        run('xcrun', 'stapler', 'validate', str(app))
        run('spctl', '--assess', '--type', 'execute', str(app))
        # Atomic replacement; never expose a partial or unverified feed.
        staged = current.with_suffix('.xml.tmp')
        staged.write_bytes(feed)
        staged.replace(current)
        print(f"Ready to publish update feed for {info['version']} (build {info['build']}).")


if __name__ == '__main__':
    main()
