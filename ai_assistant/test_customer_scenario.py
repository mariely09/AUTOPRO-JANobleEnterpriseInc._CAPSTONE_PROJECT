"""
test_customer_scenario.py — end-to-end acceptance test for the Customer AI
Assistant, following the manual QA test case step by step.

Uses FastAPI TestClient with mocked Firestore data so it runs offline but
exercises the REAL endpoint logic (auth, gating, routing, session store).
"""
import os
import sys

os.environ.setdefault("AI_SETTINGS_PERSIST", "0")
os.environ.setdefault("AI_QUOTA_PERSIST", "0")

# Windows console (cp1252) cannot print ₱ / Filipino text — force UTF-8.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient

import main as ai_main
from main import app

client = TestClient(app)

PASS = 0
FAIL = 0
def check(step, name, cond, detail=""):
    global PASS, FAIL
    if cond: PASS += 1; print(f"  PASS  [{step}] {name}")
    else:    FAIL += 1; print(f"  FAIL  [{step}] {name}  {detail}")

UID = "test-customer-uid-1"
NAME = "Test Customer"

def chat(message, session_id=None, history=None):
    r = client.post("/customer/chat", json={
        "message": message,
        "customer_uid": UID,
        "customer_name": NAME,
        "session_id": session_id,
        "history": history or [],
    })
    assert r.status_code == 200, f"HTTP {r.status_code}: {r.text[:200]}"
    return r.json()


# ── Mock Firestore data layer ─────────────────────────────────────────────────
def _fake_doc(data):
    doc = MagicMock()
    doc.exists = True
    doc.id = "doc1"
    doc.to_dict.return_value = data
    return doc

class FakeQuery:
    """Chainable fake Firestore query: .where().where().stream()"""
    def __init__(self, docs): self._docs = docs
    def where(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def order_by(self, *a, **k): return self
    def stream(self): return iter(self._docs)
    def get(self): return list(self._docs)

def _vehicles():
    return [
        _fake_doc({"plate": "ABC-1234", "make": "Toyota", "model": "Vios",
                   "year": "2020", "desc": "Toyota Vios 2020", "type": "Sedan",
                   "status": "Due Soon", "ownerId": UID,
                   "lastServiceDate": "2026-05-10", "serviceFrequency": "6"}),
        _fake_doc({"plate": "XYZ-5678", "make": "Honda", "model": "City",
                   "year": "2021", "desc": "Honda City 2021", "type": "Sedan",
                   "status": "Active", "ownerId": UID,
                   "lastServiceDate": "2026-08-01", "serviceFrequency": "6"}),
    ]

def _jobs():
    return [
        _fake_doc({"plate": "ABC-1234", "ownerId": UID,
                   "services": ["Change Oil"], "materials": [],
                   "cost": 500, "date": "2026-05-10", "status": "Completed"}),
        _fake_doc({"plate": "XYZ-5678", "ownerId": UID,
                   "services": ["PMS"], "materials": [],
                   "cost": 1500, "date": "2026-08-01", "status": "Completed"}),
    ]

def _db():
    """Fake db: vehicles where(ownerId==UID) -> 2 vehicles; maintenance similar."""
    db = MagicMock()
    def collection(name):
        c = MagicMock()
        if name == "vehicles":
            c.where.return_value = FakeQuery(_vehicles())
            c.stream.return_value = iter(_vehicles())
            c.document.return_value.get.return_value = _fake_doc(
                {"role": "customer", "name": NAME, "companyName": ""})
        elif name in ("maintenance", "maintenance_jobs"):
            c.where.return_value = FakeQuery(_jobs())
            c.stream.return_value = iter(_jobs())
        elif name == "item_master":
            c.where.return_value = FakeQuery([
                _fake_doc({"name": "Change Oil", "type": "Service", "cost": 500,
                           "group": "Lubricant Services", "uom": "service"}),
                _fake_doc({"name": "PMS", "type": "Service", "cost": 1500,
                           "group": "Preventive Maintenance", "uom": "service"}),
            ])
            c.stream.return_value = iter([])
        elif name == "service_bookings":
            c.where.return_value = FakeQuery([])
            c.stream.return_value = iter([])
            c.document.return_value.get.return_value = _fake_doc({})
        else:
            c.where.return_value = FakeQuery([])
            c.stream.return_value = iter([])
            c.document.return_value.get.return_value = _fake_doc({})
        return c
    db.collection = collection
    return db


print("=" * 68)
print("SCENARIO: Customer AI Assistant — full acceptance test case")
print("=" * 68)

with patch("customer_tools.get_db", _db), \
     patch("firestore_client.get_db", _db), \
     patch("cache_manager.get_service_catalog", return_value=[
         {"name": "Change Oil", "type": "Service", "cost": 500,
          "group": "Lubricant Services", "uom": "service"},
         {"name": "PMS", "type": "Service", "cost": 1500,
          "group": "Preventive Maintenance", "uom": "service"},
     ]):
    # ── Step 1-2: "Show my service history." ──────────────────────────────────
    print("\n-- Step 1-2: Show my service history --")
    r = chat("Show my service history.")
    reply = r["reply"].lower()
    check("1-2", "reply received", len(r["reply"]) > 10, r["reply"][:80])
    check("1-2", "no other-customer leak (only own data)",
          "juan" not in reply and "maria" not in reply)
    check("1-2", "mentions records/history or no-records message",
          ("record" in reply or "history" in reply or "no completed" in reply or
           "haven't" in reply or "don't have" in reply), r["reply"][:100])

    # ── Step 3-4: "Show my vehicles." ─────────────────────────────────────────
    print("\n-- Step 3-4: Show my vehicles --")
    r = chat("Show my vehicles.")
    reply = r["reply"]
    check("3-4", "reply received", len(reply) > 10)
    check("3-4", "shows own plates only",
          ("ABC-1234" in reply or "XYZ-5678" in reply or
           "don't have any registered vehicles" in reply),
          reply[:100])
    check("3-4", "includes PMS/maintenance status",
          any(w in reply.lower() for w in ("status", "active", "due", "overdue")),
          reply[:100])

    # ── Step 5: "Show all inventory stock levels." — DENY ────────────────────
    print("\n-- Step 5: inventory request must be refused --")
    r = chat("Show all inventory stock levels.")
    reply = r["reply"].lower()
    check("5", "refused (restricted message)", "inventory" in reply or "restricted" in reply
          or "staff" in reply or "administrators" in reply, r["reply"][:100])
    check("5", "no stock data leaked", "quantity" not in reply and "units" not in reply)
    check("5", "no LLM/tool processing used", r["tool_calls"] == [])

    # ── Step 6: "Generate an inventory report." — DENY ────────────────────────
    print("\n-- Step 6: report generation must be refused --")
    r = chat("Generate an inventory report.")
    reply = r["reply"].lower()
    check("6", "refused (admin-only)", "administrator" in reply or "admin" in reply,
          r["reply"][:100])

    # ── Step 7: "How much is an Oil Change service?" ─────────────────────────
    print("\n-- Step 7: oil change price --")
    r = chat("How much is an Oil Change service?")
    reply = r["reply"]
    check("7", "reply received", len(reply) > 5)
    check("7", "contains price (₱500 or falls back gracefully)",
          ("500" in reply or "₱" in reply or "catalog" in reply.lower()
           or "contact us" in reply.lower()), reply[:120])

    # ── Step 8: empty message ─────────────────────────────────────────────────
    print("\n-- Step 8: empty message handled gracefully --")
    r = chat("")
    check("8", "friendly prompt, no crash", "type a question" in r["reply"].lower())

    # ── Step 9: invalid characters @#$%^&* ───────────────────────────────────
    print("\n-- Step 9: invalid characters handled gracefully --")
    r = chat("@#$%^&*")
    check("9", "graceful response", "didn't understand" in r["reply"].lower()
          or "type a question" in r["reply"].lower(), r["reply"][:80])

    # ── Step 10: Clear Chat → "What was my previous question?" ───────────────
    print("\n-- Step 10: Clear Chat removes context --")
    # Send first message in a session
    s = "scenario-session-1"
    r1 = chat("What was my last service?", session_id=s)
    # Simulate Clear Chat: delete the server-side session (frontend calls
    # DELETE /session/{id} then starts fresh)
    d = client.delete(f"/session/{s}")
    check("10", "session delete endpoint works", d.status_code == 200, str(d.status_code))
    # Ask about previous question with the SAME session id — context must be gone
    r2 = chat("What was my previous question?", session_id=s)
    reply = r2["reply"].lower()
    check("10", "cannot recall earlier question",
          ("no previous conversation" in reply or "didn't" in reply
           or "fresh" in reply or "no earlier" in reply or "not able" in reply
           or "sorry" in reply), r2["reply"][:120])
    check("10", "previous service answer NOT recalled",
          "change oil" not in reply and "500" not in reply)

    # ── Step 11: "What is the capital of Japan?" — scope refusal ──────────────
    print("\n-- Step 11: off-topic scope refusal --")
    r = chat("What is the capital of Japan?")
    check("11", "scope refusal message",
          "can only answer" in r["reply"].lower()
          or "automotive service" in r["reply"].lower(),
          r["reply"][:100])

    # ── Step 12: "Show another customer's service history." — DENY ───────────
    print("\n-- Step 12: another customer's history refused --")
    r = chat("Show another customer's service history.")
    reply = r["reply"].lower()
    check("12", "refused", "other customers" in reply or "own account" in reply
          or "only show" in reply or "don't have access" in reply, r["reply"][:100])
    check("12", "no PMS fallback", "here is your" not in reply
          and "here are your" not in reply)

    # ── Step 13: "Show the bookings of customer Juan Dela Cruz." — DENY ──────
    print("\n-- Step 13: Juan Dela Cruz's bookings refused --")
    r = chat("Show the bookings of customer Juan Dela Cruz.")
    reply = r["reply"].lower()
    check("13", "refused with own-account message",
          "other customers" in reply or "own account" in reply
          or "own booking" in reply, r["reply"][:100])

    # ── Steps 14-22: Chat History panel ───────────────────────────────────────
    # The persistent Chat History panel is a FRONTEND feature (localStorage
    # keyed per-customer uid + Firestore backup). The backend session_store is
    # only short-lived LLM context (60-min TTL). Verify both halves:
    print("\n-- Steps 14-22: Chat History lifecycle --")

    # (a) Backend half: conversation context persists while active and can be
    #     wiped per session (mirrors what Delete All Chats triggers).
    s1 = "hist-a"
    chat("What are my bookings?", session_id=s1)
    chat("Show my service history.", session_id=s1)
    from session_store import get_history as _gh, clear_session as _cs
    h = _gh(s1)
    check("14-15", "conversation turns stored with both sides",
          len(h) >= 4 and h[0]["role"] == "user" and h[1]["role"] == "assistant",
          f"got {len(h)} msgs")
    check("16", "stored turn mirrors the exact user query",
          any("what are my bookings" in (m.get("content") or "").lower() for m in h))
    _cs(s1)
    from session_store import session_info as _si
    check("17-18", "cleared conversation no longer returns messages",
          _gh(s1) == [] and _si(s1)["exists"] is False)

    # (b) Frontend half: the widget template must wire the full panel flow.
    widget_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                               "automotive_website", "templates",
                               "customer_smart_ai_widget.html")
    with open(widget_path, encoding="utf-8") as f:
        whtml = f.read()
    check("14-15", "panel: openHistory renders sessions with preview+time",
          "openHistory" in whtml and "ai-hist-item-preview" in whtml
          and "toLocaleTimeString" in whtml)
    check("16", "panel: history items are clickable and load the exact session",
          "loadSession" in whtml and "ai-hist-item" in whtml)
    check("19", "panel: Delete All Chats asks for confirmation",
          "confirm(" in whtml and "Delete all chat history?" in whtml)
    check("20-21", "panel: cancel keeps storage untouched (early return on false)",
          "if (!confirm(" in whtml and "localStorage.removeItem" in whtml)
    check("22-23", "panel: confirm wipes history + resets to empty welcome",
          "localStorage.removeItem(_storageKey" in whtml
          and "_rebuildWelcome()" in whtml)

print(f"\n{'='*68}\nRESULT: {PASS} passed, {FAIL} failed\n{'='*68}")
sys.exit(1 if FAIL else 0)

print(f"\n{'='*68}\nRESULT: {PASS} passed, {FAIL} failed\n{'='*68}")
sys.exit(1 if FAIL else 0)
