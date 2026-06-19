"""
Extract warp connections from Pokemon Yellow Legacy ASM source files.

Two ground-truth sources in the cRz-Shadows/Pokemon_Yellow_Legacy disassembly:
  1. data/maps/objects/<Camel>.asm -- `warp_event x, y, DEST_MAP, warp_id`
     (doors / gates / stairs / cave entrances). The landing tile is the
     destination map's warp_event #warp_id (1-indexed). DEST of LAST_MAP is a
     return leg and is synthesised from the explicit side instead.
  2. data/maps/headers/<Camel>.asm -- `connection <dir>, <Label>, <CONST>, <offset>`
     (walk-off-the-edge map transitions). dest_block = src_block - offset.

Outputs seeds/nav_map_warps.csv with the same schema the hand-authored seed used:
    from_map, from_x, from_y, to_map, to_x, to_y, warp_type, notes

Coordinates are player tiles (0-indexed), matching nav_map_tiles.csv / the
memory reader. Map dimensions in MAP_DIMENSIONS are blocks; player tiles = 2x.

Usage:
    python scripts/extract_map_warps.py
"""

import csv
import re
from pathlib import Path

from extract_map_tiles import (
    MAP_DIMENSIONS,
    get_blk_name,
    download_file,
    CACHE_DIR,
    SEEDS_DIR,
    REPO_BASE,
)

OUTPUT_WARPS_CSV = SEEDS_DIR / "nav_map_warps.csv"
TILES_CSV = SEEDS_DIR / "nav_map_tiles.csv"
METADATA_CSV = SEEDS_DIR / "nav_map_metadata.csv"

WARP_EVENT_RE = re.compile(r"warp_event\s+(-?\d+),\s*(-?\d+),\s*(\w+),\s*(\w+)")
CONNECTION_RE = re.compile(r"connection\s+(\w+),\s*(\w+),\s*(\w+),\s*(-?\d+)")

# Map-name floor suffixes used to detect same-building stairs warps.
FLOOR_SUFFIX_RE = re.compile(r"_(B?\d+F|ROOF|ELEVATOR)$")


def fetch(path: str) -> str | None:
    """Download a text asm file from the disassembly (cached)."""
    cache_path = CACHE_DIR / path.replace("/", "_")
    data = download_file(f"{REPO_BASE}/{path}", cache_path)
    return data.decode("utf-8", "replace") if data else None


def load_walkable() -> dict[str, set[tuple[int, int]]]:
    """walkable_by_map[map_name] = {(x, y), ...} from the tiles seed."""
    walkable: dict[str, set[tuple[int, int]]] = {}
    with open(TILES_CSV, newline="") as f:
        for row in csv.DictReader(f):
            if row["walkable"] == "True":
                walkable.setdefault(row["map_name"], set()).add(
                    (int(row["x"]), int(row["y"]))
                )
    return walkable


def load_area_types() -> dict[str, str]:
    with open(METADATA_CSV, newline="") as f:
        return {r["map_name"]: r["area_type"] for r in csv.DictReader(f)}


def parse_warp_events(const: str) -> list[tuple[int, int, str, int]]:
    """Return [(x, y, dest_const, warp_id), ...] for a map's object file."""
    blk = get_blk_name(const)
    if blk is None:
        return []
    text = fetch(f"data/maps/objects/{blk}.asm")
    if text is None:
        return []
    events = []
    for x, y, dest, wid in WARP_EVENT_RE.findall(text):
        if not wid.isdigit():
            continue  # non-numeric warp id (rare/unsupported) -- skip
        events.append((int(x), int(y), dest, int(wid)))
    return events


def parse_connections(const: str) -> list[tuple[str, str, int]]:
    """Return [(direction, dest_const, offset), ...] for a map's header file."""
    blk = get_blk_name(const)
    if blk is None:
        return []
    text = fetch(f"data/maps/headers/{blk}.asm")
    if text is None:
        return []
    return [(d.lower(), dest, int(off)) for d, _lbl, dest, off in CONNECTION_RE.findall(text)]


def base_name(const: str) -> str:
    return FLOOR_SUFFIX_RE.sub("", const)


def classify(from_const: str, to_const: str, area_types: dict[str, str]) -> str:
    if area_types.get(to_const) == "gate":
        return "gate"
    if base_name(from_const) == base_name(to_const) and from_const != to_const:
        return "stairs"
    return "door"


def dims_tiles(const: str) -> tuple[int, int]:
    w, h = MAP_DIMENSIONS[const]
    return w * 2, h * 2


def snap_walkable(walk: set[tuple[int, int]], target: int, axis_is_x: bool,
                  fixed: int) -> int:
    """Nearest walkable coord along an edge to `target` (fixed perpendicular)."""
    candidates = [(p[0] if axis_is_x else p[1]) for p in walk
                  if (p[1] == fixed if axis_is_x else p[0] == fixed)]
    if not candidates:
        return target
    return min(candidates, key=lambda c: abs(c - target))


def build_edge_warps(const: str, walk_all: dict, area_types: dict) -> list[dict]:
    """One edge warp per header connection, snapped to walkable boundary tiles."""
    src_w, src_h = dims_tiles(const)
    rows = []
    for direction, dest, offset in parse_connections(const):
        if dest not in MAP_DIMENSIONS:
            continue
        dst_w, dst_h = dims_tiles(dest)
        src_walk = walk_all.get(const, set())
        dst_walk = walk_all.get(dest, set())
        # src edge row/col + the axis we travel along
        if direction == "north":
            axis_is_x, src_fixed, dst_fixed = True, 0, dst_h - 1
        elif direction == "south":
            axis_is_x, src_fixed, dst_fixed = True, src_h - 1, 0
        elif direction == "west":
            axis_is_x, src_fixed, dst_fixed = False, 0, dst_w - 1
        elif direction == "east":
            axis_is_x, src_fixed, dst_fixed = False, src_w - 1, 0
        else:
            continue
        # representative src boundary tile (median walkable along the edge)
        along = sorted(p[0] if axis_is_x else p[1] for p in src_walk
                       if (p[1] == src_fixed if axis_is_x else p[0] == src_fixed))
        if not along:
            continue
        src_along = along[len(along) // 2]
        # dest_block = src_block - offset  ->  player tiles = block*2
        dst_along = snap_walkable(dst_walk, (src_along // 2 - offset) * 2,
                                  axis_is_x, dst_fixed)
        if axis_is_x:
            fx, fy, tx, ty = src_along, src_fixed, dst_along, dst_fixed
        else:
            fx, fy, tx, ty = src_fixed, src_along, dst_fixed, dst_along
        rows.append(dict(from_map=const, from_x=fx, from_y=fy, to_map=dest,
                         to_x=tx, to_y=ty, warp_type="edge",
                         notes=f"{direction.capitalize()} edge to {dest}"))
    return rows


def main() -> None:
    print("Loading tile walkability + metadata ...")
    walk_all = load_walkable()
    area_types = load_area_types()

    print("Parsing warp_events for all maps ...")
    events: dict[str, list] = {}
    for const in MAP_DIMENSIONS:
        events[const] = parse_warp_events(const)

    warps: dict[tuple[str, int, int, str], dict] = {}
    explicit_from: set[tuple[str, int, int]] = set()

    def add(row: dict) -> None:
        key = (row["from_map"], row["from_x"], row["from_y"], row["to_map"])
        warps.setdefault(key, row)

    # 1) explicit warp_events (+ synthesised reverse for LAST_MAP return legs)
    for const, evs in events.items():
        for x, y, dest, wid in evs:
            if dest == "LAST_MAP" or dest not in events:
                continue
            dest_evs = events[dest]
            if wid - 1 >= len(dest_evs):
                continue
            lx, ly = dest_evs[wid - 1][0], dest_evs[wid - 1][1]
            wtype = classify(const, dest, area_types)
            add(dict(from_map=const, from_x=x, from_y=y, to_map=dest,
                     to_x=lx, to_y=ly, warp_type=wtype, notes=f"To {dest}"))
            explicit_from.add((const, x, y))

    # 2) synthesise reverse legs (dest tile -> origin) where dest side is LAST_MAP
    for const, evs in events.items():
        for x, y, dest, wid in evs:
            if dest == "LAST_MAP" or dest not in events:
                continue
            dest_evs = events[dest]
            if wid - 1 >= len(dest_evs):
                continue
            lx, ly = dest_evs[wid - 1][0], dest_evs[wid - 1][1]
            if (dest, lx, ly) in explicit_from:
                continue  # dest already has its own explicit warp here
            wtype = classify(dest, const, area_types)
            add(dict(from_map=dest, from_x=lx, from_y=ly, to_map=const,
                     to_x=x, to_y=y, warp_type=wtype, notes=f"To {const}"))

    # 3) edge connections
    for const in MAP_DIMENSIONS:
        for row in build_edge_warps(const, walk_all, area_types):
            add(row)

    rows = sorted(warps.values(),
                  key=lambda r: (r["from_map"], r["from_y"], r["from_x"]))
    with open(OUTPUT_WARPS_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "from_map", "from_x", "from_y", "to_map", "to_x", "to_y",
            "warp_type", "notes"])
        writer.writeheader()
        writer.writerows(rows)

    by_type: dict[str, int] = {}
    for r in rows:
        by_type[r["warp_type"]] = by_type.get(r["warp_type"], 0) + 1
    print(f"Wrote {len(rows)} warps to {OUTPUT_WARPS_CSV}: {by_type}")


if __name__ == "__main__":
    main()
