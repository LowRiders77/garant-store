# Presentation design specification (implemented in DEV)

* Design direction: dark graphite / navy to deep teal; soft mint and cyan accents.
* Brand: Garant Store, direct utilitarian messaging, restrained highlights.
* Components: GDI+ GradientPanel, GradientButton, GradientProgress, FastGrid.
* Layout: hero -> search -> quick apps -> actions -> operation state -> results.
* Background: a full-surface diagonal gradient, panels with rounded corners.
* Progress: no inferred percent where backend cannot provide one. A marquee
  indicates waiting; a gradient fill represents an actual completion fraction.
* Status pills: installed mint, checking cyan, update amber, source Store teal,
  source WinGet indigo. DataGridView cell contents remain copyable.
* Visual performance: buffered controls, animation only while active, no
  unbounded timers or external image/WebView runtime.
* Release contract: user-visible design is smoke-tested on real Windows.
