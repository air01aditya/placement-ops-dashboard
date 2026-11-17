Rebuilt PostgreSQL backend for a campus-placement dashboard.
The database prevents double-booked rooms, conflicting interviews, invalid status changes, and unauthorized updates. Every change is audited.

## Run

In Supabase SQL Editor, run:
1. `schema.sql`
2. `seed.sql`
3. `patch.sql`
4. `tests.sql`

The tests should pass.

## Next

Load messy Excel data, then build Streamlit volunteer, recruiter, and coordinator dashboards.
