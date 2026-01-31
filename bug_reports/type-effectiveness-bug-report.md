# FIXED: Type Effectiveness Applied Against Wrong Pokemon

## Summary

The `int_battle_outcomes` model has a critical bug where **type effectiveness is calculated against the player's pokemon type instead of the target's pokemon type**. This causes super effective moves to be treated as neutral or even resisted.

## Impact

This bug completely breaks the battle outcome calculations:

| Example Matchup | Expected | Model Shows | Error |
|-----------------|----------|-------------|-------|
| Dugtrio (Ground) uses Dig vs Raichu (Electric) | 2.0x (super effective) | 1.0x (neutral) | Missing 2x damage |
| Goldeen (Water) uses Bubble vs Geodude (Rock/Ground) | 4.0x (super effective) | 0.5x (resisted) | 8x damage difference |

**Real-world effect:** Dugtrio with Dig should KO Lt. Surge's Raichu in ~1.6 hits, but the model shows 3.7 hits — incorrectly marking it as a losing matchup.

## Root Cause

In the `int_battle_outcomes` model (or the `calculate_damage_rby` macro), the type effectiveness join is using the wrong column for the defending type:

```sql
-- INCORRECT (current behavior)
left join {{ ref('stg_moves_type_effectiveness') }} te1 
    on move_type = te1.attacking_type 
    and player_type1 = te1.defending_type  -- BUG: using player's type!

-- CORRECT (should be)
left join {{ ref('stg_moves_type_effectiveness') }} te1 
    on move_type = te1.attacking_type 
    and target_type1 = te1.defending_type  -- FIX: use target's type
```

## How to Fix

### Step 1: Locate the Bug

Open `models/intermediate/int_battle_outcomes.sql` and/or `macros/calculate_damage_rby.sql` and find the type effectiveness join for player damage calculation.

Look for a join pattern like:
```sql
left join {{ ref('stg_moves_type_effectiveness') }} player_te1
    on [move_type_column] = player_te1.attacking_type
    and [WRONG_COLUMN] = player_te1.defending_type
```

### Step 2: Apply the Fix

Change the defending type column from the player's type to the target's type:

**For Type1 effectiveness:**
```sql
left join {{ ref('stg_moves_type_effectiveness') }} player_te1
    on player_move.move_type = player_te1.attacking_type
    and target_pokemon.type1 = player_te1.defending_type  -- target's type1
```

**For Type2 effectiveness:**
```sql
left join {{ ref('stg_moves_type_effectiveness') }} player_te2
    on player_move.move_type = player_te2.attacking_type
    and target_pokemon.type2 = player_te2.defending_type  -- target's type2
```

### Step 3: Verify Column Names

Check that you're using the correct column aliases. Common patterns:

| Context | Player Pokemon | Target Pokemon |
|---------|---------------|----------------|
| Player attacking trainer | `player_stats.type1` | `trainer_stats.type1` |
| Type effectiveness for player's move | `player_move.move_type` | `opponent.type1`, `opponent.type2` |

### Step 4: Check the Macro

If using `calculate_damage_rby` macro, the fix may need to be applied there. The macro should accept parameters for:
- `attacker_type1`, `attacker_type2` (for STAB calculation)
- `defender_type1`, `defender_type2` (for type effectiveness calculation)

Ensure these are passed correctly at the call site.

## Verification Query

After fixing, run this query to verify Dugtrio vs Raichu is now correct:

```sql
select 
    player_pokemon,
    player_pkmn_move,
    trainer_pokemon,
    player_attempts_to_ko,
    -- Should be ~1.6 after fix (was 3.69 before)
    case when player_attempts_to_ko < 2 then 'PASS' else 'FAIL' end as test_result
from {{ ref('int_battle_outcomes') }}
where trainer = 'Lt._Surge' 
  and player_pokemon = 'Dugtrio' 
  and player_pkmn_move = 'Dig'
```

**Expected after fix:**
- `player_attempts_to_ko` ≈ 1.59 (down from 3.69)
- Dugtrio with Dig should now show as a winning matchup vs Lt. Surge

## Additional Test Cases

| Player | Move | Target | Expected Hits | 
|--------|------|--------|---------------|
| Dugtrio | Dig | Raichu | ~1.6 |
| Goldeen | Bubble | Geodude | Should be low (4x effective) |
| Pikachu | Thunderbolt | Starmie | ~1-2 (2x effective) |
| Charizard | Flamethrower | Exeggutor | ~1 (4x effective) |

## Gen 1 Damage Formula Reference

For reference, the correct Gen 1 damage formula is:

```
Damage = ((2 × Level / 5 + 2) × Power × A / D / 50 + 2) × STAB × Type1 × Type2 × Random
```

Where:
- **STAB** = 1.5 if move type matches attacker's type, else 1.0
- **Type1** = effectiveness vs defender's first type (0.5, 1.0, or 2.0)
- **Type2** = effectiveness vs defender's second type (0.5, 1.0, or 2.0), or 1.0 if no second type
- **Random** = 217-255 / 255 (average ~0.925)

The bug is in Type1/Type2 — they're being calculated against the attacker's types instead of the defender's types.
