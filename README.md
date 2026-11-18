Rebuilt PostgreSQL backend for a campus-placement dashboard.
The database prevents:
double-booked rooms, conflicting interviews, invalid status changes, and unauthorized updates.
Every change is audited.

## Run
In Supabase SQL Editor, run:
1. `schema.sql`
2. `seed.sql`
3. `patch.sql`
4. `tests.sql`
The tests should pass.

## Screens
One Streamlit app with login: `streamlit run app/main.py`
- Volunteers see only their own room, refreshed every 5 seconds
- Recruiters see only their own company
- The coordinator sees all rooms and can undo a wrong tap

Live read-only dashboard: https://placement-ops-aditya.streamlit.app

## Future work
Separate password per user, an admin screen to add candidates.
