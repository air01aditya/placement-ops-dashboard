import os
import threading
import psycopg2
from dotenv import load_dotenv

load_dotenv()
URL = os.environ["DATABASE_URL"]

ELIGIBLE = """
    SELECT q.queue_entry_id, q.version, a.room_id
    FROM queue_entries q
    JOIN room_allocations a ON a.allocation_id = q.allocation_id
    WHERE q.status = 'In queue'
      AND NOT EXISTS (SELECT 1 FROM queue_entries x
                      WHERE x.candidate_id = q.candidate_id AND x.status = 'Interviewing')
"""

conn = psycopg2.connect(URL)
cur = conn.cursor()
cur.execute(f"""
    WITH e AS ({ELIGIBLE})
    SELECT room_id FROM e
    WHERE room_id NOT IN (
        SELECT a.room_id FROM queue_entries q
        JOIN room_allocations a ON a.allocation_id = q.allocation_id
        WHERE q.status = 'Interviewing')
    GROUP BY room_id HAVING count(*) >= 2
    ORDER BY room_id LIMIT 1
""")
room_id = cur.fetchone()[0]
cur.execute(f"""
    WITH e AS ({ELIGIBLE})
    SELECT queue_entry_id, version FROM e WHERE room_id = %s
    ORDER BY queue_entry_id LIMIT 2
""", (room_id,))
entries = cur.fetchall()
cur.execute("SELECT user_id FROM room_volunteers WHERE room_id = %s ORDER BY user_id", (room_id,))
vols = [r[0] for r in cur.fetchall()]
cur.execute("SELECT user_id FROM users WHERE role = 'coordinator' LIMIT 1")
coord = cur.fetchone()[0]
conn.close()

print("room:", room_id, "entries:", [e[0] for e in entries])

barrier = threading.Barrier(2)
results = []


def tap(i):
    c = psycopg2.connect(URL)
    try:
        barrier.wait()
        with c, c.cursor() as k:
            k.execute(
                "SELECT change_status(%s, 'Interviewing', %s, %s)",
                (entries[i][0], vols[i], entries[i][1]),
            )
        results.append((i, "OK", entries[i][0]))
    except psycopg2.Error as e:
        results.append((i, "BLOCKED: " + (e.diag.message_primary or str(e)), entries[i][0]))
    finally:
        c.close()


threads = [threading.Thread(target=tap, args=(i,)) for i in range(2)]
for t in threads:
    t.start()
for t in threads:
    t.join()

for r in results:
    print("volunteer", r[0] + 1, "->", r[1])

ok = [r for r in results if r[1] == "OK"]
print("PASS" if len(ok) == 1 else "FAIL", "-", len(ok), "of 2 taps succeeded")

# put the winner back so data stays clean
conn = psycopg2.connect(URL)
with conn, conn.cursor() as k:
    for r in ok:
        k.execute("SELECT change_status(%s, 'In queue', %s)", (r[2], coord))
conn.close()