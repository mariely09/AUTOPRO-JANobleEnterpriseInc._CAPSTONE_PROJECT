"""
Customer AI tools — strictly scoped to the logged-in customer's own data.

Rules enforced here (never trust the LLM alone):
  - Every vehicle query filters by owner == customer_name
  - Every maintenance query filters by plate IN customer's plates
  - Every booking query filters by customerId == customer_uid
  - Pricing / catalog queries are public (no customer PII exposed)
  - NO admin data: no stock levels, no issuances, no deliveries, no other users

All functions receive `customer_uid` and `customer_name` so Firestore
filtering happens server-side, not post-fetch.

PRIVACY GUARD: `customer_name` and `customer_uid` are injected by the backend
from the authenticated Firebase session — the LLM cannot override these values
through its function arguments. Any argument named differently is ignored.
"""
import re
from datetime import datetime
from firestore_client import get_db
from google.cloud.firestore_v1.base_query import FieldFilter


# ── Privacy helpers ───────────────────────────────────────────────────────────

def _privacy_error() -> dict:
    """Standard response when a tool detects an out-of-scope data access attempt."""
    return {
        "error": "ACCESS_DENIED",
        "message": "I can only show information for your own account.",
    }


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


# ── Customer tools ────────────────────────────────────────────────────────────

def get_my_vehicles(customer_uid: str, customer_name: str, **_) -> dict:
    """Return all vehicles owned by this customer with their current PMS status."""
    if not customer_name or not customer_uid:
        return _privacy_error()

    db = get_db()
    vehicles = []
    for doc in db.collection("vehicles").where(
            filter=FieldFilter("owner", "==", customer_name)).stream():
        d = doc.to_dict()
        vehicles.append({
            "plate":       d.get("plate", ""),
            "desc":        d.get("desc", ""),
            "type":        d.get("type", ""),
            "status":      d.get("status", "Active"),
            "lastSvcDate": d.get("lastSvcDate", ""),
            "svcFreq":     d.get("svcFreq", ""),
            "odo":         d.get("odo", ""),
        })

    from collections import Counter
    status_counts = Counter(v["status"] for v in vehicles)
    return {
        "owner":          customer_name,
        "total_vehicles": len(vehicles),
        "status_summary": dict(status_counts),
        "vehicles":       vehicles,
    }


def get_my_service_history(customer_uid: str, customer_name: str,
                           plate: str | None = None, **_) -> dict:
    """
    Return completed maintenance jobs for this customer's vehicles.
    Optionally filter by a specific plate number.
    """
    if not customer_name or not customer_uid:
        return _privacy_error()

    db = get_db()

    # Get this customer's plates first
    plate_list = []
    for doc in db.collection("vehicles").where(
            filter=FieldFilter("owner", "==", customer_name)).stream():
        p = doc.to_dict().get("plate", "")
        if p:
            plate_list.append(p)

    if not plate_list:
        return {"owner": customer_name, "total_jobs": 0, "total_cost": "₱0.00", "jobs": []}

    # Filter to specific plate if requested
    if plate:
        plate_list = [p for p in plate_list if p.upper() == plate.upper()]
        if not plate_list:
            return {
                "owner": customer_name, "plate": plate,
                "total_jobs": 0, "total_cost": "₱0.00", "jobs": [],
                "note": f"No vehicle with plate {plate} found under your account.",
            }

    # Firestore 'in' max 10 — chunk if needed
    jobs = []
    for i in range(0, len(plate_list), 10):
        chunk = plate_list[i:i+10]
        for doc in db.collection("maintenance").where(
                filter=FieldFilter("plate", "in", chunk)).stream():
            d = doc.to_dict()
            # Only show completed jobs to the customer
            if (d.get("status") or "").lower() != "completed":
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

    return {
        "owner":      customer_name,
        "plate":      plate or "all vehicles",
        "total_jobs": len(jobs),
        "total_cost": _fmt_cost(total_cost),
        "jobs":       jobs[:20],   # cap at 20 most recent
    }


def get_my_pms_status(customer_uid: str, customer_name: str, **_) -> dict:
    """Return PMS schedule status for each of this customer's vehicles."""
    if not customer_name or not customer_uid:
        return _privacy_error()

    db = get_db()
    now = datetime.now()
    vehicles = []

    for doc in db.collection("vehicles").where(
            filter=FieldFilter("owner", "==", customer_name)).stream():
        d = doc.to_dict()
        plate      = d.get("plate", "")
        last_svc   = d.get("lastSvcDate", "")
        svc_freq   = d.get("svcFreq", "")
        status     = d.get("status", "Active")

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
            "plate":       plate,
            "desc":        d.get("desc", ""),
            "status":      status,
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


def get_my_bookings(customer_uid: str, customer_name: str, **_) -> dict:
    """Return this customer's service bookings (all statuses)."""
    if not customer_name or not customer_uid:
        return _privacy_error()

    db = get_db()
    bookings = []

    # Primary filter: by customerId (Firebase UID)
    for doc in db.collection("service_bookings").where(
            filter=FieldFilter("customerId", "==", customer_uid)).stream():
        d = doc.to_dict()
        svcs = d.get("services", [])
        bookings.append({
            "date":     d.get("preferredDate", ""),
            "time":     d.get("preferredTime", ""),
            "plate":    d.get("plate", ""),
            "vehicle":  d.get("vehicleDesc", ""),
            "services": ", ".join(svcs) if isinstance(svcs, list) else str(svcs),
            "status":   d.get("status", ""),
        })

    # Fallback: by customerName (for older bookings that may not have customerId)
    if not bookings:
        for doc in db.collection("service_bookings").where(
                filter=FieldFilter("customerName", "==", customer_name)).stream():
            d = doc.to_dict()
            svcs = d.get("services", [])
            bookings.append({
                "date":     d.get("preferredDate", ""),
                "time":     d.get("preferredTime", ""),
                "plate":    d.get("plate", ""),
                "vehicle":  d.get("vehicleDesc", ""),
                "services": ", ".join(svcs) if isinstance(svcs, list) else str(svcs),
                "status":   d.get("status", ""),
            })

    bookings.sort(key=lambda b: b["date"], reverse=True)
    pending   = [b for b in bookings if (b["status"] or "").lower() == "pending"]
    confirmed = [b for b in bookings if (b["status"] or "").lower() in ("confirmed", "in progress", "ongoing")]

    return {
        "owner":     customer_name,
        "total":     len(bookings),
        "pending":   len(pending),
        "confirmed": len(confirmed),
        "bookings":  bookings,
    }


def get_service_prices(customer_uid: str, customer_name: str,
                       service_name: str | None = None, **_) -> dict:
    """
    Return the list of services and their prices from the item catalog.
    This is public pricing information — any authenticated customer can view it.
    Optionally filter by service name keyword.
    """
    db = get_db()
    services = []
    for doc in db.collection("item_master").where(
            filter=FieldFilter("type", "==", "Service")).stream():
        d = doc.to_dict()
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
        "filter":          service_name or "all services",
        "total_services":  len(services),
        "services":        services,
    }


def estimate_service_cost(customer_uid: str, customer_name: str,
                          service_names: list[str], **_) -> dict:
    """
    Estimate the total cost for one or more services by name.
    Used when a customer asks 'how much would a change oil + brake cleaning cost?'
    """
    db = get_db()
    matched   = []
    unmatched = []
    total     = 0.0

    # Load all services once
    catalog = {}
    for doc in db.collection("item_master").where(
            filter=FieldFilter("type", "==", "Service")).stream():
        d = doc.to_dict()
        catalog[d.get("name", "").lower()] = {
            "name": d.get("name", ""),
            "cost": _strip_currency(d.get("cost", 0)),
            "uom":  d.get("uom", ""),
        }

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


# ── Tool schemas (OpenAI / Groq format) ──────────────────────────────────────
# NOTE: customer_uid and customer_name are NOT listed as parameters here —
# they are injected server-side from the authenticated session so the LLM
# cannot attempt to pass a different customer's identity.

CUSTOMER_TOOL_SCHEMAS = [
    {
        "type": "function",
        "function": {
            "name": "get_my_vehicles",
            "description": (
                "Return all vehicles registered under the logged-in customer's name, "
                "including their current PMS status (Active, Overdue, Due Soon, Under Maintenance). "
                "Use for: 'my fleet', 'my vehicles', 'list my cars', 'fleet summary', "
                "'how many vehicles do I have', 'show my vehicles'."
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
                "Return the completed maintenance/service history for the customer's vehicles. "
                "Shows job date, services performed, cost per job, and total spent. "
                "Use for: 'service history', 'past services', 'how much have I spent', "
                "'maintenance records', 'show my service history'. "
                "Optionally filter by a specific plate number."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "plate": {
                        "type": "string",
                        "description": "Specific plate number to filter by. Omit for all vehicles.",
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
                "(negative = overdue). "
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
                "Public information — any customer can ask about pricing. "
                "Use for: 'how much is a change oil', 'list of services', 'service prices', "
                "'what services do you offer', 'Oil Change price', 'how much is [service name]'."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "service_name": {
                        "type": "string",
                        "description": (
                            "Keyword to filter services by name. "
                            "E.g. 'oil change', 'brake'. Omit to list all services."
                        ),
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
                "Estimate the total cost for one or more named services. "
                "Use when the customer asks: "
                "'how much would a change oil and brake cleaning cost?', "
                "'estimate the cost for change ATF and change coolant', "
                "'if I get X and Y, how much total?'."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "service_names": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of service names to estimate the combined cost for.",
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
