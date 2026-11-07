# Garant Store - one-time GitHub activation

The source repository is NOT connected yet. A different repository,
`rassroschka-ai`, is available in the linked GitHub account; do not use it
for this project.

1. Create a **private** GitHub repository named `garant-store`, without
   auto-initializing README/.gitignore/license.
2. Grant the ChatGPT GitHub connector access to this repository (if its
   installation is scoped to selected repositories).
3. Upload or commit the contents of this source package to `main`.
   The `.github` and `CI` directories must be preserved.
4. Open GitHub -> `garant-store` -> Actions -> `Garant Store - Windows CI`.
   The push to main should start the checks automatically.
5. Do **not** create a release tag until Windows CI is green.

No local Windows tests are required from the end user. If the hosted runner
cannot start the GUI, publication remains blocked until an interactive
Windows GUI runner is configured. This is infrastructure setup, not a
request for manual repeat testing.

## Milestone publication

Change VERSION.txt from `0.8.0-dev` to `0.8.0` only after the change set
is significant and the Windows CI is green. Commit the change, then push
tag `v0.8.0`. The release workflow reruns the full source and extracted
archive gate and publishes one GitHub Release containing:

- `GarantStore-v0.8.0-VERIFIED.zip`
- `GarantStore-v0.8.0-VERIFIED.release-report.json`
- `SHA256SUMS.txt`

Do not upload development ZIPs as releases.
