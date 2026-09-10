"""
test_input_normalizer.py — offline unit tests for input normalization + intent routing.

Validates that typo'd, abbreviated, and informally-phrased prompts are routed to
the same deterministic fast paths as their clean equivalents, without any
network, Firestore, or LLM calls.

Usage:
    cd ai_assistant
    venv\\Scripts\\python test_input_normalizer.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from input_normalizer import normalize
from model_router import (
    classify_intent,
    classify_customer_intent,
    DATABASE_LOOKUP, DATABASE_CALCULATION,
    BOOK_SERVICE, MAINTENANCE_REMINDER, MY_SERVICE_HISTORY,
    REPORT_GENERATION,
)
from intent_classifier import classify_and_run

GREEN = "\033[92m"; RED = "\033[91m"; BOLD = "\033[1m"; RESET = "\033[0m"

passed = 0
failed = 0


def check(name: str, ok: bool, detail: str = ""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  {GREEN}PASS{RESET}  {name}")
    else:
        failed += 1
        print(f"  {RED}FAIL{RESET}  {name}  {detail}")


print(f"\n{BOLD}== Normalizer =={RESET}")
for raw, want in [
    ("show inventry", "show inventory"),
    ("what stok is low", "what stock is low"),
    ("show maintenence", "show maintenance"),
    ("show vehcle history", "show vehicle history"),
    ("show bookngs", "show bookings"),
    ("can u show the inventory", "can you show the inventory"),
    ("How Many Cars Do I Have?", "how many cars do i have"),
    ("  multiple   spaces\t here ", "multiple spaces here"),
    ("what is a PMS?", "what is a pms"),
]:
    got = normalize(raw)
    check(f"normalize({raw!r})", got == want, f"got {got!r}, want {want!r}")

# Vocab words must never be altered
for w in ["maintenance", "inventory", "bookings", "vehicle", "hello"]:
    check(f"preserve {w!r}", normalize(w) == w, f"got {normalize(w)!r}")


print(f"\n{BOLD}== Admin intent routing (typo tolerance) =={RESET}")
for msg, want_intent, want_fastpath in [
    ("show inventry", DATABASE_LOOKUP, True),
    ("what stok is low", DATABASE_LOOKUP, True),
    ("show maintenence", DATABASE_LOOKUP, True),
    ("show vehcle history", DATABASE_LOOKUP, True),
    ("show bookngs", DATABASE_LOOKUP, True),
    ("show pms", DATABASE_LOOKUP, True),
    ("what items need restocking", DATABASE_LOOKUP, True),
    ("which parts are almost out", DATABASE_LOOKUP, True),
    ("can u show the inventory", DATABASE_LOOKUP, True),
    ("show inventory", DATABASE_LOOKUP, True),
    ("show stock", DATABASE_LOOKUP, True),
    ("show maintenance", DATABASE_LOOKUP, True),
    ("how many cars do we have", DATABASE_CALCULATION, False),
    ("generate inventory report as pdf", REPORT_GENERATION, False),
    ("hello", None, False),
]:
    got_intent = classify_intent(msg)
    got_fp = bool(classify_and_run(msg))
    if want_intent is None:
        check(f"fastpath skip {msg!r}", not got_fp, f"unexpected fastpath (intent={got_intent})")
    else:
        check(f"{msg!r}", got_intent == want_intent and got_fp == want_fastpath,
              f"intent={got_intent}, fastpath={got_fp}")


print(f"\n{BOLD}== Customer intent routing (booking / PMS) =={RESET}")
for msg, want in [
    ("I want to book a service.", BOOK_SERVICE),
    ("I want to book PMS.", BOOK_SERVICE),
    ("Schedule maintenance for my Toyota.", BOOK_SERVICE),
    ("When is my next PMS?", MAINTENANCE_REMINDER),
    ("When should I schedule my next maintenance?", MAINTENANCE_REMINDER),
    ("Can you book my car for next week?", BOOK_SERVICE),
    ("I need an oil change", BOOK_SERVICE),
    ("Can you help me book maintenance?", BOOK_SERVICE),
    ("When should I bring my car for PMS?", MAINTENANCE_REMINDER),
    ("I want to have my vehicle serviced next week.", BOOK_SERVICE),
    # Customer stock questions are OUT OF SCOPE: they stay DATABASE_LOOKUP
    # (no self-reference) and access_control.classify_denial BLOCKS them as
    # INVENTORY before any Firestore read (asserted below).
    ("what stok is low", DATABASE_LOOKUP),
    ("what products are running low", DATABASE_LOOKUP),
    ("which items need replenishment", DATABASE_LOOKUP),
    ("what parts are almost out", DATABASE_LOOKUP),
]:
    got = classify_customer_intent(msg)
    check(f"{msg!r}", got == want, f"got {got}, want {want}")


print(f"\n{BOLD}== Customer out-of-scope ordering (no wasted Firestore reads) =={RESET}")
# Stock questions must be BLOCKED (scope check) before any DB read can happen.
import inspect
import main

src = inspect.getsource(main._run_customer_chat)
i_scope = src.find("_OUT_OF_SCOPE_RE.search")
i_direct = src.find("_customer_direct_lookup(")
check("scope check runs before direct-DB path", 0 < i_scope < i_direct)

for msg in [
    "what stok is low",
    "what products are running low",
    "which items need replenishment",
    "what parts are almost out",
    "how much engine oil is in stock",
]:
    norm = main._normalize_input(msg) or msg
    blocked = bool(
        main._OUT_OF_SCOPE_RE.search(norm) or main._STOCK_QTY_RE.search(norm)
    )
    check(f"blocked: {msg!r}", blocked, "fell through scope check")


print(f"\n{BOLD}{passed} passed, {failed} failed{RESET}")
sys.exit(1 if failed else 0)
