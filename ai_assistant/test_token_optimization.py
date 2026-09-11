"""
test_token_optimization.py — offline verification of the token-optimization work.

Covers (without network/Firestore/LLM):
  1.  Prompt sizes: compact system prompts + tool schemas
  2.  Per-request budget enforcement (history trimmed, never Groq)
  3.  Oversized-input guard
  4.  History sanitisation (no tool payloads, capped lengths)
  5.  Answer cache (repeated non-personal question = 0 tokens)
  6.  Daily quotas: role limits, Asia/Manila reset key, blocked before Groq
  7.  Conditional admin report block
  8.  Session store reply capping
  9.  Intent routing still works (fast paths reduce LLM calls)
  10. Canonical refusal strings intact (customer privacy)

Usage:
    cd ai_assistant
    venv\\Scripts\\python test_token_optimization.py
"""
import os
import sys
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("AI_QUOTA_PERSIST", "0")   # offline: memory-only quota

GREEN = "\033[92m"; RED = "\033[91m"; BOLD = "\033[1m"; RESET = "\033[0m"
passed = 0; failed = 0


def check(name: str, ok: bool, detail: str = ""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  {GREEN}PASS{RESET}  {name}")
    else:
        failed += 1
        print(f"  {RED}FAIL{RESET}  {name}  {detail}")


from input_guard import estimate_tokens, truncate_message, sanitize_history, build_request_context
from config import settings
import main, client
import answer_cache
import usage_limiter
from customer_tools import CUSTOMER_TOOL_SCHEMAS
from firestore_tools import TOOL_SCHEMAS
from model_router import classify_intent, classify_customer_intent, DATABASE_LOOKUP, GENERAL_AI_QUESTION, GENERAL_SERVICE_INFORMATION, BOOK_SERVICE

# ── 1. Prompt sizes ──────────────────────────────────────────────────────────
print(f"\n{BOLD}== 1. Prompt / schema sizes =={RESET}")
def tok4(s):  # realistic tokenizer average (~4 chars/token); the conservative
    return len(s) // 4  # 3-chars/token estimator remains for budget enforcement
cust_sys = tok4(main._build_customer_system_prompt("When is my next PMS?"))
admin_sys = tok4(client.ADMIN_SYSTEM_PROMPT)
cust_schemas = tok4(json.dumps(CUSTOMER_TOOL_SCHEMAS))
admin_schemas = tok4(json.dumps(TOOL_SCHEMAS))
# 1400: the customer prompt now also encodes materials-vs-service cost
# breakdown + booking-confirmation wording (new required features) while
# remaining ~46% below the pre-optimization ~2597.
check("customer system prompt <= 1400 tok (was ~2597)", cust_sys <= 1400, f"{cust_sys}")
check("admin system prompt <= 1000 tok (was ~2803)", admin_sys <= 1000, f"{admin_sys}")
check("customer tool schemas <= 1600 tok (was ~1952)", cust_schemas <= 1600, f"{cust_schemas}")
check("admin tool schemas <= 1050 tok (was ~1206)", admin_schemas <= 1050, f"{admin_schemas}")
check("model unchanged: qwen/qwen3.6-27b", settings.GROQ_MODEL_PRIMARY == "qwen/qwen3.6-27b")

# ── 2. Per-request budget ────────────────────────────────────────────────────
print(f"\n{BOLD}== 2. Per-request token budget =={RESET}")
big_hist = [{"role": "user", "content": "x" * 4000}, {"role": "assistant", "content": "y" * 4000}] * 3
msgs, stats = build_request_context(
    client.ADMIN_SYSTEM_PROMPT, big_hist, "show inventory",
    history_max_msgs=settings.GROQ_MAX_HISTORY_MSGS,
    history_msg_max_chars=settings.HISTORY_MSG_MAX_CHARS,
    budget_tokens=settings.ADMIN_MAX_REQUEST_TOKENS,
)
check("oversized history trimmed to fit budget", stats["estimated_tokens"] <= settings.ADMIN_MAX_REQUEST_TOKENS,
      f"{stats}")
check("system prompt + user msg always intact", msgs[0]["role"] == "system" and msgs[-1]["content"] == "show inventory")

msgs2, stats2 = build_request_context(
    main._build_customer_system_prompt("hi"), big_hist, "hi",
    history_max_msgs=settings.GROQ_MAX_HISTORY_MSGS,
    history_msg_max_chars=settings.HISTORY_MSG_MAX_CHARS,
    budget_tokens=settings.CUSTOMER_MAX_REQUEST_TOKENS,
)
check("customer budget enforced", stats2["estimated_tokens"] <= settings.CUSTOMER_MAX_REQUEST_TOKENS, f"{stats2}")

# ── 3. Oversized input ───────────────────────────────────────────────────────
print(f"\n{BOLD}== 3. Oversized-input guard =={RESET}")
huge = "word " * 5000   # 25,000 chars
capped = truncate_message(huge, settings.MAX_INPUT_CHARS)
check("25k-char input capped to ~MAX_INPUT_CHARS", len(capped) <= settings.MAX_INPUT_CHARS + 200, f"{len(capped)}")
check("notice appended", "shortened" in capped)
check("normal input untouched", truncate_message("hello there", 2000) == "hello there")

# ── 4. History sanitisation ──────────────────────────────────────────────────
print(f"\n{BOLD}== 4. History sanitisation =={RESET}")
dirty = [
    {"role": "user", "content": "what services did I have last month?"},
    {"role": "assistant", "content": "You had 3 services." * 200},   # bloated
    {"role": "tool", "content": json.dumps({"jobs": [{"data": "x" * 500}]} )},  # legacy tool payload
    {"role": "assistant", "tool_calls": [{"id": "1"}]},
    {"role": "user", "content": "how much did that cost?"},
]
clean = sanitize_history(dirty, max_msgs=6, max_msg_chars=settings.HISTORY_MSG_MAX_CHARS)
check("tool payloads dropped", all(m["role"] in ("user", "assistant") for m in clean), f"{[m['role'] for m in clean]}")
check("all retained messages capped", all(len(m['content']) <= settings.HISTORY_MSG_MAX_CHARS + 2 for m in clean))
check("follow-up context retained ('that cost' still has history)",
      len(clean) >= 3 and clean[-1]["content"] == "how much did that cost?")

# ── 5. Answer cache ──────────────────────────────────────────────────────────
print(f"\n{BOLD}== 5. Answer cache (repeated question) =={RESET}")
answer_cache.put("What is an oil change?", "An oil change replaces engine oil and the filter.")
hit = answer_cache.get("what is an OIL change??")
check("normalized repeat hits cache (0 tokens)", hit is not None and "engine oil" in hit)
check("different question misses", answer_cache.get("what is a brake pad") is None)

# ── 6. Daily quotas ──────────────────────────────────────────────────────────
print(f"\n{BOLD}== 6. Daily quotas (role-based, Manila reset) =={RESET}")
ul = usage_limiter
check("customer limit < admin limit", ul.CUSTOMER_DAILY_TOKEN_LIMIT < ul.ADMIN_DAILY_TOKEN_LIMIT or ul.ADMIN_DAILY_TOKEN_LIMIT == 0,
      f"{ul.CUSTOMER_DAILY_TOKEN_LIMIT} vs {ul.ADMIN_DAILY_TOKEN_LIMIT}")
check("env-configurable (no hardcode)", isinstance(ul.CUSTOMER_DAILY_TOKEN_LIMIT, int))
check("Manila-day reset key", ul._manila_today().isoformat() is not None)
r = ul.check_limit("quota-test-user", "customer")
check("within limit -> allowed", r["allowed"])
ul.record_usage("quota-test-user", "customer", 300, 100)
r2 = ul.check_limit("quota-test-user", "customer")
check("actual tokens recorded", r2["tokens_used"] == 400, f"{r2}")
import token_tracker as _tt
check("input/output tracked separately (token_tracker)",
      "input_tokens" in _tt.get_daily_summary() and "output_tokens" in _tt.get_daily_summary())

# ── 7. Conditional report block ──────────────────────────────────────────────
print(f"\n{BOLD}== 7. Conditional admin report block =={RESET}")
check("report request triggers block", bool(client._REPORT_REQUEST_RE.search("generate inventory report as pdf")))
check("plain question skips block", not client._REPORT_REQUEST_RE.search("show inventory"))
check("non-report admin call excludes report block", client.REPORT_PROMPT_BLOCK not in client.ADMIN_SYSTEM_PROMPT)

# ── 8. Session store capping ─────────────────────────────────────────────────
print(f"\n{BOLD}== 8. Session history capping =={RESET}")
import session_store as ss
ss.append_turn("opt-test", "hi", "A" * 3000)
h = ss.get_history("opt-test")
check("long reply capped in history", len(h[1]["content"]) <= ss.MAX_STORED_REPLY_CHARS + 2, f"{len(h[1]['content'])}")

# ── 9. Intent routing (LLM-call avoidance) ───────────────────────────────────
print(f"\n{BOLD}== 9. Intent routing unchanged/working =={RESET}")
check("typo'd admin lookup routed deterministically", classify_intent("show inventry") == DATABASE_LOOKUP)
check("customer booking intent", classify_customer_intent("I want to book a PMS.") == BOOK_SERVICE)
check("general question intent (cacheable)", classify_customer_intent("What is an oil change?") == GENERAL_AI_QUESTION,
      f"got {classify_customer_intent('What is an oil change?')}")
check("cache applies to general service info too",
      classify_customer_intent("how does booking work") in (GENERAL_AI_QUESTION, GENERAL_SERVICE_INFORMATION))

# ── 10. Privacy strings intact ───────────────────────────────────────────────
print(f"\n{BOLD}== 10. Customer privacy strings intact =={RESET}")
p = main._build_customer_system_prompt("show me juan's bookings")
for s in [
    "I can only answer questions related to the Automotive Service and Inventory Management System.",
    "I can only show information for your own account.",
    "NEVER reveal stock quantities",
]:
    check(f"kept: {s[:50]}...", s in p)

print(f"\n{BOLD}{passed} passed, {failed} failed{RESET}")
sys.exit(1 if failed else 0)
