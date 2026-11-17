import os
import pandas as pd
import psycopg2
import streamlit as st
from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv(usecwd=True))
st.set_page_config(page_title="Dashboard", layout="wide")


def query(sql, cols):
    conn = psycopg2.connect(os.environ["DATABASE_URL"])
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
            return pd.DataFrame(cur.fetchall(), columns=cols)
    finally:
        conn.close()


st.title("Placement day dashboard")
if st.button("Refresh"):
    st.rerun()

status = query(
    "SELECT status, count(*) FROM queue_entries GROUP BY status",
    ["status", "n"],
).set_index("status")["n"]

m1, m2, m3, m4 = st.columns(4)
m1.metric("Total", int(status.sum()))
m2.metric("In queue", int(status.get("In queue", 0)))
m3.metric("Interviewing", int(status.get("Interviewing", 0)))
m4.metric("Done", int(status.get("Done", 0)))

left, right = st.columns(2)

with left:
    st.subheader("Rooms by status")
    rooms = query("""
        SELECT r.room_name, q.status, count(*)
        FROM queue_entries q
        JOIN room_allocations a ON a.allocation_id = q.allocation_id
        JOIN rooms r ON r.room_id = a.room_id
        GROUP BY r.room_name, q.status
    """, ["room", "status", "n"])
    st.bar_chart(rooms.pivot_table(index="room", columns="status", values="n", fill_value=0))

with right:
    st.subheader("Outcomes by company")
    out = query("""
        SELECT co.company_name, q.outcome, count(*)
        FROM queue_entries q
        JOIN room_allocations a ON a.allocation_id = q.allocation_id
        JOIN rounds ro ON ro.round_id = a.round_id
        JOIN companies co ON co.company_id = ro.company_id
        WHERE q.outcome IS NOT NULL
        GROUP BY co.company_name, q.outcome
    """, ["company", "outcome", "n"])
    st.bar_chart(out.pivot_table(index="company", columns="outcome", values="n", fill_value=0))

st.subheader("Latest changes")
hist = query("""
    SELECT h.changed_at, u.full_name, c.full_name,
           coalesce(h.old_status, '-') || ' -> ' || coalesce(h.new_status, '-'),
           h.remark
    FROM status_history h
    JOIN users u ON u.user_id = h.changed_by
    JOIN queue_entries q ON q.queue_entry_id = h.queue_entry_id
    JOIN candidates c ON c.candidate_id = q.candidate_id
    ORDER BY h.changed_at DESC, h.status_history_id DESC
    LIMIT 15
""", ["When", "By", "Candidate", "Status", "Note"])
st.dataframe(hist, width="stretch", hide_index=True)