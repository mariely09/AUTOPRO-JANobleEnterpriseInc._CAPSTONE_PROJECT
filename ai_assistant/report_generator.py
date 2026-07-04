"""
Report generator for Caltex AutoPro AI Assistant.

Produces PDF and Excel reports that match the exact branded layout used by
the website's print_layout_header.js — same header, same table style, same
colour scheme (#E8001C red, #1a202c dark, #003087 blue).

Supported report types:
  inventory      → stock_inventory collection
  issuance       → issuances collection
  maintenance    → maintenance collection
  vehicles       → vehicles collection
  bookings       → service_bookings collection
"""

import io
import os
import re as _re
from datetime import datetime

from firestore_client import get_db

# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────

_MONTHS_FULL = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]
_MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def _fmt_date(raw: str) -> str:
    """Normalise any date string to 'March 10, 2026' format."""
    if not raw:
        return "—"
    # Already "March 10, 2026" or "Mar 10, 2026"
    m = _re.match(r"^([A-Za-z]+)\s+(\d+),?\s+(\d{4})", raw)
    if m:
        mo, day, yr = m.group(1), int(m.group(2)), m.group(3)
        abbr = mo[:3].capitalize()
        if abbr in _MONTHS_SHORT:
            return f"{_MONTHS_FULL[_MONTHS_SHORT.index(abbr)]} {day}, {yr}"
        return f"{mo} {day}, {yr}"
    # "7/2/2026" or "07/02/2026"
    m2 = _re.match(r"^(\d{1,2})/(\d{1,2})/(\d{4})", raw)
    if m2:
        return f"{_MONTHS_FULL[int(m2.group(1)) - 1]} {int(m2.group(2))}, {m2.group(3)}"
    # "2026-07-02"
    m3 = _re.match(r"^(\d{4})-(\d{2})-(\d{2})", raw)
    if m3:
        return f"{_MONTHS_FULL[int(m3.group(2)) - 1]} {int(m3.group(3))}, {m3.group(1)}"
    try:
        dt = datetime.fromisoformat(raw)
        return f"{_MONTHS_FULL[dt.month - 1]} {dt.day}, {dt.year}"
    except Exception:
        return raw


def _parse_month_year(raw: str):
    """Return (month_index_0based, year_int) or None. Handles all common date formats."""
    if not raw:
        return None
    # "March 10, 2026" or "Mar 10, 2026" — month name first
    m = _re.match(r"^([A-Za-z]+)\s+\d+,?\s+(\d{4})", raw)
    if m:
        abbr = m.group(1)[:3].capitalize()
        if abbr in _MONTHS_SHORT:
            return _MONTHS_SHORT.index(abbr), int(m.group(2))
    # "3/10/2026" or "03/10/2026"
    m2 = _re.match(r"^(\d{1,2})/(\d{1,2})/(\d{4})", raw)
    if m2:
        return int(m2.group(1)) - 1, int(m2.group(3))
    # "2026-03-10" (ISO)
    m3 = _re.match(r"^(\d{4})-(\d{2})-(\d{2})", raw)
    if m3:
        return int(m3.group(2)) - 1, int(m3.group(1))
    # Try Python datetime parsing as last resort
    try:
        from datetime import datetime as _dt
        dt = _dt.fromisoformat(raw[:19])
        return dt.month - 1, dt.year
    except Exception:
        pass
    return None

# ── Brand constants (match print_layout_header.js) ────────────────────────────
BRAND_NAME    = "JA Noble Enterprise Inc."
BRAND_SUB     = "Caltex San Pedro"
BRAND_CITY    = "Laguna"
BRAND_ADDRESS = "102 National Highway, Brgy. Landayan, San Pedro, Laguna"
FOOTER_TEXT   = "Caltex San Pedro · JA Noble Enterprise Inc."
RED           = (232, 0, 28)        # #E8001C
DARK          = (26, 32, 44)        # #1a202c
BLUE          = (0, 48, 135)        # #003087
GREY          = (113, 128, 150)     # #718096
LIGHT_GREY    = (247, 248, 250)     # #f7f8fa
WHITE         = (255, 255, 255)
ROW_ALT       = (248, 250, 252)     # #f8fafc  (even row bg)

LOGO_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "automotive_website", "static", "img", "LOGO_CALTEX.png"
)


# ─────────────────────────────────────────────────────────────────────────────
#  Firestore data fetchers
# ─────────────────────────────────────────────────────────────────────────────

def _fetch_inventory():
    db = get_db()
    rows = []
    for doc in db.collection("stock_inventory").stream():
        d = doc.to_dict()
        stock   = d.get("stock", 0)
        min_lvl = d.get("min", 0)
        max_lvl = d.get("max", 0)
        reorder = d.get("reorder", 0)
        status  = d.get("status", "")
        if not status:
            if int(stock) <= int(reorder):
                status = "Low"
            elif int(stock) > int(max_lvl) and int(max_lvl) > 0:
                status = "Over"
            else:
                status = "OK"
        rows.append({
            "num":    d.get("num", ""),
            "name":   d.get("name", "") or d.get("itemName", ""),
            "group":  d.get("group", "") or d.get("commodityGroup", ""),
            "stock":  stock,
            "uom":    d.get("uom", "") or d.get("unit", ""),
            "min":    min_lvl,
            "max":    max_lvl,
            "reorder":reorder,
            "status": status,
        })
    rows.sort(key=lambda r: r["name"])
    return rows


def _fetch_issuances(month: str | None = None):
    """Fetch issuances, optionally filtered to a specific month name (e.g. 'March 2026')."""
    db = get_db()
    rows = []
    for doc in db.collection("issuances").stream():
        d = doc.to_dict()
        raw_date = d.get("date", "")
        rows.append({
            "date":       raw_date,
            "plate":      d.get("plate", ""),
            "itemNum":    d.get("itemNum", ""),
            "itemName":   d.get("itemName", ""),
            "itemType":   d.get("itemType", ""),
            "group":      d.get("commodityGroup", ""),
            "uom":        d.get("uom", ""),
            "qty":        d.get("qty", "") or d.get("quantity", ""),
            "unitCost":   d.get("unitCost", "") or d.get("unit_cost", ""),
            "subtotal":   d.get("subtotal", ""),
        })
    rows.sort(key=lambda r: r["date"], reverse=True)

    # ── Month filter ──────────────────────────────────────────
    if month:
        # month may be "March 2026" or "Mar 2026" — normalise to (mo_idx, year)

        m = _re.match(r"([A-Za-z]+)\s+(\d{4})", month.strip())
        if m:
            abbr = m.group(1)[:3].capitalize()
            target_mo  = _MONTHS_SHORT.index(abbr) if abbr in _MONTHS_SHORT else -1
            target_yr  = int(m.group(2))
            if target_mo >= 0:
                filtered = []
                for r in rows:
                    parsed = _parse_month_year(r["date"])
                    if parsed and parsed[0] == target_mo and parsed[1] == target_yr:
                        filtered.append(r)
                rows = filtered

    return rows


def _fetch_maintenance(month: str | None = None):
    db = get_db()
    rows = []
    for doc in db.collection("maintenance").stream():
        d = doc.to_dict()
        rows.append({
            "id":      d.get("id", doc.id),
            "plate":   d.get("plate", ""),
            "desc":    d.get("desc", ""),
            "mechanic":d.get("mechanic", ""),
            "date":    d.get("date", ""),
            "status":  d.get("status", ""),
            "cost":    d.get("cost", ""),
        })
    rows.sort(key=lambda r: r["date"], reverse=True)
    if month:

        m = _re.match(r"([A-Za-z]+)\s+(\d{4})", month.strip())
        if m:
            abbr      = m.group(1)[:3].capitalize()
            target_mo = _MONTHS_SHORT.index(abbr) if abbr in _MONTHS_SHORT else -1
            target_yr = int(m.group(2))
            if target_mo >= 0:
                filtered = []
                for r in rows:
                    parsed = _parse_month_year(r["date"])
                    if parsed and parsed[0] == target_mo and parsed[1] == target_yr:
                        filtered.append(r)
                rows = filtered
    return rows


def _fetch_vehicles():
    db = get_db()
    rows = []
    for doc in db.collection("vehicles").stream():
        d = doc.to_dict()
        rows.append({
            "plate":       d.get("plate", ""),
            "desc":        d.get("desc", ""),
            "owner":       d.get("owner", ""),
            "type":        d.get("type", ""),
            "status":      d.get("status", ""),
            "lastSvcDate": d.get("lastSvcDate", ""),
            "odo":         d.get("odo", ""),
        })
    rows.sort(key=lambda r: r["plate"])
    return rows


def _fetch_bookings(month: str | None = None):
    db = get_db()
    rows = []
    for doc in db.collection("service_bookings").stream():
        d = doc.to_dict()
        svcs = d.get("services", [])
        rows.append({
            "date":          d.get("preferredDate", ""),
            "time":          d.get("preferredTime", ""),
            "customerName":  d.get("customerName", ""),
            "plate":         d.get("plate", ""),
            "vehicleDesc":   d.get("vehicleDesc", ""),
            "services":      ", ".join(svcs) if isinstance(svcs, list) else str(svcs),
            "status":        d.get("status", ""),
        })
    rows.sort(key=lambda r: r["date"], reverse=True)
    if month:

        m = _re.match(r"([A-Za-z]+)\s+(\d{4})", month.strip())
        if m:
            abbr      = m.group(1)[:3].capitalize()
            target_mo = _MONTHS_SHORT.index(abbr) if abbr in _MONTHS_SHORT else -1
            target_yr = int(m.group(2))
            if target_mo >= 0:
                filtered = []
                for r in rows:
                    parsed = _parse_month_year(r["date"])
                    if parsed and parsed[0] == target_mo and parsed[1] == target_yr:
                        filtered.append(r)
                rows = filtered
    return rows


# ─────────────────────────────────────────────────────────────────────────────
#  Report config: columns + row mapper per report type
# ─────────────────────────────────────────────────────────────────────────────

REPORT_CONFIG = {
    "inventory": {
        "title":   "Inventory Report",
        "fetcher": _fetch_inventory,
        # Status column removed per requirements
        "columns": ["Item No.", "Item Name", "Group", "Stock", "UOM", "Min", "Max", "Reorder Pt."],
        "mapper":  lambda r: [
            r["num"], r["name"], r["group"],
            str(r["stock"]), r["uom"],
            str(r["min"]), str(r["max"]), str(r["reorder"]),
        ],
        "col_widths_pdf":  [50, 120, 80, 38, 38, 32, 32, 50],   # pts
        "col_widths_xlsx": [12, 34, 22, 10, 10, 8, 8, 14],
    },
    "issuance": {
        "title":   "Issuance Report",
        "fetcher": _fetch_issuances,
        # Type/Status column removed per requirements; date formatted to full month name
        "columns": ["Date", "Plate", "Item No.", "Item Name", "Group", "UOM", "Qty", "Unit Cost", "Subtotal"],
        "mapper":  lambda r: [
            _fmt_date(r["date"]), r["plate"], r["itemNum"], r["itemName"],
            r["group"], r["uom"],
            str(r["qty"]), str(r["unitCost"]), str(r["subtotal"]),
        ],
        "col_widths_pdf":  [55, 50, 40, 100, 65, 28, 25, 47, 47],
        "col_widths_xlsx": [20, 16, 12, 32, 20, 8, 8, 15, 15],
    },
    "maintenance": {
        "title":   "Maintenance Report",
        "fetcher": _fetch_maintenance,
        "columns": ["Job ID", "Plate", "Description", "Mechanic", "Date", "Status", "Cost"],
        "mapper":  lambda r: [
            r["id"], r["plate"], r["desc"], r["mechanic"],
            r["date"], r["status"], str(r["cost"]),
        ],
        "col_widths_pdf":  [55, 45, 110, 80, 50, 50, 55],
        "col_widths_xlsx": [16, 14, 32, 24, 14, 14, 16],
    },
    "vehicles": {
        "title":   "Vehicle Fleet Report",
        "fetcher": _fetch_vehicles,
        "columns": ["Plate No.", "Description", "Owner", "Type", "Status", "Last Service", "Odometer"],
        "mapper":  lambda r: [
            r["plate"], r["desc"], r["owner"], r["type"],
            r["status"], r["lastSvcDate"], str(r["odo"]),
        ],
        "col_widths_pdf":  [55, 110, 80, 50, 50, 55, 45],
        "col_widths_xlsx": [14, 30, 24, 14, 14, 16, 14],
    },
    "bookings": {
        "title":   "Service Bookings Report",
        "fetcher": _fetch_bookings,
        "columns": ["Date", "Time", "Customer", "Plate", "Vehicle", "Services", "Status"],
        "mapper":  lambda r: [
            r["date"], r["time"], r["customerName"],
            r["plate"], r["vehicleDesc"], r["services"], r["status"],
        ],
        "col_widths_pdf":  [45, 35, 80, 45, 80, 100, 50],
        "col_widths_xlsx": [14, 10, 24, 14, 24, 30, 14],
    },
}


# ─────────────────────────────────────────────────────────────────────────────
#  PDF generation  (reportlab)
# ─────────────────────────────────────────────────────────────────────────────

def _rgb(t): return tuple(v / 255 for v in t)


def generate_pdf(report_type: str, month: str | None = None) -> bytes:
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.units import mm, pt as _pt
    from reportlab.lib import colors
    from reportlab.platypus import (
        SimpleDocTemplate, Table, TableStyle, Paragraph,
        Spacer, HRFlowable, Image, KeepTogether,
    )
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.lib.enums import TA_LEFT, TA_RIGHT, TA_CENTER

    cfg     = REPORT_CONFIG[report_type]
    fetcher = cfg["fetcher"]
    _month_supported = {"issuance", "maintenance", "bookings"}
    data    = fetcher(month=month) if report_type in _month_supported else fetcher()
    columns = cfg["columns"]
    mapper  = cfg["mapper"]
    widths  = [w * _pt for w in cfg["col_widths_pdf"]]

    buf = io.BytesIO()
    # Use landscape A4 for wide tables — matches website behaviour
    page_size = landscape(A4) if sum(cfg["col_widths_pdf"]) > 450 else A4

    # ── Margins: match website @page { margin: 8mm } ──────────
    doc = SimpleDocTemplate(
        buf, pagesize=page_size,
        leftMargin=8*mm, rightMargin=8*mm,
        topMargin=8*mm,  bottomMargin=8*mm,
    )

    # ── Colours (identical to print_layout_header.js) ─────────
    red_c    = colors.Color(*_rgb(RED))        # #E8001C
    dark_c   = colors.Color(*_rgb(DARK))       # #1a202c
    blue_c   = colors.Color(*_rgb(BLUE))       # #003087
    grey_c   = colors.Color(*_rgb(GREY))       # #718096
    lgrey_c  = colors.Color(0.63, 0.69, 0.77)  # #a0aec0
    alt_c    = colors.Color(*_rgb(ROW_ALT))    # #f8fafc
    white_c  = colors.white
    bdr_c    = colors.Color(0.88, 0.91, 0.94)  # #e2e8f0
    cell_c   = colors.Color(0.18, 0.20, 0.28)  # #2d3748

    # ── Text styles — sizes match website px values ────────────
    # website: .ap-brand = 18px  →  ~13.5pt; .ap-report-title = 16px → ~12pt
    brand_style = ParagraphStyle(
        "brand", fontName="Helvetica-Bold", fontSize=13.5,
        textColor=dark_c, leading=15, spaceAfter=2,
    )
    sub_style = ParagraphStyle(
        "sub", fontName="Helvetica-Bold", fontSize=5.5,
        textColor=grey_c, leading=7, spaceAfter=2,
        wordWrap='LTR',
    )
    addr_style = ParagraphStyle(
        "addr", fontName="Helvetica", fontSize=5.5,
        textColor=lgrey_c, leading=7,
    )
    label_style = ParagraphStyle(
        "lbl", fontName="Helvetica-Bold", fontSize=5.5,
        textColor=lgrey_c, alignment=TA_RIGHT, leading=7, spaceAfter=2,
        charSpace=1.5,
    )
    title_style = ParagraphStyle(
        "title", fontName="Helvetica-Bold", fontSize=12,
        textColor=dark_c, alignment=TA_RIGHT, leading=14, spaceAfter=3,
    )
    meta_style = ParagraphStyle(
        "meta", fontName="Helvetica", fontSize=6,
        textColor=grey_c, alignment=TA_RIGHT, leading=8,
    )
    # Header column: 7px uppercase — matches thead th exactly
    th_style = ParagraphStyle(
        "th", fontName="Helvetica-Bold", fontSize=5.5,
        textColor=colors.Color(1, 1, 1, 0.92),
        leading=7, wordWrap='LTR',
    )
    # Body cells: 8.5px matching tbody td
    cell_style = ParagraphStyle(
        "cell", fontName="Helvetica", fontSize=6.5,
        textColor=cell_c, leading=8.5,
    )
    foot_style = ParagraphStyle(
        "foot", fontName="Helvetica", fontSize=5.5,
        textColor=lgrey_c, alignment=TA_CENTER, leading=7,
    )

    # ── Timestamps ────────────────────────────────────────────
    now      = datetime.now()
    date_str = now.strftime("%B %d, %Y").replace(" 0", " ")
    time_str = now.strftime("%I:%M %p")

    # ── Header: logo | brand block | right block ──────────────
    # Matches .ap-header-inner layout from print_layout_header.js
    left_block = [
        Paragraph(BRAND_NAME, brand_style),
        Paragraph(BRAND_SUB.upper(), sub_style),
        Paragraph(BRAND_ADDRESS, addr_style),
    ]

    right_block = [
        Paragraph("OFFICIAL REPORT", label_style),
        Paragraph(cfg["title"] + (f" — {month}" if month else ""), title_style),
        Paragraph(f'Generated on <b>{date_str}</b> at {time_str}', meta_style),
        Paragraph(f'{len(data)} record(s)' + (f' · {month}' if month else ''), meta_style),
    ]

    logo_cell: list = []
    if os.path.exists(LOGO_PATH):
        # website: .ap-logo = 44px × 44px
        logo_cell = [Image(LOGO_PATH, width=33, height=33)]

    usable_w = doc.width
    # logo col ≈ 44px, left brand takes ~45%, right block takes rest
    logo_w  = 38
    brand_w = (usable_w - logo_w) * 0.50
    right_w = (usable_w - logo_w) * 0.50

    header_table = Table(
        [[logo_cell, left_block, right_block]],
        colWidths=[logo_w, brand_w, right_w],
    )
    header_table.setStyle(TableStyle([
        ("VALIGN",       (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING",  (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING",(0, 0), (-1, -1), 0),
        ("TOPPADDING",   (0, 0), (-1, -1), 0),
        ("LEFTPADDING",  (1, 0), (1, 0),   8),   # gap between logo and brand text
    ]))

    # ── Data table ────────────────────────────────────────────
    # thead th: uppercase, 7px, dark bg — matches website exactly
    header_row = [
        Paragraph(c.upper(), th_style) for c in columns
    ]

    table_data = [header_row]
    for row in data:
        mapped = mapper(row)
        table_data.append([
            Paragraph(str(v) if v else "—", cell_style) for v in mapped
        ])

    # Alternate row colours: white / #f8fafc — matches tbody tr.even
    ts = [
        ("BACKGROUND",     (0, 0), (-1, 0),  dark_c),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [white_c, alt_c]),
        ("GRID",           (0, 0), (-1, -1), 0.5, bdr_c),
        ("LINEBELOW",      (0, 0), (-1, 0),  0,   dark_c),
        ("VALIGN",         (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING",     (0, 0), (-1, 0),  6),    # thead: 8px
        ("BOTTOMPADDING",  (0, 0), (-1, 0),  6),
        ("TOPPADDING",     (0, 1), (-1, -1), 3.5),  # tbody: 5px
        ("BOTTOMPADDING",  (0, 1), (-1, -1), 3.5),
        ("LEFTPADDING",    (0, 0), (-1, -1), 5.5),  # 7px
        ("RIGHTPADDING",   (0, 0), (-1, -1), 5.5),
        # border-radius effect: rounded outer border via table border
        ("BOX",            (0, 0), (-1, -1), 1.5, bdr_c),
    ]

    # Status column colour coding
    status_cols = {
        "maintenance": 5,
        "vehicles":    4,
        "bookings":    6,
    }
    sc = status_cols.get(report_type)
    if sc is not None:
        for i, row in enumerate(data, start=1):
            s = (mapper(row)[sc] or "").lower()
            if s in ("low", "overdue", "cancelled", "rejected"):
                ts.append(("TEXTCOLOR", (sc, i), (sc, i), red_c))
                ts.append(("FONTNAME",  (sc, i), (sc, i), "Helvetica-Bold"))
            elif s in ("ok", "active", "completed", "approved"):
                ts.append(("TEXTCOLOR", (sc, i), (sc, i), colors.Color(0.13, 0.55, 0.13)))
                ts.append(("FONTNAME",  (sc, i), (sc, i), "Helvetica-Bold"))
            elif s in ("pending", "in progress", "ongoing"):
                ts.append(("TEXTCOLOR", (sc, i), (sc, i), colors.Color(0.55, 0.40, 0.02)))
                ts.append(("FONTNAME",  (sc, i), (sc, i), "Helvetica-Bold"))

    data_table = Table(table_data, colWidths=widths, repeatRows=1)
    data_table.setStyle(TableStyle(ts))

    # ── Issuance totals row ───────────────────────────────────
    # Matches .ap-total-bar from print_layout_header.js
    totals_table = None
    if report_type == "issuance" and data:
        def _to_float(v):
            try:
                return float(str(v).replace("₱", "").replace(",", "").strip())
            except (ValueError, TypeError):
                return 0.0

        total_qty      = sum(_to_float(r["qty"])      for r in data)
        total_subtotal = sum(_to_float(r["subtotal"]) for r in data)

        ncols      = len(columns)
        label_span = ncols - 3   # spans Date → UOM

        tot_label = ParagraphStyle(
            "tot_lbl", fontName="Helvetica-Bold", fontSize=7,
            textColor=white_c, alignment=TA_RIGHT, leading=9)
        tot_val = ParagraphStyle(
            "tot_val", fontName="Helvetica-Bold", fontSize=7,
            textColor=white_c, leading=9)

        tot_row = (
            [Paragraph("TOTAL", tot_label)] * label_span
            + [Paragraph(f"{total_qty:g}", tot_val)]
            + [Paragraph("", tot_val)]         # Unit Cost — no sum
            + [Paragraph(f"₱{total_subtotal:,.2f}", tot_val)]
        )
        totals_table = Table([tot_row], colWidths=widths)
        totals_table.setStyle(TableStyle([
            ("BACKGROUND",    (0, 0), (-1, 0), dark_c),
            ("TEXTCOLOR",     (0, 0), (-1, 0), white_c),
            ("SPAN",          (0, 0), (label_span - 1, 0)),
            ("ALIGN",         (0, 0), (label_span - 1, 0), "RIGHT"),
            ("TOPPADDING",    (0, 0), (-1, 0), 6),
            ("BOTTOMPADDING", (0, 0), (-1, 0), 6),
            ("LEFTPADDING",   (0, 0), (-1, 0), 5.5),
            ("RIGHTPADDING",  (0, 0), (-1, 0), 5.5),
            ("LINEABOVE",     (0, 0), (-1, 0), 2, dark_c),
        ]))

    # ── Assemble ──────────────────────────────────────────────
    # Header top padding matches website .ap-header-inner { padding: 14px 0 12px }
    story = [
        Spacer(1, 4),
        header_table,
        Spacer(1, 10),
        # Red divider: .ap-header-rule { height: 2px; background: #E8001C }
        HRFlowable(width="100%", thickness=2, color=red_c, spaceAfter=0),
        # .ap-content { padding: 14px 20px 0 } — replicated as spacer + side margins via doc margins
        Spacer(1, 10),
        data_table,
    ]
    if totals_table:
        story.append(totals_table)
    story += [
        # .ap-print-footer { margin-top: 18px; border-top: 1px solid #e2e8f0 }
        Spacer(1, 14),
        HRFlowable(width="100%", thickness=0.75, color=bdr_c, spaceAfter=8),
        Paragraph(FOOTER_TEXT, foot_style),
    ]

    doc.build(story)
    return buf.getvalue()


# ─────────────────────────────────────────────────────────────────────────────
#  Excel generation  (openpyxl)
# ─────────────────────────────────────────────────────────────────────────────

def generate_excel(report_type: str, month: str | None = None) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import (
        Font, PatternFill, Alignment, Border, Side, GradientFill,
    )
    from openpyxl.utils import get_column_letter

    cfg     = REPORT_CONFIG[report_type]
    fetcher = cfg["fetcher"]
    _month_supported = {"issuance", "maintenance", "bookings"}
    data    = fetcher(month=month) if report_type in _month_supported else fetcher()
    columns = cfg["columns"]
    mapper  = cfg["mapper"]
    col_ws  = cfg["col_widths_xlsx"]

    wb = Workbook()
    ws = wb.active
    ws.title = cfg["title"][:31]  # sheet name limit

    now      = datetime.now()
    date_str = now.strftime("%B %d, %Y").replace(" 0", " ")  # e.g. "March 10, 2026"

    # ── Colour helpers ────────────────────────────────────────
    def fill(hex_str):  return PatternFill("solid", fgColor=hex_str)
    def side():         return Side(style="thin", color="E2E8F0")
    thin_border = Border(left=side(), right=side(), top=side(), bottom=side())

    # ── Title block (rows 1-4) ────────────────────────────────
    ncols = len(columns)
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=ncols)
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=ncols)
    ws.merge_cells(start_row=3, start_column=1, end_row=3, end_column=ncols)
    ws.merge_cells(start_row=4, start_column=1, end_row=4, end_column=ncols)

    r1 = ws.cell(1, 1, BRAND_NAME)
    r1.font      = Font(name="Calibri", bold=True, size=14, color="1A202C")
    r1.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[1].height = 22

    r2 = ws.cell(2, 1, BRAND_SUB + ", " + BRAND_CITY + "  ·  " + BRAND_ADDRESS)
    r2.font      = Font(name="Calibri", size=9, color="718096")
    r2.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[2].height = 14

    r3 = ws.cell(3, 1, cfg["title"].upper() + (f"  —  {month.upper()}" if month else ""))
    r3.font      = Font(name="Calibri", bold=True, size=16, color="E8001C")
    r3.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[3].height = 26

    r4 = ws.cell(4, 1, f"Generated: {date_str}  ·  {len(data)} record(s)" + (f"  ·  {month}" if month else ""))
    r4.font      = Font(name="Calibri", size=9, color="718096")
    r4.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[4].height = 14

    # Red divider row
    ws.row_dimensions[5].height = 3
    for c in range(1, ncols + 1):
        ws.cell(5, c).fill = fill("E8001C")

    ws.row_dimensions[6].height = 6  # spacer

    # ── Header row (row 7) ────────────────────────────────────
    HDR_ROW = 7
    ws.row_dimensions[HDR_ROW].height = 20
    for ci, col_name in enumerate(columns, 1):
        cell = ws.cell(HDR_ROW, ci, col_name.upper())
        cell.font      = Font(name="Calibri", bold=True, size=9, color="FFFFFF")
        cell.fill      = fill("1A202C")
        cell.alignment = Alignment(horizontal="left", vertical="center",
                                   wrap_text=False)
        cell.border    = thin_border

    # ── Data rows ────────────────────────────────────────────
    STATUS_COLORS = {
        "low":         ("E8001C", "FFF5F5"),
        "overdue":     ("E8001C", "FFF5F5"),
        "cancelled":   ("E8001C", "FFF5F5"),
        "rejected":    ("E8001C", "FFF5F5"),
        "ok":          ("276749", "F0FFF4"),
        "active":      ("276749", "F0FFF4"),
        "completed":   ("003087", "EBF8FF"),
        "approved":    ("276749", "F0FFF4"),
        "pending":     ("975A16", "FFFBEB"),
        "in progress": ("975A16", "FFFBEB"),
        "ongoing":     ("975A16", "FFFBEB"),
    }

    status_col_idx = {
        "maintenance": 5,
        "vehicles":    4,
        "bookings":    6,
    }.get(report_type)

    for ri, row in enumerate(data):
        excel_row = HDR_ROW + 1 + ri
        ws.row_dimensions[excel_row].height = 15
        mapped = mapper(row)
        is_even = ri % 2 == 1
        row_bg = "F8FAFC" if is_even else "FFFFFF"

        for ci, val in enumerate(mapped, 1):
            cell = ws.cell(excel_row, ci, val if val else "—")
            cell.font      = Font(name="Calibri", size=9, color="2D3748")
            cell.fill      = fill(row_bg)
            cell.alignment = Alignment(vertical="center", wrap_text=False)
            cell.border    = thin_border

            # Status colour overrides
            if status_col_idx and ci == status_col_idx + 1:
                key = (val or "").lower()
                if key in STATUS_COLORS:
                    fc, bc = STATUS_COLORS[key]
                    cell.font = Font(name="Calibri", size=9, bold=True, color=fc)
                    cell.fill = fill(bc)

    # ── Issuance totals row (Excel) ───────────────────────────
    last_data_row = HDR_ROW + len(data)
    if report_type == "issuance" and data:
        def _to_float_xl(v):
            try:
                return float(str(v).replace("₱", "").replace(",", "").strip())
            except (ValueError, TypeError):
                return 0.0

        total_qty_xl      = sum(_to_float_xl(mapper(r)[6]) for r in data)
        total_subtotal_xl = sum(_to_float_xl(mapper(r)[8]) for r in data)

        tot_row_xl = HDR_ROW + len(data) + 1
        ws.row_dimensions[tot_row_xl].height = 18
        # Merge label cols (Date … UOM = cols 1-6)
        ws.merge_cells(start_row=tot_row_xl, start_column=1,
                       end_row=tot_row_xl, end_column=6)
        lbl = ws.cell(tot_row_xl, 1, "TOTAL")
        lbl.font      = Font(name="Calibri", bold=True, size=9, color="FFFFFF")
        lbl.fill      = fill("1A202C")
        lbl.alignment = Alignment(horizontal="right", vertical="center")
        lbl.border    = thin_border

        qty_c = ws.cell(tot_row_xl, 7, total_qty_xl)
        qty_c.font      = Font(name="Calibri", bold=True, size=9, color="FFFFFF")
        qty_c.fill      = fill("1A202C")
        qty_c.alignment = Alignment(horizontal="left", vertical="center")
        qty_c.border    = thin_border

        blank = ws.cell(tot_row_xl, 8, "")
        blank.fill   = fill("1A202C")
        blank.border = thin_border

        sub_c = ws.cell(tot_row_xl, 9, f"₱{total_subtotal_xl:,.2f}")
        sub_c.font      = Font(name="Calibri", bold=True, size=9, color="FFFFFF")
        sub_c.fill      = fill("1A202C")
        sub_c.alignment = Alignment(horizontal="left", vertical="center")
        sub_c.border    = thin_border

        last_data_row = tot_row_xl  # footer goes after totals

    # ── Column widths ─────────────────────────────────────────
    for ci, w in enumerate(col_ws, 1):
        ws.column_dimensions[get_column_letter(ci)].width = w

    # Freeze header row
    ws.freeze_panes = ws.cell(HDR_ROW + 1, 1)

    # ── Footer ────────────────────────────────────────────────
    foot_row = last_data_row + 2
    ws.merge_cells(start_row=foot_row, start_column=1, end_row=foot_row, end_column=ncols)
    fc = ws.cell(foot_row, 1, f"{FOOTER_TEXT} · Generated {date_str}")
    fc.font      = Font(name="Calibri", size=8, color="A0AEC0", italic=True)
    fc.alignment = Alignment(horizontal="center")

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


# ─────────────────────────────────────────────────────────────────────────────
#  Public API
# ─────────────────────────────────────────────────────────────────────────────

def build_report(report_type: str, file_format: str, month: str | None = None) -> bytes:
    """
    Generate a report file.

    Args:
        report_type: one of inventory | issuance | maintenance | vehicles | bookings
        file_format: pdf | excel | xlsx
        month:       optional month filter string, e.g. "March 2026" (issuance only)

    Returns:
        Raw bytes of the generated file.
    """
    if report_type not in REPORT_CONFIG:
        raise ValueError(f"Unknown report type '{report_type}'. "
                         f"Use: {', '.join(REPORT_CONFIG.keys())}")
    fmt = file_format.lower().replace("xlsx", "excel")
    if fmt == "pdf":
        return generate_pdf(report_type, month=month)
    elif fmt in ("excel", "xlsx"):
        return generate_excel(report_type, month=month)
    else:
        raise ValueError(f"Unknown format '{file_format}'. Use: pdf or excel")
