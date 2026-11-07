# Garant Store v0.9.0

Garant Store is a compact Windows 10/11 software manager powered by WinGet and Microsoft Store.

## Interface
- One compact navy/graphite interface with soft teal accents and light, optional hover transitions.
- Search, curated categories, installed/update filters and a high-density results list.
- App artwork column: exact curated names and IDs use network-loaded website icons from a small trusted allowlist with on-disk caching; every unmatched app receives a clean fallback monogram.
- Artwork downloads are asynchronous and are never required for package search or installation.
- Nonessential maintenance actions are consolidated into a Tools menu.
- Fixed the result column-data mapping so ID, status, source, and version appear in the correct columns.

## Installation
Download the VERIFIED ZIP from GitHub Releases, extract and run Start-GarantStore.cmd. Windows 10/11 with Windows PowerShell 5.1 is required.
Search and package status work independently of icon downloads. Microsoft Store agreements require explicit consent, and installations require user confirmation.

## Quality
Windows CI checks parsing, StrictMode, cmd.exe, startup/shutdown of real WinForms, GUI structure and logo fallbacks, packaging, SHA256 and unpacked-ZIP retest. Windows CI cannot guarantee every app icon exists: unknown titles display an identity-safe placeholder. Stable 0.8.0 stays available as an earlier release.
