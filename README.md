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
Streamlit screens for room volunteers, recruiters, and the coordinator.
Put `DATABASE_URL` in a `.env` file, then run `streamlit run app/volunteer.py` (or `recruiter.py`, `coordinator.py`).

## Next
Dashboard charts, then live-day hardening.
