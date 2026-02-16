# LFGFilter

**LFGFilter** adds a filter side panel to the LFG Browse frame, letting you filter search results by role and class with separate controls for groups and solo players.

Built specifically for **TBC Classic Anniversary**.

---

## Features

- **Two-column layout** - Separate filters for Groups (2+) and Singles (1)
- **Role filters** - Tank, Healer, DPS toggle icons
- **Class filters** - All 9 TBC classes with class-colored labels
- **Include/Exclude** - Left-click to require, right-click to exclude
- **Smart exclusion** - Groups: reject if excluded role/class is present. Singles: reject only if all listed roles are excluded (a healer+dps passes a healer exclusion)
- **Show/Hide toggle** - Checkbox to hide all groups or all singles entirely
- **Auto-delist cleanup** - Removes filled/delisted entries in real-time
- **Smart sorting** - Groups shown first, singles sorted by class when filters active
- **Resizable** - Drag the bottom-right corner to scale the panel

---

## Usage

Open the LFG Browse window. The filter panel appears automatically to the right.

### Controls

- **Left-click** a role or class to include it (must have)
- **Right-click** a role or class to exclude it (must NOT have)
- Click again to clear the filter
- Uncheck the section header checkbox to hide all groups or singles

---

## Configuration Options

- Role filters: Tank, Healer, DPS (per section)
- Class filters: Druid, Hunter, Mage, Paladin, Priest, Rogue, Shaman, Warlock, Warrior (per section)
- Show/Hide toggle per section
- Panel scale via drag-to-resize grip

---

## License

MIT License - Open source and free to use.

---

## Feedback & Issues

Found a bug or have a suggestion? Post a comment / message me on CurseForge, or open an issue on GitHub: https://github.com/clearcmos/LFGFilter
