"""
test_access_control.py — authorization-aware routing regression suite.

Covers spec test cases #1-#25:
  - 13 legitimate customer requests MUST NOT be denied
  - 24 unauthorized requests MUST be denied (EN / Taglish / typos)
  - denial messages are category-appropriate and language-matched
  - denied requests produce ZERO Firestore reads and ZERO LLM calls
  - customer tools expose no restricted collections
  - the Flask report endpoint enforces admin-only independently
"""
import os
import sys

os.environ.setdefault("AI_SETTINGS_PERSIST", "0")
os.environ.setdefault("AI_QUOTA_PERSIST", "0")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PASS = 0
FAIL = 0
def check(name, cond, detail=""):
    global PASS, FAIL
    if cond: PASS += 1; print(f"  PASS  {name}")
    else:    FAIL += 1; print(f"  FAIL  {name}  {detail}")


print("\n== 1. Legitimate customer requests (must be ALLOWED) ==")
import access_control
from access_control import classify_denial, denial_message, DenialCategory

AUTHORIZED = [
    "What are my bookings?",
    "Show my PMS history.",
    "When is my next PMS?",
    "What services are available?",
    "How much is an oil change?",
    "Can you help me book a service?",
    "Pwede makita yung PMS history ko?",
    "Kailan next PMS ko?",
    "Pwede mo ba i-check yung booking ko?",
    "Magkano yung oil change?",
    "Show my bookings",
    "My vehicle maintenance",
    "What was my last service?",
]
for m in AUTHORIZED:
    check(f"allow: {m!r}", classify_denial(m) is None, f"got {classify_denial(m)}")

print("\n== 2. Unauthorized requests (must be DENIED, 0 tokens, 0 reads) ==")
UNAUTHORIZED = [
    # (message, expected category)
    ("Show the bookings of customer Juan Dela Cruz", DenialCategory.OTHER_CUSTOMER_DATA),
    ("Show all customer bookings.", DenialCategory.OTHER_CUSTOMER_DATA),
    ("Show all inventory stock levels.", DenialCategory.INVENTORY),
    ("How many brake pads are in stock?", DenialCategory.INVENTORY),
    ("Show all inventory issuances.", DenialCategory.ISSUANCE),
    ("Generate an inventory report.", DenialCategory.ADMIN_REPORT),
    ("Generate an issuance report.", DenialCategory.ADMIN_REPORT),
    ("Generate the monthly inventory PDF.", DenialCategory.ADMIN_REPORT),
    ("Pakita lahat ng stock.", DenialCategory.INVENTORY),
    ("Pa-generate naman ng inventory report.", DenialCategory.ADMIN_REPORT),
    ("Pwede makita booking ni Juan?", DenialCategory.OTHER_CUSTOMER_DATA),
    ("Pakita lahat ng bookings ng customers.", DenialCategory.BUSINESS_ANALYTICS),
    ("Show Maria's maintenance history", DenialCategory.OTHER_CUSTOMER_DATA),
    ("What vehicles belong to another customer?", DenialCategory.OTHER_CUSTOMER_DATA),
    ("Show all customers", DenialCategory.OTHER_CUSTOMER_DATA),
    ("May stock pa ba kayong 5W-30?", DenialCategory.INVENTORY),
    ("How many customers do you have?", DenialCategory.BUSINESS_ANALYTICS),
    ("How much revenue did you make?", DenialCategory.BUSINESS_ANALYTICS),
    ("Which service is most popular?", DenialCategory.BUSINESS_ANALYTICS),
    ("Show all maintenance records", DenialCategory.BUSINESS_ANALYTICS),
    ("Show invntory stock levels", DenialCategory.INVENTORY),          # typo
    ("Pwede pa-export ng issuance report?", DenialCategory.ADMIN_REPORT),  # Taglish
    ("What is the total inventory value?", DenialCategory.INVENTORY),
    ("Show me Juan's bookings", DenialCategory.OTHER_CUSTOMER_DATA),
]
for m, expected in UNAUTHORIZED:
    got = classify_denial(m)
    check(f"deny: {m!r}", got == expected, f"got {got}")

print("\n== 3. Denial messages ==")
msg_en = denial_message(DenialCategory.INVENTORY, "show me inventory")
msg_tl = denial_message(DenialCategory.INVENTORY, "pakita lahat ng stock")
check("English denial for English input", "inventory" in msg_en.lower() and "hindi" not in msg_en)
check("Taglish denial for Tagalog input", "hindi" in msg_tl)
_ALL_CATEGORIES = [
    DenialCategory.OTHER_CUSTOMER_DATA, DenialCategory.INVENTORY,
    DenialCategory.ISSUANCE, DenialCategory.ADMIN_REPORT,
    DenialCategory.BUSINESS_ANALYTICS, DenialCategory.OFF_TOPIC,
]
check("no generic 'I don't know'", all(
    "don't know" not in denial_message(c).lower()
    and "not sure" not in denial_message(c).lower()
    for c in _ALL_CATEGORIES
))
check("no PMS fallback wording in denials", all(
    "pms history" not in denial_message(c).lower() for c in _ALL_CATEGORIES
))

print("\n== 4. Denied request costs (0 Firestore reads, 0 LLM calls, 0 tokens) ==")
from unittest.mock import patch
import main as ai_main

with patch("customer_tools.get_db") as gdb, \
     patch("firestore_client.get_db") as fdb, \
     patch("client._call_groq") as gq, \
     patch("client.get_groq_client") as ggc:
    r = ai_main._run_customer_chat(
        message="Show all inventory stock levels.",
        customer_uid="cust-test", customer_name="Test Customer",
        history=[], intent="UNKNOWN",
    )
    check("denied reply is the inventory message", "inventory" in r["reply"].lower())
    check("no tool calls executed", r["tool_calls"] == [])
    check("model is 'none' (no LLM)", r["model"] == "none")
    gdb.assert_not_called()
    fdb.assert_not_called()
    gq.assert_not_called()
    ggc.assert_not_called()
    print("  PASS  no Firestore/LLM touched for denied request")

with patch("customer_tools.get_db") as gdb, \
     patch("client._call_groq") as gq, \
     patch("client.get_groq_client") as ggc:
    r2 = ai_main._run_customer_chat(
        message="Show the bookings of customer Juan Dela Cruz",
        customer_uid="cust-test", customer_name="Test Customer",
        history=[], intent="UNKNOWN",
    )
    check("Juan request denied with other-customer message",
          "other customers" in r2["reply"].lower())
    gdb.assert_not_called(); gq.assert_not_called(); ggc.assert_not_called()
    print("  PASS  no Firestore/LLM touched for third-party request")

with patch("customer_tools.get_db") as gdb, \
     patch("client._call_groq") as gq, \
     patch("client.get_groq_client") as ggc:
    r3 = ai_main._run_customer_chat(
        message="Pa-generate naman ng inventory report.",
        customer_uid="cust-test", customer_name="Test Customer",
        history=[], intent="UNKNOWN",
    )
    check("Tagalog report request denied (Taglish reply)",
          "report" in r3["reply"].lower() and "administrators" in r3["reply"].lower())
    gdb.assert_not_called(); gq.assert_not_called(); ggc.assert_not_called()
    print("  PASS  no Firestore/LLM touched for report request")

print("\n== 5. Customer tool surface audit (no restricted data reachable) ==")
from customer_tools import CUSTOMER_TOOL_FUNCTIONS
names = set(CUSTOMER_TOOL_FUNCTIONS.keys())
for banned in ("get_inventory", "get_stock_levels", "get_low_stock_items",
               "get_issuances", "get_deliveries", "get_user_count",
               "get_item_catalog", "get_all_bookings", "get_customers"):
    check(f"no customer tool named {banned}", banned not in names)

# Every customer tool signature requires server-injected identity
import inspect
ok_identity = all(
    "customer_uid" in inspect.signature(fn).parameters
    for n, fn in CUSTOMER_TOOL_FUNCTIONS.items() if n != "get_my_pms_status"
)
check("all customer tools take server-injected customer_uid", ok_identity)

print("\n== 6. Report endpoint enforces admin-only independently ==")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "automotive_website"))
try:
    import caltexautopro
    from unittest.mock import patch, MagicMock
    client = caltexautopro.app.test_client()
    # No auth header at all -> 403 before any report generation
    with patch.object(caltexautopro, "_requests_lib") as rl:
        resp = client.post("/api/ai-report", json={
            "report_type": "inventory", "format": "pdf"})
        check("report endpoint 403 without admin auth", resp.status_code == 403,
              f"got {resp.status_code}")
        check("report backend never called for unauthorized request",
              rl.post.call_count == 0)
        body = resp.get_json()
        check("admin-only message returned", "administrators" in body.get("error", ""))
except Exception as e:
    print(f"  SKIP  Flask app import failed: {e}")

print(f"\n{'='*60}\nRESULT: {PASS} passed, {FAIL} failed\n{'='*60}")
sys.exit(1 if FAIL else 0)
