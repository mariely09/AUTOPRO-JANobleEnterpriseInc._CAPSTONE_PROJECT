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
    # NOTE: only matches plain "services" queries — bookings are handled above
    if re.search(r"(list|show|what|display|get).*(service.offerings?|service.types?|service.catalog)"
                 r"|(service.offerings?|service.types?|service.catalog)", t):
        return {"intent": "item_catalog_services", "result": get_item_catalog(item_type="Service")}

    # ── Materials catalog ─────────────────────────────────────────────────────
    if re.search(r"(list|show|display|get).*(all\s+)?(materials?|parts?|supplies?|items?|stock.items?|inventory)"
                 r"|all.*(materials?|parts?|supplies?)", t):
        return {"intent": "stock_levels", "result": get_stock_levels()}

    # ── Full item catalog ─────────────────────────────────────────────────────
    if re.search(r"(item.catalog|price.list|all.items|catalog)", t):
        return {"intent": "item_catalog_all", "result": get_item_catalog()}

    # ── Maintenance summary ───────────────────────────────────────────────────
    if re.search(r"(maintenance|repair).*(summary|overview|total|count|how.many)"
                 r"|(how.many.*(maintenance|repair|service).jobs?)"
                 r"|(service).*(summary|overview|count|how.many)", t):
        return {"intent": "maintenance_summary", "result": get_maintenance_summary()}

    # ── Maintenance jobs by status ────────────────────────────────────────────
    if re.search(r"(completed|in.progress|pending).*(maintenance|repair|service|jobs?)"
                 r"|(maintenance|repair|service|jobs?).*(completed|in.progress|pending)", t):
        status = None
        if "completed" in t:
            status = "Completed"
        elif "in progress" in t or "in-progress" in t:
            status = "In Progress"
        elif "pending" in t:
            status = "Pending"
        return {"intent": "maintenance_jobs", "result": get_maintenance_jobs(status=status)}

    # ── Deliveries ────────────────────────────────────────────────────────────
    if re.search(r"(list|show|all|pending|approved).*(deliveries|delivery|deliveries?)"
                 r"|(deliveries?|delivery).*(list|show|all|status)", t):
        status = None
        if "pending" in t:
            status = "Pending"
        elif "approved" in t:
            status = "Approved"
        return {"intent": "deliveries", "result": get_deliveries(status=status)}

    # ── Vehicles ──────────────────────────────────────────────────────────────
    if re.search(r"(list|show|all|registered).*(vehicles?|fleet|cars?|trucks?)"
                 r"|(vehicles?|fleet).*(list|show|all|registered|count)", t):
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
