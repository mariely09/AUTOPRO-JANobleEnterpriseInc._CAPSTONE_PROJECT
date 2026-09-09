"""
booking_gather.py — deterministic fast path for service-booking requests.

Makes the Customer AI actually complete bookings with the MINIMUM number
of LLM calls (usually ZERO):

  Turn 1  "I want to book an oil change."
          -> gather: plate missing, date missing, time missing
          -> asks ONLY for the missing details (0 LLM calls)

  Turn 2  "ABC-1234, tomorrow 9am"
          -> all four required fields present
          -> check_booking_availability + create_customer_booking (0 LLM calls)

  "When will be the earliest schedule for my service?"
          -> asks for vehicle + service (0 LLM calls)
          -> once known: availability scan -> offers earliest slots
             (0 LLM calls; user confirms -> booked)

Authorization: plate ownership is verified inside
create_customer_booking / check_booking_availability (existing code) —
this module only GATHERS information; it never relaxes any check.
The customer_uid is always injected server-side by main.py, never read
from message content.
"""

import re
from datetime import datetime, timedelta

from customer_tools import (
    get_my_vehicles,
    check_booking_availability,
    create_customer_booking,
    _parse_date_flexible,
)


# ── Message parsing helpers ───────────────────────────────────────────────────

# Plate formats: ABC-1234, ABC 1234, ABC1234, ab12345 (PH plates), etc.
_PLATE_RE = re.compile(
    r"\b([A-Z]{1,3}[\s\-]?[0-9]{3,4}|[A-Z]{2,3}[0-9]{4,6})\b",
)

_TIME_RE = re.compile(
    r"\b(?:(1[0-2]|0?[1-9])(?::([0-5][0-9]))?\s*(am|pm|a\.m\.|p\.m\.)"
    r"|(1[0-9]|2[0-4]|0?[0-9]):([0-5][0-9]))\b",
    re.IGNORECASE,
)

_DATE_WORDS_RE = re.compile(
    r"\b(today|tomorrow|next\s+(?:mon|tues|wednes|thurs|fri|satur|sun)day"
    r"|(?:mon|tues|wednes|thurs|fri|satur|sun)day"
    r"|\d{4}-\d{1,2}-\d{1,2}|\d{1,2}/\d{1,2}/\d{4}"
    r"|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:st|nd|rd|th)?)\b",
    re.IGNORECASE,
)

# "earliest" / "as soon as possible" — user wants the first open slot
_EARLIEST_RE = re.compile(
    r"\b(earliest|asap|as\s+soon\s+as\s+possible|soonest|first\s+available|"
    r"anytime|any\s+(?:time|day)|soonest\s+schedule)\b",
    re.IGNORECASE,
)

_SERVICE_WORDS_RE = re.compile(
    r"\b(change\s+oil|oil\s+change|pms|preventive\s+maintenance|"
    r"brake\s+(?:service|pads|inspection)|battery\s+(?:check|replace\w*)|"
    r"tire\s+(?:rotation|change|replacement)|wheel\s+alignment|"
    r"air\s+condition(?:er|ing)?\s+(?:service|clean\w*)|ac\s+clean\w*|"
    r"transmission\s+(?:service|flush)|coolant\s+flush|"
    r"engine\s+(?:tune|wash|detail\w*)|car\s+wash|"
    r"service|maintenance)\b",
    re.IGNORECASE,
)

_AFFIRM_RE = re.compile(r"\b(yes|yeah|yep|ok|okay|sure|sige|go\s+ahead|"
                        r"please\s+do|confirm|book\s+it|tuloy)\b", re.IGNORECASE)
_NEGATE_RE = re.compile(r"\b(no|nope|not\s+that|cancel|wag|ayoko|"
                        r"different|other|another)\b", re.IGNORECASE)


def _extract_plate(text: str) -> str | None:
    m = _PLATE_RE.search(text.upper())
    return m.group(1).replace(" ", "-") if m else None


def _extract_time(text: str) -> str | None:
    """Normalize any time phrasing to the shop's 'H:MM AM/PM' slot format."""
    m = _TIME_RE.search(text)
    if not m:
        return None
    hour = m.group(1) or m.group(4)
    minute = m.group(2) or m.group(5) or "00"
    ampm = (m.group(3) or "").replace(".", "").upper() or None
    try:
        h = int(hour)
        if ampm:
            if ampm == "PM" and h < 12:
                h += 12
            if ampm == "AM" and h == 12:
                h = 0
        # 24-hour input (e.g. "14:30") normalizes to 12-hour display
        disp_h = h % 12 or 12
        disp_ampm = "AM" if h < 12 else "PM"
        return f"{disp_h}:{minute} {disp_ampm}"
    except Exception:
        return None


def _extract_date_text(text: str) -> str | None:
    m = _DATE_WORDS_RE.search(text)
    if m:
        return m.group(1)
    return None


def _extract_service(text: str) -> list[str] | None:
    found = [m.group(0) for m in _SERVICE_WORDS_RE.finditer(text)]
    # de-duplicate, drop bare "service"/"maintenance" if a specific service present
    specific = [s for s in found if s.lower() not in ("service", "maintenance")]
    picked = specific or found
    if not picked:
        return None
    seen, out = set(), []
    for s in picked:
        k = s.lower().strip()
        if k not in seen:
            seen.add(k)
            out.append(s.strip().title())
    return out


def _format_slots(slots: list[str], date_display: str) -> str:
    lines = "\n".join(f"\u2022 {s}" for s in slots)
    return (
        f"Here are the available times for {date_display}:\n{lines}\n\n"
        "Which time works for you?"
    )


def _ask_missing(plate: str | None, services: list[str] | None,
                 date_txt: str | None, time_txt: str | None,
                 earliest: bool, vehicle_count: int) -> str:
    """Compose a friendly message asking ONLY for what is missing."""
    missing = []
    if not plate:
        missing.append("vehicle")
    if not services:
        missing.append("service")
    if not date_txt and not earliest:
        missing.append("date")
    if not time_txt and not earliest:
        missing.append("time")

    if not missing:
        return ""

    parts = []
    if "vehicle" in missing:
        if vehicle_count:
            parts.append("which of your registered vehicles should I book")
        else:
            parts.append("you don't have any registered vehicles on file yet \u2014 "
                         "please register a vehicle first, then I can book for you")
    if "service" in missing:
        parts.append("what service you need (e.g. change oil, PMS, brake service)")
    if "date" in missing and "time" in missing:
        parts.append("your preferred date and time")
    elif "date" in missing:
        parts.append("your preferred date")
    elif "time" in missing:
        parts.append("your preferred time")

    if not plate and services and len(parts) == 2:
        # vehicle + service ask — combine naturally
        return ("I'd be happy to book that for you! To get started, could you tell me "
                f"{parts[0]}, and {parts[1]}? "
                "(I'll also need your preferred date and time \u2014 or I can suggest the "
                "earliest available schedule.)")
    lead = "I can help you book that! " if not plate else "Almost there! "
    body = "; ".join(parts)
    return lead + f"Please let me know {body}."


# ── Public API ────────────────────────────────────────────────────────────────

def try_handle_booking(message: str, customer_uid: str, customer_name: str,
                       history: list[dict]) -> dict | None:
    """
    Deterministic booking handler. Returns the same shape as
    _run_customer_chat ({reply, tool_calls, model, intent}) when it handles
    the message, or None to fall through to the normal LLM pipeline.

    Zero LLM calls on every path. All Firestore work goes through the
    existing customer_tools functions (authorization preserved).
    """
    if not message or not message.strip():
        return None

    text = message.strip()
    t = text.lower()
    earliest = bool(_EARLIEST_RE.search(text))

    # ── Collect required fields from message + recent history ────────────────
    plate = _extract_plate(text)
    services = _extract_service(text)
    date_txt = _extract_date_text(text)
    time_txt = _extract_time(text)

    if not (plate or services or date_txt or time_txt or earliest
            or _AFFIRM_RE.search(t) or _NEGATE_RE.search(t)):
        return None  # not booking-shaped at all

    # Carry known values from the previous gather turn (context continuity)
    prev_plate = prev_services = None
    for m in reversed(history[-4:] if history else []):
        if m.get("role") == "assistant":
            c = m.get("content") or ""
            if not prev_plate:
                p = _extract_plate(c)
                if p:
                    prev_plate = p
            if not prev_services:
                s = _extract_service(c)
                if s:
                    prev_services = s

    plate = plate or prev_plate
    if not services and prev_services:
        services = prev_services
    # Treat "the usual"/"same service" style affirmations without specifics
    if not services and _AFFIRM_RE.search(t) and _extract_service(str(history or "")):
        services = prev_services

    # ── Fetch vehicles when needed (1 read; cached per-request upstream) ─────
    vehicles = None
    need_vehicle_list = (not plate) or earliest
    if need_vehicle_list or services is None:
        vres = get_my_vehicles(customer_uid=customer_uid, customer_name=customer_name)
        if isinstance(vres, dict):
            vehicles = vres.get("vehicles") or []
            # Auto-select ONLY when the customer has exactly one vehicle —
            # otherwise ask which one (never guess between several).
            if not plate and vehicles and len(vehicles) == 1:
                plate = (vehicles[0].get("plate") or "").strip() or None

    # ── Case 1: not enough info yet -> ask for ONLY the missing pieces ───────
    if not plate or not services or (not date_txt and not earliest and not time_txt):
        vcount = len(vehicles) if vehicles is not None else 0
        # Multiple vehicles and no plate given -> show the actual plate list
        if not plate and vehicles and len(vehicles) > 1:
            plates = ", ".join((v.get("plate") or "?") for v in vehicles)
            svc_txt = " for " + services[0] if services else ""
            ask = (f"I'd be happy to book{svc_txt} for you! "
                   f"Which vehicle should I book — {plates}? "
                   "(I'll also need your preferred date and time, or I can "
                   "suggest the earliest available schedule.)")
            return {
                "reply": ask,
                "tool_calls": [{"tool": "get_my_vehicles", "args": {},
                                "result": {"count": vcount, "plates": plates}}],
                "model": "none",
                "intent": "BOOK_SERVICE",
            }
        ask = _ask_missing(plate, services, date_txt, time_txt, earliest, vcount)
        if ask:
            return {
                "reply": ask,
                "tool_calls": [{"tool": "get_my_vehicles", "args": {},
                                "result": {"count": vcount}}],
                "model": "none",
                "intent": "BOOK_SERVICE",
            }
        if not plate and vehicles is not None and not vehicles:
            return None  # no vehicles; fall through (tools will report it)

    # ── Case 2: earliest-schedule request -> scan slots, offer times ─────────
    if earliest and not time_txt:
        try:
            start = datetime.now() + timedelta(days=1)
            for offset in range(7):
                day = start + timedelta(days=offset)
                ds = day.strftime("%Y-%m-%d")
                avail = check_booking_availability(
                    customer_uid=customer_uid, customer_name=customer_name,
                    preferred_date=ds,
                )
                if avail.get("error") or avail.get("status") == "error":
                    break
                slots = avail.get("available_slots") or []
                if slots:
                    date_display = avail.get("date_display") or day.strftime("%B %d, %Y")
                    svc_txt = ", ".join(services) if services else "your service"
                    return {
                        "reply": (
                            f"The earliest available schedule for {svc_txt} is on "
                            f"**{date_display}**.\n\n"
                            + _format_slots(slots, date_display)
                            + "\n\nReply with a time to confirm your booking."
                        ),
                        "tool_calls": [{"tool": "check_booking_availability",
                                        "args": {"date": ds},
                                        "result": {"available_slots": slots}}],
                        "model": "none",
                        "intent": "BOOK_SERVICE",
                    }
        except Exception:
            return None  # fall through to LLM path on any failure

    # ── Case 3: we have everything -> check availability, then book ──────────
    if plate and services and (date_txt or earliest) and time_txt:
        try:
            parsed = _parse_date_flexible(date_txt or "tomorrow")
            date_str = parsed.strftime("%Y-%m-%d")
        except ValueError:
            return {
                "reply": ("I couldn't quite read that date. Could you give it as "
                          "MM/DD/YYYY, a weekday (e.g. \"next Monday\"), or "
                          "\"today\"/\"tomorrow\"?"),
                "tool_calls": [], "model": "none", "intent": "BOOK_SERVICE",
            }
        avail = check_booking_availability(
            customer_uid=customer_uid, customer_name=customer_name,
            preferred_date=date_str, preferred_time=time_txt,
        )
        if avail.get("error") or avail.get("status") == "error":
            return {
                "reply": avail.get("message") or
                         "I couldn't check availability right now. Please try again.",
                "tool_calls": [{"tool": "check_booking_availability",
                                "args": {"date": date_str, "time": time_txt},
                                "result": avail}],
                "model": "none", "intent": "BOOK_SERVICE",
            }
        if avail.get("requested_time_available") is False:
            slots = avail.get("available_slots") or []
            date_display = avail.get("date_display") or date_str
            if slots:
                reply = (f"Sorry, {time_txt} on {date_display} is already taken.\n\n"
                         + _format_slots(slots, date_display))
            else:
                reply = (f"Sorry, {date_display} is fully booked. "
                         "Would another day work for you?")
            return {"reply": reply,
                    "tool_calls": [{"tool": "check_booking_availability",
                                    "args": {"date": date_str, "time": time_txt},
                                    "result": avail}],
                    "model": "none", "intent": "BOOK_SERVICE"}

        res = create_customer_booking(
            customer_uid=customer_uid, customer_name=customer_name,
            plate=plate, services=services,
            preferred_date=date_str, preferred_time=time_txt,
        )
        if res.get("success"):
            return {
                "reply": res.get("message") or "Your booking has been created!",
                "tool_calls": [{"tool": "create_customer_booking",
                                "args": {"plate": plate, "services": services,
                                         "date": date_str, "time": time_txt},
                                "result": {"success": True,
                                           "booking_id": res.get("booking_id")}}],
                "model": "none", "intent": "BOOK_SERVICE",
            }
        # Ownership/catalog/date errors — surface the specific reason
        return {
            "reply": res.get("message") or
                     "I couldn't complete the booking. Please try again.",
            "tool_calls": [{"tool": "create_customer_booking",
                            "args": {"plate": plate, "services": services},
                            "result": res}],
            "model": "none", "intent": "BOOK_SERVICE",
        }

    # Case 4: date known but no time -> offer slots for that date
    if plate and services and date_txt and not time_txt:
        try:
            parsed = _parse_date_flexible(date_txt)
            date_str = parsed.strftime("%Y-%m-%d")
        except ValueError:
            return None
        avail = check_booking_availability(
            customer_uid=customer_uid, customer_name=customer_name,
            preferred_date=date_str,
        )
        if avail.get("error") or avail.get("status") == "error":
            return None
        slots = avail.get("available_slots") or []
        if slots:
            date_display = avail.get("date_display") or date_str
            return {
                "reply": _format_slots(slots, date_display),
                "tool_calls": [{"tool": "check_booking_availability",
                                "args": {"date": date_str},
                                "result": {"available_slots": slots}}],
                "model": "none", "intent": "BOOK_SERVICE",
            }

    return None  # anything ambiguous -> normal pipeline
