"""
Customer AI tools — strictly scoped to the logged-in customer's own data.

Vehicle lookup strategy (applied consistently across ALL functions):
  Pass 1 — Firestore query: owner == customer_name        (exact, indexed)
  Pass 2 — Firestore query: owner == companyName          (exact, only if
                                                           company differs)
  Pass 3 — Case-insensitive full scan over vehicles,      (always runs,
            skipping already-found doc IDs                 catches casing
                                                           mismatches from
                                                           manual admin input)

Service history lookup strategy:
  Step 1 — Resolve ALL plate numbers owned by this customer using the
            3-pass vehicle lookup above.
  Step 2 — Query maintenance WHERE plate IN [resolved plates]
  Step 3 — Keep only status == "Completed" records.

Booking lookup:
  Pass 1 — customerId == customer_uid  (UID-based, most reliable)
  Pass 2 — customerName == customer_name / companyName
  Pass 3 — Case-insensitive scan (last resort)

Privacy rules (enforced here, never delegated to the LLM):
  - NO data from other customers.
  - NO admin-only data: inventory, stock, issuances, deliveries.
  - customer_uid and customer_name are injected server-side from the
    authenticated Firebase session — the LLM cannot override them.
"""
import logging
import re
from datetime import datetime
from firestore_client import get_db
from google.cloud.firestore_v1.base_query import FieldFilter

logger = logging.getLogger(__name__)


# ── Firestore quota guard ─────────────────────────────────────────────────────

def _is_firestore_quota(exc: Exception) -> bool:
    msg = str(exc).lower()
    return (
        "quota exceeded"     in msg
        or "resource_exhausted" in msg
        or "resourceexhausted"  in msg
        or "429"                in msg
    )

def _quota_error() -> dict:
    return {
        "error": "QUOTA_EXCEEDED",
        "message": (
            "The database is temporarily unavailable due to a Firestore free-tier "
            "quota limit. Please try again in a few minutes."
        ),
    }


# ── Privacy / error helpers ───────────────────────────────────────────────────

def _privacy_error() -> dict:
    return {
        "error":   "ACCESS_DENIED",
        "message": "I can only show information for your own account.",
    }

def _db_error(exc: Exception) -> dict:
    return {"error": "DB_ERROR", "message": str(exc)}


# ── Currency helpers ──────────────────────────────────────────────────────────

def _strip_currency(value) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        cleaned = re.sub(r"[₱,\s]", "", value)
        try:
            return float(cleaned)
        except ValueError:
            return 0.0
    return 0.0

def _fmt_cost(value) -> str:
    amount = _strip_currency(value)
    return f"₱{amount:,.2f}" if amount else "—"


# ── Shared helpers ────────────────────────────────────────────────────────────

def _resolve_company_name(db, customer_uid: str) -> str:
    """Look up the customer's companyName from their users document."""
    try:
        doc = db.collection("users").document(customer_uid).get()
        if doc.exists:
            return doc.to_dict().get("companyName", "") or ""
    except Exception:
        pass
    return ""


def _iter_customer_vehicles(db, customer_name: str, company_name: str):
    """
    Yield Firestore vehicle documents that belong to this customer.

    Pass 1 — owner == customer_name  (exact Firestore query)
    Pass 2 — owner == company_name   (exact, only when company differs)
    Pass 3 — case-insensitive full collection scan, skipping already-yielded
             doc IDs.  Runs ALWAYS so casing mismatches from manual admin
             input are caught (e.g. "JOHN DELA CRUZ" vs "John Dela Cruz").
    """
    seen: set = set()
    name_lower    = customer_name.lower().strip()
    company_lower = company_name.lower().strip() if company_name else ""

    # Pass 1: exact match on owner == customer_name
    for doc in db.collection("vehicles").where(
            filter=FieldFilter("owner", "==", customer_name)).stream():
        if doc.id not in seen:
            seen.add(doc.id)
            yield doc

    # Pass 2: exact match on owner == company_name (when it differs)
    if company_name and company_lower != name_lower:
        for doc in db.collection("vehicles").where(
                filter=FieldFilter("owner", "==", company_name)).stream():
            if doc.id not in seen:
                seen.add(doc.id)
                yield doc

    # Pass 3: case-insensitive full scan — catches any casing/spacing mismatch
    for doc in db.collection("vehicles").stream():
        if doc.id in seen:
            continue
        stored = (doc.to_dict().get("owner", "") or "").lower().strip()
        if stored and (stored == name_lower or
                       (company_lower and stored == company_lower)):
            seen.add(doc.id)
            yield doc


def _get_customer_plates(db, customer_name: str, company_name: str) -> list:
    """
    Return a list of plate numbers for all vehicles owned by this customer.
    Uses _iter_customer_vehicles — same 3-pass strategy.
    """
    plates = []
    for doc in _iter_customer_vehicles(db, customer_name, company_name):
        p = doc.to_dict().get("plate", "")
        if p:
            plates.append(p)
    logger.info(
        "_get_customer_plates: owner=%r company=%r → plates=%s",
        customer_name, company_name, plates,
    )
    return plates


# ── Customer tools ────────────────────────────────────────────────────────────

def get_my_vehicles(customer_uid: str, customer_name: str, **_) -> dict:
    """
    Return all vehicles whose `owner` field matches this customer's name,
    with their current PMS status.
    """
    if not customer_name:
        return _privacy_error()
    logger.info("get_my_vehicles: uid=%s name=%r", customer_uid, customer_name)

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)
        vehicles     = []

        for doc in _iter_customer_vehicles(db, customer_name, company_name):
            d = doc.to_dict()
            vehicles.append({
                "plate":       d.get("plate", ""),
                "desc":        d.get("desc", "") or d.get("assetDescription", ""),
                "type":        d.get("type", ""),
                "status":      d.get("status", "Active"),
                "lastSvcDate": d.get("lastSvcDate", "") or d.get("lastServiceDate", ""),
                "svcFreq":     d.get("svcFreq", "") or str(d.get("serviceFrequency", "")),
                "odo":         d.get("odo", ""),
            })

        logger.info("get_my_vehicles: found %d vehicle(s) for %r", len(vehicles), customer_name)

        from collections import Counter
        status_counts = Counter(v["status"] for v in vehicles)
        return {
            "owner":          customer_name,
            "total_vehicles": len(vehicles),
            "status_summary": dict(status_counts),
            "vehicles":       vehicles,
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_my_vehicles error")
        return _db_error(e)


def get_my_service_history(customer_uid: str, customer_name: str,
                           plate: str | None = None, **_) -> dict:
    """
    Return completed maintenance jobs for this customer's vehicles.

    Step 1: resolve all plates belonging to the customer via owner-name lookup.
    Step 2: query maintenance WHERE plate IN [those plates].
    Step 3: keep only status == 'Completed'.

    If `plate` is given, restrict to that single plate only.
    """
    if not customer_name:
        return _privacy_error()
    logger.info("get_my_service_history: uid=%s name=%r plate=%r",
                customer_uid, customer_name, plate)

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)

        # Step 1 — resolve plates by owner name
        all_plates = _get_customer_plates(db, customer_name, company_name)

        if not all_plates:
            return {
                "owner":      customer_name,
                "plate":      plate or "all vehicles",
                "total_jobs": 0,
                "total_cost": "₱0.00",
                "jobs":       [],
            }

        # Narrow to a specific plate when requested
        if plate:
            target_plates = [p for p in all_plates if p.upper() == plate.upper()]
            if not target_plates:
                return {
                    "owner":      customer_name,
                    "plate":      plate,
                    "total_jobs": 0,
                    "total_cost": "₱0.00",
                    "jobs":       [],
                    "note":       f"No vehicle with plate {plate} found under your account.",
                }
        else:
            target_plates = all_plates

        # Step 2 — query maintenance by plate (Firestore 'in' max 10 — chunk)
        jobs = []
        for i in range(0, len(target_plates), 10):
            chunk = target_plates[i:i + 10]
            for doc in db.collection("maintenance").where(
                    filter=FieldFilter("plate", "in", chunk)).stream():
                d = doc.to_dict()

                # Step 3 — customers only see completed jobs
                if (d.get("status") or "").strip().lower() != "completed":
                    continue

                cost = _strip_currency(d.get("cost", 0))
                jobs.append({
                    "id":        d.get("id", doc.id),
                    "plate":     d.get("plate", ""),
                    "desc":      d.get("desc", ""),
                    "date":      d.get("date", ""),
                    "mechanic":  d.get("mechanic", ""),
                    "status":    d.get("status", ""),
                    "cost":      _fmt_cost(d.get("cost", 0)),
                    "cost_raw":  cost,
                    "services":  [r.get("name", "") for r in (d.get("svcRows") or [])],
                    "materials": [r.get("name", "") for r in (d.get("matRows") or [])],
                })

        jobs.sort(key=lambda j: j["date"], reverse=True)
        total_cost = sum(j["cost_raw"] for j in jobs)

        logger.info("get_my_service_history: %d completed job(s) for %r plates=%s",
                    len(jobs), customer_name, target_plates)
        return {
            "owner":      customer_name,
            "plate":      plate or "all vehicles",
            "total_jobs": len(jobs),
            "total_cost": _fmt_cost(total_cost),
            "jobs":       jobs,
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_my_service_history error")
        return _db_error(e)


def get_my_pms_status(customer_uid: str, customer_name: str, **_) -> dict:
    """
    Return PMS schedule status for each of this customer's vehicles.
    Vehicles are resolved by owner name using the same 3-pass strategy.
    """
    if not customer_name:
        return _privacy_error()

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)
        now          = datetime.now()
        vehicles     = []

        for doc in _iter_customer_vehicles(db, customer_name, company_name):
            d        = doc.to_dict()
            last_svc = d.get("lastSvcDate", "") or d.get("lastServiceDate", "")
            svc_freq = d.get("svcFreq", "") or str(d.get("serviceFrequency", ""))

            next_pms   = ""
            days_until = None
            try:
                if last_svc and svc_freq:
                    months  = int(svc_freq)
                    last_dt = datetime.fromisoformat(last_svc)
                    next_dt = datetime(
                        last_dt.year + (last_dt.month + months - 1) // 12,
                        (last_dt.month + months - 1) % 12 + 1,
                        last_dt.day,
                    )
                    next_pms   = next_dt.strftime("%b %d, %Y")
                    days_until = (next_dt - now).days
            except Exception:
                pass

            urgency = "Active"
            if days_until is not None:
                if days_until < 0:
                    urgency = "Overdue"
                elif days_until <= 7:
                    urgency = "Due This Week"
                elif days_until <= 30:
                    urgency = "Due Soon"

            vehicles.append({
                "plate":       d.get("plate", ""),
                "desc":        d.get("desc", "") or d.get("assetDescription", ""),
                "status":      d.get("status", "Active"),
                "lastSvcDate": last_svc,
                "nextPMS":     next_pms,
                "daysUntil":   days_until,
                "urgency":     urgency,
            })

        overdue  = [v for v in vehicles if v["urgency"] == "Overdue"]
        due_soon = [v for v in vehicles if v["urgency"] in ("Due This Week", "Due Soon")]

        return {
            "owner":    customer_name,
            "total":    len(vehicles),
            "overdue":  len(overdue),
            "due_soon": len(due_soon),
            "vehicles": vehicles,
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_my_pms_status error")
        return _db_error(e)


def get_my_bookings(customer_uid: str, customer_name: str, **_) -> dict:
    """
    Return this customer's service bookings (all statuses).

    Pass 1: customerId == customer_uid  (UID — most reliable)
    Pass 2: customerName == customer_name / companyName
    Pass 3: case-insensitive scan (last resort, only when 1+2 found nothing)
    """
    if not customer_name:
        return _privacy_error()

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)
        name_lower   = customer_name.lower()
        company_lower = company_name.lower() if company_name else ""

        bookings   = []
        seen_b_ids = set()

        def _add(doc):
            if doc.id in seen_b_ids:
                return
            seen_b_ids.add(doc.id)
            d    = doc.to_dict()
            svcs = d.get("services", [])
            bookings.append({
                "date":     d.get("preferredDate", ""),
                "time":     d.get("preferredTime", ""),
                "plate":    d.get("plate", ""),
                "vehicle":  d.get("vehicleDesc", ""),
                "services": ", ".join(svcs) if isinstance(svcs, list) else str(svcs),
                "status":   d.get("status", ""),
            })

        # Pass 1: by Firebase UID
        for doc in db.collection("service_bookings").where(
                filter=FieldFilter("customerId", "==", customer_uid)).stream():
            _add(doc)

        # Pass 2a: exact customerName
        for doc in db.collection("service_bookings").where(
                filter=FieldFilter("customerName", "==", customer_name)).stream():
            _add(doc)

        # Pass 2b: company name
        if company_name and company_lower != name_lower:
            for doc in db.collection("service_bookings").where(
                    filter=FieldFilter("customerName", "==", company_name)).stream():
                _add(doc)

        # Pass 3: case-insensitive scan — only when nothing found yet
        if not bookings and customer_name:
            for doc in db.collection("service_bookings").stream():
                if doc.id in seen_b_ids:
                    continue
                stored = (doc.to_dict().get("customerName", "") or "").lower().strip()
                if stored and (stored == name_lower or
                               (company_lower and stored == company_lower)):
                    _add(doc)

        bookings.sort(key=lambda b: b["date"], reverse=True)
        pending   = [b for b in bookings if (b["status"] or "").lower() == "pending"]
        confirmed = [b for b in bookings if (b["status"] or "").lower() in
                     ("confirmed", "in progress", "ongoing")]

        return {
            "owner":     customer_name,
            "total":     len(bookings),
            "pending":   len(pending),
            "confirmed": len(confirmed),
            "bookings":  bookings,
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_my_bookings error")
        return _db_error(e)


def get_service_prices(customer_uid: str, customer_name: str,
                       service_name: str | None = None, **_) -> dict:
    """
    Return services and prices from the item catalog.
    Public information — any authenticated customer may view it.
    """
    try:
        db       = get_db()
        services = []
        for doc in db.collection("item_master").where(
                filter=FieldFilter("type", "==", "Service")).stream():
            d    = doc.to_dict()
            name = d.get("name", "")
            if service_name and service_name.lower() not in name.lower():
                continue
            services.append({
                "num":   d.get("num", ""),
                "name":  name,
                "group": d.get("group", ""),
                "uom":   d.get("uom", ""),
                "cost":  _fmt_cost(d.get("cost", 0)),
            })

        services.sort(key=lambda s: s["name"])
        return {
            "filter":         service_name or "all services",
            "total_services": len(services),
            "services":       services,
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        return _db_error(e)


def estimate_service_cost(customer_uid: str, customer_name: str,
                          service_names: list[str], **_) -> dict:
    """
    Estimate combined cost for one or more named services.
    """
    try:
        db      = get_db()
        catalog = {}
        for doc in db.collection("item_master").where(
                filter=FieldFilter("type", "==", "Service")).stream():
            d = doc.to_dict()
            catalog[d.get("name", "").lower()] = {
                "name": d.get("name", ""),
                "cost": _strip_currency(d.get("cost", 0)),
                "uom":  d.get("uom", ""),
            }

        matched   = []
        unmatched = []
        total     = 0.0

        for svc in service_names:
            key  = svc.lower().strip()
            item = catalog.get(key)
            if not item:
                for k, v in catalog.items():
                    if key in k or k in key:
                        item = v
                        break
            if item:
                matched.append({
                    "service": item["name"],
                    "cost":    _fmt_cost(item["cost"]),
                    "uom":     item["uom"],
                })
                total += item["cost"]
            else:
                unmatched.append(svc)

        return {
            "requested":       service_names,
            "matched":         matched,
            "unmatched":       unmatched,
            "estimated_total": _fmt_cost(total),
            "note": (
                "Some services were not found in the catalog. "
                "Please ask for the full service list to see available options."
                if unmatched else ""
            ),
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        return _db_error(e)


# ── Tool schemas (OpenAI / Groq format) ──────────────────────────────────────
# customer_uid and customer_name are NOT listed as parameters — they are
# injected server-side so the LLM cannot substitute a different customer.

CUSTOMER_TOOL_SCHEMAS = [
    {
        "type": "function",
        "function": {
            "name": "get_my_vehicles",
            "description": (
                "Return all vehicles registered under the logged-in customer's name, "
                "including their current PMS status (Active, Overdue, Due Soon, Under Maintenance). "
                "ALWAYS use this tool when the customer asks about THEIR OWN vehicles — "
                "regardless of phrasing: 'all my vehicles', 'my fleet', 'my cars', "
                "'list my vehicles', 'show all my vehicles', 'how many vehicles do I have', "
                "'fleet summary', etc."
            ),
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_my_service_history",
            "description": (
                "Return all completed maintenance/service records for the customer's vehicles. "
                "Shows job date, plate, services performed, materials used, cost per job, "
                "and total amount spent across all vehicles. "
                "Use for: 'service history', 'past services', 'how much have I spent', "
                "'maintenance records', 'show my service history', 'pms history', "
                "'completed maintenance', 'service records per car'. "
                "Optionally filter by a specific plate number."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "plate": {
                        "type": "string",
                        "description": "Specific plate number to filter by. Omit to get history for all vehicles.",
                    },
                },
                "required": [],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_my_pms_status",
            "description": (
                "Return the Preventive Maintenance Schedule (PMS) status for each of the "
                "customer's vehicles: last service date, next PMS due date, days until due "
                "(negative means overdue). "
                "Use for: 'when is my next PMS', 'which cars are overdue', "
                "'PMS schedule', 'maintenance due', 'due soon'."
            ),
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_my_bookings",
            "description": (
                "Return the customer's own service booking appointments — pending, "
                "confirmed, or completed. "
                "Use for: 'my bookings', 'my appointments', 'upcoming service', "
                "'did I book a service', 'show my bookings'."
            ),
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_service_prices",
            "description": (
                "Return the list of available services and their prices from the shop catalog. "
                "Public — any customer can view. "
                "Use for: 'how much is a change oil', 'list of services', 'service prices', "
                "'what services do you offer', 'how much is [service name]'."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "service_name": {
                        "type": "string",
                        "description": "Keyword to filter services. E.g. 'oil change', 'brake'. Omit to list all.",
                    },
                },
                "required": [],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "estimate_service_cost",
            "description": (
                "Estimate the combined cost for one or more named services. "
                "Use when the customer asks: "
                "'how much would a change oil and brake cleaning cost?', "
                "'estimate the cost for X and Y', 'if I get X and Y how much total?'."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "service_names": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of service names to estimate combined cost for.",
                    },
                },
                "required": ["service_names"],
                "additionalProperties": False,
            },
        },
    },
]

CUSTOMER_TOOL_FUNCTIONS = {
    "get_my_vehicles":        get_my_vehicles,
    "get_my_service_history": get_my_service_history,
    "get_my_pms_status":      get_my_pms_status,
    "get_my_bookings":        get_my_bookings,
    "get_service_prices":     get_service_prices,
    "estimate_service_cost":  estimate_service_cost,
}
