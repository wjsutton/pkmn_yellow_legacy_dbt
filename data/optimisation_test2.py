import pandas as pd
import random
from deap import base, creator, tools, algorithms

# Function to calculate score for a combination of team members
def calculate_team_score(selected_members, df):
    combo_df = df[df['player_pkmn_id'].isin(selected_members)]
    combo_df = combo_df.groupby(['run','game_stage','trainer', 'trainer_pkmn_id'], as_index=False).agg({'metric_total': 'max'})
    score = combo_df['metric_total'].sum()
    return score

def model(dbt, session):
    # Configure the model
    dbt.config(materialized="table")
    
    # Reference an upstream model or source
    matchup_df = dbt.ref("matchups_summary").df()
    stg_run_trainers_df = dbt.ref("stg_run_trainers").df()
    
    df = pd.merge(matchup_df, stg_run_trainers_df, on=['trainer','game_stage'])

    badges = df['game_stage'].unique()
    runs = df['run'].unique()

    all_results = []

    for badge in badges:
        for run in runs:
            print(f"Run: {run}")
            print(f"Badge: {badge}")
            # Filter for Badge and Run
            filtered_df = df[(df['game_stage'] == badge) & (df['run'] == run)]

            if filtered_df.empty:
                continue  # Skip if no data for this badge and run combination

            filtered_df = filtered_df.groupby(['run', 'game_stage', 'trainer', 'trainer_pkmn_id', 'player_pkmn_id','player_move'], as_index=False).agg({'metric_total': 'max'})

            # Set up the Genetic Algorithm components
            team_members = filtered_df['player_pkmn_id'].unique()
            team_size = 6

            # Define the problem as maximizing the score (FitnessMax)
            creator.create("FitnessMax", base.Fitness, weights=(1.0,))
            creator.create("Individual", list, fitness=creator.FitnessMax)

            toolbox = base.Toolbox()

            # Create an individual by selecting a random combination of team members
            toolbox.register("indices", random.sample, list(team_members), team_size)
            toolbox.register("individual", tools.initIterate, creator.Individual, toolbox.indices)
            toolbox.register("population", tools.initRepeat, list, toolbox.individual)

            # Fitness function using the existing score calculation
            def evalTeam(individual):
                score = calculate_team_score(individual, filtered_df)
                return score,

            toolbox.register("evaluate", evalTeam)
            toolbox.register("mate", tools.cxTwoPoint)
            toolbox.register("mutate", tools.mutShuffleIndexes, indpb=0.05)
            toolbox.register("select", tools.selTournament, tournsize=3)

            # Genetic Algorithm parameters
            population_size = 1000
            generations = 100
            crossover_probability = 0.7
            mutation_probability = 0.2

            # Create the population and evolve
            population = toolbox.population(n=population_size)
            algorithms.eaSimple(population, toolbox, cxpb=crossover_probability, mutpb=mutation_probability, ngen=generations, verbose=False)

            # Extract the best individual
            best_individual = tools.selBest(population, k=1)[0]
            best_score = calculate_team_score(best_individual, filtered_df)

            # Generate output DataFrame based on the best combination
            best_df = filtered_df[filtered_df['player_pkmn_id'].isin(best_individual)]
            best_df['best_score'] = best_score

            all_results.append(best_df)

            # Clear the DEAP creator to avoid conflicts in the next iteration
            del creator.FitnessMax
            del creator.Individual

    # Combine all results
    final_df = pd.concat(all_results, ignore_index=True)

    return final_df