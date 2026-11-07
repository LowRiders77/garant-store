# CI status - 2026-10-31

| Area | State |
|---|---|
| Source is assembled with CI workflows | Prepared locally |
| Windows 2022 hosted workflow | Configured, not executed |
| PowerShell 5.1, CMD, regression source gate | Configured, not executed here |
| Archive SHA256 + extraction + second gate | Configured, not executed here |
| Real WinForms GUI startup and layout | Must pass Windows runner; hosted UI limitations possible |
| GitHub Release publication after valid version tag | Configured, not activated |
| Connected dedicated GitHub repository | Missing; only `rassroschka-ai` is connected |
| Last public VERIFIED version | Existing v0.7 base; v0.8 remains DEV |

Do not describe CI as green or releases as automated until the separate
repository has been connected and an actual Windows workflow has succeeded.
The code here is a source integration package, not a public binary release.
