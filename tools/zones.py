#!/usr/bin/env python3
"""Regenerate the subzone table in Compat_Forever.lua from the Forever client.

Usage: python3 tools/zones.py <AreaTable.json> <Map.json> [<Compat_Forever.lua> [<build>]]

The JSON files are the client's AreaTable and Map tables decoded to lists of
rows, for example with the wow-dev skill's `wowdata.py tables <work> AreaTable
Map`, which writes them to <work>/cached/. Every area with a parent is grouped
under its top-level zone (ParentAreaID 0), following nested parents. When a
name occurs both in the open world and on an instance, battleground or unknown
map (Old Hillsbrad, the Nightmare Grove raid's zone copies), only the
open-world occurrences are kept. Without the Lua file it only prints counts;
<build> labels the generated block. The table holds area IDs: the addon reads
the localized names in game with C_Map.GetAreaInfo, and leaves a name that
still falls under more than one zone, or is itself a zone name, as it is.
"""
import json
import re
import sys

BEGIN = "-- BEGIN GENERATED SUBZONES (tools/zones.py)"
BUILD = sys.argv[4] if len(sys.argv) > 4 else "data"
END = "-- END GENERATED SUBZONES"


def roots(rows, maps):
    by_id = {row["ID"]: row for row in rows}

    def open_world(row):
        m = maps.get(row.get("ContinentID"))
        return m is not None and m.get("InstanceType") == 0

    world_names = {r.get("AreaName_lang") for r in rows if r.get("ParentAreaID", 0) != 0 and open_world(r)}
    # Every zone is listed, with or without subzones, so the addon knows all zone names.
    groups = {r["ID"]: [] for r in rows if r.get("ParentAreaID", 0) == 0}
    for row in rows:
        if row.get("ParentAreaID", 0) == 0:
            continue
        if not open_world(row) and row.get("AreaName_lang") in world_names:
            continue  # an instance copy of an open-world subzone
        seen, area = set(), row
        while area.get("ParentAreaID", 0) != 0 and area["ID"] not in seen:
            seen.add(area["ID"])
            parent = by_id.get(area["ParentAreaID"])
            if parent is None:
                break
            area = parent
        if area.get("ParentAreaID", 0) != 0:
            continue  # a broken or circular chain: leave the area out
        groups.setdefault(area["ID"], []).append(row["ID"])
    return by_id, groups


def lua_block(groups, build):
    lines = [BEGIN, f"-- Client {build}: every top-level zone ID -> its subzone IDs, nested ones included.",
             "SUBZONES = {"]
    for root in sorted(groups):
        ids = ", ".join(str(i) for i in sorted(groups[root]))
        lines.append(f"    [{root}] = {{ {ids} }}," if ids else f"    [{root}] = {{}},")
    lines += ["}", END]
    return "\n".join(lines)


def report(by_id, groups):
    names = {}
    for root, ids in groups.items():
        for i in ids:
            names.setdefault(by_id[i].get("AreaName_lang", ""), set()).add(by_id[root].get("AreaName_lang", ""))
    root_names = {by_id[r].get("AreaName_lang", "") for r in by_id if by_id[r].get("ParentAreaID", 0) == 0}
    ambiguous = sorted(n for n, r in names.items() if len(r) > 1)
    shadowed = sorted(n for n in names if n in root_names)
    count = sum(len(ids) for ids in groups.values())
    print(f"{count} subzones under {sum(1 for ids in groups.values() if ids)} of {len(groups)} zones")
    print(f"{len(ambiguous)} names under more than one zone (shown unmapped): {', '.join(ambiguous)}")
    print(f"{len(shadowed)} names that are also a zone (shown as is): {', '.join(shadowed)}")


def main():
    if len(sys.argv) not in (3, 4, 5):
        sys.exit(__doc__)
    with open(sys.argv[1], encoding="utf-8") as f:
        rows = json.load(f)
    with open(sys.argv[2], encoding="utf-8") as f:
        maps = {m["ID"]: m for m in json.load(f)}
    by_id, groups = roots(rows, maps)
    report(by_id, groups)
    if len(sys.argv) >= 4:
        path = sys.argv[3]
        with open(path, encoding="utf-8") as f:
            source = f.read()
        block = lua_block(groups, BUILD)
        pattern = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.S)
        if not pattern.search(source):
            sys.exit(f"{path} has no generated block between the markers")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(pattern.sub(lambda _: block, source))
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
