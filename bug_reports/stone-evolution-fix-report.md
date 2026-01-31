# FIXED: Stone Evolution Availability Bug Fix

## Problem Summary

The `int_pokemon_availability` model currently hardcodes stone evolution availability to Celadon City (Badge 4), regardless of where evolution stones are actually found in the game. This causes incorrect earliest availability calculations for stone-evolved Pokemon.

**Example:** Nidoking currently shows as first available at Badge 4, but since the Moon Stone is found in Mt. Moon (Badge 2), players can actually have Nidoking ready for Misty's gym.

## Affected Pokemon

All 15 stone evolution Pokemon are potentially affected:

| Stone | Pokemon | Evolves Into |
|-------|---------|--------------|
| Moon | Nidorina | Nidoqueen |
| Moon | Nidorino | Nidoking |
| Moon | Clefairy | Clefable |
| Moon | Jigglypuff | Wigglytuff |
| Fire | Vulpix | Ninetales |
| Fire | Growlithe | Arcanine |
| Fire | Eevee | Flareon |
| Water | Poliwhirl | Poliwrath |
| Water | Shellder | Cloyster |
| Water | Staryu | Starmie |
| Water | Eevee | Vaporeon |
| Thunder | Eevee | Jolteon |
| Leaf | Gloom | Vileplume |
| Leaf | Weepinbell | Victreebel |
| Leaf | Exeggcute | Exeggutor |

## Root Cause

The model lacks stone location data. Stone evolutions are currently assigned availability based on Celadon City (where the department store sells stones), ignoring earlier obtainable stones found as items in the overworld.

## Solution

### Step 1: Create New Seed File

Create `seeds/item_stone_locations.csv` with all stone locations in the game. Since stones can be found in multiple locations, include all of them—the model will select the earliest.

```csv
stone_type,map,quantity,source_type
Moon,MtMoonB2F,1,Hidden
Moon,MtMoonB2F,1,Visible
Moon,PokemonMansion1F,1,Hidden
Moon,CeladonCity,unlimited,Shop
Fire,PokemonMansion1F,1,Hidden
Fire,CeladonCity,unlimited,Shop
Water,SeafoamIslandsB3F,1,Hidden
Water,CeladonCity,unlimited,Shop
Thunder,PowerPlant,1,Hidden
Thunder,CeladonCity,unlimited,Shop
Leaf,VictoryRoad2F,1,Hidden
Leaf,CeladonCity,unlimited,Shop
```

**Notes:**
- `source_type` distinguishes between hidden items, visible pickups, and shop purchases
- `quantity` can help with future features (tracking limited vs unlimited stones)
- Mt. Moon has two Moon Stones (one hidden, one visible), hence two rows

### Step 2: Create Staging Model

Create `models/staging/stg_item_stone_locations.sql`:

```sql
with source as (
    select * from {{ ref('item_stone_locations') }}
),

with_route_order as (
    select
        s.stone_type,
        s.map,
        s.quantity,
        s.source_type,
        r.game_order,
        r.next_gym
    from source s
    left join {{ ref('stg_game_route_order') }} r
        on s.map = r.map
)

select
    {{ dbt_utils.generate_surrogate_key(['stone_type', 'map', 'source_type']) }} as id,
    stone_type,
    map,
    quantity,
    source_type,
    game_order,
    next_gym
from with_route_order
```

### Step 3: Create Stone Availability Helper

Create `models/intermediate/int_stone_availability.sql` to find the earliest location for each stone:

```sql
with stone_locations as (
    select * from {{ ref('stg_item_stone_locations') }}
),

earliest_per_stone as (
    select
        stone_type,
        min(game_order) as earliest_game_order
    from stone_locations
    group by stone_type
)

select
    sl.stone_type,
    sl.map as earliest_map,
    sl.game_order as earliest_route,
    sl.next_gym as earliest_game_stage,
    sl.source_type
from stone_locations sl
inner join earliest_per_stone eps
    on sl.stone_type = eps.stone_type
    and sl.game_order = eps.earliest_game_order
```

### Step 4: Update int_pokemon_availability

Modify the stone evolution CTE in `int_pokemon_availability` to join against the new stone availability data instead of hardcoding Celadon City.

**Current logic (pseudocode):**
```sql
-- Stone evolutions hardcoded to Celadon
'Available from Celadon City' as source
```

**Updated logic:**
```sql
-- Join to get actual stone availability
left join {{ ref('int_stone_availability') }} sa
    on e.evolution_stone = sa.stone_type

-- Use the earliest stone location
sa.earliest_map as stone_source_map,
sa.earliest_route as stone_earliest_route,
sa.earliest_game_stage as stone_game_stage,

-- Update source text
'Available from ' || sa.earliest_map as source
```

The key change is that stone evolution availability should be the **later of**:
1. When the base Pokemon becomes available
2. When the required stone becomes available

```sql
case
    when base_pokemon_route > stone_earliest_route
    then base_pokemon_route
    else stone_earliest_route
end as earliest_route
```

## Expected Results After Fix

| Pokemon | Current | Expected | Reason |
|---------|---------|----------|--------|
| Nidoking | Badge 4 | Badge 2 | Moon Stone in Mt. Moon |
| Nidoqueen | Badge 4 | Badge 2 | Moon Stone in Mt. Moon |
| Clefable | Badge 4 | Badge 2 | Moon Stone in Mt. Moon, Clefairy in Mt. Moon |
| Wigglytuff | Badge 4 | Badge 3 | Moon Stone in Mt. Moon, Jigglypuff on Route 5-6 |
| Ninetales | Badge 4 | Badge 4 | Fire Stone only in Celadon, Vulpix in Celadon |
| Arcanine | Badge 4 | Badge 4 | Fire Stone only in Celadon (earliest shop) |
| Jolteon | Badge 4 | Badge 4 | Thunder Stone in Power Plant (Badge 4+) or Celadon |
| Vaporeon | Badge 4 | Badge 4 | Water Stone in Seafoam or Celadon |
| Flareon | Badge 4 | Badge 4 | Fire Stone in Celadon |

## Testing

After implementation, verify with:

```sql
select 
    pokemon,
    min(earliest_route) as first_available_route,
    min(game_stage) as first_available_stage
from {{ ref('int_pokemon_availability') }}
where pokemon in ('Nidoking', 'Nidoqueen', 'Clefable', 'Wigglytuff')
group by pokemon
order by first_available_route
```

Expected output should show Badge 2 for Nidoking, Nidoqueen, and Clefable.

## Future Considerations

- The `item_stone_locations` seed could be expanded to include all key items (HMs, rods, etc.) for a more comprehensive item availability system
- Consider adding a `notes` field to capture details like "hidden behind a rock requiring Strength"
- Some stones require HMs to access (e.g., Seafoam Islands needs Surf/Strength)—a future enhancement could factor in HM availability
