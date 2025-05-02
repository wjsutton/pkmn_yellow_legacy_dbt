import pandas as pd
import random
import math
import re
from deap import base, creator, tools, algorithms

def calculate_route_score(group, difficulty_df):
    """
    Calculate route score based on battle difficulty ratings.
    """
    # For each opponent Pokemon, find the best matchup from our team
    best_matchups = group.loc[group.groupby(['trainer', 'trainer_pkmn_id'])['battle_score'].idxmax()]
    
    # Merge battle difficulty information
    matchups_with_difficulty = pd.merge(
        best_matchups,
        difficulty_df,
        on=['trainer', 'trainer_pkmn_id'],
        how='left'
    )
    
    # Apply difficulty-based weights
    difficulty_weights = {
        'Easy': 1.0,
        'Requires Specific Counter': 1.5,
        'Medium': 2.0,
        'Hard': 3.0,
        'Very Hard': 4.0
    }
    
    # Default to 1.0 for any missing difficulty ratings
    matchups_with_difficulty['difficulty_weight'] = matchups_with_difficulty['difficulty_rating'].map(
        difficulty_weights).fillna(1.0)
    
    # Apply weights to battle scores
    matchups_with_difficulty['weighted_score'] = matchups_with_difficulty['battle_score'] * \
                                               matchups_with_difficulty['difficulty_weight']
    
    # Calculate total weighted score across all trainers
    total_trainers = matchups_with_difficulty['trainer'].nunique()
    
    if total_trainers == 0:
        return 0
        
    # Each trainer contributes equally to the total score (1/n weighting)
    trainer_weight = 1.0 / total_trainers
    weighted_scores = matchups_with_difficulty.groupby('trainer')['weighted_score'].sum() * trainer_weight
    
    return weighted_scores.sum()

def calculate_team_score(selected_members, df, difficulty_df):
    """
    Calculate team score by finding the best Pokemon matchup against each opponent,
    weighted by battle difficulty. Also checks for single-use TM conflicts.
    """
    combo_df = df[df['player_pkmn_id'].isin(selected_members)]
    
    # Check for single-use TM conflicts
    tm_conflicts = {}
    has_conflicts = False
    
    if 'single_use_tm' in combo_df.columns:
        # Get all single-use TMs in the team
        single_use_tms = combo_df[combo_df['single_use_tm'] == 1]
        
        if not single_use_tms.empty:
            # Group by move name and check which single-use TMs are used by multiple Pokémon
            tm_conflicts = single_use_tms.groupby('player_pkmn_move').apply(
                lambda x: list(x['player_pkmn_id'].unique()) if len(x['player_pkmn_id'].unique()) > 1 else []
            ).to_dict()
            
            # Remove empty lists from the conflicts dictionary
            tm_conflicts = {k: v for k, v in tm_conflicts.items() if v}
            has_conflicts = bool(tm_conflicts)
    
    # Calculate scores by game stage
    scores = combo_df.groupby('game_stage', group_keys=False).apply(
        lambda x: calculate_route_score(x, difficulty_df)
    )
    total_score = scores.sum()
    
    # Apply penalty for single-use TM conflicts
    if has_conflicts:
        # The penalty is proportional to the number of conflicts
        conflict_penalty = 0.1 * len(tm_conflicts)
        total_score *= max(0.5, 1 - conflict_penalty)  # Cap the penalty at 50%
    
    # Get detailed matchup information including moves
    best_matchups = combo_df.loc[combo_df.groupby(['trainer', 'trainer_pkmn_id'])['battle_score'].idxmax()]
    
    return total_score, best_matchups, has_conflicts, tm_conflicts

def get_adaptive_parameters(pool_size):
    """
    Calculate appropriate genetic algorithm parameters based on available candidate pool size.
    """
    if pool_size <= 10:
        return {
            'population_size': 100,
            'generations': 50,
            'crossover_probability': 0.7,
            'mutation_probability': 0.1
        }
    
    population_size = min(2000, max(300, int(300 + 50 * math.sqrt(pool_size))))
    generations = min(200, max(50, int(50 + 10 * math.log(pool_size + 1))))

    if pool_size <= 20:
        crossover_prob = 0.7
        mutation_prob = 0.1
    elif pool_size <= 50:
        crossover_prob = 0.75
        mutation_prob = 0.12
    else:
        crossover_prob = 0.8
        mutation_prob = 0.15
    
    return {
        'population_size': population_size,
        'generations': generations,
        'crossover_probability': crossover_prob,
        'mutation_probability': mutation_prob
    }

def resolve_single_use_tm_conflicts(team_pokemon_ids, filtered_df):
    """
    Resolve conflicts where multiple Pokémon use the same single-use TM.
    For each conflicting TM, choose the Pokémon that gets the highest battle score with it.
    Returns a dictionary mapping Pokémon IDs to their optimal moves.
    """
    if 'single_use_tm' not in filtered_df.columns:
        return {}
        
    team_df = filtered_df[filtered_df['player_pkmn_id'].isin(team_pokemon_ids)].copy()
    
    # Get all single-use TMs used by the team
    single_use_tms = team_df[team_df['single_use_tm'] == 1]
    
    if single_use_tms.empty:
        return {}
    
    # Find conflicts (TMs used by multiple Pokémon)
    tm_usage = single_use_tms.groupby('player_pkmn_move')['player_pkmn_id'].apply(list)
    conflicting_tms = {tm: pkmns for tm, pkmns in tm_usage.items() if len(set(pkmns)) > 1}
    
    # For each Pokémon, store its best moves with scores
    pokemon_moves = {}
    for pokemon in team_pokemon_ids:
        # Get all moves for this Pokémon with their battle scores
        pokemon_df = team_df[team_df['player_pkmn_id'] == pokemon]
        
        # Group by move and get average battle score
        move_scores = pokemon_df.groupby('player_pkmn_move')['battle_score'].mean()
        
        # Also track which moves are single-use TMs
        move_types = {}
        for move in move_scores.index:
            is_tm = any(pokemon_df[pokemon_df['player_pkmn_move'] == move]['single_use_tm'] == 1)
            move_types[move] = 'single_use_tm' if is_tm else 'normal'
            
        pokemon_moves[pokemon] = {
            'moves': {move: {'score': score, 'type': move_types[move]} 
                     for move, score in move_scores.items()}
        }
    
    # Resolve conflicts using a greedy approach
    resolved_moves = {}
    assigned_tms = set()
    
    # First, handle non-conflicting TMs
    for tm, users in tm_usage.items():
        if tm not in conflicting_tms:
            pokemon = users[0]  # Only one Pokémon uses this TM
            resolved_moves[pokemon] = tm
            assigned_tms.add(tm)
    
    # For conflicting TMs, use a greedy approach
    # Sort conflicts by the difference in score between best and second-best Pokémon
    conflict_priorities = []
    
    for tm, users in conflicting_tms.items():
        # Get unique Pokémon IDs that use this TM
        unique_users = list(set(users))
        
        # Calculate the score for each Pokémon with this TM
        tm_scores = {pokemon: pokemon_moves[pokemon]['moves'][tm]['score'] 
                    for pokemon in unique_users if tm in pokemon_moves[pokemon]['moves']}
        
        # Sort Pokémon by their score with this TM
        sorted_users = sorted(tm_scores.items(), key=lambda x: x[1], reverse=True)
        
        # Calculate the score difference between best and second-best
        if len(sorted_users) >= 2:
            score_diff = sorted_users[0][1] - sorted_users[1][1]
        else:
            score_diff = sorted_users[0][1]
            
        conflict_priorities.append((tm, sorted_users, score_diff))
    
    # Sort conflicts by score difference (prioritize TMs where one Pokémon is clearly better)
    conflict_priorities.sort(key=lambda x: x[2], reverse=True)
    
    # Assign TMs in order of priority
    for tm, sorted_users, _ in conflict_priorities:
        for pokemon, _ in sorted_users:
            # Skip if this Pokémon already has a move assigned
            if pokemon in resolved_moves:
                continue
                
            # Assign this TM to this Pokémon
            resolved_moves[pokemon] = tm
            assigned_tms.add(tm)
            break
    
    # For Pokémon without assigned moves, find their best non-TM move
    for pokemon in team_pokemon_ids:
        if pokemon not in resolved_moves:
            # Get best non-TM move
            moves = pokemon_moves[pokemon]['moves']
            best_non_tm = None
            best_score = -1
            
            for move, data in moves.items():
                if data['type'] != 'single_use_tm' or move not in assigned_tms:
                    if data['score'] > best_score:
                        best_non_tm = move
                        best_score = data['score']
            
            if best_non_tm:
                resolved_moves[pokemon] = best_non_tm
    
    return resolved_moves

def model(dbt, session):
    # Configure the model
    dbt.config(materialized="table")
    
    # Reference upstream models
    matchup_df = dbt.ref("int_pkmn_team_optimisation_prep").df()
    int_trainers_by_game_route_df = dbt.ref("int_trainers_by_game_route").df()
    battle_difficulty_df = dbt.ref("int_pkmn_team_battle_difficulty").df()
    
    df = pd.merge(matchup_df, int_trainers_by_game_route_df, on=['trainer', 'game_stage'])
    
    badges = sorted(df['game_stage'].unique())
    base_runs = sorted(df['run'].unique())
    
    # Create all runs including Pikachu variants
    runs = []
    for run in base_runs:
        runs.append(run)

    # runs = ['Flareon_Standard_Ledges']  # For testing, just use one run
    
    all_results = []
    
    for run in runs:
        print(f"Run: {run}")
        
        for badge in badges:
            print(f"... Working on: {badge}")
            filtered_df = df[(df['game_stage'] == badge) & (df['run'] == run)].copy()
            
            # Remove legendary pokemon if NoLedges
            if run.endswith('NoLedges'):
                filter_names = ['Moltres', 'Articuno', 'Zapdos', 'Mewtwo', 'Mew']
                pattern = '|'.join(f'^{re.escape(name)}' for name in filter_names)
                filtered_df = filtered_df[~filtered_df['player_pkmn_id'].str.match(pattern, case=False)]
            
            if filtered_df.empty:
                continue

            team_members = set(filtered_df['player_pkmn_id'].unique())
            
            pool_size = len(team_members)
            team_members = list(team_members)  # Convert to list for indexing
            
            params = get_adaptive_parameters(pool_size)
            
            print(f"\nPool size: {pool_size} Pokemon")
            print(f"Using parameters: {params}")
            
            team_size = 6
            
            # Clean up any existing creator classes
            if 'FitnessMax' in dir(creator):
                del creator.FitnessMax
            if 'Individual' in dir(creator):
                del creator.Individual
            
            # Define fitness and individual for this iteration
            creator.create("FitnessMax", base.Fitness, weights=(1.0,))
            creator.create("Individual", list, fitness=creator.FitnessMax)

            # Define evalTeam function for this iteration
            def evalTeam(individual):
                selected_pokemon = [team_members[i] for i in individual]
                
                # Check for single-use TM conflicts
                score, _, has_conflicts, tm_conflicts = calculate_team_score(
                    selected_pokemon, 
                    filtered_df, 
                    battle_difficulty_df
                )
                
                # The penalty for conflicts is now handled directly in calculate_team_score
                return score,

            toolbox = base.Toolbox()

            toolbox.register("indices", random.sample, list(range(len(team_members))), team_size)
            toolbox.register("individual", tools.initIterate, creator.Individual, toolbox.indices)
            toolbox.register("population", tools.initRepeat, list, toolbox.individual)
            toolbox.register("evaluate", evalTeam)
            toolbox.register("mate", tools.cxTwoPoint)
            toolbox.register("mutate", tools.mutShuffleIndexes, indpb=0.05)
            toolbox.register("select", tools.selTournament, tournsize=3)

            population = toolbox.population(n=params['population_size'])
            algorithms.eaSimple(population, toolbox, 
                              cxpb=params['crossover_probability'], 
                              mutpb=params['mutation_probability'], 
                              ngen=params['generations'], 
                              verbose=False)

            # Get the best team from the final population
            best_individuals = tools.selBest(population, k=len(team_members))
            best_team = []
            seen = set()
            
            for individual in best_individuals:
                pokemon_names = [team_members[i] for i in individual]
                for pokemon in pokemon_names:
                    if pokemon not in seen:
                        best_team.append(pokemon)
                        seen.add(pokemon)
                        if len(best_team) == 6:
                            break
                if len(best_team) == 6:
                    break

            # Resolve any single-use TM conflicts in the final team
            move_assignments = resolve_single_use_tm_conflicts(best_team, filtered_df)
            
            # Recalculate best score after resolving conflicts
            best_score, matchup_analysis, has_conflicts, tm_conflicts = calculate_team_score(
                best_team, 
                filtered_df, 
                battle_difficulty_df
            )

            filtered_df['run'] = run
            best_df = filtered_df[filtered_df['player_pkmn_id'].isin(best_team)].copy()
            best_df['best_score'] = best_score
            
            # Flag the final move assignments in the result dataframe
            if move_assignments:
                best_df['is_assigned_move'] = False
                for idx, row in best_df.iterrows():
                    if (row['player_pkmn_id'] in move_assignments and 
                        row['player_pkmn_move'] == move_assignments[row['player_pkmn_id']]):
                        best_df.at[idx, 'is_assigned_move'] = True

            all_results.append(best_df)

            # Print team information
            print(f"\nBest Team for {badge}:")             
            print("Team Members:")
            for pokemon in sorted(best_df['player_pkmn_id'].unique()):
                print(f"- {pokemon}")

            # Print key matchups
            print("\nKey Matchups:")
            for trainer in matchup_analysis['trainer'].unique():
                trainer_matchups = matchup_analysis[matchup_analysis['trainer'] == trainer]
                is_gym = trainer_matchups['is_gym_leader'].iloc[0] == 1
                trainer_type = "Gym Leader" if is_gym else "Trainer"
                print(f"\n{trainer} ({trainer_type}):")
                for _, row in trainer_matchups.iterrows():
                    # Check if this is the assigned move for this Pokémon
                    is_assigned = (row['player_pkmn_id'] in move_assignments and 
                                   row['player_pkmn_move'] == move_assignments[row['player_pkmn_id']])
                    
                    assigned_marker = " (ASSIGNED)" if is_assigned else ""
                    
                    print(f"- {row['trainer_pkmn_id']}: Best counter is {row['player_pkmn_id']} "
                          f"using {row['player_pkmn_move']}{assigned_marker} "
                          f"(Score: {row['battle_score']:.2f})")
            
            # Print single-use TM assignments if any exist
            if 'single_use_tm' in filtered_df.columns:
                single_use_tms = filtered_df[(filtered_df['player_pkmn_id'].isin(best_team)) & 
                                           (filtered_df['single_use_tm'] == 1)]
                
                if not single_use_tms.empty:
                    print("\nSingle-Use TM Assignments:")
                    
                    # Group by TM to see if any are conflicting
                    tm_users = {}
                    for _, row in single_use_tms.iterrows():
                        tm = row['player_pkmn_move']
                        pokemon = row['player_pkmn_id']
                        
                        if tm not in tm_users:
                            tm_users[tm] = []
                        
                        if pokemon not in tm_users[tm]:
                            tm_users[tm].append(pokemon)
                    
                    # Print TM assignments
                    for tm, users in tm_users.items():
                        if len(users) > 1:
                            print(f"- TM {tm} has {len(users)} potential users: {', '.join(users)}")
                            
                            # Show the resolution
                            for pokemon in users:
                                assigned_tm = move_assignments.get(pokemon)
                                if assigned_tm == tm:
                                    print(f"  → {pokemon} has been assigned {tm}")
                                else:
                                    alt_move = move_assignments.get(pokemon, "no alternative")
                                    print(f"  → {pokemon} will use {alt_move} instead")
                        else:
                            print(f"- {users[0]} will use {tm}")

            print(f"\nOverall Score: {best_score:.2f}")
            if has_conflicts:
                print("Note: TM conflicts were detected and resolved.")
            print("----------------------------")


    final_df = pd.concat(all_results, ignore_index=True)
    return final_df