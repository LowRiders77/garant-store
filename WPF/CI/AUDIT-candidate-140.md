# Candidate-140 audit: Lenovo 82QY (2026-11-06)

## Evidence and source identity
Read diagnostics-20261106-182800 and both Garant-PO archives before/after Windows Update activation.
Candidate-140 BuildId 42236481676 embeds source merge commit 6dd798d4555137017ea4f3b426aca3eca48a2563. PR head is 722331119256d320131271284c7aeb17a92501ae; these are different Git identities for the same tested PR integration, not evidence of an old installer.

## Confirmed defects
* All 9 WUA Update rows lack canSelect and Selected. The WPF fallback enables only Missing/Issue/GPU. Therefore applicable update rows are disabled. Previous UI tests supplied canSelect=true by hand, masking the producer/consumer defect.
* EulaAccepted was not initialized on each loop iteration. A COM read failure could reuse the prior update's value.
* RepairVerified tests CLI/search only; UI must not imply Store deployment or application launch has been verified.
* Footer action buttons are arranged on one unbounded horizontal line after a long hint.

## Changes
UpdateCatalog emits explicit capabilities and selection state through a shared converter; no license is accepted automatically. Firmware/BIOS and unidentified targets remain unavailable. WPF supports legacy Update rows only when existing EULA/hardware metadata supports selection, respecting explicit canSelect=false.
UI Automation now consumes the production converter and a legacy row missing canSelect, instead of manually forcing an update to be selectable. Engine regression checks accepted/unaccepted EULA, unknown hardware and firmware.
Footer actions wrap below the hint.
Repair result records CLIAndSearchOnly with deployment/installation/launch NotTested. UI says installation is confirmed, launch not tested.
Diagnostics add current-process-user WhatsApp registration and up to 50 recent warning/error events per channel (last 2 hours), filtered for WhatsApp. Unavailable channels are reported. No application is launched, reset or removed.

## Real observations, not inferred test results
Before enabling WU: 151 Inventory, 0 problem devices, 0 updates, 10 components.
After: 152 Inventory, 0 problem devices, 9 updates, 10 components.
Five components are detected installed; five have unknown need. This is not proof all ten require installation.
Local inventory: approximately 22 seconds before, 24 seconds after; WU search after activation 41.399 seconds. No measured performance improvement is claimed.
WhatsApp 9NKSQGP7F2NH 2.2642.101.0: 247421939 downloaded bytes, process 102.14 seconds; winget list confirms installation. These archives contain no activation exception. Screenshot alone cannot establish why launching fails.

## Architecture and outstanding work
Keep WPF/PowerShell and local API for this defect fix: capability-contract mismatch does not require a framework migration.
This is a bounded critical-fix stage, not completion of the full product request.
Still unverified/unimplemented: real Lenovo update installation and reboot verification; WhatsApp activation root cause and Store comparison on the same machine; richer library dependency discovery and official installers; backup/restore workflow; full My System screen/history management; physical DPI matrix and performance comparison.
Mocked WUA objects prove contract and selection logic, not a real driver installation.
Windows CI results are attached to the resulting commit in Actions. Do not label this stage VERIFIED.
