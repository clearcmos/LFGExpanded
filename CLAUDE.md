# LFGExpanded - Development Guide

## Project Overview

**LFG Expanded** is a WoW Classic Anniversary addon that adds a filter side panel to the LFG Browse frame, letting you filter search results by role and class.

### Key Files
- `LFGExpanded.lua` - Main addon code (all logic in single file, ~1125 lines)
- `LFGExpanded.toc` - Addon manifest
- `README.md` - Documentation (also used for CurseForge description)
- Deployed to: `/mnt/data/games/World of Warcraft/_anniversary_/Interface/AddOns/LFGExpanded/`

### Features
- Side panel attached to LFG Browse frame with single-column layout
- **Role filters**: Tank, Healer, DPS toggle icons with include/exclude (disabled until a search is performed)
- **Class filters**: All 9 TBC classes with class-colored labels, include/exclude
- **Per-class role breakdown**: Each class row shows role counts with native Group Browser icons
- **Class notes tooltips**: Hover info icon to see listing notes from leaders of that class, with class-colored names and lazy name resolution
- **Gear dropdown menu**: Show Groups (2+), Show Singles (1), Show 70 Only options
- Smart sorting when filters active: groups first, singles sorted by class
- Scroll position preserved during filter updates
- Search Again and Reset Filters buttons
- Info button with tooltip explaining controls

### Architecture
- Single Lua file, no XML, no SavedVariables (filters reset each session)
- Hooks `LFGBrowseFrame.UpdateResultList` to filter/sort results before rendering
- Single filter state table: `filters` (roles, excludeRoles, classes, excludeClasses)
- Separate boolean flags: `showGroups`, `showSingles`, `show70Only` (toggled via gear dropdown)
- Uses `C_LFGList.GetSearchResultMemberCounts` for group role data
- Uses `C_LFGList.GetSearchResultPlayerInfo().lfgRoles` for single role data (member counts are unreliable for singles)
- Uses `C_LFGList.GetSearchResultPlayerInfo().classFilename` for class detection
- Notes are stored with `resultID` and leader names resolved lazily at tooltip display time
- Three-state visual for role/class buttons: off (desaturated), require (bright + checkmark), exclude (red tint + red X)
- Native LFG frame styling using `PortraitFrameTemplate`, `UI-LFG-FRAME` background textures, and `CharacterFrameTabButtonTemplate` tab
- Gear dropdown uses native `DropdownButton` with `LFGOptionsButton` template and `SetupMenu` API
- Waits for `Blizzard_GroupFinder_VanillaStyle` ADDON_LOADED before initializing

### Filter Logic
- **Groups**: role/class exclusion means the group must have zero members matching the excluded role/class
- **Singles role exclusion**: rejects only if ALL of the player's listed roles are in the exclude set (e.g., healer+dps passes a healer exclusion because dps isn't excluded)
- **Class exclusion**: applies to both groups and singles (reject if excluded class is present)
- Include and exclude are mutually exclusive per role/class (setting one clears the other)

### Development Workflow

See the `/wow-addon` skill for the standard development workflow (test, version, commit, deploy).

### Manual Zip (Deprecated - use CI/CD instead)

```bash
cd ~/git/mine/LFGExpanded && \
rm -f ~/LFGExpanded-*.zip && \
zip -r ~/LFGExpanded-$(grep "## Version:" LFGExpanded.toc | cut -d' ' -f3 | tr -d '\r').zip \
    LFGExpanded.toc LFGExpanded.lua LICENSE.md
```

## WoW API Reference

For WoW Classic Anniversary API documentation, patterns, and development workflow, use the `/wow-addon` skill:
```
/wow-addon
```
This loads the shared TBC API reference, common patterns, and gotchas.
