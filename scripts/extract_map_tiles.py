"""
Extract walkable tile data from Pokemon Yellow Legacy ASM source files.

Downloads binary .blk (map block) and .bst (blockset) files from the
cRz-Shadows/Pokemon_Yellow_Legacy GitHub repo, then:
  1. Expands each block to its 4x4 tile grid using the blockset
  2. Checks collision tile IDs for each player-coordinate metatile
  3. Classifies each tile as path/grass/water/wall/ledge
  4. Outputs seeds/nav_map_tiles.csv and seeds/nav_map_tileset.csv

Usage:
    python scripts/extract_map_tiles.py
"""

import csv
import re
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
# Map name overrides: UPPER_SNAKE_CASE -> CamelCase BLK filename
# Only needed where auto-conversion fails. All others are derived
# automatically by converting UPPER_SNAKE_CASE to CamelCase.
# ---------------------------------------------------------------------------
BLK_NAME_OVERRIDES = {
    "PLAYERS_HOUSE_1F": "RedsHouse1F",
    "PLAYERS_HOUSE_2F": "RedsHouse2F",
    "RIVALS_HOUSE": "BluesHouse",
    "OAKS_LAB": "OaksLab",
    "PEWTER_MUSEUM_1F": "Museum1F",
    "PEWTER_MUSEUM_2F": "Museum2F",
    "ROUTE_2_TRADE_HOUSE": "Route2TradeHouse",
    "DIGLETTS_CAVE_ROUTE_2": "DiglettsCaveRoute2",
    "DIGLETTS_CAVE_ROUTE_11": "DiglettsCaveRoute11",
    "DIGLETTS_CAVE": "DiglettsCave",
    "CERULEAN_MELANIES_HOUSE": None,  # No BLK file exists
    "CERULEAN_TRASHED_HOUSE_COPY": None,
    "UNDERGROUND_PATH_ROUTE_6_COPY": None,
    "UNDERGROUND_PATH_ROUTE_7_COPY": None,
    "CINNABAR_MART_COPY": None,
    "SS_ANNE_1F": "SSAnne1F",
    "SS_ANNE_2F": "SSAnne2F",
    "SS_ANNE_3F": "SSAnne3F",
    "SS_ANNE_B1F": "SSAnneB1F",
    "SS_ANNE_BOW": "SSAnneBow",
    "SS_ANNE_KITCHEN": "SSAnneKitchen",
    "SS_ANNE_CAPTAINS_ROOM": "SSAnneCaptainsRoom",
    "SS_ANNE_1F_ROOMS": "SSAnne1FRooms",
    "SS_ANNE_2F_ROOMS": "SSAnne2FRooms",
    "SS_ANNE_B1F_ROOMS": "SSAnneB1FRooms",
    "MR_FUJIS_HOUSE": "MrFujisHouse",
    "MR_PSYCHICS_HOUSE": "MrPsychicsHouse",
    "BILLS_HOUSE": "BillsHouse",
    "FUCHSIA_BILLS_GRANDPAS_HOUSE": "FuchsiaBillsGrandpasHouse",
}

# ---------------------------------------------------------------------------
# Tileset name -> display name mapping (ASM UPPER_SNAKE -> script CamelCase)
# ---------------------------------------------------------------------------
TILESET_NAME_MAP = {
    "OVERWORLD": "Overworld",
    "REDS_HOUSE_1": "RedsHouse1",
    "REDS_HOUSE_2": "RedsHouse2",
    "HOUSE": "House",
    "DOJO": "Dojo",
    "GYM": "Gym",
    "MART": "Mart",
    "POKECENTER": "Pokecenter",
    "FOREST": "Forest",
    "FOREST_GATE": "ForestGate",
    "MUSEUM": "Museum",
    "GATE": "Gate",
    "LAB": "Lab",
    "CAVERN": "Cavern",
    "SHIP": "Ship",
    "SHIP_PORT": "ShipPort",
    "CEMETERY": "Cemetery",
    "INTERIOR": "Interior",
    "FACILITY": "Facility",
    "MANSION": "Mansion",
    "PLATEAU": "Plateau",
    "LOBBY": "Lobby",
    "CLUB": "Club",
    "UNDERGROUND": "Underground",
    "BEACH_HOUSE": "BeachHouse",
}

# ---------------------------------------------------------------------------
# Map name -> tileset (from ROM map headers, fetched in bulk)
# Format: CamelCase BLK name -> ASM tileset name
# ---------------------------------------------------------------------------
MAP_TILESET_FROM_HEADER = {
    "AgathasRoom": "DOJO",
    "BikeShop": "HOUSE",
    "BillsHouse": "HOUSE",
    "BluesHouse": "HOUSE",
    "BrunosRoom": "DOJO",
    "CeladonChiefHouse": "HOUSE",
    "CeladonCity": "OVERWORLD",
    "CeladonDiner": "GATE",
    "CeladonGym": "GYM",
    "CeladonHotel": "POKECENTER",
    "CeladonMansion1F": "MANSION",
    "CeladonMansion2F": "MANSION",
    "CeladonMansion3F": "MANSION",
    "CeladonMansionRoof": "MANSION",
    "CeladonMansionRoofHouse": "HOUSE",
    "CeladonMart1F": "MART",
    "CeladonMart2F": "MART",
    "CeladonMart3F": "MART",
    "CeladonMart4F": "MART",
    "CeladonMart5F": "MART",
    "CeladonMartElevator": "FACILITY",
    "CeladonMartRoof": "MART",
    "CeladonPokecenter": "POKECENTER",
    "CeruleanBadgeHouse": "HOUSE",
    "CeruleanCave1F": "CAVERN",
    "CeruleanCave2F": "CAVERN",
    "CeruleanCaveB1F": "CAVERN",
    "CeruleanCity": "OVERWORLD",
    "CeruleanGym": "GYM",
    "CeruleanMart": "MART",
    "CeruleanPokecenter": "POKECENTER",
    "CeruleanTradeHouse": "HOUSE",
    "CeruleanTrashedHouse": "HOUSE",
    "ChampionsRoom": "LOBBY",
    "CinnabarGym": "GYM",
    "CinnabarIsland": "OVERWORLD",
    "CinnabarLab": "LAB",
    "CinnabarLabFossilRoom": "LAB",
    "CinnabarLabMetronomeRoom": "LAB",
    "CinnabarLabTradeRoom": "LAB",
    "CinnabarMart": "MART",
    "CinnabarPokecenter": "POKECENTER",
    "Colosseum": "GATE",
    "CopycatsHouse1F": "HOUSE",
    "CopycatsHouse2F": "REDS_HOUSE_2",
    "Daycare": "HOUSE",
    "DiglettsCave": "CAVERN",
    "DiglettsCaveRoute11": "CAVERN",
    "DiglettsCaveRoute2": "CAVERN",
    "FightingDojo": "DOJO",
    "FuchsiaBillsGrandpasHouse": "HOUSE",
    "FuchsiaCity": "OVERWORLD",
    "FuchsiaGoodRodHouse": "HOUSE",
    "FuchsiaGym": "GYM",
    "FuchsiaMart": "MART",
    "FuchsiaMeetingRoom": "POKECENTER",
    "FuchsiaPokecenter": "POKECENTER",
    "GameCorner": "CLUB",
    "GameCornerPrizeRoom": "GATE",
    "HallOfFame": "LOBBY",
    "IndigoPlateau": "OVERWORLD",
    "IndigoPlateauLobby": "LOBBY",
    "LancesRoom": "DOJO",
    "LavenderCuboneHouse": "HOUSE",
    "LavenderMart": "MART",
    "LavenderPokecenter": "POKECENTER",
    "LavenderTown": "OVERWORLD",
    "LoreleisRoom": "DOJO",
    "MrFujisHouse": "HOUSE",
    "MrPsychicsHouse": "HOUSE",
    "MtMoon1F": "CAVERN",
    "MtMoonB1F": "CAVERN",
    "MtMoonB2F": "CAVERN",
    "MtMoonPokecenter": "POKECENTER",
    "Museum1F": "MUSEUM",
    "Museum2F": "MUSEUM",
    "NameRatersHouse": "HOUSE",
    "OaksLab": "DOJO",
    "PalletTown": "OVERWORLD",
    "PewterCity": "OVERWORLD",
    "PewterGym": "GYM",
    "PewterMart": "MART",
    "PewterNidoranHouse": "HOUSE",
    "PewterPokecenter": "POKECENTER",
    "PewterSpeechHouse": "HOUSE",
    "PokemonFanClub": "CLUB",
    "PokemonMansion1F": "MANSION",
    "PokemonMansion2F": "MANSION",
    "PokemonMansion3F": "MANSION",
    "PokemonMansionB1F": "MANSION",
    "PokemonTower1F": "CEMETERY",
    "PokemonTower2F": "CEMETERY",
    "PokemonTower3F": "CEMETERY",
    "PokemonTower4F": "CEMETERY",
    "PokemonTower5F": "CEMETERY",
    "PokemonTower6F": "CEMETERY",
    "PokemonTower7F": "CEMETERY",
    "PowerPlant": "FACILITY",
    "RedsHouse1F": "REDS_HOUSE_1",
    "RedsHouse2F": "REDS_HOUSE_2",
    "RockTunnel1F": "CAVERN",
    "RockTunnelB1F": "CAVERN",
    "RockTunnelPokecenter": "POKECENTER",
    "RocketHideoutB1F": "FACILITY",
    "RocketHideoutB2F": "FACILITY",
    "RocketHideoutB3F": "FACILITY",
    "RocketHideoutB4F": "FACILITY",
    "RocketHideoutElevator": "FACILITY",
    "Route1": "OVERWORLD",
    "Route10": "OVERWORLD",
    "Route11": "OVERWORLD",
    "Route11Gate1F": "GATE",
    "Route11Gate2F": "GATE",
    "Route12": "OVERWORLD",
    "Route12Gate1F": "GATE",
    "Route12Gate2F": "GATE",
    "Route12SuperRodHouse": "HOUSE",
    "Route13": "OVERWORLD",
    "Route14": "OVERWORLD",
    "Route15": "OVERWORLD",
    "Route15Gate1F": "GATE",
    "Route15Gate2F": "GATE",
    "Route16": "OVERWORLD",
    "Route16FlyHouse": "HOUSE",
    "Route16Gate1F": "GATE",
    "Route16Gate2F": "GATE",
    "Route17": "OVERWORLD",
    "Route18": "OVERWORLD",
    "Route18Gate1F": "GATE",
    "Route18Gate2F": "GATE",
    "Route19": "OVERWORLD",
    "Route2": "OVERWORLD",
    "Route20": "OVERWORLD",
    "Route21": "OVERWORLD",
    "Route22": "OVERWORLD",
    "Route22Gate": "GATE",
    "Route23": "OVERWORLD",
    "Route24": "OVERWORLD",
    "Route25": "OVERWORLD",
    "Route2Gate": "GATE",
    "Route2TradeHouse": "HOUSE",
    "Route3": "OVERWORLD",
    "Route4": "OVERWORLD",
    "Route5": "OVERWORLD",
    "Route5Gate": "GATE",
    "Route6": "OVERWORLD",
    "Route6Gate": "GATE",
    "Route7": "OVERWORLD",
    "Route7Gate": "GATE",
    "Route8": "OVERWORLD",
    "Route8Gate": "GATE",
    "Route9": "OVERWORLD",
    "SSAnne1F": "SHIP",
    "SSAnne1FRooms": "SHIP",
    "SSAnne2F": "SHIP",
    "SSAnne2FRooms": "SHIP",
    "SSAnne3F": "SHIP",
    "SSAnneB1F": "SHIP",
    "SSAnneB1FRooms": "SHIP",
    "SSAnneBow": "SHIP",
    "SSAnneCaptainsRoom": "SHIP",
    "SSAnneKitchen": "SHIP",
    "SafariZoneCenter": "OVERWORLD",
    "SafariZoneCenterRestHouse": "INTERIOR",
    "SafariZoneEast": "OVERWORLD",
    "SafariZoneEastRestHouse": "INTERIOR",
    "SafariZoneGate": "GATE",
    "SafariZoneNorth": "OVERWORLD",
    "SafariZoneNorthRestHouse": "INTERIOR",
    "SafariZoneSecretHouse": "INTERIOR",
    "SafariZoneWest": "OVERWORLD",
    "SafariZoneWestRestHouse": "INTERIOR",
    "SaffronCity": "OVERWORLD",
    "SaffronGym": "GYM",
    "SaffronMart": "MART",
    "SaffronPidgeyHouse": "HOUSE",
    "SaffronPokecenter": "POKECENTER",
    "SeafoamIslands1F": "CAVERN",
    "SeafoamIslandsB1F": "CAVERN",
    "SeafoamIslandsB2F": "CAVERN",
    "SeafoamIslandsB3F": "CAVERN",
    "SeafoamIslandsB4F": "CAVERN",
    "SilphCo10F": "FACILITY",
    "SilphCo11F": "FACILITY",
    "SilphCo1F": "FACILITY",
    "SilphCo2F": "FACILITY",
    "SilphCo3F": "FACILITY",
    "SilphCo4F": "FACILITY",
    "SilphCo5F": "FACILITY",
    "SilphCo6F": "FACILITY",
    "SilphCo7F": "FACILITY",
    "SilphCo8F": "FACILITY",
    "SilphCo9F": "FACILITY",
    "SilphCoElevator": "FACILITY",
    "SummerBeachHouse": "BEACH_HOUSE",
    "TradeCenter": "GATE",
    "UndergroundPathNorthSouth": "UNDERGROUND",
    "UndergroundPathRoute5": "UNDERGROUND",
    "UndergroundPathRoute6": "UNDERGROUND",
    "UndergroundPathRoute7": "UNDERGROUND",
    "UndergroundPathRoute8": "UNDERGROUND",
    "UndergroundPathWestEast": "UNDERGROUND",
    "UnusedDiglettsCaveCopy": None,
    "UnusedEmptyMap": None,
    "UnusedPokecenterCopy": None,
    "VermilionCity": "OVERWORLD",
    "VermilionDock": "SHIP_PORT",
    "VermilionGym": "GYM",
    "VermilionMart": "MART",
    "VermilionOldRodHouse": "HOUSE",
    "VermilionPidgeyHouse": "HOUSE",
    "VermilionPokecenter": "POKECENTER",
    "VermilionTradeHouse": "HOUSE",
    "VictoryRoad1F": "CAVERN",
    "VictoryRoad2F": "CAVERN",
    "VictoryRoad3F": "CAVERN",
    "ViridianCity": "OVERWORLD",
    "ViridianForest": "FOREST",
    "ViridianForestNorthGate": "FOREST_GATE",
    "ViridianForestSouthGate": "FOREST_GATE",
    "ViridianGym": "GYM",
    "ViridianMart": "MART",
    "ViridianNicknameHouse": "HOUSE",
    "ViridianPokecenter": "POKECENTER",
    "ViridianSchoolHouse": "HOUSE",
    "WardensHouse": "LAB",
}

# ---------------------------------------------------------------------------
# Map dimensions from constants/map_constants.asm
# Format: UPPER_SNAKE_CASE -> (width, height) in blocks
# ---------------------------------------------------------------------------
MAP_DIMENSIONS = {
    "PALLET_TOWN": (10, 9),
    "VIRIDIAN_CITY": (20, 18),
    "PEWTER_CITY": (20, 18),
    "CERULEAN_CITY": (20, 18),
    "LAVENDER_TOWN": (10, 9),
    "VERMILION_CITY": (20, 18),
    "CELADON_CITY": (25, 18),
    "FUCHSIA_CITY": (20, 18),
    "CINNABAR_ISLAND": (10, 9),
    "INDIGO_PLATEAU": (10, 9),
    "SAFFRON_CITY": (20, 18),
    "ROUTE_1": (10, 18),
    "ROUTE_2": (10, 36),
    "ROUTE_3": (35, 9),
    "ROUTE_4": (45, 9),
    "ROUTE_5": (10, 18),
    "ROUTE_6": (10, 18),
    "ROUTE_7": (10, 9),
    "ROUTE_8": (30, 9),
    "ROUTE_9": (30, 9),
    "ROUTE_10": (10, 36),
    "ROUTE_11": (30, 9),
    "ROUTE_12": (10, 54),
    "ROUTE_13": (30, 9),
    "ROUTE_14": (10, 27),
    "ROUTE_15": (30, 9),
    "ROUTE_16": (20, 9),
    "ROUTE_17": (10, 72),
    "ROUTE_18": (25, 9),
    "ROUTE_19": (10, 27),
    "ROUTE_20": (50, 9),
    "ROUTE_21": (10, 45),
    "ROUTE_22": (20, 9),
    "ROUTE_23": (10, 72),
    "ROUTE_24": (10, 18),
    "ROUTE_25": (30, 9),
    "PLAYERS_HOUSE_1F": (4, 4),
    "PLAYERS_HOUSE_2F": (4, 4),
    "RIVALS_HOUSE": (4, 4),
    "OAKS_LAB": (5, 6),
    "VIRIDIAN_POKECENTER": (7, 4),
    "VIRIDIAN_MART": (4, 4),
    "VIRIDIAN_SCHOOL_HOUSE": (4, 4),
    "VIRIDIAN_NICKNAME_HOUSE": (4, 4),
    "VIRIDIAN_GYM": (10, 9),
    "DIGLETTS_CAVE_ROUTE_2": (4, 4),
    "VIRIDIAN_FOREST_NORTH_GATE": (5, 4),
    "ROUTE_2_TRADE_HOUSE": (4, 4),
    "ROUTE_2_GATE": (5, 4),
    "VIRIDIAN_FOREST_SOUTH_GATE": (5, 4),
    "VIRIDIAN_FOREST": (17, 24),
    "MUSEUM_1F": (10, 4),
    "MUSEUM_2F": (7, 4),
    "PEWTER_GYM": (5, 7),
    "PEWTER_NIDORAN_HOUSE": (4, 4),
    "PEWTER_MART": (4, 4),
    "PEWTER_SPEECH_HOUSE": (4, 4),
    "PEWTER_POKECENTER": (7, 4),
    "MT_MOON_1F": (20, 18),
    "MT_MOON_B1F": (14, 14),
    "MT_MOON_B2F": (20, 18),
    "CERULEAN_TRASHED_HOUSE": (4, 4),
    "CERULEAN_POKECENTER": (7, 4),
    "CERULEAN_GYM": (5, 7),
    "BIKE_SHOP": (4, 4),
    "CERULEAN_MART": (4, 4),
    "MT_MOON_POKECENTER": (7, 4),
    "ROUTE_5_GATE": (4, 3),
    "UNDERGROUND_PATH_ROUTE_5": (4, 4),
    "DAYCARE": (4, 4),
    "ROUTE_6_GATE": (4, 3),
    "UNDERGROUND_PATH_ROUTE_6": (4, 4),
    "ROUTE_7_GATE": (3, 4),
    "UNDERGROUND_PATH_ROUTE_7": (4, 4),
    "ROUTE_8_GATE": (3, 4),
    "UNDERGROUND_PATH_ROUTE_8": (4, 4),
    "ROCK_TUNNEL_POKECENTER": (7, 4),
    "ROCK_TUNNEL_1F": (20, 18),
    "POWER_PLANT": (20, 18),
    "ROUTE_11_GATE_1F": (4, 5),
    "DIGLETTS_CAVE_ROUTE_11": (4, 4),
    "ROUTE_11_GATE_2F": (4, 4),
    "ROUTE_12_GATE_1F": (5, 4),
    "BILLS_HOUSE": (4, 4),
    "VERMILION_POKECENTER": (7, 4),
    "POKEMON_FAN_CLUB": (4, 4),
    "VERMILION_MART": (4, 4),
    "VERMILION_GYM": (5, 9),
    "VERMILION_PIDGEY_HOUSE": (4, 4),
    "VERMILION_DOCK": (14, 6),
    "SS_ANNE_1F": (20, 9),
    "SS_ANNE_2F": (20, 9),
    "SS_ANNE_3F": (10, 3),
    "SS_ANNE_B1F": (15, 4),
    "SS_ANNE_BOW": (10, 7),
    "SS_ANNE_KITCHEN": (7, 8),
    "SS_ANNE_CAPTAINS_ROOM": (3, 4),
    "SS_ANNE_1F_ROOMS": (12, 8),
    "SS_ANNE_2F_ROOMS": (12, 8),
    "SS_ANNE_B1F_ROOMS": (12, 8),
    "VICTORY_ROAD_1F": (10, 9),
    "LANCES_ROOM": (13, 13),
    "HALL_OF_FAME": (5, 4),
    "UNDERGROUND_PATH_NORTH_SOUTH": (4, 23),  # Yellow Legacy changed from 4x24
    "CHAMPIONS_ROOM": (4, 4),
    "UNDERGROUND_PATH_WEST_EAST": (25, 4),
    "CELADON_MART_1F": (10, 4),
    "CELADON_MART_2F": (10, 4),
    "CELADON_MART_3F": (10, 4),
    "CELADON_MART_4F": (10, 4),
    "CELADON_MART_ROOF": (10, 4),
    "CELADON_MART_ELEVATOR": (2, 2),
    "CELADON_MANSION_1F": (4, 6),
    "CELADON_MANSION_2F": (4, 6),
    "CELADON_MANSION_3F": (4, 6),
    "CELADON_MANSION_ROOF": (4, 6),
    "CELADON_MANSION_ROOF_HOUSE": (4, 4),
    "CELADON_POKECENTER": (7, 4),
    "CELADON_GYM": (5, 9),
    "GAME_CORNER": (10, 9),
    "CELADON_MART_5F": (10, 4),
    "GAME_CORNER_PRIZE_ROOM": (5, 4),
    "CELADON_DINER": (5, 4),
    "CELADON_CHIEF_HOUSE": (4, 4),
    "CELADON_HOTEL": (7, 4),
    "LAVENDER_POKECENTER": (7, 4),
    "POKEMON_TOWER_1F": (10, 9),
    "POKEMON_TOWER_2F": (10, 9),
    "POKEMON_TOWER_3F": (10, 9),
    "POKEMON_TOWER_4F": (10, 9),
    "POKEMON_TOWER_5F": (10, 9),
    "POKEMON_TOWER_6F": (10, 9),
    "POKEMON_TOWER_7F": (10, 9),
    "MR_FUJIS_HOUSE": (4, 4),
    "LAVENDER_MART": (4, 4),
    "LAVENDER_CUBONE_HOUSE": (4, 4),
    "FUCHSIA_MART": (4, 4),
    "FUCHSIA_BILLS_GRANDPAS_HOUSE": (4, 4),
    "FUCHSIA_POKECENTER": (7, 4),
    "WARDENS_HOUSE": (5, 4),
    "SAFARI_ZONE_GATE": (4, 3),
    "FUCHSIA_GYM": (5, 9),
    "FUCHSIA_MEETING_ROOM": (7, 4),
    "SEAFOAM_ISLANDS_B1F": (15, 9),
    "SEAFOAM_ISLANDS_B2F": (15, 9),
    "SEAFOAM_ISLANDS_B3F": (15, 9),
    "SEAFOAM_ISLANDS_B4F": (15, 9),
    "VERMILION_OLD_ROD_HOUSE": (4, 4),
    "FUCHSIA_GOOD_ROD_HOUSE": (4, 4),
    "POKEMON_MANSION_1F": (15, 14),
    "CINNABAR_GYM": (10, 9),
    "CINNABAR_LAB": (9, 4),
    "CINNABAR_LAB_TRADE_ROOM": (4, 4),
    "CINNABAR_LAB_METRONOME_ROOM": (4, 4),
    "CINNABAR_LAB_FOSSIL_ROOM": (4, 4),
    "CINNABAR_POKECENTER": (7, 4),
    "CINNABAR_MART": (4, 4),
    "INDIGO_PLATEAU_LOBBY": (8, 6),
    "COPYCATS_HOUSE_1F": (4, 4),
    "COPYCATS_HOUSE_2F": (4, 4),
    "FIGHTING_DOJO": (5, 6),
    "SAFFRON_GYM": (10, 9),
    "SAFFRON_PIDGEY_HOUSE": (4, 4),
    "SAFFRON_MART": (4, 4),
    "SILPH_CO_1F": (15, 9),
    "SAFFRON_POKECENTER": (7, 4),
    "MR_PSYCHICS_HOUSE": (4, 4),
    "ROUTE_15_GATE_1F": (4, 5),
    "ROUTE_15_GATE_2F": (4, 4),
    "ROUTE_16_GATE_1F": (4, 7),
    "ROUTE_16_GATE_2F": (4, 4),
    "ROUTE_16_FLY_HOUSE": (4, 4),
    "ROUTE_12_SUPER_ROD_HOUSE": (4, 4),
    "ROUTE_18_GATE_1F": (4, 5),
    "ROUTE_18_GATE_2F": (4, 4),
    "SEAFOAM_ISLANDS_1F": (15, 9),
    "ROUTE_22_GATE": (5, 4),
    "VICTORY_ROAD_2F": (15, 9),
    "ROUTE_12_GATE_2F": (4, 4),
    "VERMILION_TRADE_HOUSE": (4, 4),
    "DIGLETTS_CAVE": (20, 18),
    "VICTORY_ROAD_3F": (15, 9),
    "ROCKET_HIDEOUT_B1F": (15, 14),
    "ROCKET_HIDEOUT_B2F": (15, 14),
    "ROCKET_HIDEOUT_B3F": (15, 14),
    "ROCKET_HIDEOUT_B4F": (15, 12),
    "ROCKET_HIDEOUT_ELEVATOR": (3, 4),
    "SILPH_CO_2F": (15, 9),
    "SILPH_CO_3F": (15, 9),
    "SILPH_CO_4F": (15, 9),
    "SILPH_CO_5F": (15, 9),
    "SILPH_CO_6F": (13, 9),
    "SILPH_CO_7F": (13, 9),
    "SILPH_CO_8F": (13, 9),
    "POKEMON_MANSION_2F": (15, 14),
    "POKEMON_MANSION_3F": (15, 9),
    "POKEMON_MANSION_B1F": (15, 14),
    "SAFARI_ZONE_EAST": (15, 13),
    "SAFARI_ZONE_NORTH": (20, 18),
    "SAFARI_ZONE_WEST": (15, 13),
    "SAFARI_ZONE_CENTER": (15, 13),
    "SAFARI_ZONE_CENTER_REST_HOUSE": (4, 4),
    "SAFARI_ZONE_SECRET_HOUSE": (4, 4),
    "SAFARI_ZONE_WEST_REST_HOUSE": (4, 4),
    "SAFARI_ZONE_EAST_REST_HOUSE": (4, 4),
    "SAFARI_ZONE_NORTH_REST_HOUSE": (4, 4),
    "CERULEAN_CAVE_2F": (15, 9),
    "CERULEAN_CAVE_B1F": (15, 9),
    "CERULEAN_CAVE_1F": (15, 9),
    "NAME_RATERS_HOUSE": (4, 4),
    "CERULEAN_BADGE_HOUSE": (4, 4),
    "ROCK_TUNNEL_B1F": (20, 18),
    "SILPH_CO_9F": (13, 9),
    "SILPH_CO_10F": (8, 9),
    "SILPH_CO_11F": (9, 9),
    "SILPH_CO_ELEVATOR": (2, 2),
    "TRADE_CENTER": (5, 4),
    "COLOSSEUM": (5, 4),
    "LORELEIS_ROOM": (5, 6),
    "BRUNOS_ROOM": (5, 6),
    "AGATHAS_ROOM": (5, 6),
    "SUMMER_BEACH_HOUSE": (7, 4),
}

# ---------------------------------------------------------------------------
# Tileset name -> blockset .bst file name
# ---------------------------------------------------------------------------
TILESET_TO_BST = {
    "Overworld": "overworld.bst",
    "RedsHouse1": "reds_house.bst",
    "RedsHouse2": "reds_house.bst",
    "House": "house.bst",
    "Dojo": "gym.bst",
    "Gym": "gym.bst",
    "Mart": "pokecenter.bst",
    "Pokecenter": "pokecenter.bst",
    "Forest": "forest.bst",
    "ForestGate": "gate.bst",
    "Museum": "gate.bst",
    "Gate": "gate.bst",
    "Lab": "lab.bst",
    "Cavern": "cavern.bst",
    "Ship": "ship.bst",
    "ShipPort": "ship_port.bst",
    "Cemetery": "cemetery.bst",
    "Interior": "interior.bst",
    "Facility": "facility.bst",
    "Mansion": "mansion.bst",
    "Plateau": "plateau.bst",
    "Lobby": "lobby.bst",
    "Club": "club.bst",
    "Underground": "underground.bst",
    "BeachHouse": "beach_house.bst",
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
    "Ship": {0x04, 0x0d, 0x17, 0x1d, 0x1e, 0x23, 0x34, 0x37, 0x39, 0x4a},
    "ShipPort": {0x0a, 0x1a, 0x32, 0x3b},
    "Cemetery": {0x01, 0x10, 0x13, 0x1b, 0x22, 0x42, 0x52},
    "Interior": {0x04, 0x0f, 0x15, 0x1f, 0x3b, 0x45, 0x47, 0x55, 0x56},
    "Facility": {0x01, 0x10, 0x11, 0x13, 0x1b, 0x20, 0x21, 0x22, 0x30, 0x31,
                 0x32, 0x42, 0x43, 0x48, 0x52, 0x55, 0x58, 0x5e},
    "Mansion": {0x01, 0x05, 0x11, 0x12, 0x14, 0x1a, 0x1c, 0x2c, 0x53},
    "Plateau": {0x1b, 0x23, 0x2c, 0x2d, 0x3b, 0x45},
    "Lobby": {0x14, 0x17, 0x1a, 0x1c, 0x20, 0x38, 0x45},
    "Club": {0x0f, 0x1a, 0x1f, 0x26, 0x28, 0x29, 0x2c, 0x2d, 0x2e, 0x2f, 0x41},
    "Underground": {0x0b, 0x0c, 0x13, 0x15, 0x18},
    "BeachHouse": {0x01, 0x11, 0x12, 0x14},
}

# ---------------------------------------------------------------------------
# Grass tile per tileset (from tileset_headers.asm)
# ---------------------------------------------------------------------------
GRASS_TILES = {
    "Overworld": 0x52,
    "Forest": 0x20,
    "Plateau": 0x45,
}

EXTRA_GRASS_TILES = {
    "Overworld": set(),
    "Forest": {0x52},
}

# ---------------------------------------------------------------------------
# Water tile IDs per tileset (from data/tilesets/water_tilesets.asm)
# Tile 0x14 is the universal water tile across all tilesets that have water.
# These are NOT passable on foot but represent fishable/surfable water.
# ---------------------------------------------------------------------------
WATER_TILES = {
    "Overworld": {0x14},
    "Forest": {0x14},
    "Dojo": {0x14},
    "Gym": {0x14},
    "Ship": {0x14},
    "ShipPort": {0x14},
    "Cavern": {0x14},
    "Facility": {0x14},
    "Plateau": {0x14},
}

# ---------------------------------------------------------------------------
# Ledge tiles (from data/tilesets/ledge_tiles.asm)
# Only apply to Overworld tileset.
# ---------------------------------------------------------------------------
LEDGE_TARGET_TILES = {
    "Overworld": {
        0x37: "down",
        0x36: "down",
        0x27: "left",
        0x0D: "right",
        0x1D: "right",
    }
}


def snake_to_camel(name: str) -> str:
    """Convert UPPER_SNAKE_CASE to CamelCase.

    Handles floor suffixes like 1F, 2F, B1F by keeping the F uppercase.
    """
    parts = name.lower().split("_")
    result = []
    for part in parts:
        # Floor suffixes: "1f" -> "1F", "b1f" -> "B1F"
        if re.match(r'^b?\d+f$', part):
            result.append(part.upper())
        else:
            result.append(part.capitalize())
    return "".join(result)


def get_blk_name(map_name: str) -> str | None:
    """Get the CamelCase BLK filename for a map."""
    if map_name in BLK_NAME_OVERRIDES:
        return BLK_NAME_OVERRIDES[map_name]
    return snake_to_camel(map_name)


def get_tileset(blk_name: str) -> str | None:
    """Get the tileset name for a map (returns CamelCase tileset name)."""
    asm_tileset = MAP_TILESET_FROM_HEADER.get(blk_name)
    if asm_tileset is None:
        return None
    return TILESET_NAME_MAP.get(asm_tileset, asm_tileset)


def download_file(url: str, cache_path: Path) -> bytes | None:
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


# Seed map names -> disassembly constant names where they differ
# (Yellow-Legacy display names vs original Red constants; inverse of
# extract_map_warps.DEST_CONST_ALIASES).
SEED_TO_DISASM_ALIASES = {
    "PLAYERS_HOUSE_1F": "REDS_HOUSE_1F",
    "PLAYERS_HOUSE_2F": "REDS_HOUSE_2F",
    "RIVALS_HOUSE": "BLUES_HOUSE",
}

MAP_CONST_RE = re.compile(r"map_const\s+(\w+),\s*-?\d+,\s*-?\d+\s*(?:;\s*\$([0-9A-Fa-f]+))?")


def load_map_ids() -> dict[str, int]:
    """Parse constants/map_constants.asm -> {map_constant: numeric id}.

    IDs are sequential from const_def; each entry's `; $XX` comment is used
    as a cross-check where present.
    """
    data = download_file(
        f"{REPO_BASE}/constants/map_constants.asm",
        CACHE_DIR / "constants_map_constants.asm",
    )
    if data is None:
        raise RuntimeError("Could not fetch constants/map_constants.asm")
    ids: dict[str, int] = {}
    for i, (name, hex_comment) in enumerate(MAP_CONST_RE.findall(data.decode("utf-8", "replace"))):
        if hex_comment:
            assert int(hex_comment, 16) == i, f"{name}: sequential id {i} != comment ${hex_comment}"
        ids[name] = i
    assert ids, "no map_const entries parsed"
    return ids


def download_blk(blk_name: str) -> bytes | None:
    """Download the .blk file for a given map."""
    url = f"{REPO_BASE}/maps/{blk_name}.blk"
    cache_path = CACHE_DIR / "maps" / f"{blk_name}.blk"
    return download_file(url, cache_path)


def download_bst(tileset_name: str) -> bytes | None:
    """Download the .bst blockset file for a given tileset."""
    bst_file = TILESET_TO_BST.get(tileset_name)
    if not bst_file:
        print(f"  WARNING: No .bst mapping for tileset {tileset_name}")
        return None
    url = f"{REPO_BASE}/gfx/blocksets/{bst_file}"
    cache_path = CACHE_DIR / "blocksets" / bst_file
    return download_file(url, cache_path)


def get_block_tiles(bst_data: bytes, block_id: int) -> list[int]:
    """Extract the 16 tile IDs for a given block from the blockset data."""
    offset = block_id * 16
    if offset + 16 > len(bst_data):
        return [0] * 16
    return list(bst_data[offset:offset + 16])


def get_collision_tile(block_tiles: list[int], mx: int, my: int) -> int:
    """Get the collision-check tile for a metatile position within a block."""
    row = my * 2 + 1
    col = mx * 2
    idx = row * 4 + col
    return block_tiles[idx]


def classify_tile(tile_id: int, tileset_name: str) -> tuple[str, bool, str]:
    """
    Classify a tile as (tile_type, walkable, ledge_direction).

    Returns:
        tile_type: "path", "grass", "water", "wall", or "ledge"
        walkable: True if passable (path, grass, or ledge)
        ledge_direction: direction string for ledges, empty otherwise
    """
    passable_tiles = COLLISION_TILES.get(tileset_name, set())
    grass_tile = GRASS_TILES.get(tileset_name)
    extra_grass = EXTRA_GRASS_TILES.get(tileset_name, set())
    ledge_targets = LEDGE_TARGET_TILES.get(tileset_name, {})
    water_tiles = WATER_TILES.get(tileset_name, set())

    # Check ledge first
    if tile_id in ledge_targets:
        direction = ledge_targets[tile_id]
        return ("ledge", True, direction)

    # Check if passable
    if tile_id in passable_tiles:
        if tile_id == grass_tile or tile_id in extra_grass:
            return ("grass", True, "")
        else:
            return ("path", True, "")

    # Check if it's a water tile (not passable on foot, but fishable/surfable)
    if tile_id in water_tiles:
        return ("water", False, "")

    # Not passable
    return ("wall", False, "")


def process_map(map_name: str, width: int, height: int,
                blk_name: str, tileset_name: str,
                bst_cache: dict) -> list[dict]:
    """Process a single map and return a list of tile rows."""
    # Download .blk
    blk_data = download_blk(blk_name)
    if blk_data is None:
        print(f"  WARNING: Could not download {blk_name}.blk")
        return []

    expected_size = width * height
    if len(blk_data) != expected_size:
        print(f"  WARNING: {map_name} .blk size {len(blk_data)} != expected "
              f"{expected_size} ({width}x{height})")
        return []

    # Get blockset data
    if tileset_name not in bst_cache:
        bst_data = download_bst(tileset_name)
        if bst_data is None:
            return []
        bst_cache[tileset_name] = bst_data
    bst_data = bst_cache[tileset_name]

    rows = []
    for by in range(height):
        for bx in range(width):
            block_id = blk_data[by * width + bx]
            block_tiles = get_block_tiles(bst_data, block_id)

            for my in range(2):
                for mx in range(2):
                    px = bx * 2 + mx
                    py = by * 2 + my
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

    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    map_ids = load_map_ids()
    bst_cache: dict[str, bytes] = {}
    all_tile_rows = []
    tileset_rows = []
    metadata_rows = []
    skipped = []

    for map_name, (width, height) in sorted(MAP_DIMENSIONS.items()):
        blk_name = get_blk_name(map_name)
        if blk_name is None:
            skipped.append(map_name)
            continue

        tileset_name = get_tileset(blk_name)
        if tileset_name is None:
            print(f"  WARNING: No tileset for {map_name} ({blk_name}), skipping")
            skipped.append(map_name)
            continue

        print(f"Processing {map_name} ({width}x{height}, tileset={tileset_name})...")

        tile_rows = process_map(map_name, width, height,
                                blk_name, tileset_name, bst_cache)
        if tile_rows:
            all_tile_rows.extend(tile_rows)
            counts = {}
            for r in tile_rows:
                counts[r["tile_type"]] = counts.get(r["tile_type"], 0) + 1
            walkable = sum(1 for r in tile_rows if r["walkable"])
            parts = ", ".join(f"{c} {t}" for t, c in sorted(counts.items()) if t != "wall")
            print(f"  -> {len(tile_rows)} tiles: {walkable} walkable ({parts}), "
                  f"{counts.get('wall', 0)} wall")

        tileset_rows.append({
            "map_name": map_name,
            "tileset_name": tileset_name,
        })

        # Determine area type for metadata
        area_type = "indoor"
        name_lower = map_name.lower()
        if "route" in name_lower and "gate" not in name_lower and "house" not in name_lower:
            area_type = "route"
        elif any(t in name_lower for t in ["_town", "_city", "_island", "_plateau"]):
            if map_name in ("PALLET_TOWN", "VIRIDIAN_CITY", "PEWTER_CITY", "CERULEAN_CITY",
                            "VERMILION_CITY", "CELADON_CITY", "LAVENDER_TOWN", "FUCHSIA_CITY",
                            "SAFFRON_CITY", "CINNABAR_ISLAND", "INDIGO_PLATEAU"):
                area_type = "town" if "town" in name_lower else "city"
        elif any(t in name_lower for t in ["cave", "tunnel", "mt_moon", "seafoam",
                                            "victory_road", "power_plant", "digletts"]):
            area_type = "dungeon"
        elif "gate" in name_lower:
            area_type = "gate"
        elif map_name == "VIRIDIAN_FOREST":
            area_type = "dungeon"
        elif any(map_name.startswith(sz) for sz in ["SAFARI_ZONE_CENTER", "SAFARI_ZONE_EAST",
                                                      "SAFARI_ZONE_NORTH", "SAFARI_ZONE_WEST"]):
            if "REST_HOUSE" not in map_name and "SECRET_HOUSE" not in map_name and "GATE" not in map_name:
                area_type = "route"

        # Determine parent area
        parent = ""
        city_map = {
            "PALLET": "PALLET_TOWN", "VIRIDIAN": "VIRIDIAN_CITY", "PEWTER": "PEWTER_CITY",
            "CERULEAN": "CERULEAN_CITY", "VERMILION": "VERMILION_CITY", "CELADON": "CELADON_CITY",
            "LAVENDER": "LAVENDER_TOWN", "FUCHSIA": "FUCHSIA_CITY", "SAFFRON": "SAFFRON_CITY",
            "CINNABAR": "CINNABAR_ISLAND", "INDIGO": "INDIGO_PLATEAU",
        }
        for prefix, city_name in city_map.items():
            if map_name.startswith(prefix) and area_type == "indoor":
                parent = city_name
                break

        map_id = map_ids[SEED_TO_DISASM_ALIASES.get(map_name, map_name)]
        metadata_rows.append({
            "map_name": map_name,
            "map_id_hex": f"0x{map_id:02X}",
            "width": width * 2,  # blocks -> player coordinates
            "height": height * 2,
            "area_type": area_type,
            "parent_area": parent,
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

    # Write nav_map_metadata.csv
    print(f"Writing {METADATA_CSV}...")
    with open(METADATA_CSV, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "map_name", "map_id_hex", "width", "height", "area_type", "parent_area"
        ])
        writer.writeheader()
        writer.writerows(metadata_rows)
    print(f"  -> {len(metadata_rows)} metadata rows written")

    # Summary
    print(f"\n{'=' * 60}")
    print("Summary:")
    total = len(all_tile_rows)
    if total == 0:
        print("  No tiles extracted!")
        return

    counts = {}
    for r in all_tile_rows:
        counts[r["tile_type"]] = counts.get(r["tile_type"], 0) + 1

    total_walkable = sum(1 for r in all_tile_rows if r["walkable"])
    print(f"  Maps processed: {len(tileset_rows)}")
    print(f"  Total tiles:    {total}")
    print(f"  Walkable:       {total_walkable} ({total_walkable / total * 100:.1f}%)")
    print(f"    - Path:       {counts.get('path', 0)}")
    print(f"    - Grass:      {counts.get('grass', 0)}")
    print(f"    - Ledge:      {counts.get('ledge', 0)}")
    print(f"  Water:          {counts.get('water', 0)} ({counts.get('water', 0) / total * 100:.1f}%)")
    print(f"  Wall:           {counts.get('wall', 0)} ({counts.get('wall', 0) / total * 100:.1f}%)")

    if skipped:
        print(f"\n  Skipped {len(skipped)} maps: {', '.join(skipped[:10])}")

    print(f"\nDone!")


if __name__ == "__main__":
    main()
