import os
import psycopg2
import streamlit as st
from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv(usecwd=True))
st.set_page_config(page_title="Room Volunteer", layout="centered")


def run(sql, params=None, fetch=True):
    conn = psycopg2.connect(os.environ["DATABASE_URL"])
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(sql, params)
                return cur.fetchall() if fetch else None
    finally:
        conn.close()


volunteers = run("""
    SELECT u.user_id, u.full_name, r.room_id, r.room_name
    FROM users u
    JOIN room_volunteers rv ON rv.user_id = u.user_id
    JOIN rooms r ON r.room_id = rv.room_id
    ORDER BY r.room_id, u.user_id
""")
labels = {f"{v[1]} ({v[3]})": v for v in volunteers}

st.title("Room volunteer")
who = labels[st.selectbox("Who are you?", list(labels))]
user_id, room_id, room_name = who[0], who[2], who[3]
st.subheader(room_name)

rows = run("""
    SELECT q.queue_entry_id, c.full_name, co.company_name, q.status, q.version
    FROM queue_entries q
    JOIN candidates c ON c.candidate_id = q.candidate_id
    JOIN room_allocations a ON a.allocation_id = q.allocation_id
    JOIN rounds ro ON ro.round_id = a.round_id
    JOIN companies co ON co.company_id = ro.company_id
    WHERE a.room_id = %s AND q.status <> 'Done'
    ORDER BY CASE q.status WHEN 'Interviewing' THEN 0 ELSE 1 END, q.queue_entry_id
    LIMIT 25
""", (room_id,))

if not rows:
    st.info("Nobody waiting in this room.")

NEXT = {
    "In queue": ("Start interview", "Interviewing"),
    "Interviewing": ("Mark done", "Done"),
}

for entry_id, name, company, status, version in rows:
    c1, c2, c3 = st.columns([3, 2, 2])
    c1.write(f"**{name}**  \n{company}")
    c2.write(status)
    label, new_status = NEXT[status]
    if c3.button(label, key=f"b{entry_id}"):
        try:
            run(
                "SELECT change_status(%s, %s, %s, %s)",
                (entry_id, new_status, user_id, version),
                fetch=False,
            )
            st.rerun()
        except psycopg2.Error as e:
            st.error(e.diag.message_primary or str(e))