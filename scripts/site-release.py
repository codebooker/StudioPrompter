#!/usr/bin/env python3
"""Resolve the newest published Mac DMG at Pages build time, including tester releases."""
import json, pathlib, re, sys
releases=json.load(sys.stdin)
candidates=[]
for release in releases:
    tag=release.get('tag_name','')
    if release.get('draft') or not re.fullmatch(r'\d+\.\d+\.\d+',tag):
        continue
    name=f'StudioPrompter-{tag}-macos-arm64.dmg'
    for asset in release.get('assets',[]):
        expected=f'https://github.com/codebooker/StudioPrompter/releases/download/{tag}/{name}'
        if asset.get('name')==name and asset.get('state')=='uploaded' and asset.get('browser_download_url')==expected:
            candidates.append((tuple(map(int,tag.split('.'))),tag,expected))
if not candidates:
    raise SystemExit('No published StudioPrompter Mac DMG is available.')
_,version,dmg=max(candidates)
folder=pathlib.Path('website')
(folder/'release.json').write_text(json.dumps({'version':version,'dmg':dmg})+'\n')
for path in (folder/'index.html', folder/'demo/index.html'):
    html=path.read_text()
    html=re.sub(r'https://github.com/codebooker/StudioPrompter/releases/download/[^"\s]+\.dmg',dmg,html)
    html=re.sub(r'(<span id="release-version">)[^<]+',lambda m:m[1]+version,html)
    path.write_text(html)
print(f'Website download: {version} — {dmg}',file=sys.stderr)
