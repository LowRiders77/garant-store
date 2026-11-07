# Garant Store automated Windows delivery

This folder exists for developers and CI. It is intentionally NOT included
in the customer-facing ZIP.

- `Invoke-WindowsCI.ps1`: real Windows PowerShell 5.1, regression, CMD,
  WinForms GUI startup/layout smoke, source tree + extracted ZIP gates.
- `PackageTools.ps1`: a single allowlist for runtime archives, SHA256 manifest
  generation and validation, ZIP traversal checks, and extraction.
- `.github/workflows/windows-ci.yml`: Windows checks on pushes and PRs. Does
  not publish development builds.
- `.github/workflows/publish-release.yml`: tagged milestone builds only,
  checks version and SHA256, publishes GitHub Release after full Windows gate.

## Important limit

GitHub-hosted Windows runners may lack an interactive visible desktop.
The smoke script attempts actual STA WinForms initialization and form close.
If the runner cannot perform that, the CI job MUST fail; do not disable the
GUI smoke and still label the release VERIFIED. Use a dedicated Windows GUI
runner or a different verified interactive test environment in that case.
A successful GUI smoke tests creation/layout/start-close, not visual design
quality; a screenshot review is separate.

## No user QA loop

`Validate-DEV.cmd` is a developer diagnostic tool, not a task the end user
must execute each time. Normal users receive only milestones that have
passed CI, along with an official GitHub Release link and SHA256 report.
