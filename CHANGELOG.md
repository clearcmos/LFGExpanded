# Changelog

## v2.0.0

- Now for WoW Forever only; Classic Anniversary stays on v1.0.3
- Filters side tab under Blizzard's Group Finder tabs; the panel uses Forever's group finder art
- Level range (minimum and maximum) replaces 70 Only
- Singles is now Players, the name of Blizzard's section for solo listings
- Class rows that no listing could fill are hidden
- Filters are kept between sessions until Reset Filters
- The listing tooltip shows a solo player's zone, and a zone after each group member once known
- Left-click a group listing to look up the next member's zone with /who, with a countdown between lookups
- Subzones are shown as their zone
- Filtering pauses with a message when the game restricts listing details

## v1.0.3

- Fix Lua error from stale LFG search results when groups delist while browsing
- Reduce GC pressure by reusing tables across search updates instead of reallocating

## v1.0.2

- Replace gear dropdown with inline Groups/Singles/70 Only checkboxes below role icons for better discoverability
- Fix 70 Only toggle reordering listings when no non-70s were present

## v1.0.1

- Localize hot-path C_LFGList API calls to reduce global lookups in filter loops
- Replace O(n²) table.remove filtering with O(n) in-place compaction
- Eliminate redundant API calls by reordering filter/class-data pipeline
- Cache search result info during filtering for reuse in sorting
- Move LARGE_ROLE_ATLAS to module scope (was allocated 9 times per init)

## v1.0.0

Initial release.
