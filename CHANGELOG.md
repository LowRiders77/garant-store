# Garant Store v0.11.0 — Apple-inspired workspace

- Removed the duplicated top Popular shortcuts completely and preserved the full catalog as the single app-discovery surface.
- Made the search, catalog, and status area more spacious, reclaiming vertical space for real applications.
- Refined dark graphite/navy colors, flattened panel fills, reduced distracting gradients and visually consolidated common controls.
- Preserved cached application artwork and the existing fast WinGet and Microsoft Store workflows.
- Added real Windows GUI layout smoke checks for maximized-like wide windows to detect overflow and footer overlap.
- Retained the Windows release gates for source, launcher, regression suite and extracted verified ZIP.

Design acceptance: the Windows CI gate validates geometry and initialization, not subjective appearance or a captured screenshot of a live user desktop. If visual artifacts remain, they require a follow-up visual fix rather than claiming they have been visually verified.
