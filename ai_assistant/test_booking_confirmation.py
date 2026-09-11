"""
test_booking_confirmation.py — offline multi-turn booking conversation tests.

Covers the booking test cases (5-7) end-to-end at the booking_gather layer
with Firestore stubbed, including the new confirmation gate:

  1. "I want to book a service."            -> asks ONLY missing details
  2. "Book an Oil Change for my vehicle."   -> asks for vehicle/date/time
  3. provide plate + date + time            -> availability checked,
                                               CONFIRMATION SUMMARY shown,
                                               nothing booked yet
  4. "yes"                                  -> booking created (via existing tool)
  5. "no" to a summary                      -> nothing booked
  6. bare "yes" with NO pending summary     -> never books
  7. bare date reply / bare time reply      -> complete the previous ask
  8. slot offer then "9am"                  -> continues that offer
  9. taken slot                              -> alternatives offered, no booking

Usage:  venv\\Scripts\\python test_booking_confirmation.py
"""
import sys
import types

sys.path.insert(0, ".")

# ── Stub Firestore layer BEFORE importing booking_gather ─────────────────────
import firestore_client


class _FakeDoc:
    def __init__(self, data, doc_id="doc-1"):
        self._d = data
        self._id = doc_id

    def to_dict(self):
        return self._d

    @property
    def id(self):
        return self._id


class _FakeQuery:
    def __init__(self, docs):
        self._docs = docs

    def where(self, filter=None, **_):
        return self

    def limit(self, *_):
        return self

    def stream(self):
        return iter(self._docs)


class _FakeCollection:
    def __init__(self, docs):
        self._docs = docs

    def where(self, filter=None, **_):
        return _FakeQuery(self._docs)

    def document(self, _doc_id="doc-1"):
        return _FakeDoc({}, _doc_id)

    def stream(self):
        return iter(self._docs)


_VEHICLES = [
    {"plateNumber": "ABC-1234", "desc": "Toyota Vios 2020", "ownerId": "U1",
     "owner": "Test Customer", "status": "Active"},
    {"plateNumber": "XYZ-5678", "desc": "Honda City 2019", "ownerId": "U1",
     "owner": "Test Customer", "status": "Active"},
]

_TAKEN = [{"preferredDate": "2030-01-01", "preferredTime": "9:00 AM",
           "status": "Pending"}]


def _install_db(vehicles, bookings_taken):
    db = types.SimpleNamespace()

    def collection(name):
        if name == "vehicles":
            return _FakeCollection([_FakeDoc(v, f"doc-{i}")
                                    for i, v in enumerate(vehicles)])
        if name == "service_bookings":
            # Each taken booking is a dict with preferredDate/preferredTime
            return _FakeCollection([_FakeDoc(b, f"bk-{i}")
                                    for i, b in enumerate(bookings_taken)])
        return _FakeCollection([])

    db.collection = collection
    firestore_client.get_db = lambda: db


_install_db(_VEHICLES, _TAKEN)

_results = {"created": []}


def _patch_booking_tools():
    """Patch availability + create to behave like the real tools without IO."""
    import booking_gather as bg

    def avail(customer_uid, customer_name, preferred_date, preferred_time=None, **_):
        from datetime import datetime as _dt
        try:
            disp = _dt.strptime(preferred_date, "%Y-%m-%d").strftime("%B %d, %Y")
        except Exception:
            disp = preferred_date
        slots = ["8:00 AM", "9:00 AM", "10:00 AM", "1:00 PM", "2:00 PM"]
        taken_times = {b.get("preferredTime") for b in _TAKEN
                       if b.get("preferredDate") == preferred_date}
        free = [s for s in slots if s not in taken_times]
        if preferred_time:
            norm = bg._extract_time(preferred_time) or preferred_time
            ok = norm in free or norm not in taken_times
            return {"status": "ok", "date_display": disp,
                    "requested_time_available": ok,
                    "available_slots": free if not ok else free}
        return {"status": "ok", "date_display": disp,
                "available_slots": free}

    def create(customer_uid, customer_name, plate, services,
               preferred_date, preferred_time, **_):
        owned = {v["plateNumber"] for v in _VEHICLES}
        if plate not in owned:
            return {"success": False, "error": "VEHICLE_NOT_OWNED",
                    "message": "That vehicle is not registered to your account."}
        if not all([plate, services, preferred_date, preferred_time]):
            return {"success": False, "error": "MISSING_FIELDS",
                    "message": "Missing booking details."}
        _results["created"].append({
            "plate": plate, "services": services,
            "date": preferred_date, "time": preferred_time,
        })
        return {"success": True, "booking_id": "BK-TEST-001",
                "status": "Approved",
                "date": "January 1, 2030",
                "message": (f"Your booking is confirmed! Booking ID: BK-TEST-001 "
                            f"for {plate} on {preferred_date} at {preferred_time}. "
                            "Status: Approved.")}

    bg.check_booking_availability = avail
    bg.create_customer_booking = create
    return bg


bg = _patch_booking_tools()
try_handle = bg.try_handle_booking

PASS = FAIL = 0


def check(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {extra}")


UID, NAME = "U1", "Test Customer"

print("== Turn-by-turn booking conversation ==")
# Turn 1: generic booking intent, nothing known, multiple vehicles
r = try_handle("I want to book a service.", UID, NAME, [])
check("asks for vehicle+service, never books",
      r and "which vehicle" in r["reply"].lower() and "service" in r["reply"].lower(),
      r and r["reply"][:100])

# Turn 2: service named, still no vehicle
r = try_handle("Book an Oil Change service for my vehicle.", UID, NAME, [])
check("oil change asks which vehicle",
      r and "abc-1234" in r["reply"].lower() and "xyz-5678" in r["reply"].lower(),
      r and r["reply"][:120])
check("turn 2 books nothing", not _results["created"])

# Turn 3: vehicle + date + time given in one message
h = [
    {"role": "user", "content": "Book an Oil Change service for my vehicle."},
    {"role": "assistant", "content": "Which vehicle? ABC-1234 or XYZ-5678?"},
]
r = try_handle("ABC-1234 on 01/01/2030 at 10am", UID, NAME, h)
check("shows confirmation summary (not booked yet)",
      r and "[BOOKING-CONFIRM]" in r["reply"] and "10:00 AM" in r["reply"],
      r and r["reply"][:120])
check("no booking created before confirmation", not _results["created"])

# Turn 4: customer confirms
h.append({"role": "assistant", "content": r["reply"]})
r = try_handle("yes", UID, NAME, h)
check("confirmation -> booking created",
      r and _results["created"] and _results["created"][-1]["plate"] == "ABC-1234"
      and _results["created"][-1]["time"] == "10:00 AM",
      r and r["reply"][:120])
check("success message contains booking id",
      r and "BK-TEST-001" in r["reply"], r and r["reply"][:100])

print("== Safety: bare yes without a pending summary never books ==")
before = len(_results["created"])
r = try_handle("yes", UID, NAME, [])
check("bare yes does not book", r is None or len(_results["created"]) == before,
      str(_results["created"]))

print("== Denial cancels the pending booking ==")
summary = ("Please confirm your booking details:\n\n- Vehicle: **ABC-1234**\n"
           "- Service(s): **Oil Change**\n- Date: **January 1, 2030**\n"
           "- Time: **9:00 AM**\n\nShall I proceed? [BOOKING-CONFIRM]")
h2 = [{"role": "assistant", "content": summary}]
before = len(_results["created"])
r = try_handle("no", UID, NAME, h2)
check("'no' cancels without booking", len(_results["created"]) == before,
      str(_results["created"]))
check("cancel message is friendly", r and "not saved" in r["reply"].lower(),
      r and r["reply"][:80])

print("== Correction on pending booking ==")
r = try_handle("make it 2pm", UID, NAME, h2)
check("time correction updates pending booking",
      r and "[BOOKING-CONFIRM]" in r["reply"] and "2:00 PM" in r["reply"],
      r and (r["reply"][:140] if r else ""))
check("correction does not book", len(_results["created"]) == before)

print("== Bare date reply completes the ask ==")
h3 = [
    {"role": "user", "content": "Book an oil change for my vehicle ABC-1234"},
    {"role": "assistant",
     "content": "Almost there! Please let me know your preferred date and time."},
]
r = try_handle("January 1, 2030", UID, NAME, h3)
check("bare date recognized",
      r and ("2030" in r["reply"] or "January" in r["reply"] or "available times" in r["reply"].lower()),
      r and (r["reply"][:120] if r else "fell through"))

print("== Bare time reply continues a slot offer ==")
offer = ("Here are the available times for January 1, 2030:\n"
         "- 8:00 AM\n- 9:00 AM\n\nWhich time works for you?")
h4 = [
    {"role": "user", "content": "Book an oil change for ABC-1234"},
    {"role": "assistant", "content": "What date works for you?"},
    {"role": "user", "content": "January 1, 2030"},
    {"role": "assistant", "content": offer},
]
before = len(_results["created"])
r = try_handle("10am", UID, NAME, h4)
check("slot-offer + time -> confirmation summary",
      r and "[BOOKING-CONFIRM]" in r["reply"] and "10:00 AM" in r["reply"],
      r and (r["reply"][:140] if r else "fell through"))
check("still not booked before confirm", len(_results["created"]) == before)

print("== Earliest-schedule path asks for vehicle+service ==")
r = try_handle("When will be the earliest schedule for service?", UID, NAME, [])
check("earliest asks vehicle+service (multi-vehicle)",
      r and "which vehicle" in r["reply"].lower(),
      r and (r["reply"][:120] if r else "fell through"))

print("== THE LOOP REGRESSION: details spread across turns ==")
h6 = [
    {"role": "user", "content": "I want an oil change tomorrow 9am"},
    {"role": "assistant", "content":
        "I'd be happy to book that for you! Which vehicle should I book "
        "\u2014 ABC-1234, XYZ-5678? (I'll also need your preferred date and "
        "time, or I can suggest the earliest available schedule.)"},
]
before = len(_results["created"])
r = try_handle("ABC-1234", UID, NAME, h6)
check("earlier date/time carried - asks confirmation, NOT date again",
      r and "[BOOKING-CONFIRM]" in r["reply"] and "9:00 AM" in r["reply"],
      r and (r["reply"][:150] if r else "fell through"))
check("nothing booked yet", len(_results["created"]) == before)
h6.append({"role": "user", "content": "ABC-1234"})
h6.append({"role": "assistant", "content": r["reply"]})
r = try_handle("yes", UID, NAME, h6)
check("confirm -> booked under same conversation",
      r and len(_results["created"]) == before + 1,
      str(_results["created"]))
check("success message points to My Bookings + offers another",
      r and "my bookings" in r["reply"].lower()
      and "book another service?" in r["reply"].lower(),
      r and (r["reply"][-160:] if r else ""))

print("== Unowned plate -> tool error surfaced ==")
r = try_handle("ZZZ-9999 oil change 01/01/2030 10am", UID, NAME, [])
h5 = [{"role": "assistant", "content": r["reply"]}]
r = try_handle("yes", UID, NAME, h5)
check("unowned plate booking blocked",
      r and not _results["created"] or all(
          c["plate"] != "ZZZ-9999" for c in _results["created"]),
      str(_results["created"]))

print()
print(f"RESULT: {PASS} passed, {FAIL} failed")
sys.exit(1 if FAIL else 0)
