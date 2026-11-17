import os
from urllib.parse import urlparse
from dotenv import load_dotenv

load_dotenv()
u = urlparse(os.environ["DATABASE_URL"])
print("user:", repr(u.username))
print("host:", u.hostname, "port:", u.port)
print("password length:", len(u.password or ""))
print("only letters and digits:", (u.password or "").isalnum())