"""
Smoke test for _require_admin() and the /api/ai-settings gate (offline).

Confirms:
  1. The broken `firestore_client` import is gone (admin lookup works).
  2. A token whose Firestore role is 'admin' passes _require_admin.
  3. A customer/staff token is rejected with 403.
  4. A garbage token is rejected.
"""
import os
import sys

# Hermetic: don't touch Firestore from ai_assistant imports.
os.environ.setdefault("AI_SETTINGS_PERSIST", "0")
os.environ.setdefault("AI_QUOTA_PERSIST", "0")
os.environ.setdefault("FIREBASE_CREDENTIALS",
                      "../ai_assistant/caltex-autopro-1e664-firebase-adminsdk-fbsvc-07b4fc625e.json")

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # app dir
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))                  # tests dir

from unittest.mock import patch, MagicMock
import caltexautopro

app = caltexautopro.app
client = app.test_client()

PASS = 0
FAIL = 0
def check(name, cond, detail=""):
    global PASS, FAIL
    if cond: PASS += 1; print(f"  PASS  {name}")
    else:    FAIL += 1; print(f"  FAIL  {name}  {detail}")


# ── 1. module import sanity: legacy broken import must not be referenced ──────
src = open("caltexautopro.py", encoding="utf-8").read()
check("no dead 'firestore_client' admin import remains",
      "from firestore_client import get_db as _get_admin" not in src)

# ── 2. admin token → 200 ──────────────────────────────────────────────────────
def _fake_verify(token_str):
    return {"uid": "admin-uid-1", "admin": False, "role": "customer"}  # claims carry nothing — role must come from Firestore

def _fake_doc(role):
    doc = MagicMock()
    doc.exists = role is not None
    doc.to_dict.return_value = {"role": role} if role else {}
    return doc

with patch.object(caltexautopro.fb_auth, "verify_id_token", side_effect=_fake_verify), \
     patch("firebase_admin.firestore.client") as _fc:
    db = MagicMock()
    db.collection.return_value.document.return_value.get.side_effect = (
        lambda: _fake_doc("admin")
    )
    _fc.return_value = db

    r = client.get("/api/ai-settings", headers={"Authorization": "Bearer good-token"})
    check("admin Firestore role passes the gate (no 403)", r.status_code != 403,
          f"got {r.status_code}: {r.get_data(as_text=True)[:80]}")
    if r.status_code == 200:
        body = r.get_json()
        check("admin GET returns settings", "settings" in body)
        check("admin GET returns overview", "overview" in body)

    # ── 3. customer/staff token → 403 ─────────────────────────────────────────
    db.collection.return_value.document.return_value.get.side_effect = (
        lambda: _fake_doc("customer")
    )
    r2 = client.get("/api/ai-settings", headers={"Authorization": "Bearer cust-token"})
    check("customer role rejected with 403", r2.status_code == 403, f"got {r2.status_code}")

    # PUT by customer also rejected
    r3 = client.put("/api/ai-settings", headers={"Authorization": "Bearer cust-token"},
                    json={"customer_ai_enabled": False})
    check("customer PUT rejected with 403", r3.status_code == 403, f"got {r3.status_code}")

    # ── 4. garbage token → 403 ─────────────────────────────────────────────────
    with patch.object(caltexautopro.fb_auth, "verify_id_token", side_effect=Exception("bad")):
        r4 = client.get("/api/ai-settings", headers={"Authorization": "Bearer garbage"})
        check("invalid token rejected with 403", r4.status_code == 403, f"got {r4.status_code}")

print(f"\nRESULT: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
