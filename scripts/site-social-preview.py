#!/usr/bin/env python3
"""Prepare the 1200x630 social card using the actual Mac-app screenshot.

Serve .build/site-social-preview, capture at 1200x630 in a browser, and save
that image as website/social-preview.jpg. The composition is never deployed.
"""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent.parent
output = root / '.build/site-social-preview'
output.mkdir(parents=True, exist_ok=True)
for name in ('app-screenshot.jpg', 'icon.svg'):
    shutil.copy2(root / 'website' / name, output / name)
html = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>StudioPrompter social card</title><style>
*{box-sizing:border-box}html,body{width:1200px;height:630px;overflow:hidden;margin:0}body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#f5f5f5;background:radial-gradient(ellipse at 2% 0%,#38251f 0%,#131418 58%)}.copy{position:absolute;left:40px;top:69px;width:335px}.brand{display:flex;align-items:center;gap:12px;font-size:27px;font-weight:600;letter-spacing:-1px}.brand img{width:38px;height:38px}h1{font-size:58px;line-height:1.08;letter-spacing:-2.5px;margin:48px 0 25px}h1 span{color:#ff7d4a}p{color:#aeb6bf;font-size:19px;line-height:1.5;margin:0}.url{margin-top:38px;color:#ff7d4a;font-size:18px;font-weight:500}.note{margin-top:12px;font-size:14px}.app{position:absolute;left:408px;top:94px;width:754px;height:auto;border:1px solid #ffffff24;border-radius:9px;box-shadow:0 25px 65px #0009}
</style><body><div class="copy"><div class="brand"><img src="icon.svg" alt="">StudioPrompter</div><h1>Stay present.<br><span>Keep your place.</span></h1><p>A teleprompter that feels<br>like your own studio.</p><p class="url">studioprompter.app</p><p class="note">Free &amp; open source · Built for Mac</p></div><img class="app" src="app-screenshot.jpg" alt="The StudioPrompter Mac app"></body></html>'''
(output / 'index.html').write_text(html)
print(output)
