# import pulp
# import numpy as np
# import pandas as pd

import pandas as pd
import itertools
import numpy as np

df = pd.read_csv("pkmn_yellow_legacy_map/matchups_summary.csv")

#trainers_to_include = ["Jessie_&_James_1","Rival_3","Misty"]
trainers_to_include = ["Lorelei", "Bruno","Agatha","Lance","Champion_Vaporeon"]
df = df[df['trainer'].isin(trainers_to_include)]

df = df.groupby(['trainer', 'trainer_pkmn_id', 'player_pkmn_id'], as_index=False).agg({'metric_total': 'max'})


# # Function to calculate score for a combination of team members
# def calculate_team_score(selected_members, df):
#     score = 0
#     combo_df = df[df['player_pkmn_id'].isin(selected_members)]
#     combo_df = combo_df.groupby(['trainer', 'trainer_pkmn_id'], as_index=False).agg({'metric_total': 'max'})
#     score = combo_df['metric_total'].sum()
#     return score

# # Enumerate all combinations of three team members
team_members = df['player_pkmn_id'].unique()
# best_score = -1
# best_combination = None

# team_size = 6

# # Calculate the total number of combinations
# combos = list(itertools.combinations(team_members, team_size))
# total_combinations = len(combos)
# print(f"Total combinations: {total_combinations}")

# for combination in itertools.combinations(team_members, team_size):
#     score = calculate_team_score(combination, df)
#     if score > best_score:
#         best_score = score
#         best_combination = combination

# print(f"The best combination of team members is: {best_combination}")
# print(f"The highest team score is: {best_score}")

# best_df = df[df['player_pkmn_id'].isin(best_combination)]
# best_df = best_df.groupby(['trainer', 'trainer_pkmn_id'], as_index=False).agg({'metric_total': 'max'})

# output_df = pd.merge(best_df,df[df['player_pkmn_id'].isin(best_combination)], on = ['trainer_pkmn_id', 'metric_total'])
# # Then, use those indices to filter the original DataFrame
# print(output_df)


from pulp import LpMaximize, LpProblem, LpVariable, lpSum

# Create the LP problem
model = LpProblem(name="team-selection", sense=LpMaximize)

# Create variables for each Pokémon, whether to include it in the team or not
team_vars = {pkmn: LpVariable(name=pkmn, cat='Binary') for pkmn in team_members}

# Objective function: Maximize the total score
model += lpSum(team_vars[pkmn] * df[df['player_pkmn_id'] == pkmn]['metric_total'].sum() for pkmn in team_members), "Total_Score"

# Constraint: Select exactly 6 Pokémon
model += lpSum(team_vars[pkmn] for pkmn in team_members) == 6, "Team_Size"

# Solve the problem
status = model.solve()

# Retrieve the selected team
selected_team = [pkmn for pkmn in team_members if team_vars[pkmn].value() == 1]
print(selected_team)



# # Number of members and opponents
# N = 10  # Total members available
# T = 3   # Total opponents

# # Randomly generate a matrix of match outcomes (values between 1 and 100)
# np.random.seed(42)
# O = np.random.randint(1, 101, size=(N, T))

# # Create a list of member indices
# members = list(range(N))

# # Create a PuLP problem instance
# prob = pulp.LpProblem("Team_Selection", pulp.LpMaximize)

# # Decision variables: x[i] is 1 if member i is selected, 0 otherwise
# x = pulp.LpVariable.dicts("x", members, 0, 1, pulp.LpBinary)

# # Objective function: Maximize the total match outcome
# prob += pulp.lpSum([O[i, j] * x[i] for i in range(N) for j in range(T)])

# # Constraint: Select exactly 6 members
# prob += pulp.lpSum([x[i] for i in range(N)]) == 6

# # Solve the problem
# prob.solve()

# # Output the results
# selected_members = [i for i in members if x[i].value() == 1]
# total_match_outcome = pulp.value(prob.objective)

# print("Selected Members:", selected_members)
# print("Total Match Outcome:", total_match_outcome)






# import pandas as pd
# from pulp import *

# # Assuming df is your dataset
# df = pd.read_csv("matchups_summary.csv")

# # List of trainers to include
# # trainers_to_include = ["Brock", "ViridianForest_Bug_Catcher_4"]
# trainers_to_include = ["Lorelei", "Bruno","Agatha","Lance","Champion_Vaporeon"]

# # Filter the DataFrame to only include the specified trainers
# df = df[df['trainer'].isin(trainers_to_include)]

# # Create a pivot table
# pivot_df = df.pivot_table(index='trainer_pkmn_id', columns='player_pkmn_id', values='metric_total', aggfunc='max')

# # Create the LP problem
# prob = LpProblem("Pokemon_Team_Selection", LpMaximize)

# # Create a binary variable for each player_pkmn_id
# pokemon_vars = LpVariable.dicts("Pokemon", pivot_df.columns, 0, 1, LpBinary)
# #
# # Objective function: maximize the total metric_total
# prob += lpSum([pokemon_vars[p] * pivot_df[p].sum() for p in pivot_df.columns])

# # Constraint: Select exactly 6 Pokemon
# prob += lpSum([pokemon_vars[p] for p in pivot_df.columns]) == 6

# # Constraint: Each trainer_pkmn_id must have at least one counter
# for trainer in pivot_df.index:
#     prob += lpSum([pokemon_vars[p] * (pivot_df.loc[trainer, p] > 0) for p in pivot_df.columns]) >= 1

# # Solve the problem
# prob.solve()

# # Get the selected Pokemon
# selected_pokemon = [p for p in pivot_df.columns if pokemon_vars[p].varValue == 1]

# print("Selected Pokemon:", selected_pokemon)
