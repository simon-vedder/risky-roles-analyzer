# Releasing

1. `CHANGELOG.md`: move *Unreleased* under the new version with today's date.
2. `src/RiskyRolesAnalyzer/RiskyRolesAnalyzer.psd1`: set `ModuleVersion`; drop `Prerelease` for a stable
   release or keep it for `-preview`.
3. Run locally: `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`
   and `Invoke-Pester ./tests`. Both clean.
4. Commit on a branch, open the PR, merge to `main`.
5. Rebuild the standalone script and commit it: `./tools/Build-StandaloneScript.ps1`. The release
   workflow refuses a tag whose `dist/Invoke-RiskyRolesAudit.ps1` does not match the sources.
6. Tag: `git tag v0.1.0 && git push origin v0.1.0`. The release workflow refuses a tag that does
   not match the manifest version, runs the analyzer and the tests, and attaches the standalone
   script and the module sources to a GitHub release.
7. Check the GitHub release, then download the attached script into a scratch folder and run it
   once against a tenant. The release is the first thing a stranger sees; a broken one is worse
   than a late one.

Nothing is published to the PowerShell Gallery. The tool ships as one file that people download
from `main`, which is the URL every page and every post points at, so a release is a marker and an
archive rather than a distribution channel. See
`decisions/0003-the-report-is-a-script-the-module-is-optional.md`. `0.1.0-preview` is unlisted on
the Gallery; if it is ever delisted for good, nothing in this repository has to change.

The repository is public, so the history is public with it. Before any release, check that it
carries no tenant, subscription or user identifiers:

```powershell
git rev-list --all | ForEach-Object { git grep -lniE '<your tenant id>|<your domain>' $_ }
```

What never goes into a release: lab resource ids, subscription or tenant ids, SAS URLs, credentials.
