import random
import pandas as pd

random.seed(1)
colleges = ["North Valley Institute", "Metro Engineering College", "Lakeside University"]
rows = []
for i in range(1, 61):
    rows.append({
        "Name": f"New Student {i:02d}",
        "Email": f"student{i:02d}@mail.test",
        "Phone": f"9{random.randint(100000000, 999999999)}",
        "College": random.choice(colleges),
        "Graduation Year": 2026,
    })

rows[3]["Name"] = "  " + rows[3]["Name"] + "  "
rows[5]["Email"] = rows[5]["Email"].upper()
rows[7]["Email"] = None
rows[9]["Phone"] = "+91 " + rows[9]["Phone"]
rows[11]["Phone"] = rows[11]["Phone"][:6]
rows[13]["College"] = rows[13]["College"].lower()
rows[15]["Graduation Year"] = "twenty26"
rows.append(dict(rows[2]))
rows.append(dict(rows[20]))

pd.DataFrame(rows).to_excel("data/candidates_messy.xlsx", index=False)
print("done", len(rows), "rows")