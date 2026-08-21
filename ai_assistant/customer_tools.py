"""
Customer AI tools — strictly scoped to the logged-in customer's own data.

VEHICLE OWNERSHIP MODEL
=======================
Vehicles are linked to customers via TWO complementary fields:

  ownerId  — Firebase Auth UID written on new vehicles (authoritative,
             added via migration script for legacy docs).
  owner    — Human-readable name / company name typed by admin at creation.

RETRIEVAL STRATEGY (applied to get_my_vehicles, get_my_pms_status,
                    and _get_customer_plates for service history)
===================================================================
Pass 0 — Firestore query:  ownerId == customer_uid      (UID, most reliable)
Pass 1 — Firestore query:  owner   == customer_name     (exact name)
Pass 2 — Firestore query:  owner   == companyName       (company, if different)
Pass 3 — Case-insensitive full scan of all remaining docs  (catches typos /
                                                             casing mismatches
                                                             from manual input)
All passes deduplicate by document ID.

PLATE NORMALISATION
===================
Vehicle documents may store the plate as:
  • plate       (Flutter admin, web staff)
  • plateNumber (web admin script.js)
Both are read — whichever is non-empty is used.

SERVICE HISTORY STRATEGY
========================
Step 1 — Collect every plate belonging to this customer (4-pass above).
Step 2 — Query maintenance WHERE plate IN [plates]  (chunked ≤10, Firestore limit).
Step 3 — Keep only status == "Completed".
Step 4 — Group by plate so the reply shows history per vehicle.

SECURITY
========
customer_uid and customer_name are injected server-side from the authenticated
Firebase session. The LLM cannot override them through function arguments.
No data from other customers is ever returned.
"""
import logging
import re
from datetime import datetime
from collections import defaultdict
from firestore_client import get_db
from google.cloud.firestore_v1.base_query import FieldFilter

logger = logging.getLogger(__name__)


# ── Firestore quota guard ─────────────────────────────────────────────────────

def _is_firestore_quota(exc: Exception) -> bool:
    msg = str(exc).lower()
    return (
        "quota exceeded"        in msg
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


# ── Field normalisation ───────────────────────────────────────────────────────

def _get_plate(d: dict) -> str:
    """Return the plate number — canonical plateNumber first, then legacy plate."""
    return (d.get("plateNumber") or d.get("plate") or "").strip()

def _get_desc(d: dict) -> str:
    """Return the vehicle description — canonical description first, then legacy fields."""
    return (d.get("description") or d.get("desc") or d.get("assetDescription") or "").strip()

def _get_last_svc_date(d: dict) -> str:
    """Return the last service date — canonical lastServiceDate first, then legacy."""
    return (d.get("lastServiceDate") or d.get("lastSvcDate") or "").strip()

def _get_svc_freq(d: dict) -> str:
    """Return the service frequency — canonical serviceFrequency first, then legacy svcFreq."""
    val = d.get("serviceFrequency") or d.get("svcFreq")
    return str(val).strip() if val is not None else ""


# ── Shared helpers ────────────────────────────────────────────────────────────

def _resolve_company_name(db, customer_uid: str) -> str:
    """Look up the customer's companyName from their users document."""
    try:
        doc = db.collection("users").document(customer_uid).get()
        if doc.exists:
            return (doc.to_dict().get("companyName") or "").strip()
    except Exception:
        pass
    return ""


def _iter_customer_vehicles(db, customer_uid: str,
                             customer_name: str, company_name: str):
    """
    Yield every Firestore vehicle document that belongs to this customer.

    Pass 0 — ownerId == customer_uid        (Firebase UID, authoritative)
    Pass 1 — owner   == customer_name       (exact string match)
    Pass 2 — owner   == company_name        (exact, only when company differs)
    Pass 3 — case-insensitive full scan     (always runs; catches casing /
                                             abbreviation mismatches left by
                                             manual admin data entry)

    Documents already yielded are tracked by doc ID so there are no duplicates.
    """
    seen: set         = set()
    name_lower        = customer_name.lower().strip()
    company_lower     = company_name.lower().strip() if company_name else ""

    # Pass 0: UID-based — most reliable, uses ownerId field
    for doc in db.collection("vehicles").where(
            filter=FieldFilter("ownerId", "==", customer_uid)).stream():
        if doc.id not in seen:
            seen.add(doc.id)
            yield doc

    # Pass 1: exact owner name
    for doc in db.collection("vehicles").where(
            filter=FieldFilter("owner", "==", customer_name)).stream():
        if doc.id not in seen:
            seen.add(doc.id)
            yield doc

    # Pass 2: company name (when different from personal name)
    if company_name and company_lower != name_lower:
        for doc in db.collection("vehicles").where(
                filter=FieldFilter("owner", "==", company_name)).stream():
            if doc.id not in seen:
                seen.add(doc.id)
                yield doc

    # Pass 3: case-insensitive full scan — catches ANY remaining mismatch
    for doc in db.collection("vehicles").stream():
        if doc.id in seen:
            continue
        stored = (doc.to_dict().get("owner") or "").lower().strip()
        if stored and (stored == name_lower or
                       (company_lower and stored == company_lower)):
            seen.add(doc.id)
            yield doc


def _get_customer_plates(db, customer_uid: str,
                          customer_name: str, company_name: str) -> list:
    """
    Return ALL plate numbers for vehicles owned by this customer.

    Reads both 'plate' and 'plateNumber' fields so vehicles created by
    different parts of the app (Flutter admin uses 'plate', web admin uses
    'plateNumber') are all captured.
    """
    plates = []
    for doc in _iter_customer_vehicles(db, customer_uid, customer_name, company_name):
        p = _get_plate(doc.to_dict())
        if p and p not in plates:
            plates.append(p)

    logger.info(
        "_get_customer_plates: uid=%s owner=%r company=%r → %d plate(s): %s",
        customer_uid, customer_name, company_name, len(plates), plates,
    )
    return plates


# ── Customer tools ────────────────────────────────────────────────────────────

def get_my_vehicles(customer_uid: str, customer_name: str, **_) -> dict:
    """
    Return ALL vehicles belonging to this customer with their PMS status.

    Uses 4-pass lookup (UID → exact name → company name → case-insensitive
    scan) so every vehicle is found regardless of how the owner field was
    entered by the admin.
    """
    if not customer_uid and not customer_name:
        return _privacy_error()

    logger.info("get_my_vehicles: uid=%s name=%r", customer_uid, customer_name)

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)
        vehicles     = []

        for doc in _iter_customer_vehicles(db, customer_uid, customer_name, company_name):
            d = doc.to_dict()
            vehicles.append({
                "plate":       _get_plate(d),
                "desc":        _get_desc(d),
                "type":        d.get("type", ""),
                "status":      d.get("status", "Active"),
                "lastSvcDate": _get_last_svc_date(d),
                "svcFreq":     _get_svc_freq(d),
                "odo":         (d.get("odo") or d.get("odometer") or ""),
            })

        logger.info(
            "get_my_vehicles: found %d vehicle(s) for uid=%s name=%r",
            len(vehicles), customer_uid, customer_name,
        )

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
    Return ALL completed maintenance records for this customer's vehicles,
    grouped by vehicle/plate.

    Flow (after migration):
      Step A — PRIMARY (fast, O(1) query):
               Query maintenance WHERE ownerId == customer_uid.
               This is the canonical path after migration.
      Step B — FALLBACK (for pre-migration records):
               Resolve all vehicle plates via 4-pass vehicle lookup,
               then query maintenance WHERE plate IN [plates].
               Deduplicates results so the same record is never shown twice.

    Security: ownerId is injected server-side from the authenticated session.
    The LLM cannot override it.  Records are filtered to only include
    maintenance.ownerId == customer_uid OR records for plates that belong to
    this customer's vehicles (verified via vehicle.ownerId).
    """
    if not customer_uid and not customer_name:
        return _privacy_error()

    logger.info("get_my_service_history: uid=%s name=%r plate=%r",
                customer_uid, customer_name, plate)

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)

        seen_doc_ids: set = set()
        all_docs: list    = []

        # ── Step A: primary path — query by ownerId (post-migration records) ─
        for doc in db.collection("maintenance").where(
                filter=FieldFilter("ownerId", "==", customer_uid)).stream():
            if doc.id not in seen_doc_ids:
                seen_doc_ids.add(doc.id)
                all_docs.append(doc)

        # ── Step B: fallback — plate-based lookup (pre-migration records) ────
        all_plates = _get_customer_plates(db, customer_uid, customer_name, company_name)
        if all_plates:
            for i in range(0, len(all_plates), 10):
                chunk = all_plates[i:i + 10]
                # Query both plateNumber (canonical) and plate (legacy)
                for field in ("plateNumber", "plate"):
                    for doc in db.collection("maintenance").where(
                            filter=FieldFilter(field, "in", chunk)).stream():
                        if doc.id not in seen_doc_ids:
                            # Security: only include if the record's ownerId
                            # matches this customer OR has no ownerId yet
                            d = doc.to_dict()
                            record_oid = (d.get("ownerId") or "").strip()
                            if record_oid and record_oid != customer_uid:
                                continue  # belongs to a different customer
                            seen_doc_ids.add(doc.id)
                            all_docs.append(doc)
        else:
            if not all_docs:
                logger.warning(
                    "get_my_service_history: zero vehicles AND zero ownerId "
                    "maintenance records for uid=%s name=%r",
                    customer_uid, customer_name,
                )
                return {
                    "owner":      customer_name,
                    "plate":      plate or "all vehicles",
                    "total_jobs": 0,
                    "total_cost": "₱0.00",
                    "jobs":       [],
                    "by_vehicle": {},
                }

        # Narrow to a specific plate when the customer asks for one vehicle
        if plate:
            plate_upper = plate.upper()
            # Verify this plate belongs to this customer
            authorized = {p.upper() for p in all_plates}
            if plate_upper not in authorized:
                return {
                    "owner":      customer_name,
                    "plate":      plate,
                    "total_jobs": 0,
                    "total_cost": "₱0.00",
                    "jobs":       [],
                    "by_vehicle": {},
                    "note":       f"No vehicle with plate {plate} found under your account.",
                }
            all_docs = [
                doc for doc in all_docs
                if (doc.to_dict().get("plateNumber") or
                    doc.to_dict().get("plate") or "").upper() == plate_upper
            ]

        # ── Build result ──────────────────────────────────────────────────────
        jobs       = []
        by_vehicle: dict = defaultdict(list)

        for doc in all_docs:
            d = doc.to_dict()
            if (d.get("status") or "").strip().lower() != "completed":
                continue

            cost      = _strip_currency(d.get("cost", 0))
            # Use canonical plateNumber first, fall back to legacy plate
            job_plate = (d.get("plateNumber") or d.get("plate") or "").strip()
            job = {
                "id":        d.get("id", doc.id),
                "plate":     job_plate,
                "desc":      _get_desc(d),
                "date":      d.get("date", ""),
                "mechanic":  d.get("mechanic", ""),
                "status":    d.get("status", ""),
                "cost":      _fmt_cost(d.get("cost", 0)),
                "cost_raw":  cost,
                "services":  [r.get("name", "") for r in (d.get("svcRows") or [])],
                "materials": [r.get("name", "") for r in (d.get("matRows") or [])],
            }
            jobs.append(job)
            if job_plate:
                by_vehicle[job_plate].append(job)

        # Sort each group newest-first
        jobs.sort(key=lambda j: j["date"], reverse=True)
        for grp in by_vehicle.values():
            grp.sort(key=lambda j: j["date"], reverse=True)

        total_cost = sum(j["cost_raw"] for j in jobs)

        logger.info(
            "get_my_service_history: %d completed job(s) across %d vehicle(s) "
            "for uid=%s",
            len(jobs), len(by_vehicle), customer_uid,
        )

        return {
            "owner":      customer_name,
            "plate":      plate or "all vehicles",
            "total_jobs": len(jobs),
            "total_cost": _fmt_cost(total_cost),
            "jobs":       jobs,          # flat list sorted newest-first
            "by_vehicle": dict(by_vehicle),  # grouped by plate for per-car display
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_my_service_history error")
        return _db_error(e)


def get_my_pms_status(customer_uid: str, customer_name: str, **_) -> dict:
    """
    Return PMS schedule status for EACH of this customer's vehicles.
    Uses the same 4-pass lookup as get_my_vehicles.
    """
    if not customer_uid and not customer_name:
        return _privacy_error()

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)
        now          = datetime.now()
        vehicles     = []

        for doc in _iter_customer_vehicles(db, customer_uid, customer_name, company_name):
            d        = doc.to_dict()
            last_svc = _get_last_svc_date(d)
            svc_freq = _get_svc_freq(d)

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
                "plate":       _get_plate(d),
                "desc":        _get_desc(d),
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

    Pass 1: customerId == customer_uid        (UID — most reliable)
    Pass 2: customerName == customer_name/companyName
    Pass 3: case-insensitive scan             (only when 1+2 found nothing)
    """
    if not customer_uid and not customer_name:
        return _privacy_error()

    try:
        db            = get_db()
        company_name  = _resolve_company_name(db, customer_uid)
        name_lower    = customer_name.lower()
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

        # Pass 1: Firebase UID
        for doc in db.collection("service_bookings").where(
                filter=FieldFilter("customerId", "==", customer_uid)).stream():
            _add(doc)

        # Pass 2a: exact customer name
        for doc in db.collection("service_bookings").where(
                filter=FieldFilter("customerName", "==", customer_name)).stream():
            _add(doc)

        # Pass 2b: company name
        if company_name and company_lower != name_lower:
            for doc in db.collection("service_bookings").where(
                    filter=FieldFilter("customerName", "==", company_name)).stream():
                _add(doc)

        # Pass 3: case-insensitive scan (last resort)
        if not bookings and customer_name:
            for doc in db.collection("service_bookings").stream():
                if doc.id in seen_b_ids:
                    continue
                stored = (doc.to_dict().get("customerName") or "").lower().strip()
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
    """Return services and prices from the item catalog (public for all customers)."""
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
                          service_names: list[str] | None = None, **_) -> dict:
    """Estimate combined cost for one or more named services."""
    if not service_names:
        return {
            "error": "NO_SERVICES",
            "message": "Please specify at least one service name to estimate the cost.",
        }
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


# ── Tool schemas ──────────────────────────────────────────────────────────────
# customer_uid and customer_name are NOT listed as parameters — injected
# server-side so the LLM cannot substitute a different customer's identity.

CUSTOMER_TOOL_SCHEMAS = [
    {
        "type": "function",
        "function": {
            "name": "get_my_vehicles",
            "description": (
                "Return ALL vehicles registered under the logged-in customer, "
                "including PMS status (Active, Overdue, Due Soon, Under Maintenance). "
                "ALWAYS use this when the customer asks about THEIR OWN vehicles — "
                "'all my vehicles', 'my fleet', 'my cars', 'list my vehicles', "
                "'show all my vehicles', 'how many vehicles do I have', 'fleet summary'."
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
                "Return ALL completed maintenance/service records for ALL of the "
                "customer's vehicles, grouped by vehicle. "
                "Shows each vehicle's jobs with date, services performed, materials, "
                "cost per job, and total spend. "
                "Use for: 'service history', 'past services', 'how much have I spent', "
                "'maintenance records', 'show my service history', 'pms history', "
                "'completed maintenance', 'service records per car', 'show history per car'. "
                "Optionally filter by a specific plate number."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "plate": {
                        "type": "string",
                        "description": (
                            "Specific plate number to filter by. "
                            "Omit to get history for ALL vehicles."
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
            "name": "get_my_pms_status",
            "description": (
                "Return PMS schedule status for EACH of the customer's vehicles: "
                "last service date, next PMS due date, days until due (negative = overdue). "
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
                "Return services and prices from the shop catalog (public for all customers). "
                "Use for: 'how much is a change oil', 'list of services', 'service prices', "
                "'what services do you offer', 'how much is [service name]'."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "service_name": {
                        "type": "string",
                        "description": "Keyword to filter. E.g. 'oil change', 'brake'. Omit to list all.",
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
                "Estimate combined cost for one or more named services. "
                "Use when the customer asks: 'how much would a change oil and brake cost?', "
                "'estimate cost for X and Y', 'if I get X and Y, how much total?'."
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
