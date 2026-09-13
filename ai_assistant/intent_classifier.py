"""
Lightweight fast-path intent classifier.

Runs before the LLM for common, unambiguous queries — no API call needed.
Returns a dict with {intent, result} on a match, or None to fall through to LLM.

Fast-path categories (0 LLM tokens each):
  out_of_scope        — non-system topics → deterministic refusal reply
  prompt_injection    — override/ignore-instructions attacks → refusal
  arithmetic          — plain arithmetic (no DB needed) → Python eval
  reorder_point       — reorder point formula RP = ADU × LT + SS → Python calc
  low_stock           — DB lookup
  service_bookings    — DB lookup
  item_catalog_*      — DB lookup
  stock_levels        — DB lookup
  maintenance_*       — DB lookup
  deliveries          — DB lookup
  vehicles            — DB lookup
  user_count          — DB lookup
"""
import re
from input_normalizer import normalize as _normalize_input
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
    get_issuances,
)

# ── Compiled patterns for zero-token fast paths ───────────────────────────────

# Out-of-scope: topics with no connection to the automotive/inventory system.
# These are answered deterministically without calling the LLM.
_OUT_OF_SCOPE_ADMIN = re.compile(
    r"\b("
    # Geography / general knowledge
    r"capital\s+(of|city\s+of)\s+\w+"
    r"|what\s+is\s+the\s+capital"
    r"|president\s+(of|in)\s+\w+"
    r"|who\s+(won|is|was|are)\s+.*(president|prime\s+minister|king|queen|champion|winner)"
    r"|who\s+invented\s+"
    r"|what\s+year\s+was\s+.*(born|founded|invented|discovered)"
    # Sports / entertainment / pop culture
    r"|fifa|world\s+cup|olympics|nba|nfl|sports\s+team"
    r"|movie|film|actor|actress|singer|song|album|music|concert"
    r"|celebrity|tv\s+show|television|netflix|youtube"
    # Food / lifestyle
    r"|recipe|how\s+to\s+cook|ingredient|food\s+for|best\s+restaurant"
    # Science / general academia (not automotive)
    r"|speed\s+of\s+light|periodic\s+table|atomic\s+(number|weight|mass)"
    r"|planet\s+(earth|mars|jupiter|saturn|venus|mercury|uranus|neptune)"
    r"|solar\s+system|big\s+bang|evolution"
    # Weather / news / politics
    r"|weather|forecast|temperature|typhoon|earthquake|flood"
    r"|news|headline|current\s+event"
    r"|politics|election|vote|congress|senate|parliament"
    # Coding / tech general
    r"|python\s+code|javascript|html\s+tag|css\s+style|how\s+to\s+program"
    r"|machine\s+learning|artificial\s+intelligence\s+tutorial|blockchain"
    r"|cryptocurrency|bitcoin|nft"
    # Love / personal / jokes
    r"|love\s+(advice|life|tips)|relationship\s+advice"
    r"|tell\s+me\s+a\s+joke|make\s+me\s+laugh|funny\s+joke"
    r")\b",
    re.IGNORECASE,
)

# Prompt injection: instructions designed to override the AI's role/scope.
_PROMPT_INJECTION = re.compile(
    r"\b("
    r"ignore\s+(all\s+)?(previous|prior|above|your)\s+(instructions?|rules?|guidelines?|constraints?|context|prompt)"
    r"|disregard\s+(all\s+)?(previous|prior|above|your)\s+(instructions?|rules?|guidelines?)"
    r"|forget\s+(all\s+)?(previous|prior|your)\s+(instructions?|rules?|context)"
    r"|you\s+are\s+now\s+a\s+(different|new|other|another)\s+(ai|assistant|bot|system|model)"
    r"|act\s+as\s+(if\s+you\s+are\s+)?(a\s+)?(different|new|unrestricted|jailbreak)"
    r"|pretend\s+(you\s+are|to\s+be)\s+(a\s+)?(different|unrestricted|jailbreak)"
    r"|bypass\s+(your\s+)?(safety|restrictions?|rules?|filter|guard)"
    r"|override\s+(your\s+)?(instructions?|rules?|safety|restrictions?)"
    r"|system\s+prompt\s*(:|=|\s*override)"
    r"|new\s+instructions?\s*[:=]"
    r"|show\s+(me\s+)?(all\s+)?(confidential|private|secret|hidden)\s+(records?|data|information)"
    r")\b",
    re.IGNORECASE,
)

# Pure arithmetic — math with no system data needed.
# Matches: "what is 250 minus 75 plus 20?", "120 - 35", "calculate 5 × 7 + 10"
# Also matches reorder point formula phrasing.
_PURE_ARITHMETIC = re.compile(
    r"\b("
    r"what\s+is\s+\d[\d\s\+\-\*\/\×\÷\(\)\.]*\d"           # "what is 5 + 3"
    r"|\d[\d\s]*\s*(plus|minus|times|divided\s+by|multiplied\s+by)\s*\d"
    r"|calculate\s+\d"
    r"|\d+\s*[\+\-\*\/]\s*\d+\s*[\+\-\*\/]?\s*\d*"         # "120 - 35 + 5"
    r")\b",
    re.IGNORECASE,
)

# Reorder point formula: RP = ADU × LT + SS
# Test case: "Calculate the reorder point for an item with an average daily
#  usage of 5 units, a lead time of 7 days, and a safety stock of 10 units."
_REORDER_POINT_RE = re.compile(
    r"\b(reorder\s+point|rop)\b"
    r".*\b(daily\s+usage|average\s+daily|adu)\b"
    r".*\b(lead\s+time|lt)\b",
    re.IGNORECASE | re.DOTALL,
)

# Also matches the "if we have X units in stock and issue Y units, how many remain"
# pattern used in AU_TC18.
_REMAINING_STOCK_RE = re.compile(
    r"\b(if\s+we\s+have|we\s+have)\s+(\d+)\s+units?\s+in\s+stock\b"
    r".*\b(issue|sell|use|remove|take|give|out)\s+(\d+)\s+units?\b",
    re.IGNORECASE | re.DOTALL,
)

# Hallucination / future prediction guard
_FUTURE_PREDICTION = re.compile(
    r"("
    # "how many X will/would visit/book/come (tomorrow|next week|next month)"
    r"how\s+many\s+\w[\w\s]*\s+(will|would|are\s+going\s+to)\s+"
    r"(visit|come|book|arrive|show\s+up|be\s+serviced)\s*"
    r"(at\s+the\s+shop\s*)?(tomorrow|next\s+week|next\s+month|soon|in\s+the\s+future)?"
    # "predict/forecast demand/revenue/bookings tomorrow|next week"
    r"|predict\s+(how\s+many|demand|revenue|sales|bookings?|visits?)"
    r"|forecast\s+(demand|revenue|sales|bookings?|visits?)"
    r")",
    re.IGNORECASE,
)


def _safe_eval_arithmetic(text: str) -> float | None:
    """
    Safely evaluate a simple arithmetic expression extracted from natural language.
    Returns the numeric result, or None if the expression can't be parsed.
    Only allows digits, spaces, and the operators + - * / ( ).
    """
    # Normalise word operators
    expr = text.lower()
    expr = re.sub(r"\bplus\b",            "+", expr)
    expr = re.sub(r"\bminus\b",           "-", expr)
    expr = re.sub(r"\btimes\b",           "*", expr)
    expr = re.sub(r"\bmultiplied\s+by\b", "*", expr)
    expr = re.sub(r"\bdivided\s+by\b",    "/", expr)
    expr = re.sub(r"[×·]",               "*", expr)
    expr = re.sub(r"[÷]",                "/", expr)

    # Find the longest run of digits / operators / spaces.
    # Using max() avoids picking up a single leading space as the first match.
    matches = re.findall(r"[\d\s\+\-\*\/\(\)\.]+", expr)
    if not matches:
        return None
    candidate = max(matches, key=len).strip()
    # Strip leading/trailing operators that make it invalid
    candidate = re.sub(r"[^\d\+\-\*\/\(\)\. ]", "", candidate).strip()
    candidate = re.sub(r"^[\+\-\*\/\s]+", "", candidate).strip()
    if not candidate:
        return None
    # Must contain at least one operator to be an expression (not just a plain number)
    if not re.search(r"[\+\-\*\/]", candidate):
        return None
    try:
        result = eval(candidate, {"__builtins__": {}})  # nosec — whitelist-only chars
        return float(result)
    except Exception:
        return None


def _extract_number(pattern: str, text: str) -> float | None:
    """Extract the first number matching *pattern* from *text*."""
    m = re.search(pattern, text, re.IGNORECASE)
    if m:
        try:
            return float(m.group(1).replace(",", ""))
        except (ValueError, IndexError):
            return None
    return None


def classify_and_run(text: str) -> dict | None:
    t = _normalize_input(text) or text.lower().strip()
    orig = text  # keep original for regex that need original casing / numbers

    # ── Prompt injection guard (0 tokens, 0 DB reads) ────────────────────────
    # Must run first — before any intent-based routing — so crafted inputs
    # cannot exploit a later pattern match to access data or skip scope checks.
    if _PROMPT_INJECTION.search(orig) or _PROMPT_INJECTION.search(t):
        return {
            "intent": "prompt_injection_blocked",
            "result": {
                "reply": (
                    "I can only answer questions related to the Automotive "
                    "Service and Inventory Management System."
                ),
                "blocked": True,
            },
        }

    # ── Out-of-scope admin fast-path (0 tokens, 0 DB reads) ──────────────────
    # Common off-topic questions that would otherwise fall through to the LLM
    # and waste tokens. Deterministic refusal, matches ADMIN_SYSTEM_PROMPT rule.
    if _OUT_OF_SCOPE_ADMIN.search(orig) or _OUT_OF_SCOPE_ADMIN.search(t):
        return {
            "intent": "out_of_scope",
            "result": {
                "reply": (
                    "I can only answer questions related to the Automotive "
                    "Service and Inventory Management System."
                ),
                "blocked": True,
            },
        }

    # ── Future-prediction guard (0 tokens) ───────────────────────────────────
    # AI_TC06: "how many vehicles will visit the shop tomorrow?" must not invent
    # a number. Return a data-honest answer without hitting the LLM.
    if _FUTURE_PREDICTION.search(orig) or _FUTURE_PREDICTION.search(t):
        return {
            "intent": "future_prediction_refused",
            "result": {
                "reply": (
                    "I can only report on data that has already been recorded in the system. "
                    "Future visit or booking numbers cannot be predicted or guaranteed — "
                    "please check the Bookings section for scheduled appointments."
                ),
                "blocked": True,
            },
        }

    # ── Reorder point formula (0 tokens, 0 DB reads) ─────────────────────────
    # AU_TC06: "Calculate the reorder point for an item with an average daily
    # usage of 5 units, a lead time of 7 days, and a safety stock of 10 units."
    # Formula: RP = ADU × LT + SS
    if _REORDER_POINT_RE.search(orig) or _REORDER_POINT_RE.search(t):
        adu = _extract_number(
            r"\b(?:average\s+daily\s+usage|daily\s+usage|adu)\s+of\s+([\d,]+(?:\.\d+)?)",
            orig,
        )
        lt = _extract_number(
            r"\b(?:lead\s+time|lt)\s+of\s+([\d,]+(?:\.\d+)?)",
            orig,
        )
        ss = _extract_number(
            r"\b(?:safety\s+stock|ss)\s+of\s+([\d,]+(?:\.\d+)?)",
            orig,
        )
        if adu is not None and lt is not None and ss is not None:
            rp = adu * lt + ss
            return {
                "intent": "reorder_point_calculation",
                "result": {
                    "formula": "Reorder Point = (Average Daily Usage × Lead Time) + Safety Stock",
                    "average_daily_usage": adu,
                    "lead_time_days": lt,
                    "safety_stock": ss,
                    "reorder_point": rp,
                    "calculation": f"({adu:.0f} × {lt:.0f}) + {ss:.0f} = {rp:.0f} units",
                    "calculated_by": "python",
                    "calculation_verified": True,
                },
            }

    # ── Remaining-stock arithmetic (0 tokens, 0 DB reads) ────────────────────
    # AU_TC18: "If we have 120 units in stock and issue 35 units, how many remain?"
    m_stock = _REMAINING_STOCK_RE.search(orig)
    if m_stock:
        try:
            initial   = float(m_stock.group(2).replace(",", ""))
            issued    = float(m_stock.group(4).replace(",", ""))
            remaining = initial - issued
            return {
                "intent": "remaining_stock_calculation",
                "result": {
                    "initial_stock": initial,
                    "issued": issued,
                    "remaining": remaining,
                    "calculation": f"{initial:.0f} - {issued:.0f} = {remaining:.0f} units",
                    "calculated_by": "python",
                    "calculation_verified": True,
                },
            }
        except (ValueError, AttributeError):
            pass  # fall through if parsing fails

    # ── Pure arithmetic (0 tokens, 0 DB reads) ───────────────────────────────
    # AI_TC05: "What is 250 minus 75 plus 20?" → 195
    if _PURE_ARITHMETIC.search(orig):
        result_val = _safe_eval_arithmetic(orig)
        if result_val is not None:
            # Guard: don't intercept DB queries that happen to contain numbers.
            _DB_KEYWORDS = re.compile(
                r"\b(stock|inventory|booking|vehicle|maintenance|repair|"
                r"service|delivery|customer|user|issuance)\b",
                re.IGNORECASE,
            )
            if not _DB_KEYWORDS.search(orig):
                result_int = int(result_val) if result_val == int(result_val) else result_val
                return {
                    "intent": "arithmetic_calculation",
                    "result": {
                        "answer": result_int,
                        "calculation": f"= {result_int}",
                        "calculated_by": "python",
                        "calculation_verified": True,
                    },
                }


    if re.search(
        r"low.?stock|reorder|running.?low|below.?reorder|out.?of.?stock"
        r"|almost.?out|nearly.?out|need[s]?\s+restock|need[s]?\s+replenish"
        r"|stock\s+(is|are)\s+low|items?\s+(is|are)\s+low"
        r"|low\s+in\s+stock|which\s+items?\s+(are|is)\s+low"
        r"|what\s+items?\s+(are|is)\s+(currently\s+)?low"
        r"|items?\s+(below|under)\s+(reorder|minimum|threshold)",
        t,
    ):
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
    # Guard: do NOT match queries about customers' personal information or history
    _PERSONAL_DATA_RE = re.compile(
        r"\b(personal\s+information|personal\s+data|service\s+history\s+of\s+(all|every)|"
        r"all\s+customers?|every\s+customer|another\s+customer|other\s+customer)\b",
        re.IGNORECASE,
    )
    if not _PERSONAL_DATA_RE.search(orig) and re.search(
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
        r"|(show|list|display|view|get)\s+(the\s+|all\s+|current\s+)?stock\b"
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
        r"|(list|show|all|get|display|view)[\w\s]*(maintenance|repair|pms)(\s+(jobs?|records?|history|list))?\b"
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

    # ── Dashboard / system summary ────────────────────────────────────────────
    # AU_TC02: "Give me a summary of the current system data."
    if re.search(
        r"(summary|overview|dashboard|system\s+data|current\s+status|"
        r"system\s+summary|give\s+me\s+(a\s+)?(summary|overview)|"
        r"what('?s|\s+is)\s+the\s+(current\s+)?(status|overview|summary))",
        t,
    ):
        # Return a combined summary: maintenance + bookings + vehicles
        summary = get_maintenance_summary()
        bookings = get_service_bookings()
        vehicles = get_vehicles()
        return {
            "intent": "system_summary",
            "result": {
                "maintenance": summary,
                "bookings": bookings,
                "vehicles": vehicles,
            },
        }

    # ── Vehicle PMS schedule / due this month ─────────────────────────────────
    # AU_TC12: "Which vehicles have preventive maintenance scheduled for this month?"
    if re.search(
        r"(vehicles?\s+(have|with|scheduled|due)\b.*(maintenance|pms|service)|"
        r"(maintenance|pms|service)\s+(scheduled|due|this\s+month)\b.*vehicles?|"
        r"which\s+vehicles?\s+(have|with|are|need).*(maintenance|pms)|"
        r"(maintenance|pms)\s+scheduled\s+for\s+(this|next)\s+month)",
        t,
    ):
        return {"intent": "maintenance_jobs", "result": get_maintenance_jobs()}

    # ── Issuances by group / date filter ─────────────────────────────────────
    # AU_TC17: "Show the lubricants issued in June 2026."
    if re.search(
        r"(issued|issuance|issuances)\b"
        r"|(show|list|display).*(issued|issuance)"
        r"|(lubricant|oil|brake|coolant|filter|material|part)s?\s+(issued|issuance)",
        t,
    ):
        return {"intent": "issuances", "result": get_issuances()}

    return None  # fall through to full LLM tool-calling loop
