"""
End-to-end local test — verifies the complete customer chat pipeline
without hitting the remote server.  Tests the direct-lookup path in main.py
using the actual Firestore data.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

GREEN = "\033[92m"; RED = "\033[91m"; CYAN = "\033[96m"; RESET = "\033[0m"
BOLD  = "\033[1m"

passed = 0; failed = 0; results = []

def check(label, got_reply, checks):
    global passed, failed
    ok = True
    notes = []
    for desc, condition in checks:
        if not condition:
            ok = False
            notes.append(f"FAIL: {desc}")
        else:
            notes.append(f"ok: {desc}")
    results.append((label, ok, got_reply[:100], notes))
    if ok:
        passed += 1
        print(f"  {GREEN}PASS{RESET}  {label}")
    else:
        failed += 1
        print(f"  {RED}FAIL{RESET}  {label}")
        for n in notes:
            if n.startswith("FAIL"):
                print(f"         {n}")
    return ok

print(f"\n{BOLD}=== Customer AI E2E Local Tests ==={RESET}\n")

# ── 1. Import the direct-lookup function ─────────────────────────────────────
try:
    from model_router import (
        classify_customer_intent, MY_VEHICLES, MY_SERVICE_HISTORY,
        MY_BOOKINGS, SERVICE_RECOMMENDATION, SERVICE_PRICES,
        CUSTOMER_MATERIALS, BOOK_SERVICE, UPDATE_BOOKING, CANCEL_BOOKING,
        MAINTENANCE_REMINDER,
    )
    print(f"{CYAN}Intent classification tests:{RESET}")
    intent_cases = [
        ("Show my vehicles.",               MY_VEHICLES),
        ("What is my plate number?",        MY_VEHICLES),
        ("Show my service history.",        MY_SERVICE_HISTORY),
        ("When was my last oil change?",    MY_SERVICE_HISTORY),
        ("Show my bookings.",               MY_BOOKINGS),
        ("Do I have any upcoming appointments?", MY_BOOKINGS),
        ("What maintenance does my car need?", SERVICE_RECOMMENDATION),
        ("Is my car due for maintenance?",  MAINTENANCE_REMINDER),
        ("How much is an oil change?",      SERVICE_PRICES),
        ("What services do you offer?",     SERVICE_PRICES),
        ("How much is a PMS?",              SERVICE_PRICES),
        ("Do you sell engine oil?",         CUSTOMER_MATERIALS),
        ("I want to book an oil change.",   BOOK_SERVICE),
        ("Book me a service appointment.",  BOOK_SERVICE),
        ("Schedule a PMS for my car.",      BOOK_SERVICE),
        ("Move my appointment to Friday.",  UPDATE_BOOKING),
        ("Reschedule my booking.",          UPDATE_BOOKING),
        ("Cancel my appointment.",          CANCEL_BOOKING),
    ]
    ic_pass = 0
    for msg, expected in intent_cases:
        got = classify_customer_intent(msg)
        if got == expected:
            ic_pass += 1
        else:
            print(f"  {RED}FAIL{RESET}  '{msg}' -> got {got}, expected {expected}")
    if ic_pass == len(intent_cases):
        print(f"  {GREEN}PASS{RESET}  All {ic_pass}/{len(intent_cases)} intent cases correct")
        passed += 1
    else:
        print(f"  {RED}FAIL{RESET}  {ic_pass}/{len(intent_cases)} intent cases correct")
        failed += 1
except Exception as e:
    print(f"  {RED}FAIL{RESET}  Intent import error: {e}")
    failed += 1

# ── 2. Service price lookups ──────────────────────────────────────────────────
print(f"\n{CYAN}Service price lookup tests:{RESET}")
try:
    from customer_tools import get_service_prices

    r = get_service_prices("uid", "Test", service_name="oil change")
    check("oil change -> returns results",
          str(r.get("services",[])),
          [("total > 0", r.get("total_services", 0) > 0),
           ("no error", not r.get("error")),
           ("catalog accessible", r.get("catalog_size", 0) > 0)])

    r = get_service_prices("uid", "Test", service_name="pms")
    check("pms synonym -> returns oil change results",
          str(r.get("services",[])),
          [("total > 0 (synonym expansion)", r.get("total_services", 0) > 0),
           ("no error", not r.get("error"))])

    r = get_service_prices("uid", "Test", service_name="brake")
    check("brake -> returns brake services",
          str(r.get("services",[])),
          [("total > 0", r.get("total_services", 0) > 0),
           ("name contains brake", any("brake" in s.get("name","").lower()
                                       for s in r.get("services",[])))])

    r = get_service_prices("uid", "Test")
    check("no keyword -> returns full catalog",
          str(r.get("total_services")),
          [("catalog has 100+ services", r.get("total_services", 0) >= 100),
           ("no error", not r.get("error"))])

    r = get_service_prices("uid", "Test", service_name="quantum hyperdrive")
    check("unknown service -> returns 0 results (no hallucination)",
          str(r.get("services",[])),
          [("total == 0", r.get("total_services", 0) == 0),
           ("no error field", r.get("error") is None)])

except Exception as e:
    print(f"  {RED}FAIL{RESET}  Service prices error: {e}")
    import traceback; traceback.print_exc()
    failed += 1

# ── 3. Customer tools security ────────────────────────────────────────────────
print(f"\n{CYAN}Security / authorization tests:{RESET}")
try:
    from customer_tools import (
        get_my_vehicles, get_my_service_history,
        get_my_bookings, create_customer_booking,
        cancel_my_booking, update_my_booking,
    )

    # Vehicle lookup uses UID correctly
    r = get_my_vehicles("test-uid-A", "Customer A")
    check("get_my_vehicles: uses UID, returns owner correctly",
          str(r.get("owner")),
          [("owner is Customer A", r.get("owner") == "Customer A"),
           ("no error", not r.get("error") or r.get("error") == "QUOTA_EXCEEDED")])

    # Booking with fake plate -> VEHICLE_NOT_OWNED
    r = create_customer_booking(
        "test-uid-A", "Customer A",
        plate="ZZZ-FAKE-0000",
        services=["Change Oil Labor (400)"],
        preferred_date="2027-06-01",
        preferred_time="9:00 AM",
    )
    check("create_booking with unowned plate -> VEHICLE_NOT_OWNED",
          str(r.get("error")),
          [("error is VEHICLE_NOT_OWNED", r.get("error") == "VEHICLE_NOT_OWNED"),
           ("success is False", not r.get("success"))])

    # Cancel non-existent booking -> BOOKING_NOT_FOUND
    r = cancel_my_booking("test-uid-A", "Customer A", "nonexistent-booking-id-99999")
    check("cancel non-existent booking -> BOOKING_NOT_FOUND",
          str(r.get("error")),
          [("error is BOOKING_NOT_FOUND", r.get("error") == "BOOKING_NOT_FOUND"),
           ("success is False", not r.get("success"))])

    # Update non-existent booking -> BOOKING_NOT_FOUND
    r = update_my_booking("test-uid-A", "Customer A", "nonexistent-999", new_date="2027-06-02")
    check("update non-existent booking -> BOOKING_NOT_FOUND",
          str(r.get("error")),
          [("error is BOOKING_NOT_FOUND", r.get("error") == "BOOKING_NOT_FOUND")])

except Exception as e:
    print(f"  {RED}FAIL{RESET}  Security test error: {e}")
    import traceback; traceback.print_exc()
    failed += 1

# ── 4. Materials (no stock data) ──────────────────────────────────────────────
print(f"\n{CYAN}Customer materials tests:{RESET}")
try:
    from customer_tools import get_customer_materials

    r = get_customer_materials("uid", "Test")
    check("get_customer_materials: no internal fields exposed",
          str(r.get("total_materials")),
          [("no error", not r.get("error") or r.get("error") == "QUOTA_EXCEEDED"),
           ("no 'stock' key in materials",
            not any("stock" in m for m in r.get("materials", []))),
           ("no 'reorder' key in materials",
            not any("reorder" in m for m in r.get("materials", []))),
           ("no 'supplier' key in materials",
            not any("supplier" in m for m in r.get("materials", [])))])

except Exception as e:
    print(f"  {RED}FAIL{RESET}  Materials test error: {e}")
    import traceback; traceback.print_exc()
    failed += 1

# ── 5. Date parsing ───────────────────────────────────────────────────────────
print(f"\n{CYAN}Date parsing tests:{RESET}")
try:
    from customer_tools import _parse_date_flexible
    from datetime import datetime

    cases = [
        ("2026-06-15",          (2026, 6, 15)),
        ("June 15, 2026",       (2026, 6, 15)),
        ("Jun 15, 2026",        (2026, 6, 15)),
        ("06/15/2026",          (2026, 6, 15)),
        ("tomorrow",            None),  # just verify it doesn't crash
        ("next Monday",         None),
    ]
    dp_pass = 0
    for s, expected_ymd in cases:
        try:
            dt = _parse_date_flexible(s)
            if expected_ymd:
                ok = (dt.year, dt.month, dt.day) == expected_ymd
            else:
                ok = isinstance(dt, datetime)
            if ok:
                dp_pass += 1
            else:
                print(f"  {RED}FAIL{RESET}  parse '{s}': got {dt.date()}, expected {expected_ymd}")
        except Exception as ex:
            print(f"  {RED}FAIL{RESET}  parse '{s}': exception {ex}")

    if dp_pass == len(cases):
        print(f"  {GREEN}PASS{RESET}  All {dp_pass}/{len(cases)} date parsing cases correct")
        passed += 1
    else:
        print(f"  {RED}FAIL{RESET}  {dp_pass}/{len(cases)} date cases correct")
        failed += 1
except Exception as e:
    print(f"  {RED}FAIL{RESET}  Date parsing error: {e}")
    import traceback; traceback.print_exc()
    failed += 1

# ── Summary ───────────────────────────────────────────────────────────────────
total = passed + failed
pct   = round(passed / total * 100) if total else 0
print(f"\n{'='*55}")
print(f"{BOLD}  Results: {passed}/{total} PASSED ({pct}%) | {failed} FAILED{RESET}")
print(f"{'='*55}\n")
sys.exit(0 if failed == 0 else 1)
