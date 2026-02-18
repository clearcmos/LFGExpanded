# Changelog

## v1.0.1

- Localize hot-path C_LFGList API calls to reduce global lookups in filter loops
- Replace O(n²) table.remove filtering with O(n) in-place compaction
- Eliminate redundant API calls by reordering filter/class-data pipeline
- Cache search result info during filtering for reuse in sorting
- Move LARGE_ROLE_ATLAS to module scope (was allocated 9 times per init)

## v1.0.0

Initial release.
