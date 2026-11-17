import os
import psycopg2
import streamlit as st
from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv(usecwd=True))
st.set_page_config(page_title="Coordinator", layout="centered")


def run(sql, params=None, fetch=True):
    conn = psycopg2.connect(os.environ["DATABASE_URL"])
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(sql, params)
                return cur.fetchall() if fetch else None
    finally:
        conn.close()


coord_id = run("SELECT user_id FROM users WHERE role = 'coordinator' LIMIT 1")[0][0]

st.title("Coordinator")

st.subheader("All rooms")
summary = run("""
    SELECT r.room_name,
           count(*) FILTER (WHERE q.status = 'In queue'),
           count(*) FILTER (WHERE q.status = 'Interviewing'),
           count(*) FILTER (WHERE q.status = 'Done')
    FROM rooms r
    JOIN room_allocations a ON a.room_id = r.room_id
    JOIN queue_entries q ON q.allocation_id = a.allocation_id
    GROUP BY r.room_id, r.room_name
    ORDER BY r.room_id
""")
st.dataframe(
    [{"Room": s[0], "In queue": s[1], "Interviewing": s[2], "Done": s[3]} for s in summary],
    use_container_width=True,
    hide_index=True,
)

st.subheader("Undo a wrong tap")
rooms = [r[0] for r in run("SELECT room_name FROM rooms ORDER BY room_id")]
room = st.selectbox("Room", rooms)

rows = run("""
    SELECT q.queue_entry_id, c.full_name, co.company_name, q.status, q.version
    FROM queue_entries q
    JOIN candidates c ON c.candidate_id = q.candidate_id
    JOIN room_allocations a ON a.allocation_id = q.allocation_id
    JOIN rooms rm ON rm.room_id = a.room_id
    JOIN rounds ro ON ro.round_id = a.round_id
    JOIN companies co ON co.company_id = ro.company_id
    WHERE rm.room_name = %s AND q.status IN ('Interviewing', 'Done')
    ORDER BY CASE q.status WHEN 'Interviewing' THEN 0 ELSE 1 END, q.queue_entry_id
    LIMIT 20
""", (room,))

if not rows:
    st.info("Nothing to undo in this room.")

BACK = {"Interviewing": ("Back to queue", "In queue"), "Done": ("Back to interviewing", "Interviewing")}

for entry_id, name, company, status, version in rows:
    c1, c2, c3 = st.columns([3, 2, 3])
    c1.write(f"**{name}**  \n{company}")
    c2.write(status)
    label, target = BACK[status]
    if c3.button(label, key=f"u{entry_id}"):
        try:
            run(
                "SELECT change_status(%s, %s, %s, %s)",
                (entry_id, target, coord_id, version),
                fetch=False,
            )
            st.rerun()
        except psycopg2.Error as e:
            st.error(e.diag.message_primary or str(e))