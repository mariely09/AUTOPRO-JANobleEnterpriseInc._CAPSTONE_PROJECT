"""
Customer AI tools — strictly scoped to the logged-in customer's own data.

SECURITY MODEL
==============
customer_uid is ALWAYS injected server-side from the authenticated Firebase
session. The LLM cannot override it through function arguments. Every tool
that touches customer-specific data uses customer_uid as the primary filter.

VEHICLE OWNERSHIP MODEL
=======================
Vehicles are linked to customers via TWO complementary fields:

  ownerId  — Firebase Auth UID written on new vehicles (authoritative).
  owner    — Human-readable name / company name typed by admin at creation.

RETRIEVAL STRATEGY (4-pass lookup)
====================================
Pass 0 — Firestore query:  ownerId == customer_uid      (UID, most reliable)
Pass 1 — Firestore query:  owner   == customer_name     (exact name)
Pass 2 — Firestore query:  owner   == companyName       (company, if different)
Pass 3 — Case-insensitive full scan  (catches typos / casing mismatches)

BOOKING WORKFLOW
================
1. check_booking_availability() — verify slot is free before committing
2. create_customer_booking()    — creates the booking only after all checks pass
3. update_my_booking()          — reschedule; verifies ownership + availability
4. cancel_my_booking()          — cancel; verifies ownership + eligible status

MATERIALS (CUSTOMER-VISIBLE)
=============================
get_customer_materials() returns customer-facing product info ONLY.
It NEVER exposes: stock quantity, min/max/reorder levels, supplier info,
purchase cost, inventory transactions, or DSS recommendations.
"""
import logging
import re
from datetime import datetime, timedelta
from collections import defaultdict
from firestore_client import get_db
from google.cloud.firestore_v1.base_query import FieldFilter
import cache_manager

logger = logging.getLogger(__name__)


# -- Firestore quota guard -----------------------------------------------------

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


# -- Privacy / error helpers ---------------------------------------------------

def _privacy_error() -> dict:
    return {
        "error":   "ACCESS_DENIED",
        "message": "I can only show information for your own account.",
    }

def _db_error(exc: Exception) -> dict:
    return {"error": "DB_ERROR", "message": "A database error occurred. Please try again."}


# -- Currency helpers ----------------------------------------------------------

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


# -- Field normalisation -------------------------------------------------------

def _get_plate(d: dict) -> str:
    return (d.get("plateNumber") or d.get("plate") or "").strip()

def _get_desc(d: dict) -> str:
    return (d.get("description") or d.get("desc") or d.get("assetDescription") or "").strip()

def _get_last_svc_date(d: dict) -> str:
    return (d.get("lastServiceDate") or d.get("lastSvcDate") or "").strip()

def _get_svc_freq(d: dict) -> str:
    val = d.get("serviceFrequency") or d.get("svcFreq")
    return str(val).strip() if val is not None else ""


# -- Shared helpers ------------------------------------------------------------

def _resolve_company_name(db, customer_uid: str) -> str:
    return cache_manager.get_company_name(db, customer_uid)


def _iter_customer_vehicles(db, customer_uid: str,
                             customer_name: str, company_name: str):
    """
    Yield every Firestore vehicle document belonging to this customer.
    4-pass: UID → exact name → company name → case-insensitive scan.
    Deduplicates by document ID.
    """
    seen: set     = set()
    name_lower    = customer_name.lower().strip()
    company_lower = company_name.lower().strip() if company_name else ""

    # Pass 0: UID-based
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

    # Pass 2: company name
    if company_name and company_lower != name_lower:
        for doc in db.collection("vehicles").where(
                filter=FieldFilter("owner", "==", company_name)).stream():
            if doc.id not in seen:
                seen.add(doc.id)
                yield doc

    # Pass 3: case-insensitive full scan
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
    plates = []
    for doc in _iter_customer_vehicles(db, customer_uid, customer_name, company_name):
        p = _get_plate(doc.to_dict())
        if p and p not in plates:
            plates.append(p)
    logger.info(
        "_get_customer_plates: uid=%s → %d plate(s): %s",
        customer_uid, len(plates), plates,
    )
    return plates


def _norm_plate(p: str) -> str:
    """
    Format-insensitive plate key: "HDK 8638", "HDK-8638" and "hdk8638"
    all normalize to "HDK8638". The DB stores plates exactly as admins
    entered them (often WITH a space) while customers type them with a dash
    or nothing — ownership checks must not fail over formatting.
    """
    return re.sub(r"[\s\-]", "", (p or "")).upper()


def _verify_vehicle_ownership(db, customer_uid: str, customer_name: str,
                               company_name: str, plate: str) -> bool:
    """Return True if the given plate belongs to this customer."""
    owned = _get_customer_plates(db, customer_uid, customer_name, company_name)
    want = _norm_plate(plate)
    return any(_norm_plate(p) == want for p in owned if p)


def _verify_booking_ownership(db, customer_uid: str, booking_id: str) -> bool:
    """Return True if the booking belongs to this customer (by UID)."""
    try:
        doc = db.collection("service_bookings").document(booking_id).get()
        if not doc.exists:
            return False
        d = doc.to_dict()
        return (d.get("customerId") or "").strip() == customer_uid
    except Exception:
        return False


# ----------------------------------------------------------------------------
#  TOOL 1 - My Vehicles
# ----------------------------------------------------------------------------

def get_my_vehicles(customer_uid: str, customer_name: str, **_) -> dict:
    """
    Return ALL vehicles belonging to this customer.
    Uses 4-pass lookup so every vehicle is found regardless of how the
    owner field was entered by the admin.
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
                "vehicleId":   doc.id,
                "plate":       _get_plate(d),
                "make":        d.get("make", ""),
                "model":       d.get("model", ""),
                "year":        d.get("year", ""),
                "desc":        _get_desc(d),
                "type":        d.get("type", ""),
                "status":      d.get("status", "Active"),
                "lastSvcDate": _get_last_svc_date(d),
                "svcFreq":     _get_svc_freq(d),
                "odo":         (d.get("odo") or d.get("odometer") or ""),
                "color":       d.get("color", ""),
            })

        logger.info(
            "get_my_vehicles: found %d vehicle(s) for uid=%s",
            len(vehicles), customer_uid,
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


# ----------------------------------------------------------------------------
#  TOOL 2 - My Service / Maintenance History
# ----------------------------------------------------------------------------

def get_my_service_history(customer_uid: str, customer_name: str,
                           plate: str | None = None,
                           service_type: str | None = None,
                           year: int | None = None,
                           recent: int | None = None,
                           **_) -> dict:
    """
    Return ALL completed maintenance records for this customer's vehicles,
    grouped by vehicle.

    Flow:
      Step A — PRIMARY: Query maintenance WHERE ownerId == customer_uid.
      Step B — FALLBACK: Resolve all vehicle plates (4-pass), then query
               maintenance WHERE plate IN [plates]. Deduplicates with Step A.

    Security: ownerId is injected server-side; records from other customers
    are filtered out even when matched by plate.

    Optional filters:
      plate        — narrow to one vehicle (must belong to this customer)
      service_type — keyword filter on service name (e.g. "oil change")
      year         — filter by calendar year of service date
      recent       — return only the N most recent records
    """
    if not customer_uid and not customer_name:
        return _privacy_error()

    logger.info(
        "get_my_service_history: uid=%s name=%r plate=%r svc=%r year=%r recent=%r",
        customer_uid, customer_name, plate, service_type, year, recent,
    )

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)
        seen_doc_ids: set = set()
        all_docs: list    = []

        # -- Step A: ownerId query (post-migration records) --------------------
        for doc in db.collection("maintenance").where(
                filter=FieldFilter("ownerId", "==", customer_uid)).stream():
            if doc.id not in seen_doc_ids:
                seen_doc_ids.add(doc.id)
                all_docs.append(doc)

        # -- Step B: plate-based fallback (pre-migration records) -------------
        all_plates = _get_customer_plates(db, customer_uid, customer_name, company_name)
        if all_plates:
            for i in range(0, len(all_plates), 10):
                chunk = all_plates[i:i + 10]
                for field in ("plateNumber", "plate"):
                    for doc in db.collection("maintenance").where(
                            filter=FieldFilter(field, "in", chunk)).stream():
                        if doc.id not in seen_doc_ids:
                            d = doc.to_dict()
                            record_oid = (d.get("ownerId") or "").strip()
                            # Security: reject records explicitly owned by someone else
                            if record_oid and record_oid != customer_uid:
                                continue
                            seen_doc_ids.add(doc.id)
                            all_docs.append(doc)
        elif not all_docs:
            logger.warning(
                "get_my_service_history: zero vehicles and zero ownerId records "
                "for uid=%s name=%r", customer_uid, customer_name,
            )
            return {
                "owner":      customer_name,
                "plate":      plate or "all vehicles",
                "total_jobs": 0,
                "total_cost": "₱0.00",
                "jobs":       [],
                "by_vehicle": {},
            }

        # -- Plate filter (verify ownership) ----------------------------------
        if plate:
            plate_upper = plate.upper()
            authorized  = {p.upper() for p in all_plates}
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

        # -- Build result ------------------------------------------------------
        jobs       = []
        by_vehicle: dict = defaultdict(list)

        for doc in all_docs:
            d = doc.to_dict()
            if (d.get("status") or "").strip().lower() != "completed":
                continue

            # Service type keyword filter
            if service_type:
                kw    = service_type.lower()
                svc_names = " ".join(
                    r.get("name", "").lower()
                    for r in (d.get("svcRows") or [])
                )
                desc_text = _get_desc(d).lower()
                if kw not in svc_names and kw not in desc_text:
                    continue

            cost      = _strip_currency(d.get("cost", 0))
            job_plate = (d.get("plateNumber") or d.get("plate") or "").strip()
            job_date  = d.get("date", "")

            # Year filter
            if year:
                try:
                    job_year = int(job_date[:4]) if job_date else 0
                    if job_year != year:
                        continue
                except (ValueError, IndexError):
                    continue

            job = {
                "id":          d.get("id", doc.id),
                "plate":       job_plate,
                "desc":        _get_desc(d),
                "date":        job_date,
                "mechanic":    d.get("mechanic", ""),
                "status":      d.get("status", ""),
                "cost":        _fmt_cost(d.get("cost", 0)),
                "cost_raw":    cost,
                # Customer-visible services (name only - no internal unit costs)
                "services":    [r.get("name", "") for r in (d.get("svcRows") or [])],
                # Customer-visible materials (name only - no supplier/purchase info)
                "materials":   [r.get("name", "") for r in (d.get("matRows") or [])],
            }
            jobs.append(job)
            if job_plate:
                by_vehicle[job_plate].append(job)

        # Sort newest-first
        jobs.sort(key=lambda j: j["date"], reverse=True)
        for grp in by_vehicle.values():
            grp.sort(key=lambda j: j["date"], reverse=True)

        # Recent filter
        if recent and recent > 0:
            jobs = jobs[:recent]

        total_cost = sum(j["cost_raw"] for j in jobs)

        logger.info(
            "get_my_service_history: %d completed job(s) across %d vehicle(s) for uid=%s",
            len(jobs), len(by_vehicle), customer_uid,
        )

        return {
            "owner":      customer_name,
            "plate":      plate or "all vehicles",
            "total_jobs": len(jobs),
            "total_cost": _fmt_cost(total_cost),
            "jobs":       jobs,
            "by_vehicle": dict(by_vehicle),
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_my_service_history error")
        return _db_error(e)


# ----------------------------------------------------------------------------
#  TOOL 3 - Maintenance Recommendations / PMS Status
# ----------------------------------------------------------------------------

def get_service_recommendations(customer_uid: str, customer_name: str, **_) -> dict:
    """
    Return maintenance recommendations for each of the customer's vehicles
    based on actual system data: vehicle lastServiceDate, serviceFrequency,
    and completed maintenance history.

    The recommendations are labelled as SYSTEM RECOMMENDATIONS — not
    guaranteed service requirements. Recommendations are only generated
    when sufficient data exists; otherwise the function says so explicitly.
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
            plate    = _get_plate(d)
            desc     = _get_desc(d)
            last_svc = _get_last_svc_date(d)
            svc_freq = _get_svc_freq(d)

            next_pms    = ""
            days_until  = None
            urgency     = "Active"
            months_freq = None

            try:
                if last_svc and svc_freq:
                    months_freq = int(svc_freq)
                    last_dt     = datetime.fromisoformat(last_svc)
                    # Compute next PMS date (add serviceFrequency months)
                    next_month  = last_dt.month + months_freq
                    next_year   = last_dt.year + (next_month - 1) // 12
                    next_month  = (next_month - 1) % 12 + 1
                    next_dt     = last_dt.replace(year=next_year, month=next_month)
                    next_pms    = next_dt.strftime("%b %d, %Y")
                    days_until  = (next_dt - now).days
            except Exception:
                pass

            if days_until is not None:
                if days_until < 0:
                    urgency = "Overdue"
                elif days_until <= 7:
                    urgency = "Due This Week"
                elif days_until <= 30:
                    urgency = "Due Soon"
                else:
                    urgency = "On Track"

            # Build recommendation text
            if days_until is None:
                if not last_svc:
                    recommendation = (
                        "Insufficient data — no last service date recorded for this vehicle. "
                        "Please visit the shop for an initial assessment."
                    )
                elif not svc_freq:
                    recommendation = (
                        "Insufficient data — no service frequency set for this vehicle. "
                        "Please contact the shop to set a maintenance schedule."
                    )
                else:
                    recommendation = "Unable to compute next service date from available data."
            elif days_until < 0:
                recommendation = (
                    f"⚠️ OVERDUE — This vehicle is {abs(days_until)} day(s) past its scheduled "
                    f"maintenance date ({next_pms}). Service is recommended as soon as possible."
                )
            elif days_until <= 7:
                recommendation = (
                    f"🔴 DUE THIS WEEK — Scheduled maintenance is due on {next_pms} "
                    f"({days_until} day(s) away). Please schedule a service appointment."
                )
            elif days_until <= 30:
                recommendation = (
                    f"🟡 DUE SOON — Scheduled maintenance is due on {next_pms} "
                    f"({days_until} day(s) away). Consider booking in advance."
                )
            else:
                recommendation = (
                    f"✅ ON TRACK — Next scheduled maintenance is on {next_pms} "
                    f"({days_until} day(s) away)."
                )

            vehicles.append({
                "plate":          plate,
                "desc":           desc,
                "status":         d.get("status", "Active"),
                "lastSvcDate":    last_svc,
                "svcFreqMonths":  months_freq,
                "nextPMS":        next_pms,
                "daysUntil":      days_until,
                "urgency":        urgency,
                "recommendation": recommendation,
            })

        overdue  = [v for v in vehicles if v["urgency"] == "Overdue"]
        due_soon = [v for v in vehicles if v["urgency"] in ("Due This Week", "Due Soon")]
        on_track = [v for v in vehicles if v["urgency"] == "On Track"]

        return {
            "owner":          customer_name,
            "total_vehicles": len(vehicles),
            "overdue":        len(overdue),
            "due_soon":       len(due_soon),
            "on_track":       len(on_track),
            "vehicles":       vehicles,
            "disclaimer":     (
                "These are system recommendations based on recorded service dates and "
                "frequency settings. They are not guaranteed service requirements. "
                "Consult the shop for a professional assessment."
            ),
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_service_recommendations error")
        return _db_error(e)


# ----------------------------------------------------------------------------
#  TOOL 4 - Service Prices (public)
# ----------------------------------------------------------------------------

def get_service_prices(customer_uid: str, customer_name: str,
                       service_name: str | None = None, **_) -> dict:
    """
    Return services and prices from the item catalog (public for all customers).
    Prices are retrieved from the database — never invented.
    """
    try:
        db      = get_db()
        catalog = cache_manager.get_service_catalog(db)

        if catalog is None:
            return _quota_error()

        if not catalog:
            logger.warning(
                "get_service_prices: catalog empty. "
                "Check item_master has documents with type='Service'."
            )
            return {
                "filter":         service_name or "all services",
                "total_services": 0,
                "services":       [],
                "catalog_size":   0,
            }

        # Filter by keyword using synonym expansion + 3-pass matching
        if service_name:
            keyword = service_name.lower().strip()

            # Synonym map: common customer terms -> actual catalog keyword
            SYNONYMS = {
                "pms":              "oil",
                "preventive maintenance": "oil",
                "tune up":          "oil",
                "tune-up":          "oil",
                "lube":             "oil",
                "lubrication":      "oil",
                "oil service":      "oil",
                "change oil":       "oil",
                "oil change":       "oil",
                "atf":              "atf",
                "transmission oil": "trans",
                "gear oil":         "gear oil",
                "coolant flush":    "coolant",
                "radiator flush":   "coolant",
                "brake fluid":      "brake",
                "brakes":           "brake",
                "tire rotation":    "tire",
                "tyre":             "tire",
                "aircon":           "aircon",
                "air con":          "aircon",
                "ac service":       "aircon",
                "wheel alignment":  "alignment",
                "balancing":        "balance",
            }
            # Expand keyword using synonym map
            expanded = SYNONYMS.get(keyword, keyword)
            words = [w for w in expanded.split() if len(w) >= 3]
            # Also keep original words as fallback
            orig_words = [w for w in keyword.split() if len(w) >= 3]

            def _make_item(item):
                return {
                    "num":   item.get("num", ""),
                    "name":  item.get("name", ""),
                    "group": item.get("group", ""),
                    "uom":   item.get("uom", ""),
                    "cost":  _fmt_cost(item.get("cost", 0)),
                }

            # Pass 1: substring match on expanded keyword
            services = [_make_item(i) for i in catalog
                        if expanded in i.get("name", "").lower()]
            # Pass 2: all expanded words present
            if not services and words:
                services = [_make_item(i) for i in catalog
                            if all(w in i.get("name", "").lower() for w in words)]
            # Pass 3: original keyword substring
            if not services:
                services = [_make_item(i) for i in catalog
                            if keyword in i.get("name", "").lower()]
            # Pass 4: original words (any significant word)
            if not services and orig_words:
                for w in orig_words:
                    services = [_make_item(i) for i in catalog
                                if w in i.get("name", "").lower()]
                    if services:
                        break
        else:
            services = [
                {
                    "num":   item.get("num", ""),
                    "name":  item.get("name", ""),
                    "group": item.get("group", ""),
                    "uom":   item.get("uom", ""),
                    "cost":  _fmt_cost(item.get("cost", 0)),
                }
                for item in catalog
            ]

        return {
            "filter":         service_name or "all services",
            "total_services": len(services),
            "services":       services,
            "catalog_size":   len(catalog),
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_service_prices error")
        return _db_error(e)


# ----------------------------------------------------------------------------
#  TOOL 5 - Customer-Visible Materials
# ----------------------------------------------------------------------------

def get_customer_materials(customer_uid: str, customer_name: str,
                           material_name: str | None = None, **_) -> dict:
    """
    Return customer-facing material/product information from item_master.

    STRICT PRIVACY: NEVER exposes:
      - Stock quantity (stock, min, max, reorder)
      - Supplier information
      - Purchase price / unit cost
      - Inventory transactions or stock movements
      - DSS stock replenishment recommendations
      - Any admin-only inventory fields

    Only returns: name, description, customer price (cost), UOM, availability
    status if explicitly set as a customer-visible field.
    """
    try:
        db = get_db()
        from google.cloud.firestore_v1.base_query import FieldFilter as FF

        # Fetch materials from item_master (type = "Material" or "material")
        docs = list(
            db.collection("item_master")
            .where(filter=FF("type", "==", "Material"))
            .stream()
        )
        if not docs:
            # Try lowercase variant
            docs = list(
                db.collection("item_master")
                .where(filter=FF("type", "==", "material"))
                .stream()
            )
        if not docs:
            # Full scan fallback - filter in Python
            all_docs = list(db.collection("item_master").stream())
            docs = [
                d for d in all_docs
                if (d.to_dict().get("type") or "").strip().lower() == "material"
            ]

        # Build customer-visible list (NEVER include internal fields)
        materials = []
        for doc in docs:
            d = doc.to_dict()
            materials.append({
                "name":         d.get("name", ""),
                "group":        d.get("group", ""),
                "uom":          d.get("uom", ""),
                # "cost" here is the customer-facing price, NOT the purchase price
                "customer_price": _fmt_cost(d.get("cost", 0)),
                # Availability: only expose if there is a customer-visible status field
                # NEVER expose raw stock numbers
                "available":    d.get("customerVisible", True),
            })

        materials.sort(key=lambda m: m["name"])

        # Keyword filter
        if material_name:
            kw   = material_name.lower().strip()
            wds  = [w for w in kw.split() if len(w) >= 3]
            matched = [m for m in materials if kw in m["name"].lower()]
            if not matched and wds:
                matched = [m for m in materials
                           if all(w in m["name"].lower() for w in wds)]
            if not matched and wds:
                for w in wds:
                    matched = [m for m in materials if w in m["name"].lower()]
                    if matched:
                        break
            materials = matched

        return {
            "filter":          material_name or "all materials",
            "total_materials": len(materials),
            "materials":       materials,
            "note": (
                "Stock quantities and supplier information are not available "
                "through the customer assistant."
            ),
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_customer_materials error")
        return _db_error(e)


# ----------------------------------------------------------------------------
#  TOOL 6 - Check Booking Availability
# ----------------------------------------------------------------------------

def check_booking_availability(customer_uid: str, customer_name: str,
                                preferred_date: str,
                                preferred_time: str | None = None,
                                **_) -> dict:
    """
    Check whether a requested date/time slot is available for booking.
    Returns available time slots for the requested date.
    Does NOT create a booking — only checks availability.
    """
    if not preferred_date:
        return {
            "error": "MISSING_DATE",
            "message": "Please provide a preferred date to check availability.",
        }

    try:
        db = get_db()

        # Parse and validate the requested date
        try:
            req_date = _parse_date_flexible(preferred_date)
        except ValueError as ve:
            return {
                "error":   "INVALID_DATE",
                "message": str(ve),
            }

        # Don't allow past dates
        if req_date.date() < datetime.now().date():
            return {
                "error":   "PAST_DATE",
                "message": "The requested date is in the past. Please choose a future date.",
            }

        date_str = req_date.strftime("%Y-%m-%d")

        # Fetch bookings for that date to count occupancy
        existing = []
        for doc in db.collection("service_bookings").where(
                filter=FieldFilter("preferredDate", "==", date_str)).stream():
            d = doc.to_dict()
            status = (d.get("status") or "").lower()
            if status not in ("cancelled", "rejected"):
                existing.append({
                    "time":   d.get("preferredTime", ""),
                    "status": d.get("status", ""),
                })

        # Also try YYYY-MM-DD formatted as "Month D, YYYY" (format variations).
        # NOTE: %-d (day without zero-padding) is Linux-only; Windows strftime
        # raises ValueError — build it portably instead.
        if hasattr(req_date, "strftime"):
            human_date = f"{req_date.strftime('%B')} {req_date.day}, {req_date.strftime('%Y')}"
        else:
            human_date = date_str
        for doc in db.collection("service_bookings").where(
                filter=FieldFilter("preferredDate", "==", human_date)).stream():
            d = doc.to_dict()
            status = (d.get("status") or "").lower()
            if status not in ("cancelled", "rejected"):
                existing.append({
                    "time":   d.get("preferredTime", ""),
                    "status": d.get("status", ""),
                })

        booked_times = {b["time"].lower().strip() for b in existing if b["time"]}

        # Standard available time slots
        all_slots = [
            "8:00 AM", "9:00 AM", "10:00 AM", "11:00 AM",
            "1:00 PM", "2:00 PM", "3:00 PM", "4:00 PM",
        ]
        available_slots = [s for s in all_slots if s.lower() not in booked_times]

        requested_slot_available = None
        if preferred_time:
            requested_slot_available = preferred_time.lower().strip() not in booked_times

        return {
            "date":                    date_str,
            "date_display":            req_date.strftime("%B %d, %Y"),
            "total_bookings_that_day": len(existing),
            "available_slots":         available_slots,
            "requested_time":          preferred_time,
            "requested_time_available": requested_slot_available,
            "is_available":            len(available_slots) > 0,
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("check_booking_availability error")
        return _db_error(e)


# ----------------------------------------------------------------------------
#  TOOL 6B - Get Suggested Booking Dates (Based on Service History)
# ----------------------------------------------------------------------------

def suggest_booking_date(customer_uid: str, customer_name: str,
                        plate: str,
                        service_type: str | None = None,
                        **_) -> dict:
    """
    Suggest optimal booking dates for a vehicle based on:
    1. Service history (last service date + frequency)
    2. Service type (oil change intervals differ from other services)
    3. Current availability

    Returns suggested dates with reasoning based on actual vehicle data.
    """
    if not plate:
        return {
            "error": "MISSING_PLATE",
            "message": "Please specify which vehicle you'd like to book service for.",
        }

    try:
        db = get_db()
        company_name = _resolve_company_name(db, customer_uid)
        
        # Verify ownership
        if not _verify_vehicle_ownership(db, customer_uid, customer_name, company_name, plate):
            return {
                "error": "VEHICLE_NOT_OWNED",
                "message": f"Vehicle with plate {plate} is not registered under your account.",
            }

        # Get vehicle details and service frequency
        vehicle_data = None
        for doc in _iter_customer_vehicles(db, customer_uid, customer_name, company_name):
            d = doc.to_dict()
            if _get_plate(d).upper() == plate.upper():
                vehicle_data = {
                    "plate": _get_plate(d),
                    "desc": _get_desc(d),
                    "last_service_date": _get_last_svc_date(d),
                    "service_frequency_months": _get_svc_freq(d),
                    "status": d.get("status", "Active"),
                }
                break

        if not vehicle_data:
            return {
                "error": "VEHICLE_NOT_FOUND",
                "message": f"Could not retrieve data for vehicle {plate}.",
            }

        # Get last service for this specific service type if provided
        last_service_date = None
        service_context = ""
        
        if service_type:
            # Query maintenance history for this specific service
            service_history = get_my_service_history(
                customer_uid=customer_uid,
                customer_name=customer_name,
                plate=plate,
                service_type=service_type,
                recent=1
            )
            
            if service_history.get("jobs") and len(service_history["jobs"]) > 0:
                last_job = service_history["jobs"][0]
                last_service_date = last_job.get("date")
                service_context = f"Your last {service_type} was on {last_service_date}."

        # If no specific service history, use vehicle's general last service date
        if not last_service_date:
            last_service_date = vehicle_data.get("last_service_date")
            if last_service_date:
                service_context = f"Your vehicle's last recorded service was on {last_service_date}."

        # Calculate recommended date based on service frequency
        now = datetime.now()
        suggested_dates = []
        reasoning = []

        # Determine service interval (in months)
        interval_months = 3  # default for oil change
        
        if service_type:
            service_lower = service_type.lower()
            if any(kw in service_lower for kw in ["oil", "change oil", "pms", "preventive"]):
                interval_months = 3  # Oil change every 3 months
                reasoning.append("Oil change services are typically recommended every 3 months or 5,000 km.")
            elif any(kw in service_lower for kw in ["tire", "tyre", "alignment", "balance"]):
                interval_months = 6  # Tire services every 6 months
                reasoning.append("Tire and alignment services are recommended every 6 months.")
            elif any(kw in service_lower for kw in ["brake", "brakes"]):
                interval_months = 6  # Brake service every 6 months
                reasoning.append("Brake system checks are recommended every 6 months.")
            elif any(kw in service_lower for kw in ["coolant", "radiator", "flush"]):
                interval_months = 12  # Coolant service yearly
                reasoning.append("Coolant system service is typically recommended annually.")
            else:
                # Use vehicle's service frequency if set
                if vehicle_data.get("service_frequency_months"):
                    try:
                        interval_months = int(vehicle_data["service_frequency_months"])
                    except (ValueError, TypeError):
                        pass

        # Use vehicle's configured frequency if no service type specified
        elif vehicle_data.get("service_frequency_months"):
            try:
                interval_months = int(vehicle_data["service_frequency_months"])
                reasoning.append(f"Based on your vehicle's service frequency of {interval_months} months.")
            except (ValueError, TypeError):
                pass

        # Calculate next recommended date
        if last_service_date:
            try:
                last_dt = datetime.fromisoformat(last_service_date)
                # Calculate next service date
                next_month = last_dt.month + interval_months
                next_year = last_dt.year + (next_month - 1) // 12
                next_month = (next_month - 1) % 12 + 1
                recommended_date = last_dt.replace(year=next_year, month=next_month)
                
                days_until = (recommended_date - now).days
                
                if days_until < 0:
                    reasoning.append(f"⚠️ Your service is overdue by {abs(days_until)} days.")
                    # Suggest earliest available date
                    recommended_date = now + timedelta(days=1)
                elif days_until <= 7:
                    reasoning.append(f"🔴 Your service is due in {days_until} days.")
                elif days_until <= 30:
                    reasoning.append(f"🟡 Your service is coming up in {days_until} days.")
                else:
                    reasoning.append(f"✅ Your next service is recommended in {days_until} days.")
                
                # Find available slots around the recommended date
                check_dates = [
                    recommended_date,
                    recommended_date + timedelta(days=1),
                    recommended_date + timedelta(days=2),
                    recommended_date - timedelta(days=1) if days_until <= 7 else recommended_date + timedelta(days=3),
                ]
                
                for check_date in check_dates:
                    if check_date.date() < now.date():
                        continue
                    
                    avail = check_booking_availability(
                        customer_uid=customer_uid,
                        customer_name=customer_name,
                        preferred_date=check_date.strftime("%Y-%m-%d"),
                    )
                    
                    if avail.get("is_available") and len(avail.get("available_slots", [])) > 0:
                        suggested_dates.append({
                            "date": check_date.strftime("%Y-%m-%d"),
                            "date_display": check_date.strftime("%B %d, %Y (%A)"),
                            "available_slots": avail["available_slots"],
                            "is_recommended": check_date == recommended_date,
                        })
                        
            except Exception as e:
                logger.warning(f"suggest_booking_date: date calculation error: {e}")

        # If no dates calculated from history, suggest next week
        if not suggested_dates:
            reasoning.append("Based on general maintenance guidelines.")
            for days_ahead in [7, 8, 9, 10, 14]:
                check_date = now + timedelta(days=days_ahead)
                
                avail = check_booking_availability(
                    customer_uid=customer_uid,
                    customer_name=customer_name,
                    preferred_date=check_date.strftime("%Y-%m-%d"),
                )
                
                if avail.get("is_available") and len(avail.get("available_slots", [])) > 0:
                    suggested_dates.append({
                        "date": check_date.strftime("%Y-%m-%d"),
                        "date_display": check_date.strftime("%B %d, %Y (%A)"),
                        "available_slots": avail["available_slots"],
                        "is_recommended": days_ahead == 7,
                    })

        return {
            "vehicle_plate": vehicle_data["plate"],
            "vehicle_desc": vehicle_data["desc"],
            "service_type": service_type or "general service",
            "last_service_date": last_service_date,
            "service_context": service_context,
            "interval_months": interval_months,
            "suggested_dates": suggested_dates[:4],  # Top 4 suggestions
            "reasoning": reasoning,
            "message": (
                f"Based on your vehicle's service history and the recommended "
                f"{interval_months}-month interval, here are the best available dates."
            ),
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("suggest_booking_date error")
        return _db_error(e)


# ----------------------------------------------------------------------------
#  TOOL 7A - Preview Customer Booking (Confirmation Step)
# ----------------------------------------------------------------------------

def preview_customer_booking(customer_uid: str, customer_name: str,
                            plate: str,
                            services: list[str],
                            preferred_date: str,
                            preferred_time: str,
                            notes: str | None = None,
                            **_) -> dict:
    """
    Preview a booking before creation - validates all parameters and returns
    a formatted confirmation message WITHOUT creating the booking.
    
    This performs all the same validation as create_customer_booking but
    returns a preview instead of creating the booking. If validation passes,
    stores the booking details in session state for later confirmation.
    
    Returns a preview dict with:
      - preview: formatted HTML preview message
      - valid: True if all validations passed
      - booking_data: validated data (only if valid=True)
    """
    # -- Validate required fields ----------------------------------------------
    missing = []
    if not plate:
        missing.append("vehicle plate")
    if not services or len(services) == 0:
        missing.append("service(s)")
    if not preferred_date:
        missing.append("preferred date")
    if not preferred_time:
        missing.append("preferred time")
    if missing:
        return {
            "error":   "MISSING_FIELDS",
            "message": f"Missing required information: {', '.join(missing)}.",
        }

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)

        # -- Check 1: vehicle ownership ----------------------------------------
        if not _verify_vehicle_ownership(db, customer_uid, customer_name,
                                         company_name, plate):
            logger.warning(
                "preview_customer_booking: plate %s does not belong to uid=%s",
                plate, customer_uid,
            )
            return {
                "error":   "VEHICLE_NOT_OWNED",
                "message": (
                    f"Vehicle with plate {plate} is not registered under your account. "
                    "Please check your vehicles or contact the shop."
                ),
            }

        # -- Check 2: services exist in catalog --------------------------------
        catalog = cache_manager.get_service_catalog(db)
        if catalog is None:
            return _quota_error()

        catalog_names_lower = {item.get("name", "").lower() for item in catalog}
        invalid_services = []
        matched_services = []
        
        for svc in services:
            svc_lower = svc.lower().strip()
            # Accept fuzzy partial match
            found = False
            for catalog_item in catalog:
                cn = catalog_item.get("name", "").lower()
                if svc_lower in cn or cn in svc_lower:
                    matched_services.append(catalog_item.get("name", svc))
                    found = True
                    break
            
            if not found:
                # Try word overlap
                words = [w for w in svc_lower.split() if len(w) >= 3]
                for catalog_item in catalog:
                    cn = catalog_item.get("name", "").lower()
                    if words and all(w in cn for w in words):
                        matched_services.append(catalog_item.get("name", svc))
                        found = True
                        break
            
            if not found:
                invalid_services.append(svc)

        if invalid_services:
            return {
                "error":    "SERVICE_NOT_FOUND",
                "message":  (
                    f"The following service(s) were not found in our catalog: "
                    f"{', '.join(invalid_services)}. "
                    f"Please ask for the service list to see available options."
                ),
                "invalid_services": invalid_services,
            }

        # Use matched canonical service names
        services = matched_services if matched_services else services

        # -- Check 3: validate and parse date ---------------------------------
        try:
            req_date = _parse_date_flexible(preferred_date)
        except ValueError as ve:
            return {"error": "INVALID_DATE", "message": str(ve)}

        if req_date.date() < datetime.now().date():
            return {
                "error":   "PAST_DATE",
                "message": "The requested date is in the past. Please choose a future date.",
            }

        date_str = req_date.strftime("%Y-%m-%d")

        # -- Check 4: availability ---------------------------------------------
        avail = check_booking_availability(
            customer_uid=customer_uid,
            customer_name=customer_name,
            preferred_date=date_str,
            preferred_time=preferred_time,
        )
        if avail.get("error"):
            return avail

        if avail.get("requested_time_available") is False:
            available_slots = avail.get("available_slots", [])
            if available_slots:
                return {
                    "error":            "TIME_NOT_AVAILABLE",
                    "message":          (
                        f"The {preferred_time} slot on {req_date.strftime('%B %d, %Y')} "
                        f"is not available. Please choose from the available slots."
                    ),
                    "available_slots":  available_slots,
                    "requested_date":   req_date.strftime("%B %d, %Y"),
                }
            else:
                return {
                    "error":   "DATE_FULLY_BOOKED",
                    "message": (
                        f"{req_date.strftime('%B %d, %Y')} is fully booked. "
                        f"Please choose a different date."
                    ),
                }

        # -- Get vehicle description for the preview ---------------------------
        vehicle_desc = ""
        vehicle_id = ""
        canonical_plate = plate.upper()
        _want_plate = _norm_plate(plate)
        for doc in _iter_customer_vehicles(db, customer_uid, customer_name, company_name):
            d = doc.to_dict()
            if _norm_plate(_get_plate(d)) == _want_plate:
                vehicle_desc = _get_desc(d)
                vehicle_id = doc.id
                canonical_plate = (_get_plate(d) or canonical_plate).upper()
                break

        # -- Build preview message ---------------------------------------------
        services_formatted = "<br>• ".join(services)
        preview_msg = (
            f"📋 <b>Booking Preview</b><br><br>"
            f"<b>Vehicle:</b> {canonical_plate} ({vehicle_desc})<br>"
            f"<b>Service(s):</b><br>• {services_formatted}<br>"
            f"<b>Date & Time:</b> {req_date.strftime('%B %d, %Y')} at {preferred_time}<br>"
            f"<b>Status:</b> Approved (Auto-approved)"
        )
        
        if notes:
            preview_msg += f"<br><b>Notes:</b> {notes}"
        
        preview_msg += (
            "<br><br>"
            "Please confirm: Type <b>yes</b> to proceed with this booking, "
            "or <b>no</b> to cancel."
        )

        # Store validated booking data for later confirmation
        booking_data = {
            "customer_uid":   customer_uid,
            "customer_name":  customer_name,
            "vehicle_id":     vehicle_id,
            "plate":          canonical_plate,
            "vehicle_desc":   vehicle_desc,
            "services":       services,
            "date_str":       date_str,
            "date_formatted": req_date.strftime("%B %d, %Y"),
            "time":           preferred_time,
            "notes":          notes or "",
        }

        return {
            "preview":       preview_msg,
            "valid":         True,
            "booking_data":  booking_data,
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("preview_customer_booking error")
        return {
            "error":   "DB_ERROR",
            "message": "Could not preview your booking due to a database error. Please try again.",
        }


# ----------------------------------------------------------------------------
#  TOOL 7B - Create Customer Booking
# ----------------------------------------------------------------------------

def create_customer_booking(customer_uid: str, customer_name: str,
                            plate: str = "",
                            services: list[str] = None,
                            preferred_date: str = "",
                            preferred_time: str = "",
                            notes: str | None = None,
                            session_id: str | None = None,
                            use_pending: bool = False,
                            **_) -> dict:
    """
    Create a new service booking for the authenticated customer.
    
    Two modes of operation:
    1. Direct mode (use_pending=False): Validates all parameters and creates booking
    2. Pending mode (use_pending=True): Uses pre-validated data from session state
    
    When use_pending=True and session_id is provided:
      - Retrieves validated booking data from session (stored by preview_customer_booking)
      - Creates the booking immediately without re-validation
      - Clears the pending booking from session after creation
    
    When use_pending=False (default):
      - Performs all validation checks:
        1. plate belongs to this customer (ownership verified via 4-pass lookup)
        2. All requested services exist in the item catalog
        3. preferred_date is valid and not in the past
        4. preferred_time slot is not already fully booked
        5. All required fields are present
      - Creates booking only after ALL checks pass

    The function returns the actual database result — never claims success before it happens.
    """
    services = services or []
    
    # -- Check for pending booking data ----------------------------------------
    if use_pending and session_id:
        from session_store import get_pending_booking, clear_pending_booking
        pending_data = get_pending_booking(session_id)
        
        if pending_data is None:
            return {
                "error": "NO_PENDING_BOOKING",
                "message": (
                    "No pending booking found. Please start a new booking request "
                    "with your vehicle plate, service(s), date, and time."
                ),
            }
        
        # Use the pre-validated data from the preview
        plate = pending_data.get("plate", "")
        services = pending_data.get("services", [])
        preferred_date = pending_data.get("date_str", "")
        preferred_time = pending_data.get("time", "")
        notes = pending_data.get("notes", "") or notes
        vehicle_id = pending_data.get("vehicle_id", "")
        vehicle_desc = pending_data.get("vehicle_desc", "")
        date_formatted = pending_data.get("date_formatted", "")
        
        # Skip all validation - data was already validated in preview_customer_booking
        try:
            db = get_db()
            from google.cloud.firestore import SERVER_TIMESTAMP as _SRV_TS
            
            booking_data = {
                "customerId":    customer_uid,
                "customerName":  customer_name,
                "vehicleId":     vehicle_id,
                "plate":         plate,
                "vehicleDesc":   vehicle_desc,
                "services":      services,
                "preferredDate": preferred_date,
                "preferredTime": preferred_time,
                "status":        "Approved",
                "autoApproved":  True,
                "notes":         notes,
                "createdAt":     _SRV_TS,
                "createdBy":     "customer_ai",
            }

            doc_ref = db.collection("service_bookings").document()
            doc_ref.set(booking_data)

            # Verify the write succeeded
            written = doc_ref.get()
            if not written.exists:
                logger.error(
                    "create_customer_booking (pending): write verification failed for uid=%s",
                    customer_uid,
                )
                return {
                    "error":   "DB_WRITE_FAILED",
                    "message": (
                        "Your booking could not be saved due to a database error. "
                        "Please try again or contact the shop."
                    ),
                }

            booking_id = doc_ref.id
            logger.info(
                "create_customer_booking (pending): booking %s created for uid=%s plate=%s date=%s time=%s",
                booking_id, customer_uid, plate, preferred_date, preferred_time,
            )
            
            # Clear pending booking from session
            clear_pending_booking(session_id)

            return {
                "success":      True,
                "booking_id":   booking_id,
                "customer":     customer_name,
                "plate":        plate,
                "vehicle":      vehicle_desc,
                "services":     services,
                "date":         date_formatted,
                "time":         preferred_time,
                "status":       "Approved",
                "notes":        notes,
                "message":      (
                    f"✅ Your booking has been successfully created! "
                    f"Booking ID: {booking_id}. "
                    f"Status: Approved. "
                    f"We look forward to serving you on "
                    f"{date_formatted} at {preferred_time}. "
                    f"You can view this under **My Bookings**."
                ),
            }
            
        except Exception as e:
            if _is_firestore_quota(e):
                return _quota_error()
            logger.exception("create_customer_booking (pending) error")
            return {
                "error":   "DB_ERROR",
                "message": "Your booking could not be created due to a database error. Please try again.",
            }
    
    # -- Direct mode: Full validation ------------------------------------------
    # -- Validate required fields ----------------------------------------------
    missing = []
    if not plate:
        missing.append("vehicle plate")
    if not services or len(services) == 0:
        missing.append("service(s)")
    if not preferred_date:
        missing.append("preferred date")
    if not preferred_time:
        missing.append("preferred time")
    if missing:
        return {
            "error":   "MISSING_FIELDS",
            "message": f"Missing required information: {', '.join(missing)}.",
        }

    try:
        db           = get_db()
        company_name = _resolve_company_name(db, customer_uid)

        # -- Check 1: vehicle ownership ----------------------------------------
        if not _verify_vehicle_ownership(db, customer_uid, customer_name,
                                         company_name, plate):
            logger.warning(
                "create_customer_booking: plate %s does not belong to uid=%s",
                plate, customer_uid,
            )
            return {
                "error":   "VEHICLE_NOT_OWNED",
                "message": (
                    f"Vehicle with plate {plate} is not registered under your account. "
                    "Please check your vehicles or contact the shop."
                ),
            }

        # -- Check 2: services exist in catalog --------------------------------
        catalog = cache_manager.get_service_catalog(db)
        if catalog is None:
            return _quota_error()

        catalog_names_lower = {item.get("name", "").lower() for item in catalog}
        invalid_services = []
        for svc in services:
            svc_lower = svc.lower().strip()
            # Accept fuzzy partial match (e.g. "oil change" matches "Change Oil Service")
            found = any(svc_lower in cn or cn in svc_lower
                        for cn in catalog_names_lower)
            if not found:
                # Try word overlap
                words = [w for w in svc_lower.split() if len(w) >= 3]
                found = any(
                    all(w in cn for w in words)
                    for cn in catalog_names_lower
                ) if words else False
            if not found:
                invalid_services.append(svc)

        if invalid_services:
            return {
                "error":    "SERVICE_NOT_FOUND",
                "message":  (
                    f"The following service(s) were not found in our catalog: "
                    f"{', '.join(invalid_services)}. "
                    f"Please ask for the service list to see available options."
                ),
                "invalid_services": invalid_services,
            }

        # -- Check 3: validate and parse date ---------------------------------
        try:
            req_date = _parse_date_flexible(preferred_date)
        except ValueError as ve:
            return {"error": "INVALID_DATE", "message": str(ve)}

        if req_date.date() < datetime.now().date():
            return {
                "error":   "PAST_DATE",
                "message": "The requested date is in the past. Please choose a future date.",
            }

        date_str = req_date.strftime("%Y-%m-%d")

        # -- Check 4: availability ---------------------------------------------
        avail = check_booking_availability(
            customer_uid=customer_uid,
            customer_name=customer_name,
            preferred_date=date_str,
            preferred_time=preferred_time,
        )
        if avail.get("error"):
            return avail

        if avail.get("requested_time_available") is False:
            available_slots = avail.get("available_slots", [])
            if available_slots:
                return {
                    "error":            "TIME_NOT_AVAILABLE",
                    "message":          (
                        f"The {preferred_time} slot on {req_date.strftime('%B %d, %Y')} "
                        f"is not available. Please choose from the available slots."
                    ),
                    "available_slots":  available_slots,
                    "requested_date":   req_date.strftime("%B %d, %Y"),
                }
            else:
                return {
                    "error":   "DATE_FULLY_BOOKED",
                    "message": (
                        f"{req_date.strftime('%B %d, %Y')} is fully booked. "
                        f"Please choose a different date."
                    ),
                }

        # -- Get vehicle description for the booking record --------------------
        vehicle_desc = ""
        vehicle_id = ""
        canonical_plate = plate.upper()
        _want_plate = _norm_plate(plate)
        for doc in _iter_customer_vehicles(db, customer_uid, customer_name, company_name):
            d = doc.to_dict()
            if _norm_plate(_get_plate(d)) == _want_plate:
                vehicle_desc = _get_desc(d)
                vehicle_id = doc.id
                # Store the plate exactly as registered (e.g. "HDK 8638")
                canonical_plate = (_get_plate(d) or canonical_plate).upper()
                break

        # -- Create the booking ------------------------------------------------
        # Field conventions match the website's own booking flow
        # (customer_book_service.html): status "Approved" + autoApproved so
        # AI-created bookings appear in My Bookings exactly like web-created
        # ones, and createdAt uses a server timestamp so "latest first"
        # ordering works across mixed sources.
        from google.cloud.firestore import SERVER_TIMESTAMP as _SRV_TS
        booking_data = {
            "customerId":    customer_uid,
            "customerName":  customer_name,
            "vehicleId":     vehicle_id,
            "plate":         canonical_plate,
            "vehicleDesc":   vehicle_desc,
            "services":      services,
            "preferredDate": date_str,
            "preferredTime": preferred_time,
            "status":        "Approved",
            "autoApproved":  True,
            "notes":         notes or "",
            "createdAt":     _SRV_TS,
            "createdBy":     "customer_ai",
        }

        doc_ref = db.collection("service_bookings").document()
        doc_ref.set(booking_data)

        # Verify the write actually succeeded by reading it back
        written = doc_ref.get()
        if not written.exists:
            logger.error(
                "create_customer_booking: write verification failed for uid=%s",
                customer_uid,
            )
            return {
                "error":   "DB_WRITE_FAILED",
                "message": (
                    "Your booking could not be saved due to a database error. "
                    "Please try again or contact the shop."
                ),
            }

        booking_id = doc_ref.id
        logger.info(
            "create_customer_booking: booking %s created for uid=%s plate=%s date=%s time=%s",
            booking_id, customer_uid, plate, date_str, preferred_time,
        )

        return {
            "success":      True,
            "booking_id":   booking_id,
            "customer":     customer_name,
            "plate":        canonical_plate,
            "vehicle":      vehicle_desc,
            "services":     services,
            "date":         req_date.strftime("%B %d, %Y"),
            "time":         preferred_time,
            "status":       "Approved",
            "notes":        notes or "",
            "message":      (
                f"Your booking has been successfully created! "
                f"Booking ID: {booking_id}. "
                f"Status: Approved. "
                f"We look forward to serving you on "
                f"{req_date.strftime('%B %d, %Y')} at {preferred_time}. "
                f"You can view it under My Bookings."
            ),
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("create_customer_booking error")
        return {
            "error":   "DB_ERROR",
            "message": "Your booking could not be created due to a database error. Please try again.",
        }


# ----------------------------------------------------------------------------
#  TOOL 8 - My Bookings
# ----------------------------------------------------------------------------

def get_my_bookings(customer_uid: str, customer_name: str,
                    filter_status: str | None = None,
                    upcoming_only: bool = False,
                    **_) -> dict:
    """
    Return this customer's service bookings.

    Pass 1: customerId == customer_uid  (UID — most reliable)
    Pass 2: customerName == customer_name / companyName
    Pass 3: case-insensitive scan (last resort)

    Optional filters:
      filter_status  — e.g. "Pending", "Confirmed", "Completed", "Cancelled"
      upcoming_only  — if True, return only future bookings (date >= today)
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
        today_str  = datetime.now().strftime("%Y-%m-%d")

        def _add(doc):
            if doc.id in seen_b_ids:
                return
            seen_b_ids.add(doc.id)
            d    = doc.to_dict()
            svcs = d.get("services", [])
            status = d.get("status", "")

            # Filter by status if requested
            if filter_status and status.lower() != filter_status.lower():
                return

            b_date = d.get("preferredDate", "")

            # Upcoming filter: only bookings on or after today
            if upcoming_only:
                try:
                    # Handle both YYYY-MM-DD and "Month D, YYYY" formats
                    b_dt = _parse_date_flexible(b_date) if b_date else None
                    if b_dt and b_dt.date() < datetime.now().date():
                        return
                    if not b_date:
                        return
                except Exception:
                    pass

            bookings.append({
                "booking_id": doc.id,
                "date":       b_date,
                "time":       d.get("preferredTime", ""),
                "plate":      d.get("plate", ""),
                "vehicle":    d.get("vehicleDesc", ""),
                "services":   ", ".join(svcs) if isinstance(svcs, list) else str(svcs),
                "status":     status,
                "notes":      d.get("notes", ""),
            })

        # Pass 1: Firebase UID (most reliable - matches after booking created by AI)
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
                     ("approved", "confirmed", "in progress", "ongoing")]
        completed = [b for b in bookings if (b["status"] or "").lower() == "completed"]
        cancelled = [b for b in bookings if (b["status"] or "").lower() in
                     ("cancelled", "rejected")]

        return {
            "owner":     customer_name,
            "total":     len(bookings),
            "pending":   len(pending),
            "confirmed": len(confirmed),
            "completed": len(completed),
            "cancelled": len(cancelled),
            "bookings":  bookings,
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("get_my_bookings error")
        return _db_error(e)


# ----------------------------------------------------------------------------
#  TOOL 9 - Update (Reschedule) My Booking
# ----------------------------------------------------------------------------

def update_my_booking(customer_uid: str, customer_name: str,
                      booking_id: str,
                      new_date: str | None = None,
                      new_time: str | None = None,
                      new_notes: str | None = None,
                      **_) -> dict:
    """
    Reschedule or update notes for the authenticated customer's own booking.

    Pre-update checks:
      1. Booking exists
      2. Booking belongs to this customer (customerId == customer_uid)
      3. Booking status allows rescheduling (Pending or Confirmed only)
      4. New date is valid and not in the past
      5. New time slot is available

    The update is ONLY performed after ALL checks pass.
    """
    if not booking_id:
        return {
            "error":   "MISSING_BOOKING_ID",
            "message": "Please provide a booking ID to reschedule.",
        }

    if not new_date and not new_time and new_notes is None:
        return {
            "error":   "NOTHING_TO_UPDATE",
            "message": "Please provide a new date, time, or notes to update your booking.",
        }

    try:
        db = get_db()

        # -- Check 1: booking exists -------------------------------------------
        doc_ref = db.collection("service_bookings").document(booking_id)
        doc     = doc_ref.get()
        if not doc.exists:
            return {
                "error":   "BOOKING_NOT_FOUND",
                "message": "No booking found with that ID.",
            }

        d = doc.to_dict()

        # -- Check 2: ownership ------------------------------------------------
        booking_owner_id = (d.get("customerId") or "").strip()
        if booking_owner_id != customer_uid:
            logger.warning(
                "update_my_booking: uid=%s attempted to modify booking %s owned by %s",
                customer_uid, booking_id, booking_owner_id,
            )
            return _privacy_error()

        # -- Check 3: status allows update -------------------------------------
        current_status = (d.get("status") or "").lower()
        if current_status in ("completed", "cancelled", "rejected"):
            return {
                "error":   "BOOKING_NOT_EDITABLE",
                "message": (
                    f"This booking cannot be rescheduled because its status is "
                    f"'{d.get('status', '')}'. Only Pending or Confirmed bookings can be rescheduled."
                ),
            }

        updates: dict = {"updatedAt": datetime.utcnow().isoformat()}

        # -- Check 4 & 5: new date/time validation + availability --------------
        if new_date:
            try:
                req_date = _parse_date_flexible(new_date)
            except ValueError as ve:
                return {"error": "INVALID_DATE", "message": str(ve)}

            if req_date.date() < datetime.now().date():
                return {
                    "error":   "PAST_DATE",
                    "message": "The new date is in the past. Please choose a future date.",
                }

            date_str = req_date.strftime("%Y-%m-%d")
            check_time = new_time or d.get("preferredTime", "")
            avail = check_booking_availability(
                customer_uid=customer_uid,
                customer_name=customer_name,
                preferred_date=date_str,
                preferred_time=check_time,
            )

            if avail.get("error"):
                return avail

            if check_time and avail.get("requested_time_available") is False:
                # Exclude the current booking itself from "taken" count
                return {
                    "error":           "TIME_NOT_AVAILABLE",
                    "message":         (
                        f"The {check_time} slot on {req_date.strftime('%B %d, %Y')} "
                        f"is not available. Please choose from the available slots."
                    ),
                    "available_slots": avail.get("available_slots", []),
                }

            updates["preferredDate"] = date_str
            if new_time:
                updates["preferredTime"] = new_time

        elif new_time:
            # Only time is changing - check availability on the existing date
            existing_date = d.get("preferredDate", "")
            avail = check_booking_availability(
                customer_uid=customer_uid,
                customer_name=customer_name,
                preferred_date=existing_date,
                preferred_time=new_time,
            )
            if avail.get("requested_time_available") is False:
                return {
                    "error":           "TIME_NOT_AVAILABLE",
                    "message":         (
                        f"The {new_time} slot on {existing_date} is not available."
                    ),
                    "available_slots": avail.get("available_slots", []),
                }
            updates["preferredTime"] = new_time

        if new_notes is not None:
            updates["notes"] = new_notes

        # -- Perform the update ------------------------------------------------
        doc_ref.update(updates)

        # Read back to confirm
        updated = doc_ref.get()
        if not updated.exists:
            return {
                "error":   "DB_WRITE_FAILED",
                "message": "The booking update could not be confirmed. Please try again.",
            }

        ud = updated.to_dict()
        logger.info(
            "update_my_booking: booking %s updated by uid=%s → %s",
            booking_id, customer_uid, updates,
        )

        return {
            "success":    True,
            "booking_id": booking_id,
            "plate":      ud.get("plate", ""),
            "services":   ud.get("services", []),
            "new_date":   ud.get("preferredDate", ""),
            "new_time":   ud.get("preferredTime", ""),
            "status":     ud.get("status", ""),
            "message":    "Your booking has been successfully updated.",
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("update_my_booking error")
        return {
            "error":   "DB_ERROR",
            "message": "Your booking could not be updated due to a database error. Please try again.",
        }


# ----------------------------------------------------------------------------
#  TOOL 10 - Cancel My Booking
# ----------------------------------------------------------------------------

def cancel_my_booking(customer_uid: str, customer_name: str,
                      booking_id: str,
                      reason: str | None = None,
                      **_) -> dict:
    """
    Cancel the authenticated customer's own booking.

    Pre-cancellation checks:
      1. Booking exists
      2. Booking belongs to this customer (customerId == customer_uid)
      3. Booking status is eligible for cancellation (Pending or Confirmed)

    Status is only updated after ALL checks pass and Firestore write succeeds.
    The AI is told of the outcome from the database response — never assumed.
    """
    if not booking_id:
        return {
            "error":   "MISSING_BOOKING_ID",
            "message": "Please provide a booking ID to cancel.",
        }

    try:
        db = get_db()

        # -- Check 1: booking exists -------------------------------------------
        doc_ref = db.collection("service_bookings").document(booking_id)
        doc     = doc_ref.get()
        if not doc.exists:
            return {
                "error":   "BOOKING_NOT_FOUND",
                "message": "No booking found with that ID.",
            }

        d = doc.to_dict()

        # -- Check 2: ownership ------------------------------------------------
        booking_owner_id = (d.get("customerId") or "").strip()
        if booking_owner_id != customer_uid:
            logger.warning(
                "cancel_my_booking: uid=%s attempted to cancel booking %s owned by %s",
                customer_uid, booking_id, booking_owner_id,
            )
            return _privacy_error()

        # -- Check 3: status eligible for cancellation -------------------------
        current_status = (d.get("status") or "").lower()
        if current_status == "cancelled":
            return {
                "error":   "ALREADY_CANCELLED",
                "message": "This booking has already been cancelled.",
            }
        if current_status in ("completed", "rejected"):
            return {
                "error":   "CANNOT_CANCEL",
                "message": (
                    f"This booking cannot be cancelled because its status is "
                    f"'{d.get('status', '')}'. "
                    f"Only Pending or Confirmed bookings can be cancelled."
                ),
            }

        # -- Perform cancellation ----------------------------------------------
        cancel_data = {
            "status":       "Cancelled",
            "cancelledAt":  datetime.utcnow().isoformat(),
            "cancelledBy":  "customer",
            "cancelReason": reason or "",
        }
        doc_ref.update(cancel_data)

        # Read back to confirm the write
        updated = doc_ref.get()
        if not updated.exists:
            return {
                "error":   "DB_WRITE_FAILED",
                "message": "The cancellation could not be confirmed. Please try again.",
            }

        ud     = updated.to_dict()
        status = ud.get("status", "")

        if status.lower() != "cancelled":
            return {
                "error":   "CANCEL_FAILED",
                "message": "The cancellation could not be completed. Please contact the shop.",
            }

        logger.info(
            "cancel_my_booking: booking %s cancelled by uid=%s",
            booking_id, customer_uid,
        )

        return {
            "success":    True,
            "booking_id": booking_id,
            "plate":      ud.get("plate", ""),
            "services":   ud.get("services", []),
            "date":       ud.get("preferredDate", ""),
            "time":       ud.get("preferredTime", ""),
            "status":     "Cancelled",
            "message":    "Your booking has been successfully cancelled.",
        }

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        logger.exception("cancel_my_booking error")
        return {
            "error":   "DB_ERROR",
            "message": "Your booking could not be cancelled due to a database error. Please try again.",
        }


# ----------------------------------------------------------------------------
#  TOOL 11 - Estimate Service Cost
# ----------------------------------------------------------------------------

def estimate_service_cost(customer_uid: str, customer_name: str,
                          service_names: list[str] | None = None,
                          include_materials: bool = True, **_) -> dict:
    """
    Estimate combined cost for one or more named services using actual catalog prices.
    Never invents prices — returns an error for services not found in the catalog.

    SERVICES AND MATERIALS ARE SEPARATE CHARGES:
      estimated_total = service_charge + material_subtotal
    Materials (when a historical usage pattern exists for the service) are
    priced unit_price x qty from the item catalog; their subtotal is reported
    separately from the service/labor charge. When no historical pattern is
    found, materials_used is None and only the service charge is shown.
    """
    if not service_names:
        return {
            "error":   "NO_SERVICES",
            "message": "Please specify at least one service name to estimate the cost.",
        }
    try:
        db          = get_db()
        raw_catalog = cache_manager.get_service_catalog(db)
        if raw_catalog is None:
            return _quota_error()

        catalog: dict[str, dict] = {}
        for item in raw_catalog:
            catalog[item.get("name", "").lower()] = {
                "name": item.get("name", ""),
                "cost": _strip_currency(item.get("cost", 0)),
                "uom":  item.get("uom", ""),
            }

        # Material price lookup (from the same item catalog; customer-facing
        # price only — never stock/supplier fields).
        material_prices: dict[str, float] = {}
        try:
            all_items = cache_manager.get_item_catalog_cached(db)
            if all_items:
                for item in all_items:
                    if (item.get("type") or "").strip().lower() != "material":
                        continue
                    mname = (item.get("name") or "").strip().lower()
                    if mname and mname not in material_prices:
                        material_prices[mname] = _strip_currency(item.get("cost", 0))
        except Exception:
            material_prices = {}

        def _material_price(name: str) -> float | None:
            key = name.lower().strip()
            if key in material_prices:
                return material_prices[key]
            for k, v in material_prices.items():
                if key in k or k in key:
                    return v
            return None

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

        result: dict = {
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

        # ── Optional materials estimate (separate charge) ────────────────────
        # Uses the shop's historical usage pattern for the same service from
        # completed maintenance records; qty x unit price comes from the item
        # catalog. Never fabricates a price for a material that isn't listed.
        if include_materials and matched:
            try:
                svc_keys = [m["service"].lower() for m in matched]
                patterns: dict[str, dict] = {}   # material name -> {qty, uom, count}
                mats_docs = db.collection("maintenance") \
                    .where(filter=FieldFilter("status", "==", "Completed")) \
                    .limit(200).stream()
                scanned = 0
                for d in mats_docs:
                    md       = d.to_dict() or {}
                    svc_rows = md.get("svcRows") or []
                    if not svc_rows:
                        continue
                    job_svcs = {(r.get("name") or "").lower() for r in svc_rows}
                    if not any(any(sk in js or js in sk for sk in svc_keys) for js in job_svcs):
                        continue
                    scanned += 1
                    for r in (md.get("matRows") or []):
                        mname = (r.get("name") or "").strip()
                        if not mname:
                            continue
                        try:
                            qty = float(str(r.get("qty", "1") or "1").strip() or 1)
                        except ValueError:
                            qty = 1.0
                        p = patterns.setdefault(mname, {"qty": 0.0, "uom": r.get("uom", ""), "count": 0})
                        p["qty"] += qty
                        p["count"] += 1
                        if r.get("uom"):
                            p["uom"] = r.get("uom")

                materials_out = []
                mat_subtotal  = 0.0
                missing_price = []
                for mname, p in sorted(patterns.items(), key=lambda kv: -kv[1]["qty"]):
                    avg_qty = round(p["qty"] / max(1, p["count"]), 2)
                    unit    = _material_price(mname)
                    if unit is None:
                        missing_price.append(mname)
                        continue
                    line_total = unit * avg_qty
                    mat_subtotal += line_total
                    materials_out.append({
                        "material":    mname,
                        "qty":         avg_qty,
                        "uom":         p["uom"],
                        "unit_price":  _fmt_cost(unit),
                        "line_total":  _fmt_cost(line_total),
                    })

                result["service_charge"]    = _fmt_cost(total)
                result["materials_usage_note"] = (
                    f"Based on {scanned} completed job(s) with these services."
                    if scanned else None
                )
                if materials_out or missing_price:
                    result["materials"]         = materials_out
                    result["material_subtotal"] = _fmt_cost(mat_subtotal)
                    if mat_subtotal:
                        result["estimated_total"] = _fmt_cost(total + mat_subtotal)
                    if missing_price:
                        result["materials_missing_price"] = missing_price
                        result["note"] = (result["note"] + " " if result["note"] else "") + (
                            "Some materials have no price on file; their cost is not included."
                        )
                    result["charge_breakdown"] = (
                        "service_charge + material_subtotal are separate charges"
                    )
            except Exception:
                # Materials enrichment is best-effort; the service estimate stands.
                pass

        return result

    except Exception as e:
        if _is_firestore_quota(e):
            return _quota_error()
        return _db_error(e)


# ----------------------------------------------------------------------------
#  Date parsing helper
# ----------------------------------------------------------------------------

def _parse_date_flexible(date_str: str) -> datetime:
    """
    Parse a date string in various formats into a datetime object.
    Raises ValueError with a friendly message if parsing fails.
    Supported: YYYY-MM-DD, MM/DD/YYYY, "March 10, 2026", "Mar 10, 2026",
               "next Monday", "tomorrow", "Friday".
    """
    if not date_str:
        raise ValueError("Please provide a valid date.")

    s = date_str.strip()

    # -- Natural language ------------------------------------------------------
    s_lower = s.lower()
    now = datetime.now()

    if s_lower == "today":
        return now.replace(hour=0, minute=0, second=0, microsecond=0)
    if s_lower == "tomorrow":
        return (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    if "next" in s_lower:
        day_names = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]
        for i, dn in enumerate(day_names):
            if dn in s_lower:
                today_wd = now.weekday()
                days_ahead = (i - today_wd) % 7 or 7
                return (now + timedelta(days=days_ahead)).replace(
                    hour=0, minute=0, second=0, microsecond=0)

    # -- ISO format: YYYY-MM-DD ------------------------------------------------
    import re as _re
    m = _re.match(r"^(\d{4})-(\d{2})-(\d{2})", s)
    if m:
        try:
            return datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            pass

    # -- MM/DD/YYYY ------------------------------------------------------------
    m2 = _re.match(r"^(\d{1,2})/(\d{1,2})/(\d{4})", s)
    if m2:
        try:
            return datetime(int(m2.group(3)), int(m2.group(1)), int(m2.group(2)))
        except ValueError:
            pass

    # -- Month name formats ----------------------------------------------------
    MONTHS = ["january","february","march","april","may","june",
              "july","august","september","october","november","december"]
    MONTHS_SHORT = ["jan","feb","mar","apr","may","jun",
                    "jul","aug","sep","oct","nov","dec"]

    m3 = _re.match(r"^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})", s)
    if m3:
        mo_str = m3.group(1).lower()[:3]
        if mo_str in MONTHS_SHORT:
            mo = MONTHS_SHORT.index(mo_str) + 1
            try:
                return datetime(int(m3.group(3)), mo, int(m3.group(2)))
            except ValueError:
                pass

    # Day-of-week (e.g. "Friday") - assume next occurrence
    day_names = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]
    for i, dn in enumerate(day_names):
        if s_lower == dn:
            today_wd    = now.weekday()
            days_ahead  = (i - today_wd) % 7 or 7
            return (now + timedelta(days=days_ahead)).replace(
                hour=0, minute=0, second=0, microsecond=0)

    raise ValueError(
        f"I couldn't understand the date '{date_str}'. "
        "Please use a format like 'March 10, 2026', '2026-03-10', or 'MM/DD/YYYY'."
    )


# ----------------------------------------------------------------------------
#  Tool Schemas - LLM-facing definitions
#  customer_uid and customer_name are NOT listed as parameters - they are
#  always injected server-side to prevent identity spoofing.
# ----------------------------------------------------------------------------

CUSTOMER_TOOL_SCHEMAS = [
    {
        "type": "function",
        "function": {
            "name": "get_my_vehicles",
            "description": (
                "Customer's own registered vehicles. Use for: my vehicles/cars/fleet, "
                "plate numbers, vehicle status, how many vehicles I have."
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
            "name": "suggest_booking_date",
            "description": (
                "Suggest booking dates from service history + intervals. Use for: "
                "'when should I book', 'suggest a date', or when helping pick a booking date."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "plate": {
                        "type": "string",
                        "description": "Plate number.",
                    },
                    "service_type": {
                        "type": "string",
                        "description": "Optional service type.",
                    },
                },
                "required": ["plate"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_my_service_history",
            "description": (
                "Completed service records for the customer's vehicles. Use for: service "
                "history, past services, last oil change, PMS history, how much spent. "
                "Optional filters: plate, service_type, year, recent(N)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "plate": {
                        "type": "string",
                        "description": "Plate filter. Omit = all vehicles.",
                    },
                    "service_type": {
                        "type": "string",
                        "description": "Service keyword filter.",
                    },
                    "year": {
                        "type": "integer",
                        "description": "Year filter.",
                    },
                    "recent": {
                        "type": "integer",
                        "description": "Return N most recent.",
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
            "name": "get_service_recommendations",
            "description": (
                "Maintenance status per vehicle (from lastServiceDate + serviceFrequency). "
                "Use for: 'is my car due', 'next PMS', 'overdue', 'maintenance reminder'."
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
                "Service catalog with prices. Use for: 'how much is X', 'service prices', "
                "'list all services'. For 'all'/complete list call with service_name=None. "
                "Prices from the database — never invented."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "service_name": {
                        "type": "string",
                        "description": "Keyword filter. Omit = full catalog.",
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
            "name": "get_customer_materials",
            "description": (
                "Customer-visible products/materials. Use for: 'do you sell oil', "
                "'what products do you have'. For 'all' call with material_name=None. "
                "Never reveals stock quantities, suppliers, or purchase prices."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "material_name": {
                        "type": "string",
                        "description": "Keyword filter. Omit = full catalog.",
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
            "name": "check_booking_availability",
            "description": (
                "Check available time slots for a date. Call BEFORE create_customer_booking."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "preferred_date": {
                        "type": "string",
                        "description": "Date, e.g. '2026-03-10'.",
                    },
                    "preferred_time": {
                        "type": "string",
                        "description": "Optional time, e.g. '9:00 AM'.",
                    },
                },
                "required": ["preferred_date"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "preview_customer_booking",
            "description": (
                "Preview and validate a booking before creation. Shows booking details "
                "and asks for confirmation. ALWAYS call this BEFORE create_customer_booking. "
                "Returns a formatted preview with all booking details."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "plate": {
                        "type": "string",
                        "description": "Vehicle plate (must belong to this customer).",
                    },
                    "services": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Services to book, e.g. ['Change Oil', 'PMS'].",
                    },
                    "preferred_date": {
                        "type": "string",
                        "description": "Date, e.g. '2026-03-10' or 'March 10, 2026'.",
                    },
                    "preferred_time": {
                        "type": "string",
                        "description": "Time slot, e.g. '9:00 AM' or '2:00 PM'.",
                    },
                    "notes": {
                        "type": "string",
                        "description": "Optional notes.",
                    },
                },
                "required": ["plate", "services", "preferred_date", "preferred_time"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "create_customer_booking",
            "description": (
                "Create a booking for this customer. ONLY call AFTER preview_customer_booking "
                "and user confirms with 'yes'. Use session_id and use_pending=True to complete "
                "the previously previewed booking. Never call this directly without preview."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "plate": {
                        "type": "string",
                        "description": "Vehicle plate (optional if use_pending=True).",
                    },
                    "services": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Services to book (optional if use_pending=True).",
                    },
                    "preferred_date": {
                        "type": "string",
                        "description": "Date (optional if use_pending=True).",
                    },
                    "preferred_time": {
                        "type": "string",
                        "description": "Time slot (optional if use_pending=True).",
                    },
                    "notes": {
                        "type": "string",
                        "description": "Optional notes.",
                    },
                    "session_id": {
                        "type": "string",
                        "description": "Session ID (required when use_pending=True).",
                    },
                    "use_pending": {
                        "type": "boolean",
                        "description": "True to use pre-validated pending booking data.",
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
            "name": "get_my_bookings",
            "description": (
                "Customer's own bookings. Use for: 'my bookings', 'upcoming appointments', "
                "'booking status'. Optional: filter_status, upcoming_only."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "filter_status": {
                        "type": "string",
                        "description": "Pending | Confirmed | Completed | Cancelled.",
                    },
                    "upcoming_only": {
                        "type": "boolean",
                        "description": "True = only future bookings.",
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
            "name": "update_my_booking",
            "description": (
                "Reschedule/update the customer's own booking. Use for: 'move/reschedule "
                "my appointment'. Ownership verified; never touches others' bookings."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "booking_id": {
                        "type": "string",
                        "description": "Booking document ID.",
                    },
                    "new_date": {
                        "type": "string",
                        "description": "New date.",
                    },
                    "new_time": {
                        "type": "string",
                        "description": "New time.",
                    },
                    "new_notes": {
                        "type": "string",
                        "description": "Updated notes.",
                    },
                },
                "required": ["booking_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "cancel_my_booking",
            "description": (
                "Cancel the customer's own booking. Use for: 'cancel my booking'. "
                "Ownership verified; never cancels others' bookings."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "booking_id": {
                        "type": "string",
                        "description": "The booking document ID to cancel.",
                    },
                    "reason": {
                        "type": "string",
                        "description": "Optional reason for cancellation.",
                    },
                },
                "required": ["booking_id"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "estimate_service_cost",
            "description": (
                "Combined cost of named services from actual catalog prices. Use for: "
                "'how much would X and Y cost'. Returns the SERVICE charge and the "
                "MATERIALS charge as SEPARATE line items plus the combined "
                "estimated total. Never invents prices."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "service_names": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Service names to estimate.",
                    },
                    "include_materials": {
                        "type": "boolean",
                        "description": (
                            "Also estimate materials the shop normally uses for these "
                            "services (priced separately from the service charge). "
                            "Default true."
                        ),
                    },
                },
                "required": ["service_names"],
                "additionalProperties": False,
            },
        },
    },
]

CUSTOMER_TOOL_FUNCTIONS = {
    "get_my_vehicles":            get_my_vehicles,
    "get_my_service_history":     get_my_service_history,
    "get_service_recommendations": get_service_recommendations,
    "get_service_prices":         get_service_prices,
    "get_customer_materials":     get_customer_materials,
    "suggest_booking_date":       suggest_booking_date,
    "check_booking_availability": check_booking_availability,
    "preview_customer_booking":   preview_customer_booking,
    "create_customer_booking":    create_customer_booking,
    "get_my_bookings":            get_my_bookings,
    "update_my_booking":          update_my_booking,
    "cancel_my_booking":          cancel_my_booking,
    "estimate_service_cost":      estimate_service_cost,
    # Legacy alias kept for backward compatibility with existing session history
    "get_my_pms_status":          get_service_recommendations,
}
