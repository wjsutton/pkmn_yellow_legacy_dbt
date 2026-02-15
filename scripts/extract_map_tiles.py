"""
Extract walkable tile data from Pokemon Yellow Legacy ASM source files.

Downloads binary .blk (map block) and .bst (blockset) files from the
cRz-Shadows/Pokemon_Yellow_Legacy GitHub repo, then:
  1. Expands each block to its 4x4 tile grid using the blockset
  2. Checks collision tile IDs for each player-coordinate metatile
  3. Classifies each tile as path/grass/wall/ledge
  4. Outputs seeds/nav_map_tiles.csv and seeds/nav_map_tileset.csv

Usage:
    python scripts/extract_map_tiles.py
"""

import csv
import sys
import urllib.request
import urllib.error
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent  # pkmn_yellow_legacy_dbt root
CACHE_DIR = SCRIPT_DIR / "cache"
SEEDS_DIR = PROJECT_DIR / "seeds"

METADATA_CSV = SEEDS_DIR / "nav_map_metadata.csv"
OUTPUT_TILES_CSV = SEEDS_DIR / "nav_map_tiles.csv"
OUTPUT_TILESET_CSV = SEEDS_DIR / "nav_map_tileset.csv"

REPO_BASE = "https://raw.githubusercontent.com/cRz-Shadows/Pokemon_Yellow_Legacy/main"

# ---------------------------------------------------------------------------
# Dimension overrides from ASM source (constants/map_constants.asm)
# The nav_map_metadata.csv has vanilla Yellow dimensions for some maps, but
# Yellow Legacy expanded several maps. These are the CORRECT dimensions
# from the ASM source that match the .blk file sizes.
# Format: map_name -> (width_blocks, height_blocks)
# ---------------------------------------------------------------------------
DIMENSION_OVERRIDES = {
    "ROUTE_2": (10, 36),
    "ROUTE_3": (35, 9),
    "VIRIDIAN_GYM": (10, 9),
    "VIRIDIAN_FOREST_SOUTH_GATE": (5, 4),
    "VIRIDIAN_FOREST_NORTH_GATE": (5, 4),
    "ROUTE_2_GATE": (5, 4),
    "ROUTE_22_GATE": (5, 4),
}

# ---------------------------------------------------------------------------
# Map name -> .blk file name (CamelCase) mapping
# ---------------------------------------------------------------------------
MAP_NAME_TO_BLK = {
    "PALLET_TOWN": "PalletTown",
    "VIRIDIAN_CITY": "ViridianCity",
    "PEWTER_CITY": "PewterCity",
    "ROUTE_1": "Route1",
    "ROUTE_2": "Route2",
    "ROUTE_3": "Route3",
    "ROUTE_22": "Route22",
    "PLAYERS_HOUSE_1F": "RedsHouse1F",
    "PLAYERS_HOUSE_2F": "RedsHouse2F",
    "RIVALS_HOUSE": "BluesHouse",
    "OAKS_LAB": "OaksLab",
    "VIRIDIAN_POKECENTER": "ViridianPokecenter",
    "VIRIDIAN_MART": "ViridianMart",
    "VIRIDIAN_GYM": "ViridianGym",
    "VIRIDIAN_FOREST": "ViridianForest",
    "VIRIDIAN_FOREST_SOUTH_GATE": "ViridianForestSouthGate",
    "VIRIDIAN_FOREST_NORTH_GATE": "ViridianForestNorthGate",
    "PEWTER_POKECENTER": "PewterPokecenter",
    "PEWTER_GYM": "PewterGym",
    "PEWTER_MART": "PewterMart",
    "PEWTER_MUSEUM_1F": "Museum1F",
    "PEWTER_MUSEUM_2F": "Museum2F",
    "ROUTE_2_GATE": "Route2Gate",
    "ROUTE_2_HOUSE": "Route2TradeHouse",
    "ROUTE_22_GATE": "Route22Gate",
}

# ---------------------------------------------------------------------------
# Map name -> tileset name (from map header ASM inspection)
# ---------------------------------------------------------------------------
MAP_NAME_TO_TILESET = {
    "PALLET_TOWN": "Overworld",
    "VIRIDIAN_CITY": "Overworld",
    "PEWTER_CITY": "Overworld",
    "ROUTE_1": "Overworld",
    "ROUTE_2": "Overworld",
    "ROUTE_3": "Overworld",
    "ROUTE_22": "Overworld",
    "PLAYERS_HOUSE_1F": "RedsHouse1",
    "PLAYERS_HOUSE_2F": "RedsHouse2",
    "RIVALS_HOUSE": "House",
    "OAKS_LAB": "Dojo",           # confirmed from header: DOJO tileset
    "VIRIDIAN_POKECENTER": "Pokecenter",
    "VIRIDIAN_MART": "Mart",
    "VIRIDIAN_GYM": "Gym",
    "VIRIDIAN_FOREST": "Forest",
    "VIRIDIAN_FOREST_SOUTH_GATE": "ForestGate",
    "VIRIDIAN_FOREST_NORTH_GATE": "ForestGate",
    "PEWTER_POKECENTER": "Pokecenter",
    "PEWTER_GYM": "Gym",
    "PEWTER_MART": "Mart",
    "PEWTER_MUSEUM_1F": "Museum",
    "PEWTER_MUSEUM_2F": "Museum",
    "ROUTE_2_GATE": "Gate",
    "ROUTE_2_HOUSE": "House",
    "ROUTE_22_GATE": "Gate",
}

# ---------------------------------------------------------------------------
# Tileset name -> blockset .bst file name
# From gfx/tilesets.asm, each tileset's _Block symbol points to an INCBIN.
# Some tilesets share blocksets (e.g. Dojo/Gym -> gym.bst, Mart/Pokecenter -> pokecenter.bst).
# ---------------------------------------------------------------------------
TILESET_TO_BST = {
    "Overworld": "overworld.bst",
    "RedsHouse1": "reds_house.bst",
    "RedsHouse2": "reds_house.bst",
    "House": "house.bst",
    "Dojo": "gym.bst",           # Dojo_Block = Gym_Block = gym.bst
    "Gym": "gym.bst",
    "Mart": "pokecenter.bst",    # Mart_Block = Pokecenter_Block = pokecenter.bst
    "Pokecenter": "pokecenter.bst",
    "Forest": "forest.bst",
    "ForestGate": "gate.bst",    # ForestGate_Block = Museum_Block = Gate_Block = gate.bst
    "Museum": "gate.bst",
    "Gate": "gate.bst",
    "Lab": "lab.bst",
    "Cavern": "cavern.bst",
}

# ---------------------------------------------------------------------------
# Collision tile IDs per tileset (from data/tilesets/collision_tile_ids.asm)
# These are the PASSABLE tiles -- any tile NOT in this set is a wall.
# ---------------------------------------------------------------------------
COLLISION_TILES = {
    "Overworld": {0x00, 0x10, 0x1b, 0x20, 0x21, 0x23, 0x2c, 0x2d, 0x2e,
                  0x30, 0x31, 0x33, 0x39, 0x3c, 0x3e, 0x52, 0x54, 0x58, 0x5b},
    "RedsHouse1": {0x01, 0x02, 0x03, 0x11, 0x12, 0x13, 0x14, 0x1c, 0x1a},
    "RedsHouse2": {0x01, 0x02, 0x03, 0x11, 0x12, 0x13, 0x14, 0x1c, 0x1a},
    "Mart": {0x11, 0x1a, 0x1c, 0x3c, 0x5e},
    "Pokecenter": {0x11, 0x1a, 0x1c, 0x3c, 0x5e},
    "Dojo": {0x11, 0x16, 0x19, 0x2b, 0x3c, 0x3d, 0x3f, 0x4a, 0x4c, 0x4d, 0x03},
    "Gym": {0x11, 0x16, 0x19, 0x2b, 0x3c, 0x3d, 0x3f, 0x4a, 0x4c, 0x4d, 0x03},
    "Forest": {0x1e, 0x20, 0x2e, 0x30, 0x34, 0x37, 0x39, 0x3a, 0x40, 0x51,
               0x52, 0x5a, 0x5c, 0x5e, 0x5f},
    "House": {0x01, 0x12, 0x14, 0x28, 0x32, 0x37, 0x44, 0x54, 0x5c},
    "ForestGate": {0x01, 0x12, 0x14, 0x1a, 0x1c, 0x37, 0x38, 0x3b, 0x3c, 0x5e},
    "Museum": {0x01, 0x12, 0x14, 0x1a, 0x1c, 0x37, 0x38, 0x3b, 0x3c, 0x5e},
    "Gate": {0x01, 0x12, 0x14, 0x1a, 0x1c, 0x37, 0x38, 0x3b, 0x3c, 0x5e},
    "Lab": {0x0c, 0x26, 0x16, 0x1e, 0x34, 0x37},
    "Cavern": {0x05, 0x15, 0x18, 0x1a, 0x20, 0x21, 0x22, 0x2a, 0x2d, 0x30},
}

# ---------------------------------------------------------------------------
# Grass tile per tileset (from tileset_headers.asm)
# These tiles are passable but trigger wild encounters.
# ---------------------------------------------------------------------------
GRASS_TILES = {
    "Overworld": 0x52,
    "Forest": 0x20,   # Forest grass tile from tileset header (but see note below)
}
# Note: In Forest tileset, 0x52 is also passable (tall grass sprite tile).
# The tileset header says grass=$20 for Forest, meaning the *movement tile* that
# triggers encounters is 0x20. We'll mark 0x52 in Forest as grass too since
# it also appears as walkable grass.

# Additional grass tiles by tileset (tiles that look like grass AND are passable)
EXTRA_GRASS_TILES = {
    "Overworld": set(),      # 0x52 already covered
    "Forest": {0x52},        # Forest also has 0x52 as grass encounter tile
}

# ---------------------------------------------------------------------------
# Ledge tiles (from data/tilesets/ledge_tiles.asm)
# Format: (standing_tile, target_tile) -> direction
# These only apply to Overworld tileset.
# The ledge check works by looking at the tile the player is standing on
# AND the tile in the direction they want to move.
# ---------------------------------------------------------------------------
# For our purposes, we need to identify which player coordinates have ledges.
# Ledge tiles are passable in one direction only.
# The "target" tiles (0x37, 0x36, 0x27, 0x0D, 0x1D) are what the LEDGE looks
# like. The player stands on a passable tile and can jump OVER the ledge tile.
# So the ledge tile itself is NOT normally passable (it's not in collision list).
# But the player CAN move onto it from certain directions.
#
# For the tile grid: we mark the TARGET tile positions as ledge tiles.
# A ledge tile at (x,y) means the player can land there only from the
# appropriate direction.
LEDGE_TARGET_TILES = {
    "Overworld": {
        0x37: "down",    # ledge facing down
        0x36: "down",    # ledge facing down (variant)
        0x27: "left",    # ledge facing left
        0x0D: "right",   # ledge facing right
        0x1D: "right",   # ledge facing right (variant)
    }
}


def download_file(url: str, cache_path: Path) -> bytes:
    """Download a file from URL, using local cache if available."""
    if cache_path.exists():
        return cache_path.read_bytes()

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        resp = urllib.request.urlopen(url)
        data = resp.read()
        cache_path.write_bytes(data)
        return data
    except urllib.error.HTTPError as e:
        print(f"  WARNING: HTTP {e.code} downloading {url}")
        return None


def load_metadata() -> list[dict]:
    """Load map metadata from the nav_map_metadata.csv seed.

    Applies DIMENSION_OVERRIDES where the CSV dimensions don't match the
    actual ASM source (Yellow Legacy expanded some maps).
    """
    maps = []
    with open(METADATA_CSV, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if not row["map_name"]:
                continue
            map_name = row["map_name"]
            width = int(row["width"])
            height = int(row["height"])

            # Apply dimension overrides from ASM source
            if map_name in DIMENSION_OVERRIDES:
                old_w, old_h = width, height
                width, height = DIMENSION_OVERRIDES[map_name]
                print(f"  [override] {map_name}: {old_w}x{old_h} -> {width}x{height}")

            maps.append({
                "map_name": map_name,
                "width": width,
                "height": height,
            })
    return maps


def download_blk(map_name: str) -> bytes | None:
    """Download the .blk file for a given map name."""
    blk_name = MAP_NAME_TO_BLK.get(map_name)
    if not blk_name:
        print(f"  WARNING: No .blk mapping for {map_name}, skipping")
        return None

    url = f"{REPO_BASE}/maps/{blk_name}.blk"
    cache_path = CACHE_DIR / "maps" / f"{blk_name}.blk"
    data = download_file(url, cache_path)
    if data is None:
        print(f"  WARNING: Could not download {blk_name}.blk")
    return data


def download_bst(tileset_name: str) -> bytes | None:
    """Download the .bst blockset file for a given tileset."""
    bst_file = TILESET_TO_BST.get(tileset_name)
    if not bst_file:
        print(f"  WARNING: No .bst mapping for tileset {tileset_name}")
        return None

    url = f"{REPO_BASE}/gfx/blocksets/{bst_file}"
    cache_path = CACHE_DIR / "blocksets" / bst_file
    data = download_file(url, cache_path)
    if data is None:
        print(f"  WARNING: Could not download {bst_file}")
    return data


def get_block_tiles(bst_data: bytes, block_id: int) -> list[int]:
    """
    Extract the 16 tile IDs for a given block from the blockset data.
    Returns a list of 16 bytes representing the 4x4 tile grid:
      [row0_col0, row0_col1, row0_col2, row0_col3,
       row1_col0, row1_col1, row1_col2, row1_col3,
       row2_col0, row2_col1, row2_col2, row2_col3,
       row3_col0, row3_col1, row3_col2, row3_col3]
    """
    offset = block_id * 16
    if offset + 16 > len(bst_data):
        return [0] * 16
    return list(bst_data[offset:offset + 16])


def get_collision_tile(block_tiles: list[int], mx: int, my: int) -> int:
    """
    Get the collision-check tile for a metatile position within a block.

    A block is 4x4 tiles. The player occupies 2x2 tiles. There are 4
    metatile positions per block: (0,0), (1,0), (0,1), (1,1).

    For metatile (mx, my), the 2x2 tiles are:
      top-left:     row=my*2,   col=mx*2
      top-right:    row=my*2,   col=mx*2+1
      bottom-left:  row=my*2+1, col=mx*2
      bottom-right: row=my*2+1, col=mx*2+1

    The game checks the BOTTOM-LEFT tile for collision:
      row = my*2 + 1, col = mx*2
      byte index = (my*2 + 1) * 4 + mx*2
    """
    row = my * 2 + 1
    col = mx * 2
    idx = row * 4 + col
    return block_tiles[idx]


def classify_tile(tile_id: int, tileset_name: str) -> tuple[str, bool, str]:
    """
    Classify a tile as (tile_type, walkable, ledge_direction).

    Returns:
        tile_type: "path", "grass", "wall", or "ledge"
        walkable: True if passable (path, grass, or ledge)
        ledge_direction: direction string for ledges, empty otherwise
    """
    passable_tiles = COLLISION_TILES.get(tileset_name, set())
    grass_tile = GRASS_TILES.get(tileset_name)
    extra_grass = EXTRA_GRASS_TILES.get(tileset_name, set())
    ledge_targets = LEDGE_TARGET_TILES.get(tileset_name, {})

    # Check ledge first -- ledge target tiles are NOT in the passable set
    # but are traversable in one direction
    if tile_id in ledge_targets:
        direction = ledge_targets[tile_id]
        return ("ledge", True, direction)

    # Check if passable
    if tile_id in passable_tiles:
        # Check if it's grass
        if tile_id == grass_tile or tile_id in extra_grass:
            return ("grass", True, "")
        else:
            return ("path", True, "")

    # Not passable
    return ("wall", False, "")


def process_map(map_info: dict, bst_cache: dict) -> list[dict]:
    """
    Process a single map and return a list of tile rows.

    Each row: {map_name, x, y, tile_type, walkable, ledge_direction}
    """
    map_name = map_info["map_name"]
    width_blocks = map_info["width"]
    height_blocks = map_info["height"]

    tileset_name = MAP_NAME_TO_TILESET.get(map_name)
    if not tileset_name:
        print(f"  WARNING: No tileset for {map_name}, skipping")
        return []

    # Download .blk
    blk_data = download_blk(map_name)
    if blk_data is None:
        return []

    expected_size = width_blocks * height_blocks
    if len(blk_data) != expected_size:
        print(f"  WARNING: {map_name} .blk size {len(blk_data)} != expected "
              f"{expected_size} ({width_blocks}x{height_blocks})")
        return []

    # Get blockset data
    if tileset_name not in bst_cache:
        bst_data = download_bst(tileset_name)
        if bst_data is None:
            return []
        bst_cache[tileset_name] = bst_data
    bst_data = bst_cache[tileset_name]

    rows = []
    for by in range(height_blocks):
        for bx in range(width_blocks):
            block_id = blk_data[by * width_blocks + bx]
            block_tiles = get_block_tiles(bst_data, block_id)

            # Each block has 2x2 metatile positions
            for my in range(2):
                for mx in range(2):
                    # Player coordinate on the map
                    px = bx * 2 + mx
                    py = by * 2 + my

                    # Get the collision tile
                    tile_id = get_collision_tile(block_tiles, mx, my)
                    tile_type, walkable, ledge_dir = classify_tile(
                        tile_id, tileset_name
                    )

                    rows.append({
                        "map_name": map_name,
                        "x": px,
                        "y": py,
                        "tile_type": tile_type,
                        "walkable": walkable,
                        "ledge_direction": ledge_dir,
                    })

    return rows


def main():
    print("=" * 60)
    print("Pokemon Yellow Legacy - Map Tile Extractor")
    print("=" * 60)

    # Load metadata
    if not METADATA_CSV.exists():
        print(f"ERROR: {METADATA_CSV} not found")
        sys.exit(1)

    maps = load_metadata()
    print(f"Loaded {len(maps)} maps from {METADATA_CSV.name}")

    # Create cache directory
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    # Process each map
    bst_cache: dict[str, bytes] = {}
    all_tile_rows = []
    tileset_rows = []

    for map_info in maps:
        map_name = map_info["map_name"]
        tileset_name = MAP_NAME_TO_TILESET.get(map_name, "UNKNOWN")
        print(f"\nProcessing {map_name} ({map_info['width']}x{map_info['height']} blocks, "
              f"tileset={tileset_name})...")

        tile_rows = process_map(map_info, bst_cache)
        if tile_rows:
            all_tile_rows.extend(tile_rows)
            walkable_count = sum(1 for r in tile_rows if r["walkable"])
            wall_count = sum(1 for r in tile_rows if r["tile_type"] == "wall")
            grass_count = sum(1 for r in tile_rows if r["tile_type"] == "grass")
            ledge_count = sum(1 for r in tile_rows if r["tile_type"] == "ledge")
            total = len(tile_rows)
            print(f"  -> {total} tiles: {walkable_count} walkable "
                  f"({grass_count} grass, {ledge_count} ledge), {wall_count} wall")

        tileset_rows.append({
            "map_name": map_name,
            "tileset_name": tileset_name,
        })

    # Write nav_map_tiles.csv
    print(f"\n{'=' * 60}")
    print(f"Writing {OUTPUT_TILES_CSV}...")
    with open(OUTPUT_TILES_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "map_name", "x", "y", "tile_type", "walkable", "ledge_direction"
        ])
        writer.writeheader()
        writer.writerows(all_tile_rows)
    print(f"  -> {len(all_tile_rows)} total tile rows written")

    # Write nav_map_tileset.csv
    print(f"Writing {OUTPUT_TILESET_CSV}...")
    with open(OUTPUT_TILESET_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["map_name", "tileset_name"])
        writer.writeheader()
        writer.writerows(tileset_rows)
    print(f"  -> {len(tileset_rows)} tileset rows written")

    # Summary
    print(f"\n{'=' * 60}")
    print("Summary:")
    total_walkable = sum(1 for r in all_tile_rows if r["walkable"])
    total_wall = sum(1 for r in all_tile_rows if r["tile_type"] == "wall")
    total_grass = sum(1 for r in all_tile_rows if r["tile_type"] == "grass")
    total_ledge = sum(1 for r in all_tile_rows if r["tile_type"] == "ledge")
    print(f"  Total tiles:    {len(all_tile_rows)}")
    print(f"  Walkable:       {total_walkable} "
          f"({total_walkable / len(all_tile_rows) * 100:.1f}%)")
    print(f"    - Path:       {total_walkable - total_grass - total_ledge}")
    print(f"    - Grass:      {total_grass}")
    print(f"    - Ledge:      {total_ledge}")
    print(f"  Wall:           {total_wall} "
          f"({total_wall / len(all_tile_rows) * 100:.1f}%)")
    print(f"\nDone!")


if __name__ == "__main__":
    main()
