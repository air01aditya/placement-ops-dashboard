import os
import psycopg2
import streamlit as st
from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv(usecwd=True))
st.set_page_config(page_title="Recruiter", layout="centered")


def run(sql, params=None, fetch=True):
    conn = psycopg2.connect(os.environ["DATABASE_URL"])
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(sql, params)
                return cur.fetchall() if fetch else None
    finally:
        conn.close()


recruiters = run("""
    SELECT u.user_id, u.full_name, u.company_id, c.company_name
    FROM users u
    JOIN companies c ON c.company_id = u.company_id
    WHERE u.role = 'recruiter'
    ORDER BY u.user_id
""")
labels = {f"{r[1]}": r for r in recruiters}

st.title("Recruiter")
who = labels[st.selectbox("Who are you?", list(labels))]
user_id, company_id, company_name = who[0], who[2], who[3]
st.subheader(company_name)

rows = run("""
    SELECT q.queue_entry_id, c.full_name, q.rating, q.outcome, q.version
    FROM queue_entries q
    JOIN candidates c ON c.candidate_id = q.candidate_id
    JOIN room_allocations a ON a.allocation_id = q.allocation_id
    JOIN rounds ro ON ro.round_id = a.round_id
    WHERE ro.company_id = %s AND q.status = 'Done'
    ORDER BY (q.outcome IS NOT NULL), q.queue_entry_id
    LIMIT 25
""", (company_id,))

if not rows:
    st.info("No finished interviews yet.")

OUTCOMES = ["Shortlisted", "Rejected", "On hold"]

for entry_id, name, rating, outcome, version in rows:
    c1, c2, c3, c4 = st.columns([3, 1, 2, 2])
    c1.write(f"**{name}**")
    new_rating = c2.selectbox(
        "Rating", [1, 2, 3, 4, 5],
        index=(rating - 1) if rating else 2,
        key=f"r{entry_id}", label_visibility="collapsed",
    )
    new_outcome = c3.selectbox(
        "Outcome", OUTCOMES,
        index=OUTCOMES.index(outcome) if outcome else 0,
        key=f"o{entry_id}", label_visibility="collapsed",
    )
    if c4.button("Save", key=f"s{entry_id}"):
        if new_rating == rating and new_outcome == outcome:
            st.info("No change to save.")
        else:
            try:
                run(
                    "SELECT change_evaluation(%s, %s::smallint, %s, %s, %s)",
                    (entry_id, new_rating, new_outcome, user_id, version),
                    fetch=False,
                )
                st.rerun()
            except psycopg2.Error as e:
                st.error(e.diag.message_primary or str(e))