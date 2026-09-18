"""
Admin AI tools — wired to real Firestore collections with foreign-key resolution.

Join strategy (Firestore has no native joins):
  service_bookings.customerId  → users (doc ID)        → customer name/email
  service_bookings.vehicleId   → vehicles (doc ID)     → plate, desc, owner
  maintenance.plate            → vehicles (plate field) → vehicle desc/owner
  issuances.maintenanceId      → maintenance (id field) → job context
  issuances.plate              → vehicles (plate field) → vehicle desc

All joins are done in Python after fetching. Lookup tables are built once per
call and reused — never N+1 queries.
"""
import re
from datetime import datetime, timedelta
from collections import defaultdict
from firestore_client import get_db
from google.cloud.firestore_v1.base_query import FieldFilter
import cache_manager


# ── Helpers ───────────────────────────────────────────────────────────────────

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


def _build_user_lookup(db) -> dict:
    """uid → {name, email, role} — cached for 5 minutes."""
    cached = cache_manager.get_user_lookup(db)
    if cached is not None:
        return cached
    # Fallback: build inline (should not normally reach here)
    lookup = {}
    for doc in db.collection("users").limit(500).stream():
        d = doc.to_dict()
        lookup[doc.id] = {
            "name":  d.get("name", d.get("firstName", "") + " " + d.get("lastName", "")).strip(),
            "email": d.get("email", ""),
            "role":  d.get("role", ""),
        }
    return lookup


def _build_vehicle_lookup_by_id(db) -> dict:
    """doc_id → {plate, desc, owner, ownerId, type, status} — cached for 3 minutes."""
    cached = cache_manager.get_vehicle_lookup_by_id(db)
    if cached is not None:
        return cached
    # Fallback
    lookup = {}
    for doc in db.collection("vehicles").limit(500).stream():
        d = doc.to_dict()
        lookup[doc.id] = {
            "plate":   d.get("plateNumber") or d.get("plate") or "",
            "desc":    d.get("description") or d.get("desc") or d.get("assetDescription") or "",
            "owner":   d.get("owner", ""),
            "ownerId": d.get("ownerId", ""),
            "type":    d.get("type", ""),
            "status":  d.get("status", ""),
        }
    return lookup


def _build_vehicle_lookup_by_plate(db) -> dict:
    """plateNumber → {docId, desc, owner, ownerId, type, status} — cached for 3 minutes."""
    cached = cache_manager.get_vehicle_lookup_by_plate(db)
    if cached is not None:
        return cached
    # Fallback
    lookup = {}
    for doc in db.collection("vehicles").limit(500).stream():
        d = doc.to_dict()
        plate = (d.get("plateNumber") or d.get("plate") or "").strip()
        if plate:
            lookup[plate] = {
                "docId":   doc.id,
                "desc":    d.get("description") or d.get("desc") or d.get("assetDescription") or "",
                "owner":   d.get("owner", ""),
                "ownerId": d.get("ownerId", ""),
                "type":    d.get("type", ""),
                "status":  d.get("status", ""),
            }
    return lookup


# ── Stock / Inventory ─────────────────────────────────────────────────────────

def get_stock_levels(group: str | None = None, status: str | None = None) -> dict:
    """List all stock items with current levels. Filter by group or status."""
    db = get_db()
    query = db.collection("stock_inventory")
    if group:
        query = query.where(filter=FieldFilter("group", "==", group))
    if status:
        query = query.where(filter=FieldFilter("status", "==", status))

    items = []
    for doc in query.stream():
        d = doc.to_dict()
        items.append({
            "num":     d.get("num", ""),
            "name":    d.get("name", "") or d.get("itemName", ""),
            "group":   d.get("group", "") or d.get("commodityGroup", ""),
            "stock":   d.get("stock", 0),
            "uom":     d.get("uom", "") or d.get("unit", ""),
            "min":     d.get("min", 0) or d.get("minLevel", 0),
            "max":     d.get("max", 0) or d.get("maxLevel", 0),
            "reorder": d.get("reorder", 0) or d.get("reorderQty", 0),
            "status":  d.get("status", ""),
        })

    items.sort(key=lambda x: x["name"])
    return {
        "filter_group":  group or "all groups",
        "filter_status": status or "all statuses",
        "total_items":   len(items),
        "items":         items,
    }


def get_low_stock_items() -> dict:
    """Return all items at or below their reorder point (reorder point must be > 0)."""
    db = get_db()
    items = []
    # Add limit to prevent full collection scan
    for doc in db.collection("stock_inventory").limit(200).stream():
        d = doc.to_dict()
        stock   = int(d.get("stock",   0))
        reorder = int(d.get("reorder", 0))
        min_lvl = int(d.get("min",     0))
        status  = (d.get("status") or "").strip()

        # Match the frontend logic: status=='Low' OR (stock <= min AND min > 0)
        is_low = (
            status.lower() == "low"
            or (min_lvl > 0 and stock <= min_lvl)
            or (reorder > 0 and stock <= reorder)
        )
        if is_low:
            items.append({
                "num":     d.get("num", ""),
                "name":    d.get("name", ""),
                "group":   d.get("group", ""),
                "stock":   stock,
                "min":     min_lvl,
                "reorder": reorder,
                "uom":     d.get("uom", ""),
                "status":  status or ("Low" if is_low else "OK"),
            })

    items.sort(key=lambda x: x["stock"])
    return {"low_stock_count": len(items), "items": items}


# ── Item Master (catalog) ─────────────────────────────────────────────────────

def get_item_catalog(item_type: str | None = None, group: str | None = None) -> dict:
    """
    List catalog items. item_type: 'Material' or 'Service'.
    Uses cache to avoid re-reading item_master on every admin query.
    """
    db = get_db()
    # Try the cache first (covers the common Service-only query)
    cached = cache_manager.get_item_catalog_cached(db, item_type=item_type)

    if cached is not None:
        items = cached
    else:
        # Cache miss — should not normally happen; fall through to direct query
        query = db.collection("item_master")
        if item_type:
            query = query.where(filter=FieldFilter("type", "==", item_type))
        if group:
            query = query.where(filter=FieldFilter("group", "==", group))
        items_raw = []
        for doc in query.stream():
            d = doc.to_dict()
            items_raw.append({
                "num":   d.get("num", ""),
                "name":  d.get("name", ""),
                "type":  d.get("type", ""),
                "group": d.get("group", ""),
                "uom":   d.get("uom", ""),
                "cost":  d.get("cost", ""),
            })
        items_raw.sort(key=lambda x: (x["type"], x["name"]))
        items = items_raw

    # Apply group filter post-cache (group is a secondary filter rarely used)
    if group:
        items = [i for i in items if i.get("group", "").lower() == group.lower()]

    return {
        "filter_type":  item_type or "all types",
        "filter_group": group or "all groups",
        "total_items":  len(items),
        "items":        items,
    }


# ── Maintenance jobs (joins vehicles by plate) ────────────────────────────────

def get_maintenance_jobs(status: str | None = None,
                        plate:  str | None = None,
                        owner:  str | None = None) -> dict:
    """
    List maintenance jobs. Resolves plate → vehicle description and owner.
    Also expands embedded svcRows/matRows into readable line items.

    Filters:
      status — e.g. 'Completed', 'In Progress'
      plate  — specific vehicle plate number
      owner  — customer / owner name; resolves ALL plates for that owner first,
               then queries maintenance by those plates.  Supports case-insensitive
               matching so the admin can ask "show history for john dela cruz".
    """
    db = get_db()
    vehicle_by_plate = _build_vehicle_lookup_by_plate(db)

    # ── Resolve plates when filtering by owner name ───────────────────────────
    owner_plates: list | None = None
    if owner:
        owner_lower = owner.lower().strip()
        owner_plates = [
            p for p, v in vehicle_by_plate.items()
            if (v.get("owner") or "").lower().strip() == owner_lower
        ]
        if not owner_plates:
            return {
                "filter_status": status or "all statuses",
                "filter_plate":  plate or "all vehicles",
                "filter_owner":  owner,
                "total_jobs":    0,
                "total_cost":    0.0,
                "jobs":          [],
                "note":          f"No vehicles found for owner '{owner}'.",
            }

    # ── Build maintenance query ───────────────────────────────────────────────
    if owner_plates:
        raw_jobs = []
        for i in range(0, len(owner_plates), 10):
            chunk = owner_plates[i:i + 10]
            # Query both canonical plateNumber and legacy plate
            for field in ("plateNumber", "plate"):
                q = db.collection("maintenance").where(
                    filter=FieldFilter(field, "in", chunk))
                if status:
                    q = q.where(filter=FieldFilter("status", "==", status))
                raw_jobs.extend(q.stream())
        # Deduplicate
        seen = set()
        deduped = []
        for doc in raw_jobs:
            if doc.id not in seen:
                seen.add(doc.id)
                deduped.append(doc)
        raw_jobs = deduped
    else:
        query = db.collection("maintenance")
        if status:
            query = query.where(filter=FieldFilter("status", "==", status))
        if plate:
            # Try canonical plateNumber first; include legacy plate results too
            raw_jobs = list(query.where(filter=FieldFilter("plateNumber", "==", plate)).stream())
            legacy   = list(query.where(filter=FieldFilter("plate", "==", plate)).stream())
            seen = {doc.id for doc in raw_jobs}
            raw_jobs.extend(doc for doc in legacy if doc.id not in seen)
        else:
            raw_jobs = list(query.stream())

    jobs = []
    total_cost = 0.0
    for doc in raw_jobs:
        d         = doc.to_dict()
        # Canonical plate first, then legacy
        job_plate = (d.get("plateNumber") or d.get("plate") or "").strip()
        vehicle   = vehicle_by_plate.get(job_plate, {})
        cost      = _strip_currency(d.get("cost", 0))
        total_cost += cost

        svc_rows = [
            f"{r.get('name','')} x{r.get('qty','')} {r.get('uom','')} @ ₱{r.get('cost','')}"
            for r in (d.get("svcRows") or [])
        ]
        mat_rows = [
            f"{r.get('name','')} x{r.get('qty','')} {r.get('uom','')} @ ₱{r.get('cost','')}"
            for r in (d.get("matRows") or [])
        ]

        jobs.append({
            "id":           d.get("id", doc.id),
            "vehicleId":    d.get("vehicleId", ""),
            "ownerId":      d.get("ownerId", ""),
            "plate":        job_plate,
            "vehicle_desc": vehicle.get("desc", d.get("desc") or d.get("description") or ""),
            "owner":        vehicle.get("owner", ""),
            "mechanic":     d.get("mechanic", ""),
            "date":         d.get("date", ""),
            "status":       d.get("status", ""),
            "cost":         cost,
            "services":     svc_rows,
            "materials":    mat_rows,
        })

    jobs.sort(key=lambda x: x["date"], reverse=True)
    return {
        "filter_status": status or "all statuses",
        "filter_plate":  plate or "all vehicles",
        "filter_owner":  owner or "all owners",
        "total_jobs":    len(jobs),
        "total_cost":    round(total_cost, 2),
        "jobs":          jobs,  # Show ALL jobs without truncation
    }


def get_maintenance_summary() -> dict:
    """High-level summary: job counts by status and total cost."""
    db = get_db()
    by_status: dict = defaultdict(int)
    total_cost = 0.0
    for doc in db.collection("maintenance").limit(500).stream():
        d = doc.to_dict()
        by_status[d.get("status", "Unknown")] += 1
        total_cost += _strip_currency(d.get("cost", 0))

    return {
        "total_jobs":  sum(by_status.values()),
        "by_status":   dict(by_status),
        "total_cost":  round(total_cost, 2),
    }


# ── Service bookings (joins users + vehicles by FK) ───────────────────────────

def get_service_bookings(status: str | None = None) -> dict:
    """
    List service bookings with resolved customer name/email and vehicle details.
    Joins:  customerId → users doc ID
            vehicleId  → vehicles doc ID
    
    NOTE: "Pending" means bookings that are approved/confirmed but not yet completed.
    Auto-approved bookings have status='Approved' until service is marked as finished.
    """
    db = get_db()
    user_by_id    = _build_user_lookup(db)
    vehicle_by_id = _build_vehicle_lookup_by_id(db)

    query = db.collection("service_bookings")
    if status:
        query = query.where(filter=FieldFilter("status", "==", status))

    bookings = []
    for doc in query.stream():
        d = doc.to_dict()

        cid     = d.get("customerId", "")
        vid     = d.get("vehicleId", "")
        customer = user_by_id.get(cid, {})
        vehicle  = vehicle_by_id.get(vid, {})

        # services is a list of strings embedded directly
        services = d.get("services", [])
        if isinstance(services, list):
            service_names = [s for s in services if isinstance(s, str)]
        else:
            service_names = []

        bookings.append({
            "customerName":  d.get("customerName") or customer.get("name", ""),
            "customerEmail": customer.get("email", ""),
            "plate":         d.get("plate") or d.get("plateNumber") or vehicle.get("plate", ""),
            "vehicleDesc":   d.get("vehicleDesc", vehicle.get("desc", "")),
            "vehicleOwner":  vehicle.get("owner", ""),
            "preferredDate": d.get("preferredDate", ""),
            "preferredTime": d.get("preferredTime", ""),
            "services":      service_names,
            "status":        d.get("status", ""),
        })

    bookings.sort(key=lambda x: x["preferredDate"], reverse=True)
    by_status: dict = defaultdict(int)
    for b in bookings:
        by_status[b["status"]] += 1

    return {
        "filter_status":  status or "all statuses",
        "total_bookings": len(bookings),
        "by_status":      dict(by_status),
        "bookings":       bookings,  # Show ALL bookings without truncation
    }


# ── Issuances (joins maintenance + vehicles by plate) ─────────────────────────

def get_issuances(maintenance_id: str | None = None, plate: str | None = None) -> dict:
    """
    List materials and services issued per maintenance job.
    Resolves plate → vehicle description.
    Filter by maintenance_id (e.g. 'SVC-001') or plate.
    """
    db = get_db()
    vehicle_by_plate = _build_vehicle_lookup_by_plate(db)

    query = db.collection("issuances")
    if maintenance_id:
        query = query.where(filter=FieldFilter("maintenanceId", "==", maintenance_id))
    if plate:
        query = query.where(filter=FieldFilter("plate", "==", plate))

    rows = []
    total_cost = 0.0
    for doc in query.stream():
        d = doc.to_dict()
        # Canonical plateNumber first, legacy plate fallback
        p       = (d.get("plateNumber") or d.get("plate") or "").strip()
        vehicle = vehicle_by_plate.get(p, {})
        subtotal = _strip_currency(d.get("subtotal", 0))
        total_cost += subtotal

        rows.append({
            "maintenanceId": d.get("maintenanceId", ""),
            "plate":         p,
            "vehicleDesc":   vehicle.get("desc", d.get("assetDesc", "")),
            "itemNum":       d.get("itemNum", ""),
            "itemName":      d.get("itemName", ""),
            "itemType":      d.get("itemType", ""),
            "qty":           d.get("qty", ""),
            "uom":           d.get("uom", ""),
            "unitCost":      d.get("unitCost", ""),
            "subtotal":      subtotal,
            "date":          d.get("date", ""),
            "createdBy":     d.get("createdBy", ""),
        })

    rows.sort(key=lambda x: x["date"], reverse=True)
    return {
        "filter_maintenance_id": maintenance_id or "all jobs",
        "filter_plate":          plate or "all vehicles",
        "total_rows":            len(rows),
        "total_cost":            round(total_cost, 2),
        "issuances":             rows[:30],
    }


# ── Deliveries ────────────────────────────────────────────────────────────────

def get_deliveries(status: str | None = None) -> dict:
    """List supplier deliveries with embedded item details."""
    db = get_db()
    query = db.collection("deliveries")
    if status:
        query = query.where(filter=FieldFilter("status", "==", status))

    deliveries = []
    for doc in query.stream():
        d = doc.to_dict()
        raw_items = d.get("items", [])
        item_list = []
        if isinstance(raw_items, list):
            for it in raw_items:
                if isinstance(it, dict):
                    item_list.append({
                        "itemNum":      it.get("itemNum", ""),
                        "itemName":     it.get("itemName", ""),
                        "expectedQty":  it.get("expectedQty", ""),
                        "actualQty":    it.get("actualQty", ""),
                        "uom":          it.get("uom", ""),
                        "remark":       it.get("remark", ""),
                    })

        deliveries.append({
            "supplier":    d.get("supplier", ""),
            "date":        d.get("date", ""),
            "status":      d.get("status", ""),
            "receivedBy":  d.get("receivedBy", ""),
            "notes":       d.get("notes", ""),
            "item_count":  len(item_list),
            "items":       item_list,
        })

    deliveries.sort(key=lambda x: x["date"], reverse=True)
    by_status: dict = defaultdict(int)
    for dv in deliveries:
        by_status[dv["status"]] += 1

    return {
        "filter_status":    status or "all statuses",
        "total_deliveries": len(deliveries),
        "by_status":        dict(by_status),
        "deliveries":       deliveries,  # Show ALL deliveries without truncation
    }


# ── Vehicles ──────────────────────────────────────────────────────────────────

def get_vehicles(status: str | None = None, owner: str | None = None) -> dict:
    """
    List registered fleet vehicles.

    Filters:
      status — vehicle PMS status (e.g. 'Active', 'Overdue')
      owner  — customer / owner name (case-insensitive match on the `owner` field)
    """
    db    = get_db()
    query = db.collection("vehicles")
    if status:
        query = query.where(filter=FieldFilter("status", "==", status))

    vehicles    = []
    owner_lower = owner.lower().strip() if owner else None

    for doc in query.stream():
        d = doc.to_dict()
        if owner_lower:
            stored = (d.get("owner", "") or "").lower().strip()
            if stored != owner_lower:
                continue
        # Canonical field names first, legacy fallbacks for un-migrated docs
        plate   = d.get("plateNumber") or d.get("plate") or ""
        desc    = d.get("description") or d.get("desc") or d.get("assetDescription") or ""
        lsd     = d.get("lastServiceDate") or d.get("lastSvcDate") or ""
        odo_raw = d.get("odometer") or d.get("odo") or ""
        freq    = d.get("serviceFrequency") or d.get("svcFreq") or ""
        vehicles.append({
            "vehicleId":    doc.id,
            "ownerId":      d.get("ownerId", ""),
            "plate":        plate,
            "desc":         desc,
            "owner":        d.get("owner", ""),
            "type":         d.get("type", ""),
            "status":       d.get("status", ""),
            "lastSvcDate":  lsd,
            "odo":          str(odo_raw),
            "svcFreq":      str(freq),
        })

    vehicles.sort(key=lambda x: x["plate"])
    by_status: dict = defaultdict(int)
    for v in vehicles:
        by_status[v["status"]] += 1

    return {
        "filter_status":  status or "all statuses",
        "filter_owner":   owner  or "all owners",
        "total_vehicles": len(vehicles),
        "by_status":      dict(by_status),
        "vehicles":       vehicles,
    }


# ── Users ─────────────────────────────────────────────────────────────────────

def get_user_count(role: str | None = None) -> dict:
    """Count users. role: 'customer', 'admin', 'staff'."""
    db = get_db()
    query = db.collection("users")
    if role:
        query = query.where(filter=FieldFilter("role", "==", role))

    by_role: dict = defaultdict(int)
    total = 0
    for doc in query.stream():
        d = doc.to_dict()
        by_role[d.get("role", "unknown")] += 1
        total += 1

    return {
        "filter_role": role or "all roles",
        "total_users": total,
        "by_role":     dict(by_role),
    }


def get_fleet_breakdown_by_customer() -> dict:
    """
    Return fleet breakdown showing how many vehicles each customer/company owns.
    Groups vehicles by owner (company name), showing vehicle details per customer.
    AI cannot retrieve customer names, but can display company names and vehicle details.
    """
    db = get_db()
    vehicle_by_id = _build_vehicle_lookup_by_id(db)
    
    # Group vehicles by owner/company
    fleet_by_owner: dict = defaultdict(list)
    
    for vid, vdata in vehicle_by_id.items():
        owner = vdata.get("owner", "Unknown Owner").strip() or "Unknown Owner"
        fleet_by_owner[owner].append({
            "vehicleId": vid,
            "plate": vdata.get("plate", "N/A"),
            "desc": vdata.get("desc", "N/A"),
            "type": vdata.get("type", "N/A"),
            "status": vdata.get("status", "N/A"),
        })
    
    # Sort each owner's fleet by plate number
    for owner in fleet_by_owner:
        fleet_by_owner[owner].sort(key=lambda v: v["plate"])
    
    # Convert to list format for easier display
    breakdown = []
    for owner, vehicles in sorted(fleet_by_owner.items()):
        breakdown.append({
            "company": owner,
            "vehicle_count": len(vehicles),
            "vehicles": vehicles,
        })
    
    return {
        "total_companies": len(breakdown),
        "total_vehicles": sum(len(v["vehicles"]) for v in breakdown),
        "breakdown": breakdown,
    }


# ── Tool schemas ──────────────────────────────────────────────────────────────

TOOL_SCHEMAS = [
    {
        "type": "function",
        "function": {
            "name": "get_stock_levels",
            "description": "Stock/inventory items with quantities. Use for materials/parts/supplies queries. Filter by group or status.",
            "parameters": {
                "type": "object",
                "properties": {
                    "group":  {"type": "string", "description": "Commodity group filter."},
                    "status": {"type": "string", "description": "Stock status filter (OK/Low)."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_low_stock_items",
            "description": "Items at/below reorder point. Low-stock and reorder queries.",
            "parameters": {"type": "object", "properties": {}, "required": [], "additionalProperties": False},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_item_catalog",
            "description": "Catalog items (Materials + Services) with prices. item_type='Service'|'Material' to filter; omit for all.",
            "parameters": {
                "type": "object",
                "properties": {
                    "item_type": {"type": "string", "enum": ["Material", "Service"], "description": "Type filter."},
                    "group":     {"type": "string", "description": "Commodity group filter."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_maintenance_jobs",
            "description": (
                "Maintenance/service jobs with vehicle details, services, materials. "
                "Filter by status/plate/owner (owner = all vehicles of that customer)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "description": "Job status filter, e.g. 'Completed', 'In Progress'.",
                    },
                    "plate": {
                        "type": "string",
                        "description": "Vehicle plate filter.",
                    },
                    "owner": {
                        "type": "string",
                        "description": "Customer name filter — jobs for ALL their vehicles.",
                    },
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_maintenance_summary",
            "description": "Maintenance job counts by status + total cost. High-level overview.",
            "parameters": {"type": "object", "properties": {}, "required": [], "additionalProperties": False},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_service_bookings",
            "description": "Customer service bookings (name, email, vehicle, services resolved). Filter by status.",
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {"type": "string", "description": "Booking status filter."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_issuances",
            "description": "Materials/services issued per maintenance job. Filter by maintenance_id or plate.",
            "parameters": {
                "type": "object",
                "properties": {
                    "maintenance_id": {"type": "string", "description": "Maintenance job ID filter, e.g. 'SVC-001'."},
                    "plate":          {"type": "string", "description": "Vehicle plate filter."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_deliveries",
            "description": "Supplier deliveries with item details. Filter by status.",
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {"type": "string", "description": "Delivery status filter."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_vehicles",
            "description": (
                "Registered fleet vehicles (owner, status, last service, odometer). "
                "Filter by status and/or owner (customer's vehicles)."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "description": "PMS status filter.",
                    },
                    "owner": {
                        "type": "string",
                        "description": "Customer name filter (case-insensitive).",
                    },
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_user_count",
            "description": "Count users by role (customer/admin/staff). Omit role for total.",
            "parameters": {
                "type": "object",
                "properties": {
                    "role": {"type": "string", "description": "User role filter: customer | admin | staff."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_fleet_breakdown_by_customer",
            "description": (
                "Fleet breakdown showing how many vehicles each customer/company owns. "
                "Returns vehicles grouped by owner/company name with plate numbers and vehicle types. "
                "Use this when admin asks 'how many vehicles per customer' or 'fleet breakdown by company'."
            ),
            "parameters": {"type": "object", "properties": {}, "required": [], "additionalProperties": False},
        },
    },
]

TOOL_FUNCTIONS = {
    "get_stock_levels":               get_stock_levels,
    "get_low_stock_items":            get_low_stock_items,
    "get_item_catalog":               get_item_catalog,
    "get_maintenance_jobs":           get_maintenance_jobs,
    "get_maintenance_summary":        get_maintenance_summary,
    "get_service_bookings":           get_service_bookings,
    "get_issuances":                  get_issuances,
    "get_deliveries":                 get_deliveries,
    "get_vehicles":                   get_vehicles,
    "get_user_count":                 get_user_count,
    "get_fleet_breakdown_by_customer": get_fleet_breakdown_by_customer,
}
