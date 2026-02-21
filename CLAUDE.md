# LFGExpanded - Development Guide

## Project Overview

**LFG Expanded** is a WoW Classic Anniversary addon that adds a filter side panel to the LFG Browse frame, letting you filter search results by role and class.

### Key Files
- `LFGExpanded.lua` - Main addon code (all logic in single file, ~1200 lines)
- `LFGExpanded.toc` - Addon manifest
- `README.md` - Documentation (also used for CurseForge description)
- Deployed to: `/mnt/data/games/World of Warcraft/_anniversary_/Interface/AddOns/LFGExpanded/`

### Features
- Side panel attached to LFG Browse frame with single-column layout
- **Auto-open**: Panel appears automatically when Dungeons or Raids category is selected; respects manual close until next category selection
- **Role filters**: Tank, Healer, DPS toggle icons with include/exclude (disabled until a search is performed)
- **Class filters**: All 9 TBC classes with class-colored labels, include/exclude
- **Per-class role breakdown**: Each class row shows role counts with native Group Browser icons (counts reflect only visible/filtered listings)
- **Class notes tooltips**: Hover info icon to see listing notes from leaders of that class, with class-colored names and lazy name resolution
- **Show checkboxes**: Groups, Singles, 70 Only inline checkboxes below role icons (native UICheckButtonTemplate)
- Smart sorting when role/class filters or group/singles visibility active: groups first, singles sorted by class
- Scroll position preserved during filter updates
- Dynamic button label: "Get Started" before first search, "Search Again" after
- Warning message when all show filters (groups + singles) are unchecked
- Info button with comprehensive tooltip explaining all controls

### Architecture
- Single Lua file, no XML, no SavedVariables (filters reset each session)
- Hooks `LFGBrowseFrame.UpdateResultList` to filter/sort results before rendering
- Hooks `CategoryDropdown.SetValue` to auto-show panel on Dungeons/Raids selection
- `panelDismissed` flag tracks manual close; resets on new category selection
- Single filter state table: `filters` (roles, excludeRoles, classes, excludeClasses)
- Separate boolean flags: `showGroups`, `showSingles`, `show70Only` (toggled via inline checkboxes)
- Uses `C_LFGList.GetSearchResultMemberCounts` for group role data
- Uses `C_LFGList.GetSearchResultPlayerInfo().lfgRoles` for single role data (member counts are unreliable for singles)
- Uses `C_LFGList.GetSearchResultPlayerInfo().classFilename` for class detection
- Notes are stored with `resultID` and leader names resolved lazily at tooltip display time
- Three-state visual for role/class buttons: off (desaturated), require (bright + checkmark), exclude (red tint + red X)
- Native LFG frame styling using `PortraitFrameTemplate`, `UI-LFG-FRAME` background textures, and `CharacterFrameTabButtonTemplate` tab
- Waits for `Blizzard_GroupFinder_VanillaStyle` ADDON_LOADED before initializing

### Filter Logic
- **Exclusions (AND)**: Always enforced first. Excluded roles/classes are rejected regardless of includes
- **Includes (OR across dimensions)**: A listing passes if it matches any included role OR any included class. Including Healer + Hunter shows all healers and all hunters
- **Groups role/class exclusion**: Group must have zero members matching the excluded role/class
- **Singles role exclusion**: Rejects only if ALL of the player's listed roles are in the exclude set (e.g., healer+dps passes a healer exclusion because dps isn't excluded)
- **Class exclusion**: Applies to both groups and singles (reject if excluded class is present)
- Include and exclude are mutually exclusive per role/class (setting one clears the other)

### Development Workflow

See the `/wow-addon` skill for the standard development workflow (test, version, commit, deploy).

## WoW API Reference

For WoW Classic Anniversary API documentation, patterns, and development workflow, use the `/wow-addon` skill:
```
/wow-addon
```
This loads the shared TBC API reference, common patterns, and gotchas.
