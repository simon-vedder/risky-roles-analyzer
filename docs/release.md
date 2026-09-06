# Releasing

1. `CHANGELOG.md`: move *Unreleased* under the new version with today's date.
2. `src/RiskyRolesAnalyzer/RiskyRolesAnalyzer.psd1`: set `ModuleVersion`; drop `Prerelease` for a stable
   release or keep it for `-preview`.
3. Run locally: `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`
   and `Invoke-Pester ./tests`. Both clean.
4. Commit on a branch, open the PR, merge to `main`.
5. Tag: `git tag v0.1.0 && git push origin v0.1.0`. The release workflow refuses a tag that does
   not match the manifest version, runs the analyzer and the tests, publishes to the PowerShell
   Gallery with the `PSGALLERY_API_KEY` secret and attaches the module zip to the GitHub release.
6. Check the Gallery listing (`Find-Module RiskyRolesAnalyzer -AllowPrerelease`) and the GitHub release.
7. The Gallery API key is scoped to this package and expires after a year; rotate it in the
   repository secret `PSGALLERY_API_KEY` before then. Note the expiry date here: `<date>`.

What never goes into a release: lab resource ids, subscription or tenant ids, SAS URLs, credentials.
