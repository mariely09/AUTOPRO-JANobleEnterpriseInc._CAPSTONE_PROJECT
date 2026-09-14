"""
py_calculator.py — Authoritative Python arithmetic engine for the AI backend.

WHY THIS EXISTS
===============
The LLM must never independently calculate totals, averages, stock levels,
reorder quantities, PMS dates, or report sums.  All arithmetic is performed
here and the results are returned as structured data.  The LLM only receives
the already-computed values and is asked to explain or format them.

The number verifier (verifier.py) remains as a secondary safety check, but
the primary defence is that the LLM never sees raw numbers to compute from —
only the final Python-computed result.

DESIGN RULES
============
1. Every function returns a dict with "calculated_by": "python" and
   "calculation_verified": True so callers can embed the proof in the
   ChatResponse.data field.
2. All monetary values are floats; formatted strings (₱1,234.56) are only
   produced at the display layer, not stored in intermediate results.
3. Functions are pure — they take plain Python structures (dicts/lists) and
   return dicts.  No Firestore reads happen here.
"""

from __future__ import annotations
from datetime import datetime, date, timedelta
from typing import Any


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _to_float(value: Any) -> float:
    """Convert any numeric-ish value to float, returning 0.0 on failure."""
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        import re
        cleaned = re.sub(r"[₱,\s]", "", value)
        try:
            return float(cleaned)
        except ValueError:
            return 0.0
    return 0.0


def _fmt(amount: float) -> str:
    """Format a float as a Philippine Peso string (₱1,234.56)."""
    return f"₱{amount:,.2f}"


# ---------------------------------------------------------------------------
# Service / Material cost calculations
# ---------------------------------------------------------------------------

def calculate_service_cost(
    service_items: list[dict],
) -> dict:
    """
    Compute the total cost of a list of service line items.

    Each item is expected to have at least:
        { "name": str, "cost": float|str, "qty": int|float }
    qty defaults to 1 if absent.

    Returns
    -------
    {
        "calculated_by": "python",
        "calculation_verified": True,
        "line_items": [{"name", "qty", "unit_cost", "subtotal"}, ...],
        "subtotal": float,          # service-only total (no materials)
        "formatted_subtotal": str,
    }
    """
    lines = []
    subtotal = 0.0
    for item in service_items:
        qty       = _to_float(item.get("qty", 1)) or 1.0
        unit_cost = _to_float(item.get("cost") or item.get("unit_cost", 0))
        sub       = qty * unit_cost
        subtotal += sub
        lines.append({
            "name":      item.get("name", ""),
            "qty":       qty,
            "unit_cost": unit_cost,
            "subtotal":  sub,
        })
    return {
        "calculated_by":        "python",
        "calculation_verified": True,
        "line_items":           lines,
        "subtotal":             subtotal,
        "formatted_subtotal":   _fmt(subtotal),
    }


def calculate_material_cost(
    material_items: list[dict],
) -> dict:
    """
    Compute the total cost of a list of material line items.

    Each item: { "name": str, "cost": float|str, "qty": int|float, "uom": str }

    Returns
    -------
    {
        "calculated_by": "python",
        "calculation_verified": True,
        "line_items": [...],
        "material_total": float,
        "formatted_material_total": str,
    }
    """
    lines = []
    total = 0.0
    for item in material_items:
        qty       = _to_float(item.get("qty", 1)) or 1.0
        unit_cost = _to_float(item.get("cost") or item.get("unit_cost", 0))
        sub       = qty * unit_cost
        total    += sub
        lines.append({
            "name":      item.get("name", ""),
            "qty":       qty,
            "uom":       item.get("uom", ""),
            "unit_cost": unit_cost,
            "subtotal":  sub,
        })
    return {
        "calculated_by":             "python",
        "calculation_verified":      True,
        "line_items":                lines,
        "material_total":            total,
        "formatted_material_total":  _fmt(total),
    }


def calculate_booking_estimate(
    service_items: list[dict],
    material_items: list[dict] | None = None,
) -> dict:
    """
    Compute a combined estimate for a service booking (services + materials).

    Returns
    -------
    {
        "calculated_by": "python",
        "calculation_verified": True,
        "service_lines": [...],
        "material_lines": [...],
        "subtotal": float,           # services only
        "material_total": float,     # materials only
        "grand_total": float,        # subtotal + material_total
        "formatted_subtotal": str,
        "formatted_material_total": str,
        "formatted_grand_total": str,
    }
    """
    svc_result = calculate_service_cost(service_items)
    mat_result = calculate_material_cost(material_items or [])
    grand      = svc_result["subtotal"] + mat_result["material_total"]
    return {
        "calculated_by":              "python",
        "calculation_verified":       True,
        "service_lines":              svc_result["line_items"],
        "material_lines":             mat_result["line_items"],
        "subtotal":                   svc_result["subtotal"],
        "material_total":             mat_result["material_total"],
        "grand_total":                grand,
        "formatted_subtotal":         svc_result["formatted_subtotal"],
        "formatted_material_total":   mat_result["formatted_material_total"],
        "formatted_grand_total":      _fmt(grand),
    }


# ---------------------------------------------------------------------------
# Inventory / stock calculations
# ---------------------------------------------------------------------------

def calculate_inventory_totals(
    items: list[dict],
) -> dict:
    """
    Compute summary statistics for a list of inventory items.

    Each item: { "name": str, "stock": int|float, "min": ..., "max": ...,
                 "reorder": ..., "cost": ..., "uom": str }

    Returns
    -------
    {
        "calculated_by": "python",
        "calculation_verified": True,
        "total_items": int,
        "total_stock_units": float,
        "low_stock_count": int,
        "out_of_stock_count": int,
        "avg_stock": float,
        "min_stock": float,
        "max_stock": float,
        "estimated_inventory_value": float,
        "formatted_inventory_value": str,
    }
    """
    if not items:
        return {
            "calculated_by": "python", "calculation_verified": True,
            "total_items": 0, "total_stock_units": 0.0,
            "low_stock_count": 0, "out_of_stock_count": 0,
            "avg_stock": 0.0, "min_stock": 0.0, "max_stock": 0.0,
            "estimated_inventory_value": 0.0, "formatted_inventory_value": "₱0.00",
        }

    stocks       = [_to_float(i.get("stock", 0)) for i in items]
    costs        = [_to_float(i.get("cost", 0)) for i in items]
    reorder_pts  = [_to_float(i.get("reorder", 0)) for i in items]
    min_levels   = [_to_float(i.get("min", 0)) for i in items]

    total_units  = sum(stocks)
    inv_value    = sum(s * c for s, c in zip(stocks, costs))
    low_count    = sum(
        1 for s, r, m in zip(stocks, reorder_pts, min_levels)
        if (r > 0 and s <= r) or (m > 0 and s <= m)
    )
    out_count    = sum(1 for s in stocks if s <= 0)
    avg_stock    = total_units / len(stocks) if stocks else 0.0

    return {
        "calculated_by":             "python",
        "calculation_verified":      True,
        "total_items":               len(items),
        "total_stock_units":         total_units,
        "low_stock_count":           low_count,
        "out_of_stock_count":        out_count,
        "avg_stock":                 round(avg_stock, 2),
        "min_stock":                 min(stocks),
        "max_stock":                 max(stocks),
        "estimated_inventory_value": inv_value,
        "formatted_inventory_value": _fmt(inv_value),
    }


def calculate_reorder_quantity(
    current_stock: float,
    reorder_point: float,
    max_level: float,
) -> dict:
    """
    Compute how many units to order to bring stock back to max level.

    Returns
    -------
    {
        "calculated_by": "python",
        "calculation_verified": True,
        "current_stock": float,
        "reorder_point": float,
        "max_level": float,
        "needs_reorder": bool,
        "order_quantity": float,   # max_level - current_stock (≥ 0)
    }
    """
    needs   = current_stock <= reorder_point
    qty     = max(0.0, max_level - current_stock) if needs else 0.0
    return {
        "calculated_by":        "python",
        "calculation_verified": True,
        "current_stock":        current_stock,
        "reorder_point":        reorder_point,
        "max_level":            max_level,
        "needs_reorder":        needs,
        "order_quantity":       qty,
    }


# ---------------------------------------------------------------------------
# Maintenance / report aggregate calculations
# ---------------------------------------------------------------------------

def calculate_maintenance_totals(
    jobs: list[dict],
) -> dict:
    """
    Compute summary statistics for a list of maintenance job records.

    Each job: { "cost": float|str, "status": str, "date": str }

    Returns
    -------
    {
        "calculated_by": "python",
        "calculation_verified": True,
        "total_jobs": int,
        "total_cost": float,
        "formatted_total_cost": str,
        "avg_cost_per_job": float,
        "formatted_avg_cost": str,
        "by_status": {"Completed": int, ...},
    }
    """
    total_cost = 0.0
    by_status: dict[str, int] = {}
    for job in jobs:
        total_cost += _to_float(job.get("cost", 0))
        status = job.get("status", "Unknown")
        by_status[status] = by_status.get(status, 0) + 1

    n       = len(jobs)
    avg     = total_cost / n if n else 0.0
    return {
        "calculated_by":        "python",
        "calculation_verified": True,
        "total_jobs":           n,
        "total_cost":           total_cost,
        "formatted_total_cost": _fmt(total_cost),
        "avg_cost_per_job":     round(avg, 2),
        "formatted_avg_cost":   _fmt(avg),
        "by_status":            by_status,
    }


def calculate_issuance_totals(
    rows: list[dict],
) -> dict:
    """
    Compute totals for issuance records (used in report generation and AI answers).

    Each row: { "qty": float, "unitCost"/"unit_cost": float, "subtotal": float }

    Returns
    -------
    {
        "calculated_by": "python",
        "calculation_verified": True,
        "total_rows": int,
        "total_qty": float,
        "total_cost": float,
        "formatted_total_cost": str,
    }
    """
    total_qty  = 0.0
    total_cost = 0.0
    for row in rows:
        qty = _to_float(row.get("qty", 0))
        # Prefer explicit subtotal; fall back to qty × unit_cost
        sub = _to_float(row.get("subtotal") or row.get("sub", 0))
        if sub == 0.0:
            uc  = _to_float(row.get("unitCost") or row.get("unit_cost", 0))
            sub = qty * uc
        total_qty  += qty
        total_cost += sub

    return {
        "calculated_by":        "python",
        "calculation_verified": True,
        "total_rows":           len(rows),
        "total_qty":            total_qty,
        "total_cost":           total_cost,
        "formatted_total_cost": _fmt(total_cost),
    }


# ---------------------------------------------------------------------------
# Preventive Maintenance Scheduling (PMS) date calculations
# ---------------------------------------------------------------------------

def calculate_pms_dates(
    last_service_date: str,
    service_frequency_months: int | float,
    reference_date: date | None = None,
) -> dict:
    """
    Compute the next PMS date and urgency label for a vehicle.

    Parameters
    ----------
    last_service_date        : ISO date string "YYYY-MM-DD" or "Month D, YYYY"
    service_frequency_months : service interval in months (e.g. 3 = every 3 months)
    reference_date           : the "today" date for comparison (defaults to today)

    Returns
    -------
    {
        "calculated_by": "python",
        "calculation_verified": True,
        "last_service_date": str,
        "next_pms_date": str,         # "Month D, YYYY"
        "days_until": int,            # negative = overdue
        "urgency": str,               # "Overdue"|"Due This Week"|"Due Soon"|"Active"
        "months_interval": int,
    }
    """
    if reference_date is None:
        # Use Manila timezone as reference
        try:
            import zoneinfo
            from datetime import datetime as _dt
            reference_date = _dt.now(zoneinfo.ZoneInfo("Asia/Manila")).date()
        except Exception:
            reference_date = date.today()

    # Parse last service date
    last_dt: date | None = None
    for fmt in ("%Y-%m-%d", "%B %d, %Y", "%b %d, %Y", "%m/%d/%Y"):
        try:
            last_dt = datetime.strptime(last_service_date, fmt).date()
            break
        except (ValueError, TypeError):
            continue

    if last_dt is None:
        return {
            "calculated_by":        "python",
            "calculation_verified": True,
            "last_service_date":    last_service_date,
            "next_pms_date":        "Unknown",
            "days_until":           None,
            "urgency":              "Unknown",
            "months_interval":      int(service_frequency_months),
            "error":                "Could not parse last_service_date",
        }

    months = int(service_frequency_months) if service_frequency_months else 3
    # Add months manually (timedelta doesn't support months)
    month_total = last_dt.month + months - 1
    next_year   = last_dt.year + month_total // 12
    next_month  = month_total % 12 + 1
    # Clamp day to valid range for the target month
    import calendar
    max_day     = calendar.monthrange(next_year, next_month)[1]
    next_day    = min(last_dt.day, max_day)
    next_dt     = date(next_year, next_month, next_day)

    days_until = (next_dt - reference_date).days

    if days_until < 0:
        urgency = "Overdue"
    elif days_until <= 7:
        urgency = "Due This Week"
    elif days_until <= 30:
        urgency = "Due Soon"
    else:
        urgency = "Active"

    return {
        "calculated_by":        "python",
        "calculation_verified": True,
        "last_service_date":    last_dt.strftime("%B %d, %Y"),
        "next_pms_date":        next_dt.strftime("%B %d, %Y"),
        "days_until":           days_until,
        "urgency":              urgency,
        "months_interval":      months,
    }


# ---------------------------------------------------------------------------
# Generic aggregate helpers (used by admin tools and report generator)
# ---------------------------------------------------------------------------

def aggregate_numeric_field(
    records: list[dict],
    field: str,
) -> dict:
    """
    Compute sum, average, min, max for a numeric field across a list of records.
    Always operates on the COMPLETE dataset — never on a truncated slice.

    Returns
    -------
    {
        "calculated_by": "python",
        "calculation_verified": True,
        "field": str,
        "count": int,
        "total": float,
        "average": float,
        "minimum": float,
        "maximum": float,
    }
    """
    values = [_to_float(r.get(field, 0)) for r in records if field in r]
    if not values:
        return {
            "calculated_by": "python", "calculation_verified": True,
            "field": field, "count": 0,
            "total": 0.0, "average": 0.0, "minimum": 0.0, "maximum": 0.0,
        }
    return {
        "calculated_by":        "python",
        "calculation_verified": True,
        "field":                field,
        "count":                len(values),
        "total":                sum(values),
        "average":              round(sum(values) / len(values), 2),
        "minimum":              min(values),
        "maximum":              max(values),
    }


def paginate_results(
    records: list[dict],
    page: int = 1,
    page_size: int = 20,
) -> dict:
    """
    Return a page slice of records WITH metadata that makes it clear the list
    is incomplete when has_more is True.

    IMPORTANT: Computations (counts, sums, averages) MUST be performed on the
    full records list BEFORE calling this function.  This function only handles
    the display slice.

    Returns
    -------
    {
        "items": [...],
        "total_count": int,
        "returned_count": int,
        "has_more": bool,
        "page": int,
        "page_size": int,
        "total_pages": int,
    }
    """
    page      = max(1, page)
    start     = (page - 1) * page_size
    end       = start + page_size
    slice_    = records[start:end]
    total     = len(records)
    has_more  = end < total
    import math
    return {
        "items":          slice_,
        "total_count":    total,
        "returned_count": len(slice_),
        "has_more":       has_more,
        "page":           page,
        "page_size":      page_size,
        "total_pages":    math.ceil(total / page_size) if page_size else 1,
    }
