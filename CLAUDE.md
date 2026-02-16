# LFGFilter - Development Guide

## Project Overview

**LFGFilter** is a WoW Classic Anniversary addon that adds a filter side panel to the LFG Browse frame, letting you filter search results by role and class with separate controls for groups and singles.

### Key Files
- `LFGFilter.lua` - All addon logic in a single file (~740 lines)
- `LFGFilter.toc` - Addon manifest
- Deployed to: `/mnt/data/games/World of Warcraft/_anniversary_/Interface/AddOns/LFGFilter/`

### Features
- Side panel attached to LFG Browse frame with two-column layout
- **Role filters**: Tank, Healer, DPS toggle icons with include/exclude
- **Class filters**: All 9 TBC classes with class-colored labels, include/exclude
- **Show/Hide checkboxes** per section to hide all groups or all singles entirely
- **Include** (left-click): group/single must have this role/class
- **Exclude** (right-click): group must NOT have this role/class; single is rejected only if ALL their listed roles are excluded
- Smart sorting when filters active: groups first, singles sorted by class
- Auto-removes delisted entries in real-time
- Scroll position preserved during filter/delist updates
- Drag-to-resize grip for uniform panel scaling (0.5x-2.0x)
- Help legend at bottom explaining controls

### Architecture
- Single Lua file, no XML, no SavedVariables (filters reset each session)
- Hooks `LFGBrowseFrame.UpdateResultList` to filter/sort results before rendering
- Two filter state tables: `groupFilters` (roles, excludeRoles, classes, excludeClasses) and `singleFilters` (roles, excludeRoles, classes)
- Uses `C_LFGList.GetSearchResultMemberCounts` for group role data
- Uses `C_LFGList.GetSearchResultPlayerInfo().lfgRoles` for single role data (member counts are unreliable for singles)
- Uses `C_LFGList.GetSearchResultPlayerInfo().classFilename` for class detection
- Three-state visual for role/class buttons: off (desaturated), require (bright + gold border), exclude (red tint + red X)
- Resize via `SetScale()` on the panel frame driven by bottom-right drag grip
- Listens for `LFG_LIST_SEARCH_RESULT_UPDATED` to auto-remove delisted entries
- Waits for `Blizzard_GroupFinder_VanillaStyle` ADDON_LOADED before initializing

### Filter Logic
- **Groups**: role/class exclusion means the group must have zero members matching the excluded role/class
- **Singles role exclusion**: rejects only if ALL of the player's listed roles are in the exclude set (e.g., healer+dps passes a healer exclusion because dps isn't excluded)
- **Singles have no class exclusion** (no `excludeClasses` table)
- Include and exclude are mutually exclusive per role/class (setting one clears the other)

### Development Workflow

See the `/wow-addon` skill for the standard development workflow (test, version, commit, deploy).

## WoW API Reference

For WoW Classic Anniversary API documentation, patterns, and development workflow, use the `/wow-addon` skill:
```
/wow-addon
```
This loads the shared TBC API reference, common patterns, and gotchas.
