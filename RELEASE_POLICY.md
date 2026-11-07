# GARANT STORE - Release policy

**One stable VERIFIED release + one active development branch.**

## Delivery contract

The end user does not run `Validate-DEV.cmd`, `SelfTest.ps1` or
`Build-VerifiedRelease.cmd` for every update. These are developer/CI tools.
The customer receives infrequent meaningful releases with verifiable SHA256,
changelog and a stable GitHub Releases download URL.

Only a new milestone (noticeable performance, functionality and/or UI
improvements) deserves a new version. Normal bug fixes accumulate on the
active development branch.

## Gates before VERIFIED publication

- Real Windows PowerShell Desktop 5.1 and strict-mode parse/regression tests.
- Real cmd.exe launcher and CMD metacharacter checks.
- Null, empty, singleton and many-result parser semantics.
- WinForms STA GUI startup, layout invariant checks and proper closure.
- Package exact allowlist, no .git, CI, logs, diagnostics, credentials.
- SHA256 manifest of every distributed file.
- Build ZIP, unpack it to a new path and rerun the entire Windows gate.
- Exact git tag and VERSION.txt match, no development tag.
- Publish the exact tested ZIP only after success, with separate SHA256/report.

A failure in any stage blocks the release. Do not disable a failing test to
obtain a green workflow. Validate unavailable on this non-Windows environment
means 'unverified', not 'successful'.

Visual screenshot/design reviews remain separate from the smoke test, which
only verifies control construction/layout/start/close. On noninteractive
Windows-hosted CI, the full GUI test may require a GUI-enabled runner.
