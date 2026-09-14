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

  "When will be the earliest schedule for service?"
          -> fetches customer vehicles + PMS recommendations (0 LLM calls)
          -> scans next 7 days for the first open slot
          -> presents earliest date/time with vehicle + maintenance context
          -> user picks a time -> booked

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
    get_service_recommendations,
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
    # Month-day with optional year so "January 1, 2030" keeps its year
    r"|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s*\d{4})?)\b",
    re.IGNORECASE,
)

# "earliest" / "as soon as possible" — user wants the first open slot
_EARLIEST_RE = re.compile(
    r"\b(earliest|asap|as\s+soon\s+as\s+possible|soonest|first\s+available|"
    r"anytime|any\s+(?:time|day)|soonest\s+schedule|"
    r"when\s+will\s+be\s+the\s+earliest|when\s+is\s+the\s+earliest|"
    r"what\s+is\s+the\s+earliest|what'?s\s+the\s+earliest|"
    r"when\s+can\s+i\s+(bring|come|drop\s+off)|"
    r"what\s+is\s+the\s+next\s+available|what\s+is\s+the\s+soonest)\b",
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

# Assistant turn that offered concrete slots/summary for a specific date
_SLOT_OFFER_RE = re.compile(
    r"available times for|earliest available schedule|available slots",
    re.IGNORECASE,
)

_AFFIRM_RE = re.compile(r"\b(yes|yeah|yep|ok|okay|sure|sige|go\s+ahead|"
                        r"please\s+do|confirm|book\s+it|tuloy)\b", re.IGNORECASE)
_NEGATE_RE = re.compile(r"\b(no|nope|not\s+that|cancel|wag|ayoko|"
                        r"different|other|another)\b", re.IGNORECASE)

# Marker line embedded in the confirmation summary. The next user message is
# treated as a confirmation ONLY when this marker exists in recent history —
# a bare "yes" to an unrelated question must never book anything.
_CONFIRM_MARKER = "[BOOKING-CONFIRM]"

# Generic booking phrases with no concrete service named. They must still
# enter the gather flow (and ask for the service) instead of falling through.
_GENERIC_BOOK_RE = re.compile(
    r"\b(i\s+want\s+to\s+book|i\s+need\s+to\s+book|book\s+(a\s+|an\s+|my\s+)?service"
    r"|schedule\s+(a\s+|an\s+|my\s+)?service|i\s+want\s+to\s+have\s+my\s+(car|vehicle)\s+serviced"
    r"|have\s+my\s+(car|vehicle)\s+serviced|can\s+you\s+book\s+my\s+(car|vehicle)"
    r"|can\s+i\s+schedule\s+my\s+(car|vehicle)|pa\s*book|pabook|pa\s*schedule|paschedule"
    r"|book\s+me|i\s+want\s+to\s+schedule\s+pms|i\s+want\s+to\s+schedule\s+a)",
    re.IGNORECASE,
)

# Denials that cancel a pending confirmation (checked BEFORE affirmation).
_CANCEL_RE = re.compile(
    r"\b(no|nope|not\s+yet|don'?t|do\s+not|stop|wait|cancel|wag|ayoko|huwag|"
    r"never\s*mind|nevermind|change\s+(the\s+)?(date|time|vehicle|service)|"
    r"not\s+that|wrong)\b",
    re.IGNORECASE,
)

_DATE_ONLY_RE = re.compile(
    r"^\s*(?:on\s+|sa\s+|how\s+about\s+|what\s+about\s+|make\s+it\s+|move\s+it\s+to\s+|change\s+it\s+to\s+)?"
    r"(today|tomorrow|next\s+(?:mon|tues|wednes|thurs|fri|satur|sun)day"
    r"|(?:mon|tues|wednes|thurs|fri|satur|sun)day"
    r"|\d{4}-\d{1,2}-\d{1,2}|\d{1,2}/\d{1,2}/\d{4}"
    r"|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s*\d{4})?)"
    r"\s*(?:please|po|sana|na)?\s*\.?\s*$",
    re.IGNORECASE,
)

_TIME_ONLY_RE = re.compile(
    r"^\s*(?:at\s+|sa\s+|how\s+about\s+|what\s+about\s+|make\s+it\s+|move\s+it\s+to\s+|change\s+it\s+to\s+)?"
    r"(?:(1[0-2]|0?[1-9])(?::([0-5][0-9]))?\s*(am|pm|a\.m\.|p\.m\.)"
    r"|(1[0-9]|2[0-4]|0?[0-9]):([0-5][0-9]))"
    r"\s*(?:please|po|sana|na)?\s*\.?\s*$",
    re.IGNORECASE,
)


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
    if not specific:
        # Only generic words ("book a service", "have my car serviced") —
        # no CONCRETE service named yet. Never book a fabricated "Service";
        # ask the customer what they need instead.
        return None
    seen, out = set(), []
    for s in specific:
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

def _read_pending_confirmation(history: list[dict]) -> dict | None:
    """
    Read the pending booking details from the confirmation summary in recent
    history, so the customer's "yes" (or new date/time) continues THAT booking.
    Returns {} fields with the marker present, or None when no summary is
    pending. Only values actually present in the summary are carried forward.
    """
    for m in reversed(history[-4:] if history else []):
        if m.get("role") != "assistant":
            continue
        c = m.get("content") or ""
        if _CONFIRM_MARKER not in c:
            continue
        fields: dict = {}
        pm = _PLATE_RE.search(c.upper())
        if pm:
            fields["plate"] = pm.group(1).replace(" ", "-")
        dm = _DATE_WORDS_RE.search(c)
        if dm:
            fields["date_txt"] = dm.group(1)
        tm = _TIME_RE.search(c)
        if tm:
            fields["time_txt"] = _extract_time(c)
        svcs = _extract_service(c)
        if svcs:
            fields["services"] = svcs
        return fields
    return None


def _format_confirmation(plate: str, services: list[str],
                         date_display: str, time_txt: str) -> str:
    """Pre-booking summary the customer must confirm before anything is saved."""
    svc_list = ", ".join(services)
    return (
        "📋 **Booking Preview**\n\n"
        "Please review your booking details carefully:\n\n"
        f"• **Vehicle:** {plate}\n"
        f"• **Service(s):** {svc_list}\n"
        f"• **Date:** {date_display}\n"
        f"• **Time:** {time_txt}\n\n"
        "**Please confirm:** Type **yes** to proceed with this booking, or **no** to cancel. {_CONFIRM_MARKER}"
    )


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

    # Informational-question gate: a question ABOUT a service is not a
    # booking REQUEST. "What does a transmission flush do?" / "How much is an
    # oil change?" must be answered, not hijacked into the booking flow.
    # Only fall through when there is no concrete booking signal alongside it.
    _QUESTION_RE = re.compile(
        r"\b(what\s+(is|are|does|do)|what's|how\s+(does|do|much|often)|why\s+is|"
        r"explain|meaning\s+of|difference\s+between|ano\s+po?\s+ba|ano\s+ba|"
        r"magkano)\b",
        re.IGNORECASE,
    )
    _has_booking_signal = bool(
        _EARLIEST_RE.search(text) or _DATE_WORDS_RE.search(text)
        or _TIME_RE.search(text) or _PLATE_RE.search(text)
        or re.search(r"\b(book|booking|schedule|sched|reserve|reservation|"
                     r"pa-book|pabook|i-book)\b", t)
    )
    if _QUESTION_RE.search(t) and not _has_booking_signal:
        return None  # informational — let the normal pipeline answer it

    # ── Collect required fields from message + recent history ────────────────
    plate = _extract_plate(text)
    services = _extract_service(text)
    date_txt = _extract_date_text(text)
    time_txt = _extract_time(text)
    msg_date_any = _DATE_WORDS_RE.search(text)
    msg_time_any = _TIME_RE.search(text)

    # Date/time replies with filler words ("make it 2pm", "how about sept 15",
    # "January 1, 2030") still count when they are the ONLY new information.
    if date_txt and not time_txt and not plate and not services:
        if _DATE_ONLY_RE.match(text):
            date_txt = _DATE_ONLY_RE.match(text).group(1)
        elif msg_date_any and not msg_time_any:
            date_txt = msg_date_any.group(1)
        else:
            date_txt = None
    if time_txt and not date_txt and not plate and not services:
        if _TIME_ONLY_RE.match(text):
            time_txt = _extract_time(text)
        elif msg_time_any and not msg_date_any:
            time_txt = _extract_time(text)
        else:
            time_txt = None

    raw_any = bool(plate or services or date_txt or time_txt)
    booking_phrase = bool(_GENERIC_BOOK_RE.search(t))

    if not (raw_any or booking_phrase or earliest
            or _AFFIRM_RE.search(t) or _NEGATE_RE.search(t)):
        return None  # not booking-shaped at all

    # Carry known values from the previous gather turn (context continuity).
    # IMPORTANT: Only scan USER messages for service/plate carry-over.
    # Scanning assistant messages risks picking up service names that the AI
    # suggested (e.g. "I'd be happy to book Brake Service") — the customer
    # never confirmed that, so it must not be inherited as their choice.
    prev_plate = prev_services = None
    for m in reversed(history[-4:] if history else []):
        c = m.get("content") or ""
        role = m.get("role", "")
        # Plates: allow from user messages only (assistant vehicle-menu lists
        # are the shop's inventory, not the customer's choice).
        if not prev_plate and role == "user":
            p = _extract_plate(c)
            if p:
                prev_plate = p
        # Services: ONLY from user messages — never from assistant messages.
        # An assistant saying "I can book Brake Service for you" must not
        # cause the next user turn to inherit Brake Service as their intent.
        if not prev_services and role == "user":
            s = _extract_service(c)
            if s:
                prev_services = s

    plate = plate or prev_plate
    if not services and prev_services:
        services = prev_services
    # Treat "the usual"/"same service" style affirmations without specifics
    if not services and _AFFIRM_RE.search(t) and _extract_service(str(history or "")):
        services = prev_services

    # Pending booking confirmation (read ONCE; used by the carry logic below
    # and the confirmation handling further down).
    pending = _read_pending_confirmation(history)

    # ── Carry the customer's OWN previously-stated date/time ─────────────────
    # "I want an oil change tomorrow 9am" -> "ABC-1234" must NOT re-ask for
    # the date/time the customer already gave. Only carried while a booking
    # is clearly in progress (plate/service/booking phrase present), so an
    # unrelated question never inherits an old date. Current message always
    # wins over history.
    _mid_booking = bool(plate or services or booking_phrase or pending)
    if _mid_booking and (not date_txt or not time_txt):
        for m in reversed(history[-4:] if history else []):
            if m.get("role") != "user":
                continue
            uc = m.get("content") or ""
            if not date_txt:
                dm = _DATE_WORDS_RE.search(uc)
                if dm:
                    date_txt = dm.group(1)
            if not time_txt and _TIME_RE.search(uc):
                time_txt = _extract_time(uc)
            if date_txt and time_txt:
                break

    # Carry the "earliest schedule" intent from a recent turn so a two-step
    # request ("earliest schedule?" -> "ABC-1234, oil change") still lands on
    # the availability scan instead of re-asking for a date.
    if not earliest:
        for m in reversed(history[-4:] if history else []):
            if m.get("role") == "assistant" and _EARLIEST_RE.search(m.get("content") or ""):
                earliest = True
                break

    # Carry date/time ONLY from slot-offer / confirmation-summary assistant
    # turns ("...available times for September 15, 2026..."), so a reply like
    # "9am" continues that offer instead of inheriting an unrelated date.
    if not date_txt or not time_txt:
        for m in reversed(history[-4:] if history else []):
            if m.get("role") != "assistant":
                continue
            c = m.get("content") or ""
            if not (_CONFIRM_MARKER in c or _SLOT_OFFER_RE.search(c)):
                continue
            if not date_txt:
                dm = _DATE_WORDS_RE.search(c)
                if dm:
                    date_txt = dm.group(1)
            if not time_txt and _TIME_RE.search(c):
                time_txt = _extract_time(c)
            break

    # ── Pending booking confirmation? ─────────────────────────────────────────
    # A confirmation summary is awaiting a reply: "yes" books it, a denial
    # cancels it, and a date/time correction updates the fields. Bare replies
    # only continue a booking when the marker exists — a random "yes" to any
    # other question can NEVER create a booking.
    if pending is not None and not raw_any:
        if _CANCEL_RE.search(t):
            return {
                "reply": ("No problem \u2014 that booking was not saved. "
                          "Just tell me the details again whenever you're ready."),
                "tool_calls": [], "model": "none", "intent": "BOOK_SERVICE",
            }
        if _AFFIRM_RE.search(t):
            plate    = pending.get("plate") or plate
            services = pending.get("services") or services
            date_txt = pending.get("date_txt") or date_txt
            time_txt = pending.get("time_txt") or time_txt
    elif pending is not None and (date_txt or time_txt):
        # Correction to the pending booking: replace only the provided field.
        if time_txt and not date_txt:
            date_txt = pending.get("date_txt")
        if date_txt and not time_txt:
            time_txt = pending.get("time_txt")
        plate    = plate or pending.get("plate")
        services = services or pending.get("services")

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
            # Match a customer-typed plate against the registered format
            # ("HDK-8638" typed vs "HDK 8638" registered).
            elif plate and vehicles:
                import re as _re
                _key = _re.sub(r"[\s\-]", "", plate).upper()
                for _v in vehicles:
                    if _re.sub(r"[\s\-]", "", _v.get("plate") or "").upper() == _key:
                        plate = (_v.get("plate") or plate).strip()
                        break

    # ── Case 1: not enough info yet -> ask for ONLY the missing pieces ───────
    # For "earliest schedule" queries, we allow proceeding without a named
    # service — the scan runs and we recommend based on PMS data. Only block
    # when the vehicle itself is unknown and there are multiple vehicles.
    if not plate or not services or (not date_txt and not earliest and not time_txt):
        vcount = len(vehicles) if vehicles is not None else 0

        # Earliest-schedule: if we have a plate (or only one vehicle), scan
        # immediately even without a named service. The reply will include
        # PMS-based recommendation context.
        if earliest and plate:
            pass  # fall through to Case 2 below

        # Multiple vehicles and no plate given -> show the actual plate list
        elif not plate and vehicles and len(vehicles) > 1:
            plates = ", ".join((v.get("plate") or "?") for v in vehicles)
            svc_txt = " for " + services[0] if services else ""
            svc_ask = ("" if services
                       else " And what service do you need (e.g. change oil, PMS, brake service)?")
            if earliest:
                ask = (f"I'd be happy to find the earliest available schedule{svc_txt}! "
                       f"Which vehicle should I check — {plates}?")
            else:
                ask = (f"I'd be happy to book{svc_txt} for you! "
                       f"Which vehicle should I book — {plates}?"
                       f"{svc_ask} "
                       "(I'll also need your preferred date and time, or I can "
                       "suggest the earliest available schedule.)")
            return {
                "reply": ask,
                "tool_calls": [{"tool": "get_my_vehicles", "args": {},
                                "result": {"count": vcount, "plates": plates,
                                           "asked_vehicle_choice": True}}],
                "model": "none",
                "intent": "BOOK_SERVICE",
            }
        else:
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
            # ── Fetch PMS recommendation context for this vehicle ─────────────
            pms_context = ""
            recommended_service = None
            if plate:
                try:
                    recs = get_service_recommendations(
                        customer_uid=customer_uid,
                        customer_name=customer_name,
                    )
                    if recs and not recs.get("error"):
                        for v in (recs.get("vehicles") or []):
                            if (v.get("plate") or "").upper() == plate.upper():
                                urgency = v.get("urgency", "")
                                next_pms = v.get("nextPMS", "")
                                desc = v.get("desc", "") or plate
                                if urgency == "Overdue":
                                    pms_context = (
                                        f"\n\n⚠️ Note: Your **{plate}** ({desc}) is "
                                        f"**overdue** for scheduled maintenance. "
                                        f"Booking at the earliest slot is strongly recommended."
                                    )
                                    recommended_service = services[0] if services else "PMS / Preventive Maintenance"
                                elif urgency in ("Due This Week", "Due Soon"):
                                    pms_context = (
                                        f"\n\n🔴 Note: Your **{plate}** ({desc}) is "
                                        f"due for maintenance on **{next_pms}**. "
                                        f"Booking now ensures timely service."
                                    )
                                    recommended_service = services[0] if services else "PMS / Preventive Maintenance"
                                elif next_pms:
                                    pms_context = (
                                        f"\n\nYour **{plate}** ({desc}) next scheduled "
                                        f"maintenance is on **{next_pms}**."
                                    )
                                break
                except Exception:
                    pass  # PMS context is best-effort; proceed without it

            svc_txt = ", ".join(services) if services else (recommended_service or "your service")

            start = datetime.now() + timedelta(days=1)
            for offset in range(14):  # scan up to 14 days for the first open slot
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
                    vehicle_note = f" for **{plate}**" if plate else ""
                    reply = (
                        f"The earliest available schedule{vehicle_note} is on "
                        f"**{date_display}**."
                        f"{pms_context}\n\n"
                        + _format_slots(slots, date_display)
                        + "\n\nReply with a time to confirm your booking."
                    )
                    # If the service is still unknown, ask for it alongside the time
                    if not services:
                        reply += (
                            "\n\nAlso, please let me know what **service** you need "
                            "(e.g. Change Oil, PMS, Brake Service) so I can include it in your booking."
                        )
                    return {
                        "reply": reply,
                        "tool_calls": [{"tool": "check_booking_availability",
                                        "args": {"date": ds},
                                        "result": {"available_slots": slots}}],
                        "model": "none",
                        "intent": "BOOK_SERVICE",
                    }
            # No open slot found in scan window
            return {
                "reply": (
                    "I checked the next 14 days but couldn't find any open slots. "
                    "Please contact us at janobleenterpriseinc.autopro@gmail.com "
                    "or visit the shop to arrange a schedule."
                ),
                "tool_calls": [],
                "model": "none",
                "intent": "BOOK_SERVICE",
            }
        except Exception:
            return None  # fall through to LLM path on any failure

    # ── Case 3: we have everything -> confirm, then check availability + book ─
    if plate and services and (date_txt or earliest) and time_txt:
        # Just confirmed a pending summary -> proceed to the actual booking.
        just_confirmed = (pending is not None and not raw_any
                          and bool(_AFFIRM_RE.search(t)))
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

        # ── Confirmation gate: summarize and ask before writing anything ──────
        # Only a customer who was just shown the summary and replied "yes"
        # reaches create_customer_booking. Availability was already verified
        # above, so the confirmed summary reflects a real open slot.
        if not just_confirmed:
            date_display = avail.get("date_display") or parsed.strftime("%B %d, %Y")
            return {
                "reply": _format_confirmation(plate, services, date_display, time_txt),
                "tool_calls": [{"tool": "check_booking_availability",
                                "args": {"date": date_str, "time": time_txt},
                                "result": {"requested_time_available": True}}],
                "model": "none", "intent": "BOOK_SERVICE",
            }

        res = create_customer_booking(
            customer_uid=customer_uid, customer_name=customer_name,
            plate=plate, services=services,
            preferred_date=date_str, preferred_time=time_txt,
        )
        if res.get("success"):
            svc_list = ", ".join(services)
            reply = (
                f"✅ Your booking is confirmed!\n\n"
                f"• Booking ID: **{res.get('booking_id', '')}**\n"
                f"• Vehicle: **{plate}**\n"
                f"• Service(s): **{svc_list}**\n"
                f"• Date: **{res.get('date', date_str)}**\n"
                f"• Time: **{time_txt}**\n"
                f"• Status: **{res.get('status', 'Pending')}**\n\n"
                "You can view it under **My Bookings** — we'll notify you once "
                "the shop confirms.\n\n"
                "Would you like to book another service?"
            )
            return {
                "reply": reply,
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
