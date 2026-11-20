# LFGExpanded - Development Guide

## Project Overview

**LFG Expanded** is a WoW Forever addon for Blizzard's Group Finder (the
`Blizzard_GroupFinder_VanillaStyle` browser). It adds a Filters side panel
(role, class and level filters) and shows players' zones in the listing
tooltip, looking up group members with `/who` on click.

Since v2.0.0 it is Forever-only. v1.0.3 (tag `v1.0.3`) is the last Classic
Anniversary release and the last Anniversary code tested in game. Anniversary
support was paused on 2026-11-20: few people play it, and the current shared
code was never tested there. v1.0.3's TOC says interface 20505, so the 2.5.6
client (20506) loads it only with "Load out of date AddOns".

### Key Files
- `LFGExpanded.toc` - Manifest: interface 16001, `AllowLoadGameType: camelot`, `SavedVariables: LFGExpandedDB`; loads `Compat_Forever.lua` then `LFGExpanded.lua`
- `LFGExpanded.lua` - Panel, filters, sorting, counts, notes (about 1450 lines, 83 file-scope locals); CRLF line endings
- `Compat_Forever.lua` - Forever layer: secret-value guards, panel art and layout, flags, tooltip locations, member lookups, subzone mapping (generated table at the end)
- `tests/forever.lua` - Stand-in tests: `lua5.1 tests/forever.lua` from the repo root
- `tools/zones.py` - Regenerates the subzone table in `Compat_Forever.lua` from the client's AreaTable and Map
- `README.md` - User documentation and the CurseForge description
- Installed at: `/mnt/data/games/World of Warcraft/_forever_/Interface/AddOns/LFGExpanded/`

### Features
- Filters side tab (`LFGExpandedForeverToggle`, a `LargeSideTabButtonTemplate`) under Blizzard's Create Listing, Browse and Who tabs; shown as selected while the panel is open
- Auto-open when a Dungeons or Raids category is chosen, except the first choice after a manual close
- Role filters (Tank, Healer, DPS) and class rows: left-click require, right-click exclude, click again clear; role buttons are disabled until a search has results
- Per-class role counts of the listings shown, and a total
- Class notes tooltip: comments of the listings shown, filed under the class of member 1 (leader or solo player), names resolved at display, up to 20
- Groups and Players checkboxes; a warning when both are unchecked
- Level range (min and max) in the checkbox row
- Class rows hidden when no click could fill them; a message when no rows remain
- Sorting while a role/class filter is set or a checkbox is unchecked: groups first, solo players by class
- Scroll position kept across filter updates
- Search button reads "Get Started" before results, "Search Again" after
- Filters saved between sessions until Reset Filters
- Listing tooltip zones: a Location line for solo players, a zone column for group members
- Member lookups with `/who` on left click, spaced by a live countdown
- Subzones shown as their zone

### Architecture
- `LFGExpanded.lua` reads Forever specifics only through `addon.Compat`: hooks (`CreatePanel`, `LayoutPanel`, `CreateToggle`, `StyleRoleButton`, `StyleClassRow`, `PrepareResults`, `IsCategorySupported`, `GetMaxLevel`, `HookEntryTooltip`, the `GetSearchResult*` readers) and flags (`CLASS_ROW_HEIGHT`, `HIDE_EMPTY_CLASSES`, `LEVEL_RANGE`, `PERSIST_FILTERS`, `SINGLES_LABEL`). Without them it falls back to the Anniversary code paths (PortraitFrameTemplate panel, bottom Filters tab, 70 Only checkbox); those paths run only if a TOC loads it without `Compat_Forever.lua`, and are untested with the current code.
- Waits for `Blizzard_GroupFinder_VanillaStyle` ADDON_LOADED (load on demand), or initializes at once if `LFGBrowseFrame` exists.
- Hooks `LFGBrowseFrame.UpdateResultList` to filter and sort `results` in place before Blizzard renders them, and `CategoryDropdown.SetValue` for auto-open. Blizzard's entry renderer is not replaced on Forever.
- Dungeon and raid categories are matched by Forever's IDs 2 and 114, not by name.
- State: `filters` (roles, excludeRoles, classes, excludeClasses), `showGroups`, `showSingles`, `levelMin`/`levelMax`, `panelDismissed`.
- Group roles come from `C_LFGList.GetSearchResultMemberCounts`; solo roles from `GetSearchResultPlayerInfo().lfgRoles` (member counts are unreliable for solo listings); classes from `classFilename`.
- `PERSIST_FILTERS`: includes, excludes, the checkboxes and the level range are written to `LFGExpandedDB` at PLAYER_LOGOUT (only after Initialize ran, so a session that never opened the Group Finder keeps the saved filters) and validated on restore.
- `SINGLES_LABEL` is "Players", the native browser's section header; the variable and saved key stay `showSingles`.
- `LEVEL_RANGE`: every member's level must be inside the bounds, an unknown level passes, min above max is swapped; Enter or focus loss applies, Escape reverts. The Players checkbox is centered between the end of the Groups label and the start of the Level label (`GetStringWidth`). The dash offsets account for InputBoxTemplate drawing its left border 5 px outside the box.

### Filter Logic
- Exclusions first: an excluded role or class rejects a listing whatever the includes.
- Includes are OR across roles and classes: Healer + Hunter shows every listing with a healer or a hunter.
- A group is rejected when any member matches an excluded role or class.
- A solo player is rejected when their class is excluded, and by role only when all of their listed roles are excluded.
- Include and exclude are exclusive per role or class; setting one clears the other.
- Groups/Players, the level range and the exclusions also decide which class rows show (`HIDE_EMPTY_CLASSES`); includes do not, because they are OR.

### Secret values and restricted data
Listing and member APIs carry `SecretInChatMessagingLockdown`. `Compat` copies the
fields it needs after `issecretvalue`, `canaccessvalue` and `canaccesstable`
checks, and `PrepareResults` checks every result and member before the shared
code filters. If anything is inaccessible or still loading, filtering pauses
with a warning, Blizzard's results stay as they are, and the next readable
refresh resumes. Behavior inside instances has not been tested in game.

### Listing tooltip locations
`Compat.HookEntryTooltip` (called from Initialize) post-hooks
`LFGBrowseSearchEntryTooltip_UpdateAndShow`. The API returns
`LfgSearchResultPlayerInfo.areaName`, which Blizzard's tooltip never shows; in
game on 2026-11-20 the server filled it for the leader (or solo player) only.
- Solo player: a "Location:" line between Members and Voice Chat. Voice Chat is re-anchored on every show and the tooltip grows by the line.
- Group (leader crown shown): a grey column after the role icons, at one offset for all rows, matched to rows by name because the member pool has no fixed order. The font strings live in a weak table, not as fields on Blizzard's rows. Rows show the zone or "Not found" when known; only the member the next click looks up shows a lookup status; other unknown rows stay blank.

### Member lookups
- A left click on a group listing (rows hooked through the ScrollBox's OnAcquiredFrame, after Blizzard's selection click) sends one exact `/who` (`WHO_TAG_EXACT` plus `C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator`) for the next member: the first without a zone not yet tried, then the one whose unanswered query is oldest. Groups above 10 members get none, because Blizzard's tooltip lists no member rows for them.
- `SendWho` needs a hardware event (restricted since retail 8.2.5). It works from the row click hook: lookups answered in game on 2026-11-20. LFG Forever's source notes that its first version got ADDON_ACTION_BLOCKED for `SendWho` from a click, so this path may be fragile.
- The server silently drops a query sent too soon after another and publishes no limit. After each send the next member's row counts down "Wait Ns" from 5 s, redrawn each second, and clicks send nothing until it ends. In game on 2026-11-20, queries 5.8 s or more apart all answered in 0.3 s, and one sent 100.6 s after the previous got no answer, so a missing answer does not lengthen the spacing.
- No answer in 5 s: "No answer, click to retry", and the member goes behind the untried ones. A late answer is accepted for 60 s. The server's `WHO_COOLDOWN` message, if it comes, extends the countdown. Zones and "Not found" are cached 5 minutes.
- Before sending, `SetWhoToUi(false)` is set when neither Who list is visible, because results sent to the UI make `LFGWhoListMixin` raise the Who tab. With it off, up to 3 results arrive as CHAT_MSG_SYSTEM.
- `Compat.MatchFormat` compiles `WHO_LIST_GUILD_FORMAT`, `WHO_LIST_FORMAT`, `WHO_NUM_RESULTS` and `WHO_COOLDOWN(_SHORT)` into patterns and returns the arguments by number. It handles numbered placeholders (`%2$s`) and declension blocks (`|3-6(%4$s)`), which only ruRU uses, and plural blocks (`|4a:b;`). On 2026-11-20 the format strings of all 11 client languages (Ketho's BlizzardInterfaceResources, forever branch) parsed a rendered sample line. The zero-result total ("0 players total") has not been seen in game.
- The chat filter hides only the pending query's answer, one consumed within the last second, a dropped query's answer inside its late window, and the total line that follows. Any other `/who` line is the player's own and shows.

### Subzones
`ZoneOf` maps a reported area name (`areaName` and `/who` answers) to its zone
through `SUBZONES`, a generated table at the end of `Compat_Forever.lua` of every
top-level zone ID and its subzone IDs, nested ones resolved. Names come from
`C_Map.GetAreaInfo` on first use, so any client language works. A subzone also on
an instance copy (Old Hillsbrad, the Nightmare Grove raid's zone copies, Battle
for Gilneas) maps to its open-world zone. A name still under two zones (19:
border lakes, rivers, passes, bridges and seas) or one that is itself a zone (35,
mostly dungeons and their entrances, such as Stratholme) is shown as reported.
Client 1.60.1.70959: 1078 subzones under 68 of 187 zones, Riverglades and
Forever's Mount Hyjal included. After a client patch, extract AreaTable and Map
with the wow-dev skill's `wowdata.py tables <work> AreaTable Map` and run
`python3 tools/zones.py <work>/cached/AreaTable.json <work>/cached/Map.json Compat_Forever.lua <build>`.

### Development Workflow
- Validate: `luac -p LFGExpanded.lua Compat_Forever.lua` and `lua5.1 tests/forever.lua`. Twenty stand-in tests cover data access and restriction recovery, loading, category matching, the side tab, restoring and saving filters, include/exclude rules, the level range and checkbox centering, hidden class rows and the empty-list message, tooltip locations, subzone mapping, member lookups (countdown, late answers, queue order, chat filter, raid listings) and Russian format parsing. Stand-ins do not check rendering, taint or protected calls.
- Deploy for testing: copy `LFGExpanded.toc`, `Compat_Forever.lua`, `LFGExpanded.lua` and `LICENSE.md` to the install folder. `/reload` applies Lua changes; a TOC change needs a client restart.
- Before an in-game test pass, `/console scriptErrors 1` and `/console taintLog 1`.
- Keep CRLF line endings in `LFGExpanded.lua` and `LFGExpanded.toc`; a script that rewrites them in text mode turns every line into a diff.
- Release: bump `## Version` in the TOC, add a `CHANGELOG.md` entry, dry-run the packager (`CI.md`), then tag. `.pkgmeta` keeps docs, `assets`, `tests` and `tools` out of the zip. After the upload is approved, update the CurseForge description from `README.md`.
- The wow-dev skill holds the Forever API notes, the release workflow and the CurseForge tooling.

### Not yet tested in game (v2.0.0)
- "Not found" for an offline member, the server's `WHO_COOLDOWN` message, and late answers.
- Hovering and clicking listings inside dungeons, raids or battlegrounds.
- Raid listings (over 10 members).
- Send Message and Group Invite after the row click hook.
