"""
test_ai_settings.py - offline tests for the admin AI Usage Controls backend:
ai_settings store, usage_limiter enforcement (pause/limit/dev bypass),
and the /ai-settings endpoints.
"""
import os
import sys

# Hermetic: never touch real Firestore from tests.
os.environ["AI_SETTINGS_PERSIST"] = "0"
os.environ["AI_QUOTA_PERSIST"] = "0"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PASS = 0
FAIL = 0

def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


print("\n== 1. ai_settings defaults & sanitization ==")
import ai_settings

s = ai_settings.get_settings()
check("defaults: customer AI enabled", s["customer_ai_enabled"] is True)
check("defaults: no admin limit override", s["customer_token_limit"] == 0)
check("defaults: dev access disabled", s["dev_access_enabled"] is False)
check("get_settings returns a copy", ai_settings.get_settings() is not ai_settings.get_settings())

# dev access gates
check("dev blocked while disabled",
      ai_settings.dev_access_allowed(paused=False) is False)
ai_settings.clear_cache_for_tests()

print("\n== 2. save_settings sanitization ==")
saved = ai_settings.save_settings({"customer_token_limit": "-500", "evil_key": "x"})
check("negative limit clamped to 0", saved["customer_token_limit"] == 0)
check("unknown keys ignored", "evil_key" not in saved)
saved = ai_settings.save_settings({"customer_token_limit": "45000"})
check("string limit coerced to int", saved["customer_token_limit"] == 45000)
saved = ai_settings.save_settings({"customer_ai_enabled": False, "dev_access_enabled": True})
check("bool coercion", saved["customer_ai_enabled"] is False and saved["dev_access_enabled"] is True)

print("\n== 3. usage_limiter enforcement with settings ==")
import usage_limiter
import ai_settings as _as

_as.save_settings({"customer_token_limit": 1000, "dev_access_enabled": True, "dev_bypass_token_limit": True})
usage_limiter._reset_if_new_day()
usage_limiter._mirror.clear()

# Regular customer: admin override limit (1000) applies
lim, _req = usage_limiter._limits_for("customer")
check("admin override limit wins", lim == 1000, f"got {lim}")

# Dev bypass: token limit removed (0 = unlimited), request cap intact
lim2, req2 = usage_limiter._limits_for("customer", bypass_token_limit=True)
check("dev bypass removes token cap", lim2 == 0, f"got {lim2}")
check("request cap still enforced for dev", req2 > 0, f"got {req2}")

# check_limit end-to-end with bypass flag
usage_limiter._mirror.clear()
r = usage_limiter.check_limit("dev-user-1", role="customer", bypass_token_limit=True)
check("dev user passes check with bypass", r["allowed"] is True and r["token_limit"] == 0)
usage_limiter._mirror.clear()
r2 = usage_limiter.check_limit("cust-1", role="customer")
check("regular customer sees override limit", r2["token_limit"] == 1000)
usage_limiter._mirror.clear()

_as.save_settings({"customer_token_limit": 0, "dev_access_enabled": False,
                   "dev_bypass_token_limit": False, "customer_ai_enabled": True})
usage_limiter._mirror.clear()
lim3, _ = usage_limiter._limits_for("customer")
check("override 0 falls back to env default", lim3 == usage_limiter.CUSTOMER_DAILY_TOKEN_LIMIT, f"got {lim3}")

print("\n== 4. FastAPI endpoints ==")
from fastapi.testclient import TestClient  # noqa
try:
    from main import app
    client = TestClient(app)

    resp = client.get("/ai-settings")
    check("GET /ai-settings returns 200", resp.status_code == 200, f"got {resp.status_code}")
    body = resp.json()
    check("response has settings", "settings" in body)
    check("response has overview", "overview" in body)
    ov = body["overview"]
    for k in ("customer_tokens_used", "customer_token_limit", "customers_at_limit",
              "customer_ai_status", "next_reset"):
        check(f"overview has {k}", k in ov)

    resp2 = client.put("/ai-settings", json={"customer_ai_enabled": False,
                                             "customer_token_limit": 25000})
    check("PUT /ai-settings returns 200", resp2.status_code == 200, f"got {resp2.status_code}")
    check("PUT applied customer_ai_enabled=False",
          resp2.json()["settings"]["customer_ai_enabled"] is False)
    check("PUT applied limit 25000", resp2.json()["settings"]["customer_token_limit"] == 25000)

    resp3 = client.put("/ai-settings", json={"hacker_key": "nope"})
    check("PUT with no valid keys -> 400", resp3.status_code == 400, f"got {resp3.status_code}")

    # Restore safe defaults for other tests/suites
    client.put("/ai-settings", json={"customer_ai_enabled": True, "customer_token_limit": 0})
except ImportError as e:
    print(f"  SKIP  TestClient unavailable ({e})")

print("\n== 5. Customer chat pause enforcement (endpoint-level) ==")
try:
    from main import app
    from fastapi.testclient import TestClient
    import ai_settings
    client = TestClient(app)

    ai_settings.save_settings({"customer_ai_enabled": False})
    resp = client.post("/customer/chat", json={
        "message": "hello", "customer_uid": "u-test", "customer_name": "Tester",
    })
    body = resp.json()
    check("paused AI returns friendly message", "temporarily unavailable" in body.get("reply", ""),
          f"got: {body.get('reply', '')[:60]}")
    check("paused AI flags rate_limited", body.get("rate_limited") is True)

    # Dev user with while-paused access allowed through
    ai_settings.save_settings({"customer_ai_enabled": False, "dev_access_enabled": True,
                               "dev_access_while_paused": True, "dev_bypass_token_limit": True})
    resp2 = client.post("/customer/chat", json={
        "message": "hello", "customer_uid": "u-dev", "customer_name": "Dev",
        "is_dev_user": True,
    })
    body2 = resp2.json()
    check("dev user not paused-blocked", "temporarily unavailable" not in body2.get("reply", ""),
          f"got: {body2.get('reply', '')[:60]}")

    # Restore
    ai_settings.save_settings({"customer_ai_enabled": True})
except ImportError:
    pass

print(f"\n{'='*60}\nRESULT: {PASS} passed, {FAIL} failed\n{'='*60}")
sys.exit(1 if FAIL else 0)
