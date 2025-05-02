import os
import duckdb

def create_database(db_path):
    # Create the 'data' folder if it does not exist
    data_folder = os.path.dirname(db_path)
    if not os.path.exists(data_folder):
        os.makedirs(data_folder)
    
    # If a file with the same name exists, delete it
    if os.path.exists(db_path):
        try:
            os.remove(db_path)
            print(f"Existing database '{os.path.basename(db_path)}' deleted.")
        except Exception as e:
            print(f"Failed to delete existing database: {e}")
            return  # Exit the function if deletion fails

    # Create the new database
    try:
        con = duckdb.connect(database=db_path)
        print(f"Database '{os.path.basename(db_path)}' created successfully.")
        con.close()  # Close the connection if not needed further
    except Exception as e:
        print(f"Failed to create database: {e}")

# Specify the path to the database
db_path = os.path.join('data', 'pkmn_yellow_legacy.db')

# Create the database
create_database(db_path)
