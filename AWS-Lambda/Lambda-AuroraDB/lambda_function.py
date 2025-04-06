import psycopg2
import os
import json
import requests  # To check the connection to google.com

# Method to check the connection to google.com
def check_google_connection():
    try:
        # Send a GET request to google.com to verify connectivity
        response = requests.get(""https://www.google.com"", timeout=5)
        
        if response.status_code == 200:
            # If successful, print ""Connected Successfully""
            print(""Connected Successfully to google.com"")
            return True
        else:
            print(""Failed to connect to google.com, status code:"", response.status_code)
            return False
    except requests.RequestException as e:
        # Handle any exceptions (like timeouts, DNS errors, etc.)
        print(""Error connecting to google.com:"", e)
        return False

# Method to connect to Aurora PostgreSQL via RDS Proxy
def connect_to_db():
    # Get the environment variables for database credentials
    db_host = os.environ['DB_HOST']  # RDS Proxy endpoint
    db_name = os.environ['DB_NAME']
    db_user = os.environ['DB_USER']
    db_password = os.environ['DB_PASSWORD']
    
    # Create a connection string
    conn_string = f""dbname={db_name} user={db_user} password={db_password} host={db_host} port=5432""
    
    try:
        # Establish connection to the database through RDS Proxy
        conn = psycopg2.connect(conn_string)
        cursor = conn.cursor()
        
        # Example query to fetch data (customize for your use case)
        cursor.execute(""SELECT * FROM your_table LIMIT 5;"")
        result = cursor.fetchall()
        
        # Close the cursor and connection
        cursor.close()
        conn.close()

        # Return the query results
        return result

    except Exception as e:
        print(""Error while connecting to the database:"", e)
        return None

# Lambda handler
def lambda_handler(event, context):

    print(""Lambda Innovation Started...."")
    print(event)

    # Step 1: First, check the connection to google.com
    google_connection_status = check_google_connection()

    if google_connection_status:
        # Step 2: If Google connection is successful, connect to the database
        result = connect_to_db()
        
        if result:
            # If database connection is successful, return the data
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Successfully connected to google.com and Aurora PostgreSQL!',
                    'data': result
                })
            }
        else:
            # If database connection failed, return an error message
            return {
                'statusCode': 500,
                'body': json.dumps({'message': 'Failed to connect to the database or execute the query'})
            }
    else:
        # If Google connection fails, return an error message
        return {
            'statusCode': 500,
            'body': json.dumps({'message': 'Failed to connect to google.com'})
        }					
