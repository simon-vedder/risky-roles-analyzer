# Images

`hero.png` (1600×640 base, rendered at 1.5×) sits at the top of the README and is the banner on the
tool page. Its right half is a diagram, not a terminal: the tool page already shows a console block
directly above the banner, and two terminals stacked read as one thing said twice. `social-preview.png`
(1280×640 base, rendered at 1.5×, must stay under GitHub's 1 MB limit) is uploaded by hand under
*Settings → Social preview*; there is no API for it. Both are rendered from the `.source.html`
files next to them, so a change is a text edit and a re-render, not a design tool session.

Render on macOS (any headless Chrome works the same):

```bash
cd docs/images
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1.5 --window-size=1600,640 --screenshot=hero.png "file://$PWD/hero.source.html"
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1.5 --window-size=1280,640 --screenshot=social-preview.png "file://$PWD/social-preview.source.html"
```

The central tools page on simonvedder.com reuses `hero.png`; keep the file name.

`report.png` is the README screenshot of the sample report (`docs/sample/report.html`, built by
`docs/sample/New-SampleReport.ps1` from synthetic findings):

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=1.5 --window-size=1600,1000 --screenshot=docs/images/report.png "file://$PWD/docs/sample/report.html"
```
