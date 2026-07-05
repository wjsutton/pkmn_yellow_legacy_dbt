"""
Extract item data from the Pokemon Yellow Legacy ASM source files.

Ground-truth sources in the cRz-Shadows/Pokemon_Yellow_Legacy disassembly:
  constants/item_constants.asm  -- item ids (+ add_tm/add_hm TM/HM aliases)
  data/items/names.asm          -- display names
  data/items/prices.asm         -- buy prices (bcd3)
  data/items/tm_prices.asm      -- TM prices in thousands (nybble)
  data/items/key_items.asm      -- key-item flags (dbit)
  data/items/marts.asm          -- shop inventories (script_mart per clerk)
  data/items/vending_prices.asm -- Celadon roof vending machines
  data/events/prizes.asm        -- Game Corner TM prizes (coins)
  data/events/hidden_objects.asm-- hidden items with map + coords
  data/maps/objects/<Map>.asm   -- visible item balls (object_event SPRITE_POKE_BALL)
  scripts/<Map>.asm             -- NPC gifts (`lb bc, ITEM, qty` + `call GiveItem`)

Outputs:
  seeds/items.csv          item_const, item_id, item_name, price, is_key_item,
                           tm_number, tm_move, description
  seeds/item_locations.csv map, item_const, source_type, x, y, quantity,
                           price, currency, notes

Usage:
    python scripts/extract_items.py
"""

import csv
import json
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
from extract_map_warps import DEST_CONST_ALIASES

ITEMS_CSV = SEEDS_DIR / "items.csv"
LOCATIONS_CSV = SEEDS_DIR / "item_locations.csv"

API_BASE = "https://api.github.com/repos/cRz-Shadows/Pokemon_Yellow_Legacy/contents"

CONST_RE = re.compile(r"^\tconst\s+(\w+)")
CONST_NEXT_RE = re.compile(r"^\tconst_next\s+\$?([0-9A-Fa-f]+)")
ADD_TM_RE = re.compile(r"^\tadd_tm\s+(\w+)")
ADD_HM_RE = re.compile(r"^\tadd_hm\s+(\w+)")
NAME_RE = re.compile(r'^\tli\s+"(.+)"')
PRICE_RE = re.compile(r"^\tbcd3\s+(\d+)\s*;\s*(\w+)")
KEY_ITEM_RE = re.compile(r"^\tdbit\s+(TRUE|FALSE)\s*;\s*(\w+)")
TM_PRICE_RE = re.compile(r"^\tnybble\s+(\d+)\s*;\s*TM(\d+)")
MART_LABEL_RE = re.compile(r"^(\w+)::")
SCRIPT_MART_RE = re.compile(r"^\tscript_mart\s+(.+)")
VEND_RE = re.compile(r"^\tvend_item\s+(\w+),\s*(\d+)")
HIDDEN_MAP_RE = re.compile(r"^\tdbw\s+(\w+),\s*(\w+)")
HIDDEN_OBJ_RE = re.compile(r"^\thidden_object\s+(\d+),\s*(\d+),\s*(\w+),\s*(\w+)")
ITEM_BALL_RE = re.compile(
    r"^\tobject_event\s+(\d+),\s*(\d+),\s*SPRITE_POKE_BALL,\s*\w+,\s*\w+,\s*\w+,\s*(\w+)"
)
GIVE_ITEM_LB_RE = re.compile(r"^\tlb\s+bc,\s*(\w+),\s*(\d+)")
GIVE_ITEM_CALL_RE = re.compile(r"call\s+GiveItem")
DEBUG_BLOCK_RE = re.compile(r"IF DEF\(_DEBUG\).*?ENDC", re.DOTALL)

# Short functional descriptions (Gen 1 has no in-ROM item descriptions).
DESCRIPTIONS = {
    "MASTER_BALL": "The best Ball. Catches any wild Pokemon without fail.",
    "ULTRA_BALL": "A high-performance Ball with a better catch rate than a Great Ball.",
    "GREAT_BALL": "A good Ball with a better catch rate than a Poke Ball.",
    "POKE_BALL": "A basic Ball used to catch wild Pokemon.",
    "TOWN_MAP": "A map of the Kanto region.",
    "BICYCLE": "A folding bicycle. Travel twice as fast as walking.",
    "SURFBOARD": "Lets the player surf on water without an HM user.",
    "SAFARI_BALL": "A special Ball used only in the Safari Zone.",
    "POKEDEX": "A high-tech encyclopedia that records Pokemon data.",
    "MOON_STONE": "A stone that makes certain Pokemon evolve.",
    "ANTIDOTE": "Cures a poisoned Pokemon.",
    "BURN_HEAL": "Heals a burned Pokemon.",
    "ICE_HEAL": "Defrosts a frozen Pokemon.",
    "AWAKENING": "Awakens a sleeping Pokemon.",
    "PARLYZ_HEAL": "Cures a paralyzed Pokemon.",
    "FULL_RESTORE": "Fully restores HP and cures all status problems.",
    "MAX_POTION": "Fully restores a Pokemon's HP.",
    "HYPER_POTION": "Restores 200 HP.",
    "SUPER_POTION": "Restores 50 HP.",
    "POTION": "Restores 20 HP.",
    "BOULDERBADGE": "Pewter Gym badge from Brock.",
    "CASCADEBADGE": "Cerulean Gym badge from Misty.",
    "THUNDERBADGE": "Vermilion Gym badge from Lt. Surge.",
    "RAINBOWBADGE": "Celadon Gym badge from Erika.",
    "SOULBADGE": "Fuchsia Gym badge from Koga.",
    "MARSHBADGE": "Saffron Gym badge from Sabrina.",
    "VOLCANOBADGE": "Cinnabar Gym badge from Blaine.",
    "EARTHBADGE": "Viridian Gym badge from Giovanni.",
    "ESCAPE_ROPE": "Escape instantly from a cave or dungeon.",
    "REPEL": "Repels weak wild Pokemon for 100 steps.",
    "OLD_AMBER": "Amber holding Pokemon DNA. Revives into Aerodactyl.",
    "FIRE_STONE": "A stone that makes certain Pokemon evolve.",
    "THUNDER_STONE": "A stone that makes certain Pokemon evolve.",
    "WATER_STONE": "A stone that makes certain Pokemon evolve.",
    "HP_UP": "Raises a Pokemon's HP stat.",
    "PROTEIN": "Raises a Pokemon's Attack stat.",
    "IRON": "Raises a Pokemon's Defense stat.",
    "CARBOS": "Raises a Pokemon's Speed stat.",
    "CALCIUM": "Raises a Pokemon's Special stat.",
    "RARE_CANDY": "Raises a Pokemon's level by one.",
    "DOME_FOSSIL": "A fossil that revives into Kabuto.",
    "HELIX_FOSSIL": "A fossil that revives into Omanyte.",
    "SECRET_KEY": "Opens the locked Cinnabar Gym door.",
    "BIKE_VOUCHER": "Exchange for a free Bicycle at the Bike Shop.",
    "X_ACCURACY": "Raises accuracy in battle.",
    "LEAF_STONE": "A stone that makes certain Pokemon evolve.",
    "CARD_KEY": "Opens locked doors in Silph Co.",
    "NUGGET": "A pure gold nugget. Sells for a high price.",
    "POKE_DOLL": "A doll that lets you flee from any wild battle.",
    "FULL_HEAL": "Cures all status problems.",
    "REVIVE": "Revives a fainted Pokemon with half its HP.",
    "MAX_REVIVE": "Revives a fainted Pokemon with full HP.",
    "GUARD_SPEC": "Prevents stat reduction in battle.",
    "SUPER_REPEL": "Repels weak wild Pokemon for 200 steps.",
    "MAX_REPEL": "Repels weak wild Pokemon for 250 steps.",
    "DIRE_HIT": "Raises the critical hit ratio in battle.",
    "COIN": "Game Corner currency.",
    "FRESH_WATER": "Restores 50 HP. Also given to thirsty guards.",
    "SODA_POP": "Restores 60 HP. Also given to thirsty guards.",
    "LEMONADE": "Restores 80 HP. Also given to thirsty guards.",
    "S_S_TICKET": "A ticket to board the S.S. Anne.",
    "GOLD_TEETH": "Lost gold dentures. Return to the Safari Zone Warden.",
    "X_ATTACK": "Raises Attack in battle.",
    "X_DEFEND": "Raises Defense in battle.",
    "X_SPEED": "Raises Speed in battle.",
    "X_SPECIAL": "Raises Special in battle.",
    "COIN_CASE": "Holds up to 9999 Game Corner coins.",
    "OAKS_PARCEL": "A parcel to deliver to Professor Oak.",
    "ITEMFINDER": "Detects hidden items nearby.",
    "SILPH_SCOPE": "Reveals ghosts in Pokemon Tower.",
    "POKE_FLUTE": "Awakens sleeping Pokemon, including Snorlax.",
    "LIFT_KEY": "Operates the Rocket Hideout elevator.",
    "EXP_ALL": "Shares battle EXP with the whole party.",
    "OLD_ROD": "A basic fishing rod.",
    "GOOD_ROD": "A decent fishing rod.",
    "SUPER_ROD": "The best fishing rod.",
    "PP_UP": "Raises the max PP of a move.",
    "ETHER": "Restores 10 PP of one move.",
    "MAX_ETHER": "Fully restores the PP of one move.",
    "ELIXER": "Restores 10 PP of all moves.",
    "MAX_ELIXER": "Fully restores the PP of all moves.",
}


def fetch(path: str) -> str | None:
    """Download a text asm file from the disassembly (cached)."""
    cache_path = CACHE_DIR / path.replace("/", "_")
    data = download_file(f"{REPO_BASE}/{path}", cache_path)
    return data.decode("utf-8", "replace") if data else None


# ---------------------------------------------------------------------------
# Item catalogue
# ---------------------------------------------------------------------------
def parse_item_constants() -> tuple[dict[str, int], dict[str, int], dict[str, int]]:
    """Returns (item_ids, tm_moves, hm_moves).

    item_ids: const -> id (regular items only)
    tm_moves: TM_<MOVE> alias -> (tm_number, item_id)
    """
    text = fetch("constants/item_constants.asm") or ""
    item_ids: dict[str, int] = {}
    tm_moves: dict[str, tuple[int, int]] = {}
    hm_moves: dict[str, tuple[int, int]] = {}
    counter = 0
    tm_n = hm_n = 0
    for line in text.splitlines():
        if line.strip() == "const_def":
            counter = 0
            continue
        if m := CONST_NEXT_RE.match(line):
            counter = int(m.group(1), 16)
            continue
        if m := CONST_RE.match(line):
            item_ids[m.group(1)] = counter
            counter += 1
        elif m := ADD_HM_RE.match(line):
            hm_n += 1
            hm_moves[f"HM_{m.group(1)}"] = (hm_n, counter)
            counter += 1
        elif m := ADD_TM_RE.match(line):
            tm_n += 1
            tm_moves[f"TM_{m.group(1)}"] = (tm_n, counter)
            counter += 1
    return item_ids, tm_moves, hm_moves


def parse_names() -> list[str]:
    text = fetch("data/items/names.asm") or ""
    # names.asm is not UTF-8; the only non-ASCII char is the 'é' in POKé
    return [m.group(1).replace("�", "é")
            for line in text.splitlines() if (m := NAME_RE.match(line))]


def parse_prices() -> dict[str, int]:
    text = fetch("data/items/prices.asm") or ""
    return {m.group(2): int(m.group(1))
            for line in text.splitlines() if (m := PRICE_RE.match(line))}


def parse_key_items() -> dict[str, bool]:
    text = fetch("data/items/key_items.asm") or ""
    return {m.group(2): m.group(1) == "TRUE"
            for line in text.splitlines() if (m := KEY_ITEM_RE.match(line))}


def parse_tm_prices() -> dict[int, int]:
    text = fetch("data/items/tm_prices.asm") or ""
    return {int(m.group(2)): int(m.group(1)) * 1000
            for line in text.splitlines() if (m := TM_PRICE_RE.match(line))}


def build_items() -> tuple[list[dict], dict[str, dict]]:
    """Returns (item rows, lookup by const incl. TM/HM aliases)."""
    item_ids, tm_moves, hm_moves = parse_item_constants()
    names = parse_names()
    prices = parse_prices()
    key_flags = parse_key_items()
    tm_prices = parse_tm_prices()

    rows: list[dict] = []
    for const, iid in item_ids.items():
        if const == "NO_ITEM" or const.startswith(("ITEM_", "FLOOR_")):
            continue  # placeholder slots / elevator floors
        name = names[iid - 1] if 0 < iid <= len(names) else const.replace("_", " ")
        rows.append(dict(
            item_const=const, item_id=iid, item_name=name,
            price=prices.get(const, 0), is_key_item=key_flags.get(const, False),
            tm_number="", tm_move="",
            description=DESCRIPTIONS.get(const, ""),
        ))
    for alias, (n, iid) in hm_moves.items():
        move = alias[3:]
        rows.append(dict(
            item_const=alias, item_id=iid, item_name=f"HM{n:02d} {move.replace('_', ' ')}",
            price=0, is_key_item=True, tm_number=f"HM{n:02d}", tm_move=move,
            description=f"Teaches {move.replace('_', ' ').title()}. Reusable.",
        ))
    for alias, (n, iid) in tm_moves.items():
        move = alias[3:]
        rows.append(dict(
            item_const=alias, item_id=iid, item_name=f"TM{n:02d} {move.replace('_', ' ')}",
            price=tm_prices.get(n, 0), is_key_item=False,
            tm_number=f"TM{n:02d}", tm_move=move,
            description=f"Teaches {move.replace('_', ' ').title()}. Single use.",
        ))
    rows.sort(key=lambda r: r["item_id"])
    return rows, {r["item_const"]: r for r in rows}


# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------
def camel_to_const() -> dict[str, str]:
    return {get_blk_name(c): c for c in MAP_DIMENSIONS if get_blk_name(c)}


def parse_marts(items: dict[str, dict]) -> list[dict]:
    text = fetch("data/items/marts.asm") or ""
    rev = camel_to_const()
    rows, label = [], None
    for line in text.splitlines():
        if m := MART_LABEL_RE.match(line):
            label = m.group(1)
            continue
        m = SCRIPT_MART_RE.match(line)
        if not m or not label or label.startswith("Unused"):
            continue
        camel = re.sub(r"Clerk\d*Text$", "", label)
        map_const = rev.get(camel)
        if map_const is None:
            print(f"  WARNING: no map for mart label {label}")
            continue
        # re.sub: upstream typo "HYPER_ POTION" in IndigoPlateauLobbyClerkText
        for item in [re.sub(r"\s+", "", i) for i in m.group(1).split(",")]:
            info = items.get(item)
            if info is None:
                print(f"  WARNING: unknown mart item {item} in {label}")
                continue
            rows.append(dict(map=map_const, item_const=item, source_type="mart",
                             x="", y="", quantity="unlimited",
                             price=info["price"], currency="money", notes=label))
    return rows


def parse_vending() -> list[dict]:
    text = fetch("data/items/vending_prices.asm") or ""
    # ponytail: vending machines are hardcoded to the Celadon Dept Store roof
    return [dict(map="CELADON_MART_ROOF", item_const=m.group(1),
                 source_type="vending_machine", x="", y="", quantity="unlimited",
                 price=int(m.group(2)), currency="money", notes="VendingPrices")
            for line in text.splitlines() if (m := VEND_RE.match(line))]


def parse_prizes(items: dict[str, dict]) -> list[dict]:
    """Game Corner Prize Room TM prizes (coin currency)."""
    text = fetch("data/events/prizes.asm") or ""
    m_items = re.search(r"PrizeMenuTMsEntries:(.*?)(?=\w+:)", text, re.DOTALL)
    m_costs = re.search(r"PrizeMenuTMsCost:(.*?)(?=\w+:|\Z)", text, re.DOTALL)
    if not (m_items and m_costs):
        print("  WARNING: could not parse Game Corner TM prizes")
        return []
    consts = re.findall(r"\bdb\s+(TM_\w+|[A-Z][A-Z0-9_]+)", m_items.group(1))
    costs = [int(c) for c in re.findall(r"bcd2\s+(\d+)", m_costs.group(1))]
    rows = []
    for const, cost in zip(consts, costs):
        if const in items:
            rows.append(dict(map="GAME_CORNER_PRIZE_ROOM", item_const=const,
                             source_type="prize_corner", x="", y="",
                             quantity="unlimited", price=cost, currency="coins",
                             notes="PrizeMenuTMs"))
    return rows


def parse_item_balls(items: dict[str, dict]) -> list[dict]:
    rows = []
    for const in MAP_DIMENSIONS:
        blk = get_blk_name(const)
        if blk is None:
            continue
        text = fetch(f"data/maps/objects/{blk}.asm")
        if text is None:
            continue
        text = DEBUG_BLOCK_RE.sub("", text)
        for line in text.splitlines():
            m = ITEM_BALL_RE.match(line)
            if not m:
                continue
            item = m.group(3)
            if item not in items:
                print(f"  WARNING: unknown item ball {item} in {const}")
                continue
            rows.append(dict(map=const, item_const=item, source_type="item_ball",
                             x=int(m.group(1)), y=int(m.group(2)), quantity=1,
                             price="", currency="", notes=""))
    return rows


def parse_hidden_items(items: dict[str, dict]) -> list[dict]:
    text = fetch("data/events/hidden_objects.asm") or ""
    label_to_map = {}
    for line in text.splitlines():
        if m := HIDDEN_MAP_RE.match(line):
            map_const = DEST_CONST_ALIASES.get(m.group(1), m.group(1))
            label_to_map[m.group(2)] = map_const
    rows, current_map = [], None
    for line in text.splitlines():
        if m := re.match(r"^(\w+):", line):
            current_map = label_to_map.get(m.group(1))
        if (m := HIDDEN_OBJ_RE.match(line)) and current_map:
            x, y, item, routine = int(m.group(1)), int(m.group(2)), m.group(3), m.group(4)
            if routine != "HiddenItems" or item not in items:
                continue
            if current_map not in MAP_DIMENSIONS:
                print(f"  WARNING: hidden item on unknown map {current_map}")
                continue
            rows.append(dict(map=current_map, item_const=item, source_type="hidden_item",
                             x=x, y=y, quantity=1, price="", currency="", notes=""))
    return rows


def list_script_files() -> list[str]:
    cache_path = CACHE_DIR / "api_scripts.json"
    data = download_file(f"{API_BASE}/scripts", cache_path)
    if not data:
        return []
    return [e["name"] for e in json.loads(data) if e["name"].endswith(".asm")]


def parse_npc_gifts(items: dict[str, dict]) -> list[dict]:
    rev = camel_to_const()
    rows = []
    for fname in list_script_files():
        text = fetch(f"scripts/{fname}")
        if text is None:
            continue
        lines = text.splitlines()
        camel = re.sub(r"(_\d+)?\.asm$", "", fname)
        map_const = rev.get(camel)
        for i, line in enumerate(lines):
            m = GIVE_ITEM_LB_RE.match(line)
            if not m or m.group(1) not in items:
                continue
            # GiveItem call must follow within a few lines
            if not any(GIVE_ITEM_CALL_RE.search(l) for l in lines[i + 1:i + 5]):
                continue
            if map_const is None:
                print(f"  WARNING: gift {m.group(1)} in {fname} has no map match")
                continue
            rows.append(dict(map=map_const, item_const=m.group(1),
                             source_type="npc_gift", x="", y="",
                             quantity=int(m.group(2)), price="", currency="",
                             notes=fname))
    return rows


def main() -> None:
    print("Building item catalogue ...")
    item_rows, items = build_items()
    with open(ITEMS_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(item_rows[0].keys()))
        w.writeheader()
        w.writerows(item_rows)
    print(f"Wrote {len(item_rows)} items to {ITEMS_CSV}")

    print("Extracting item locations ...")
    loc_rows = (parse_marts(items) + parse_vending() + parse_prizes(items)
                + parse_item_balls(items) + parse_hidden_items(items)
                + parse_npc_gifts(items))
    # dedupe (a script can give the same item in multiple branches)
    seen, unique = set(), []
    for r in loc_rows:
        key = (r["map"], r["item_const"], r["source_type"], r["x"], r["y"], r["quantity"])
        if key not in seen:
            seen.add(key)
            unique.append(r)
    unique.sort(key=lambda r: (r["map"], r["source_type"], r["item_const"]))
    with open(LOCATIONS_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(unique[0].keys()))
        w.writeheader()
        w.writerows(unique)
    by_type: dict[str, int] = {}
    for r in unique:
        by_type[r["source_type"]] = by_type.get(r["source_type"], 0) + 1
    print(f"Wrote {len(unique)} locations to {LOCATIONS_CSV}: {by_type}")


if __name__ == "__main__":
    main()
