import os
import psycopg2
import streamlit as st
from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv(usecwd=True))
st.set_page_config(page_title="Placement Ops", layout="centered")


def run(sql, params=None, fetch=True):
    conn = psycopg2.connect(os.environ["DATABASE_URL"])
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(sql, params)
                return cur.fetchall() if fetch else None
    finally:
        conn.close()


def login_screen():
    st.title("Placement Ops")
    email = st.text_input("Email")
    password = st.text_input("Password", type="password")
    if st.button("Log in"):
        rows = run("""
            SELECT user_id, full_name, role, company_id FROM users
            WHERE email = %s AND password_hash = crypt(%s, password_hash)
        """, (email.strip().lower(), password))
        if rows:
            st.session_state.user = rows[0]
            st.rerun()
        else:
            st.error("Wrong email or password.")


def volunteer_view(user):
    user_id = user[0]
    room = run("""
        SELECT r.room_id, r.room_name FROM room_volunteers rv
        JOIN rooms r ON r.room_id = rv.room_id WHERE rv.user_id = %s
    """, (user_id,))
    room_id, room_name = room[0]
    st.title(room_name)
    st.caption("Updates every 5 seconds")

    NEXT = {
        "In queue": ("Start interview", "Interviewing"),
        "Interviewing": ("Mark done", "Done"),
    }

    @st.fragment(run_every=5)
    def queue():
        rows = run("""
            SELECT q.queue_entry_id, c.full_name, co.company_name, q.status, q.version
            FROM queue_entries q
            JOIN candidates c ON c.candidate_id = q.candidate_id
            JOIN room_allocations a ON a.allocation_id = q.allocation_id
            JOIN rounds ro ON ro.round_id = a.round_id
            JOIN companies co ON co.company_id = ro.company_id
            WHERE a.room_id = %s AND q.status <> 'Done'
            ORDER BY CASE q.status WHEN 'Interviewing' THEN 0 ELSE 1 END, q.queue_entry_id
            LIMIT 15
        """, (room_id,))
        if not rows:
            st.info("Nobody waiting in this room.")
        for entry_id, name, company, status, version in rows:
            c1, c2, c3 = st.columns([3, 2, 2])
            c1.write(f"**{name}**  \n{company}")
            c2.write(status)
            label, new_status = NEXT[status]
            if c3.button(label, key=f"b{entry_id}"):
                try:
                    run("SELECT change_status(%s, %s, %s, %s)",
                        (entry_id, new_status, user_id, version), fetch=False)
                    st.rerun()
                except psycopg2.Error as e:
                    st.error(e.diag.message_primary or str(e))

    queue()


def recruiter_view(user):
    user_id, company_id = user[0], user[3]
    company = run("SELECT company_name FROM companies WHERE company_id = %s", (company_id,))[0][0]
    st.title(company)

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
            key=f"r{entry_id}", label_visibility="collapsed")
        new_outcome = c3.selectbox(
            "Outcome", OUTCOMES,
            index=OUTCOMES.index(outcome) if outcome else 0,
            key=f"o{entry_id}", label_visibility="collapsed")
        if c4.button("Save", key=f"s{entry_id}"):
            if new_rating == rating and new_outcome == outcome:
                st.info("No change to save.")
            else:
                try:
                    run("SELECT change_evaluation(%s, %s::smallint, %s, %s, %s)",
                        (entry_id, new_rating, new_outcome, user_id, version), fetch=False)
                    st.rerun()
                except psycopg2.Error as e:
                    st.error(e.diag.message_primary or str(e))


def coordinator_view(user):
    user_id = user[0]
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
        GROUP BY r.room_id, r.room_name ORDER BY r.room_id
    """)
    st.dataframe(
        [{"Room": s[0], "In queue": s[1], "Interviewing": s[2], "Done": s[3]} for s in summary],
        width="stretch", hide_index=True)

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

    BACK = {"Interviewing": ("Back to queue", "In queue"),
            "Done": ("Back to interviewing", "Interviewing")}
    for entry_id, name, company, status, version in rows:
        c1, c2, c3 = st.columns([3, 2, 3])
        c1.write(f"**{name}**  \n{company}")
        c2.write(status)
        label, target = BACK[status]
        if c3.button(label, key=f"u{entry_id}"):
            try:
                run("SELECT change_status(%s, %s, %s, %s)",
                    (entry_id, target, user_id, version), fetch=False)
                st.rerun()
            except psycopg2.Error as e:
                st.error(e.diag.message_primary or str(e))


user = st.session_state.get("user")
if not user:
    login_screen()
    st.stop()

st.sidebar.write(f"{user[1]}")
if st.sidebar.button("Log out"):
    del st.session_state["user"]
    st.rerun()

if user[2] == "room_volunteer":
    volunteer_view(user)
elif user[2] == "recruiter":
    recruiter_view(user)
else:
    coordinator_view(user)