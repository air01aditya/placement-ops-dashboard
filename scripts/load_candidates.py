import os
import re
import pandas as pd
import psycopg2
from dotenv import load_dotenv

load_dotenv()


def text(v):
    return "" if pd.isna(v) else str(v).strip()


def clean_phone(v):
    digits = re.sub(r"\D", "", text(v))
    if len(digits) == 12 and digits.startswith("91"):
        digits = digits[2:]
    return digits


df = pd.read_excel("data/candidates_messy.xlsx", dtype=str)
good, bad, seen = [], [], set()

for i, r in df.iterrows():
    name = text(r["Name"])
    email = text(r["Email"]).lower()
    phone = clean_phone(r["Phone"])
    college = text(r["College"]).title()
    try:
        year = int(float(text(r["Graduation Year"])))
    except ValueError:
        year = None

    reason = None
    if not name:
        reason = "missing name"
    elif "@" not in email:
        reason = "missing or bad email"
    elif len(phone) != 10:
        reason = "bad phone"
    elif not college:
        reason = "missing college"
    elif year is None or not 2020 <= year <= 2100:
        reason = "bad graduation year"
    elif email in seen:
        reason = "duplicate in file"

    if reason:
        bad.append({"excel_row": i + 2, "reason": reason, **{k: text(v) for k, v in r.items()}})
    else:
        seen.add(email)
        good.append((name, email, "+91-" + phone, college, year))

conn = psycopg2.connect(os.environ["DATABASE_URL"])
cur = conn.cursor()
inserted = 0
for g in good:
    cur.execute(
        "INSERT INTO candidates (full_name, email, phone, college, graduation_year) "
        "VALUES (%s, %s, %s, %s, %s) ON CONFLICT DO NOTHING",
        g,
    )
    inserted += cur.rowcount
conn.commit()
conn.close()

pd.DataFrame(bad).to_csv("data/rejected_rows.csv", index=False)
print("rows in file:", len(df))
print("inserted:", inserted)
print("already in database (skipped):", len(good) - inserted)
print("rejected:", len(bad), "-> data/rejected_rows.csv")