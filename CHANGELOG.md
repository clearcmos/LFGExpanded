# Changelog

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
