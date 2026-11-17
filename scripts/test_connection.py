import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()
conn = psycopg2.connect(os.environ["DATABASE_URL"])
cur = conn.cursor()
cur.execute("select count(*) from candidates")
print("candidates:", cur.fetchone()[0])
conn.close()