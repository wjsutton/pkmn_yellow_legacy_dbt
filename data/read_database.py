import duckdb

# create duckdb file'
con = duckdb.connect("data/pkmn_yellow_legacy.db")

show_tables = """
    SELECT * FROM pg_catalog.pg_tables;
"""

# See an output of all the tables
con.sql(show_tables).show()

# con.table("catchable_pkmn").show()
# con.table("usable_pkmn").show()
# con.table("player_pkmn_moves").show()
# con.table("trainer_pkmn_moves").show()
# con.table("matchups").show()
# con.table("player_pkmn_damage").show()
# con.table("trainer_pkmn_damage").show()
# con.table("matchups_summary").show()
# con.table("player_best_team").show()
#con.table("teams_optimisation").show()

#con.table("stg_pkmn_encounters").show()

query = """
SELECT * FROM stg_mandatory_trainers
"""


query2 = """
SELECT * 
FROM stg_moves_from_level_up 
WHERE pokedex_number = 11

"""

con.sql(query).show()

#con.sql(query2).show()

row_count = """
    SELECT * FROM stg_tmhm_locations;
"""

#con.sql(row_count).show()

export = """
    COPY matchups_summary TO 'matchups_summary_badge3.csv' (HEADER, DELIMITER ',');
"""

#con.sql(export)

export2 = """
    COPY teams_optimisation TO 'teams_optimisation_badge3.csv' (HEADER, DELIMITER ',');
"""

#con.sql(export2)