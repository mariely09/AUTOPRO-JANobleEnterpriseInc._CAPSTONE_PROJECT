"""
Lightweight fast-path intent classifier.

Runs before the LLM for common, unambiguous queries — no API call needed.
Returns a dict with {intent, result} on a match, or None to fall through to LLM.
"""
import re
from firestore_tools import (
    get_stock_levels,
    get_low_stock_items,
    get_item_catalog,
    get_maintenance_jobs,
    get_maintenance_summary,
    get_service_bookings,
    get_deliveries,
    get_vehicles,
    get_user_count,
)


def classify_and_run(text: str) -> dict | None:
    t = text.lower().strip()

    # ── Low stock / reorder ───────────────────────────────────────────────────
    if re.search(r"low.?stock|reorder|running.?low|below.?reorder|out.?of.?stock", t):
        result = get_low_stock_items()
        # Ensure count in result matches items list length (single source of truth for LLM)
        result["low_stock_count"] = len(result["items"])
        return {"intent": "low_stock", "result": result}

    # ── Service bookings (must come BEFORE services catalog to avoid false match) ──
    if re.search(r"(service\s+bookings?|service\s+appointments?)"
                 r"|(bookings?|appointments?)", t):
        status = None
        if "pending" in t:
            status = "Pending"
        elif "in progress" in t:
            status = "In Progress"
        elif "completed" in t:
            status = "Completed"
        return {"intent": "service_bookings", "result": get_service_bookings(status=status)}

    # ── Services catalog ──────────────────────────────────────────────────────
    # Matches: "services we offer", "list of services", "what services do you have",
    # "show services", "service list", "available services", "service offerings", etc.
    # NOTE: runs AFTER booking check to avoid false match on "service bookings"
    if re.search(
        r"(list|show|what|display|get|available|all)[\w\s]*(services?)"
        r"|(services?\s+(we\s+)?(offer|provide|have|list|available|catalog|types?|offerings?))"
        r"|(service\.offerings?|service\.types?|service\.catalog|service\.list)"
        r"|(what[\w\s]+services?\b)",
        t,
    ):
        return {"intent": "item_catalog_services", "result": get_item_catalog(item_type="Service")}

    # ── Materials / inventory ─────────────────────────────────────────────────
    if re.search(
        r"(list|show|display|get|what|all)[\w\s]*(materials?|parts?|supplies?|stock\s*items?|inventory)"
        r"|(materials?|parts?|supplies?)\s+(we\s+)?(have|use|carry|stock|list|available)"
        r"|(all\s+(materials?|parts?|supplies?|stock))"
        r"|(stock\s+levels?|inventory\s+list|current\s+stock)",
        t,
    ):
        return {"intent": "stock_levels", "result": get_stock_levels()}

    # ── Full item catalog ─────────────────────────────────────────────────────
    if re.search(r"(item[\s._-]?catalog|price[\s._-]?list|all[\s._-]?items|catalog)", t):
        return {"intent": "item_catalog_all", "result": get_item_catalog()}

    # ── Maintenance summary ───────────────────────────────────────────────────
    if re.search(
        r"(maintenance|repair)[\w\s]*(summary|overview|total|count|how\s*many)"
        r"|(how\s+many[\w\s]*(maintenance|repair|service)[\w\s]*jobs?)"
        r"|(service[\w\s]*(summary|overview|count|how\s*many))"
        r"|(maintenance\s+overview|maintenance\s+status|maintenance\s+report\s*overview)",
        t,
    ):
        return {"intent": "maintenance_summary", "result": get_maintenance_summary()}

    # ── Maintenance jobs (general + by status) ────────────────────────────────
    if re.search(
        r"(completed|in[\s-]?progress|pending|ongoing)[\w\s]*(maintenance|repair|service|jobs?)"
        r"|(maintenance|repair|service|jobs?)[\w\s]*(completed|in[\s-]?progress|pending|ongoing)"
        r"|(list|show|all|get)[\w\s]*(maintenance|repair)[\w\s]*(jobs?|records?|history)"
        r"|(maintenance|repair)\s+(jobs?|records?|list|history)",
        t,
    ):
        status = None
        if "completed" in t:
            status = "Completed"
        elif "in progress" in t or "in-progress" in t or "ongoing" in t:
            status = "In Progress"
        elif "pending" in t:
            status = "Pending"
        return {"intent": "maintenance_jobs", "result": get_maintenance_jobs(status=status)}

    # ── Deliveries ────────────────────────────────────────────────────────────
    if re.search(
        r"(list|show|all|pending|approved|get)[\w\s]*(deliveries|delivery)"
        r"|(deliveries|delivery)[\w\s]*(list|show|all|status|pending|approved)"
        r"|(supplier[\w\s]*deliveries|deliveries[\w\s]*supplier)",
        t,
    ):
        status = None
        if "pending" in t:
            status = "Pending"
        elif "approved" in t:
            status = "Approved"
        return {"intent": "deliveries", "result": get_deliveries(status=status)}

    # ── Vehicles ──────────────────────────────────────────────────────────────
    if re.search(
        r"(list|show|all|registered|get)[\w\s]*(vehicles?|fleet|cars?|trucks?|vans?|suvs?)"
        r"|(vehicles?|fleet)[\w\s]*(list|show|all|registered|count|status)"
        r"|(our\s+(vehicles?|fleet)|vehicle\s+list|fleet\s+list)",
        t,
    ):
        return {"intent": "vehicles", "result": get_vehicles()}

    # ── User / customer count ─────────────────────────────────────────────────
    if re.search(r"how.many.*(users?|customers?|clients?|staff|accounts?)"
                 r"|(number|count).*(users?|customers?|clients?|staff)", t):
        role = None
        if "customer" in t or "client" in t:
            role = "customer"
        elif "admin" in t:
            role = "admin"
        elif "staff" in t:
            role = "staff"
        return {"intent": "user_count", "result": get_user_count(role=role)}

    return None  # fall through to full LLM tool-calling loop
