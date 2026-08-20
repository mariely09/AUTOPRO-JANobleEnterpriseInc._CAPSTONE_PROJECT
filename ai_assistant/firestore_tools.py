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
    """uid → {name, email, role}"""
    lookup = {}
    for doc in db.collection("users").stream():
        d = doc.to_dict()
        lookup[doc.id] = {
            "name":  d.get("name", d.get("firstName", "") + " " + d.get("lastName", "")).strip(),
            "email": d.get("email", ""),
            "role":  d.get("role", ""),
        }
    return lookup


def _build_vehicle_lookup_by_id(db) -> dict:
    """doc_id → {plate, desc, owner, type, status}"""
    lookup = {}
    for doc in db.collection("vehicles").stream():
        d = doc.to_dict()
        lookup[doc.id] = {
            "plate":  d.get("plate", ""),
            "desc":   d.get("desc", ""),
            "owner":  d.get("owner", ""),
            "type":   d.get("type", ""),
            "status": d.get("status", ""),
        }
    return lookup


def _build_vehicle_lookup_by_plate(db) -> dict:
    """plate → {desc, owner, type, status}"""
    lookup = {}
    for doc in db.collection("vehicles").stream():
        d = doc.to_dict()
        plate = d.get("plate", "")
        if plate:
            lookup[plate] = {
                "desc":   d.get("desc", ""),
                "owner":  d.get("owner", ""),
                "type":   d.get("type", ""),
                "status": d.get("status", ""),
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
    for doc in db.collection("stock_inventory").stream():
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
    """List catalog items. item_type: 'Material' or 'Service'."""
    db = get_db()
    query = db.collection("item_master")
    if item_type:
        query = query.where(filter=FieldFilter("type", "==", item_type))
    if group:
        query = query.where(filter=FieldFilter("group", "==", group))

    items = []
    for doc in query.stream():
        d = doc.to_dict()
        items.append({
            "num":   d.get("num", ""),
            "name":  d.get("name", ""),
            "type":  d.get("type", ""),
            "group": d.get("group", ""),
            "uom":   d.get("uom", ""),
            "cost":  d.get("cost", ""),
        })

    items.sort(key=lambda x: (x["type"], x["name"]))
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
            # No vehicles found for this owner — return empty result immediately
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
        # Firestore 'in' max 10 — chunk the plate list
        raw_jobs = []
        for i in range(0, len(owner_plates), 10):
            chunk = owner_plates[i:i + 10]
            q = db.collection("maintenance").where(
                filter=FieldFilter("plate", "in", chunk))
            if status:
                q = q.where(filter=FieldFilter("status", "==", status))
            raw_jobs.extend(q.stream())
    else:
        query = db.collection("maintenance")
        if status:
            query = query.where(filter=FieldFilter("status", "==", status))
        if plate:
            query = query.where(filter=FieldFilter("plate", "==", plate))
        raw_jobs = list(query.stream())

    jobs = []
    total_cost = 0.0
    for doc in raw_jobs:
        d         = doc.to_dict()
        job_plate = d.get("plate", "")
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
            "plate":        job_plate,
            "vehicle_desc": vehicle.get("desc", d.get("desc", "")),
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
        "jobs":          jobs[:20],
    }


def get_maintenance_summary() -> dict:
    """High-level summary: job counts by status and total cost."""
    db = get_db()
    by_status: dict = defaultdict(int)
    total_cost = 0.0
    for doc in db.collection("maintenance").stream():
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
            "plate":         d.get("plate", vehicle.get("plate", "")),
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
        "bookings":       bookings[:20],
    }


# ── Issuances (joins maintenance + vehicles by plate) ─────────────────────────

def get_issuances(maintenance_id: str | None = None, plate: str | None = None) -> dict:
    """
    List items (materials + services) issued per maintenance job.
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
        p        = d.get("plate", "")
        vehicle  = vehicle_by_plate.get(p, {})
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
        "deliveries":       deliveries[:20],
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

    vehicles   = []
    owner_lower = owner.lower().strip() if owner else None

    for doc in query.stream():
        d = doc.to_dict()
        # Apply owner filter (case-insensitive) in Python — no composite index needed
        if owner_lower:
            stored = (d.get("owner", "") or "").lower().strip()
            if stored != owner_lower:
                continue
        vehicles.append({
            "plate":       d.get("plate", ""),
            "desc":        d.get("desc", ""),
            "owner":       d.get("owner", ""),
            "type":        d.get("type", ""),
            "status":      d.get("status", ""),
            "lastSvcDate": d.get("lastSvcDate", ""),
            "odo":         d.get("odo", ""),
            "svcFreq":     d.get("svcFreq", ""),
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


# ── Tool schemas ──────────────────────────────────────────────────────────────

TOOL_SCHEMAS = [
    {
        "type": "function",
        "function": {
            "name": "get_stock_levels",
            "description": "List all stock/inventory items with current quantity levels. Use for queries about materials, parts, stock, or supplies. Filter by group (e.g. 'Lubricants') or status ('OK', 'Low').",
            "parameters": {
                "type": "object",
                "properties": {
                    "group":  {"type": "string", "description": "Commodity group. Only include when filtering."},
                    "status": {"type": "string", "description": "Stock status. Only include when filtering."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_low_stock_items",
            "description": "Return items at or below reorder point. Use for low stock or reorder alerts.",
            "parameters": {"type": "object", "properties": {}, "required": [], "additionalProperties": False},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_item_catalog",
            "description": "List all catalog items (Materials and Services). Pass item_type='Service' for services list, item_type='Material' for parts. Omit for everything.",
            "parameters": {
                "type": "object",
                "properties": {
                    "item_type": {"type": "string", "enum": ["Material", "Service"], "description": "Filter by type."},
                    "group":     {"type": "string", "description": "Commodity group. Only include when filtering."},
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
                "List maintenance/service jobs with vehicle details (resolved from plate), "
                "services performed, and materials used. "
                "Filter by status, plate, or owner name. "
                "Use owner to get ALL service history for a specific customer — "
                "the tool resolves all plates belonging to that owner automatically."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "description": "Job status (e.g. 'Completed', 'In Progress'). Only include when filtering.",
                    },
                    "plate": {
                        "type": "string",
                        "description": "Vehicle plate number. Only include when filtering by a specific vehicle.",
                    },
                    "owner": {
                        "type": "string",
                        "description": (
                            "Owner / customer name to filter by. "
                            "Returns jobs for ALL vehicles registered under this owner. "
                            "Use when admin asks about a specific customer's service history."
                        ),
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
            "description": "Get counts of maintenance jobs by status and total cost. Use for high-level overview.",
            "parameters": {"type": "object", "properties": {}, "required": [], "additionalProperties": False},
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_service_bookings",
            "description": "List customer service bookings with full customer name, email, vehicle details, and requested services — all resolved from foreign keys. Filter by status.",
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {"type": "string", "description": "Booking status. Only include when filtering."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_issuances",
            "description": "List materials and services issued per maintenance job, with vehicle details resolved from plate. Filter by maintenance_id (e.g. 'SVC-001') or plate.",
            "parameters": {
                "type": "object",
                "properties": {
                    "maintenance_id": {"type": "string", "description": "Maintenance job ID (e.g. 'SVC-001'). Only include when filtering by job."},
                    "plate":          {"type": "string", "description": "Vehicle plate. Only include when filtering by vehicle."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_deliveries",
            "description": "List supplier deliveries with full item details embedded. Filter by status.",
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {"type": "string", "description": "Delivery status. Only include when filtering."},
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
                "List registered fleet vehicles with owner, status, last service date, "
                "and odometer. Filter by status and/or owner name. "
                "Use owner to see all vehicles belonging to a specific customer."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "status": {
                        "type": "string",
                        "description": "Vehicle PMS status. Only include when filtering.",
                    },
                    "owner": {
                        "type": "string",
                        "description": (
                            "Owner / customer name to filter by (case-insensitive). "
                            "Only include when the admin asks about a specific customer's vehicles."
                        ),
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
            "description": "Count users by role ('customer', 'admin', 'staff'). Omit role for total.",
            "parameters": {
                "type": "object",
                "properties": {
                    "role": {"type": "string", "description": "User role. Only include when filtering."},
                },
                "required": [], "additionalProperties": False,
            },
        },
    },
]

TOOL_FUNCTIONS = {
    "get_stock_levels":        get_stock_levels,
    "get_low_stock_items":     get_low_stock_items,
    "get_item_catalog":        get_item_catalog,
    "get_maintenance_jobs":    get_maintenance_jobs,
    "get_maintenance_summary": get_maintenance_summary,
    "get_service_bookings":    get_service_bookings,
    "get_issuances":           get_issuances,
    "get_deliveries":          get_deliveries,
    "get_vehicles":            get_vehicles,
    "get_user_count":          get_user_count,
}
