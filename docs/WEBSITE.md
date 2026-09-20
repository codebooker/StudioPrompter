# StudioPrompter website

The site at https://studioprompter.app is a static, dependency-free browser demo hosted on GitHub Pages. Source lives in `website/`. The demo provides fixed-speed playback, manual scrolling, sample scripts, visual rich-text editing with bold/underline and undo, paragraph bookmarks, a resizable reading guide, and focus view. Voice models, microphone capture, native display management, and iPad pairing are intentionally reserved for the Mac app.

## Run locally

```sh
python3 -m http.server 8765 --directory website
```

Open http://localhost:8765. There is no build step. Scripts/settings use localStorage with a versioned, validated schema and stay in the visitor's browser. Imports accept TXT/Markdown up to 100 KB; the browser library supports 30 scripts. Rendering escapes imported text before applying the small supported Markdown subset. The editor displays emphasis directly and serializes it as Markdown for storage/export; pasted text is kept plain and arbitrary HTML is never imported. Bookmark markers and editable bookmark names appear inside the editor. Export saves the current script as Markdown. There are no remote fonts, analytics scripts, or AI downloads.

## Deploy and downloads

`.github/workflows/pages.yml` deploys the site on relevant main-branch pushes, published/edited releases, or manual dispatch. It resolves the highest numeric published release with an uploaded Apple silicon DMG, including tester prereleases, through `scripts/site-release.py`. It updates the static download links and `release.json` in the deployment artifact, so downloads remain direct even without JavaScript. Draft releases and unexpected asset URLs are rejected. Source fallback currently points to 0.2.0.

The custom domain is configured in GitHub Pages settings/API. The `website/CNAME` file also documents the intended domain; Actions deployments use the repository setting. DNS is managed separately by the owner.

`package-release.sh` now creates a DMG as well as the signed Sparkle ZIP. `package-dmg.sh` copies an already verified app without modifying its signature, includes an Applications shortcut and installation instructions, and refuses to overwrite an existing image. If a notarization profile is provided, it also notarizes/staples the DMG. Upload the DMG alongside future release assets before publishing. Sparkle continues to use the ZIP.

## Native appearance

The desktop demo follows `WorkspaceView.swift`: 66 px toolbar, 224 px library, 256 px inspector, 34 px footer, 68 × 48 px Play button, system UI typography, and the native charcoal/orange palette. `icons.svg` contains original vector drawings matching the native controls’ semantics. Mobile layouts reflow the controls. Browser rendering and non-Mac font fallbacks can differ from AppKit.

## Verification

Before deployment, check playback/pause and manual-scroll handoff; editing, formatting and persistence after reload; bookmark creation/jumps; reading-guide size/position; focus mode/Escape; responsive layout; and direct DMG/GitHub/license links. Never imply that browser scripts are synced with the native app. Clearing browser site data removes the local demo library; users should export anything they want to keep.
