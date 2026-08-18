import traceback
import uuid
import re
import time
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from schemas import ChatRequest, ChatResponse, CustomerChatRequest, SessionInfoResponse
from client import chat as llm_chat, AllKeysRateLimitedError as _AllKeysRateLimitedError, InvalidApiKeyError as _InvalidApiKeyError
from intent_classifier import classify_and_run
from model_router import (
    classify_intent, select_model, needs_llm,
    DATABASE_LOOKUP, DATABASE_CALCULATION, GENERAL_AI_QUESTION,
    COMPLEX_ANALYSIS, REPORT_GENERATION, UNKNOWN,
)
from session_store import (
    get_history, append_turn, clear_session, session_info, active_session_count
)
from config import settings as _settings  # for token-limit constants in _merge_history
import token_tracker

app = FastAPI(
    title="Caltex AutoPro AI",
    description="AI assistant with server-side conversational memory",
)

# ── CORS ──────────────────────────────────────────────────────────────────────
# Required so the Flutter web app (running in a browser) can call this API
# directly. Also covers the Flutter mobile web build and any other web clients.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],       # allow all origins (API uses session keys, not cookies)
    allow_methods=["*"],       # GET, POST, DELETE, OPTIONS, etc.
    allow_headers=["*"],       # Content-Type, Authorization, etc.
    allow_credentials=False,   # must be False when allow_origins is "*"
)


# ── Rate-limit helper ─────────────────────────────────────────────────────────

def _parse_rate_limit_reset(error_message: str) -> str:
    """
    Extract the reset time from a Groq RateLimitError message.
    e.g. 'Please try again in 15m46.944s' → 'about 15 minutes'
         'Please try again in 1h30m.'     → 'about 1 hour and 30 minutes'
    """
    hours   = re.search(r'in\s+(\d+)h', error_message)
    minutes = re.search(r'in\s+(?:\d+h\s*)?(\d+)m', error_message)

    parts = []
    if hours:
        h = int(hours.group(1))
        parts.append(f"{h} hour{'s' if h != 1 else ''}")
    if minutes:
        m = int(minutes.group(1))
        parts.append(f"{m} minute{'s' if m != 1 else ''}")

    if parts:
        return "about " + " and ".join(parts)
    return "some time"


def _rate_limit_reply(error_message: str) -> dict:
    """Build a structured rate-limit response the frontends can detect."""
    reset_in = _parse_rate_limit_reset(error_message)
    return {
        "rate_limited": True,
        "reply": (
            f"⚠️ The AI service has reached its daily usage limit (Groq free tier).\n\n"
            f"It will automatically reset in {reset_in}.\n\n"
            f"Please try again later."
        ),
        "reset_in": reset_in,
    }


def _is_rate_limit(exc: Exception) -> bool:
    from client import AllKeysRateLimitedError
    if isinstance(exc, AllKeysRateLimitedError):
        return True
    cls_name = type(exc).__name__.lower()
    exc_str  = str(exc).lower()
    return (
        "ratelimit" in cls_name
        or "rate_limit" in cls_name
        or "allkeysratelimited" in cls_name
        or "429" in exc_str
        or "all api keys" in exc_str
        # Groq TPM (tokens-per-minute) errors come back as HTTP 413 with
        # type: "tokens" and code: "rate_limit_exceeded".  Rotation fires but
        # can't help (org-level limit), so we surface the friendly message
        # instead of letting it become a 500.
        or "413" in exc_str
        or ("token" in exc_str and "limit" in exc_str)
        or "request too large" in exc_str
        or "too large for model" in exc_str
        # Firestore free-tier quota (ResourceExhausted / 429 from gRPC)
        or "quota exceeded" in exc_str
        or "resource_exhausted" in exc_str
        or "resourceexhausted" in exc_str
    )


def _is_invalid_key(exc: Exception) -> bool:
    """Return True if the exception is a Groq authentication / invalid-key error."""
    from client import InvalidApiKeyError
    if isinstance(exc, InvalidApiKeyError):
        return True
    cls_name = type(exc).__name__.lower()
    exc_str  = str(exc).lower()
    return (
        "authentication" in cls_name
        or "invalidapikey" in cls_name
        or "401" in exc_str
        or "invalid api key" in exc_str
        or "invalid_api_key" in exc_str
        or "revoked" in exc_str
        or "unauthorized" in exc_str
    )


def _invalid_key_reply() -> dict:
    """Build a structured response for an invalid/revoked API key."""
    return {
        "rate_limited": False,
        "reply": (
            "⚠️ The AI service is currently unavailable due to a configuration issue.\n\n"
            "Please contact the system administrator to update the API key."
        ),
    }


# ── Health ────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {
        "status":          "ok",
        "role":            "admin",
        "active_sessions": active_session_count(),
    }


# ── Session management ────────────────────────────────────────────────────────

@app.get("/session/{session_id}", response_model=SessionInfoResponse)
def get_session_info(session_id: str):
    """Return metadata about a session (number of stored turns, last active)."""
    return session_info(session_id)


@app.delete("/session/{session_id}")
def delete_session(session_id: str):
    """Clear all stored history for a session."""
    clear_session(session_id)
    return {"success": True, "session_id": session_id, "message": "Session cleared"}


# ── Admin chat ────────────────────────────────────────────────────────────────

@app.post("/admin/chat", response_model=ChatResponse)
def admin_chat(req: ChatRequest):
    """
    Admin AI chat with server-side conversational memory and model routing.

    Flow:
      1. Resolve or create a session_id.
      2. Classify intent using deterministic rules (zero tokens).
      3. Select model: 8B for most requests, 70B only for COMPLEX_ANALYSIS.
      4. Try the admin fast-path classifier for obvious DB queries.
         — If matched and intent is DATABASE_LOOKUP/CALCULATION: return the
           data directly with a template reply (0 LLM tokens).
         — If matched but still needs phrasing: call 8B with data already fetched.
      5. Otherwise: full LLM tool-calling loop with selected model.
      6. Append exchange to session store.
      7. Return reply + session_id.
    """
    session_id = req.session_id or str(uuid.uuid4())

    try:
        server_history    = get_history(session_id)
        effective_history = _merge_history(server_history, req.history)

        # ── Step 2: intent classification (deterministic, 0 tokens) ──────────
        intent      = classify_intent(req.message)
        chosen_model = select_model(intent)

        # ── Step 3: admin fast-path (pre-fetches DB data before any LLM call) ─
        fast_path = classify_and_run(req.message)

        if fast_path:
            # Data already retrieved from Firestore.
            # For pure DB lookups, skip the LLM entirely and reply with a
            # compact template.  This saves ~400–800 tokens per request.
            if intent in (DATABASE_LOOKUP, DATABASE_CALCULATION):
                reply = _format_admin_db_reply(req.message, fast_path["result"])
                append_turn(session_id, req.message, reply)
                # Record zero LLM tokens (DB-only path)
                token_tracker.record(
                    user_id=session_id[:20],
                    role="admin",
                    model="none",
                    intent=intent,
                    input_tokens=0,
                    output_tokens=0,
                )
                return ChatResponse(
                    reply=reply,
                    session_id=session_id,
                    tool_calls=[fast_path],
                )

            # Needs phrasing — build a minimal prompt with only the retrieved data.
            # Use 8B model: if the data is already fetched, phrasing is trivial.
            phrasing_prompt = (
                f"The user asked: \"{req.message}\"\n\n"
                f"Here is the exact data retrieved from the database:\n"
                f"{fast_path['result']}\n\n"
                f"Answer the user's question using ONLY this data. "
                f"Be concise. Do not recalculate anything."
            )
            t0 = time.time()
            result = llm_chat(
                phrasing_prompt,
                history=effective_history,
                model=_settings.GROQ_MODEL_PRIMARY,  # always 8B for phrasing
                intent=intent,
                user_id=session_id[:20],
            )
            reply = result["reply"]
            tool_calls_out = [fast_path]
        else:
            # Full LLM tool-calling loop with selected model
            result = llm_chat(
                req.message,
                history=effective_history,
                model=chosen_model,
                intent=intent,
                user_id=session_id[:20],
            )
            reply = result["reply"]
            tool_calls_out = result["tool_calls"]

        append_turn(session_id, req.message, reply)

        return ChatResponse(
            reply=reply,
            session_id=session_id,
            tool_calls=tool_calls_out,
        )

    except Exception as e:
        if _is_rate_limit(e):
            rl = _rate_limit_reply(str(e))
            token_tracker.record(
                user_id=session_id[:20], role="admin",
                model=_settings.GROQ_MODEL_PRIMARY, intent="UNKNOWN",
                input_tokens=0, output_tokens=0,
                success=False, rate_limited=True,
            )
            return ChatResponse(
                reply=rl["reply"],
                session_id=session_id,
                rate_limited=True,
                reset_in=rl["reset_in"],
            )
        if _is_invalid_key(e):
            ik = _invalid_key_reply()
            return ChatResponse(
                reply=ik["reply"],
                session_id=session_id,
            )
        traceback.print_exc()
        return ChatResponse(
            reply="I'm having trouble processing your request right now. Please try again in a moment.",
            session_id=session_id,
        )


def _format_admin_db_reply(message: str, result: dict) -> str:
    """
    Build a direct template response for admin DATABASE_LOOKUP requests.
    No LLM involved — zero tokens consumed.
    """
    msg_l = message.lower()

    # Low stock
    if "low" in msg_l and "stock" in msg_l or "reorder" in msg_l:
        count = result.get("low_stock_count", len(result.get("items", [])))
        if count == 0:
            return "All items are currently at acceptable stock levels. No items are below the reorder point."
        items = result.get("items", [])[:10]
        lines = [f"**{it['name']}** — Stock: {it['stock']} {it['uom']} (Reorder: {it['reorder']})"
                 for it in items]
        tail = f"\n\n*...and {count - 10} more items.*" if count > 10 else ""
        return f"There are **{count}** item(s) at or below the reorder point:\n\n" + "\n".join(lines) + tail

    # User / customer count
    if any(k in msg_l for k in ("how many", "count", "users", "customers", "staff")):
        total = result.get("total_users", 0)
        by_role = result.get("by_role", {})
        breakdown = ", ".join(f"{v} {k}(s)" for k, v in by_role.items()) if by_role else ""
        return f"There are **{total}** registered user(s) in the system." + (
            f"\n\n**By role:** {breakdown}" if breakdown else ""
        )

    # Vehicles
    if "vehicle" in msg_l or "fleet" in msg_l:
        total = result.get("total_vehicles", 0)
        by_status = result.get("by_status", {})
        breakdown = ", ".join(f"{v} {k}" for k, v in by_status.items()) if by_status else ""
        return f"There are **{total}** registered vehicle(s)." + (
            f"\n\n**By status:** {breakdown}" if breakdown else ""
        )

    # Maintenance summary
    if "maintenance" in msg_l or "repair" in msg_l or "summary" in msg_l:
        total = result.get("total_jobs", 0)
        by_status = result.get("by_status", {})
        total_cost = result.get("total_cost", 0)
        breakdown = ", ".join(f"{v} {k}" for k, v in by_status.items()) if by_status else ""
        return (
            f"**Maintenance Summary:** {total} total job(s)"
            + (f" — {breakdown}" if breakdown else "")
            + (f"\n\n**Total Cost:** ₱{total_cost:,.2f}" if total_cost else "")
        )

    # Bookings
    if "booking" in msg_l or "appointment" in msg_l:
        total = result.get("total_bookings", 0)
        by_status = result.get("by_status", {})
        breakdown = ", ".join(f"{v} {k}" for k, v in by_status.items()) if by_status else ""
        return f"There are **{total}** booking(s) in the system." + (
            f"\n\n**By status:** {breakdown}" if breakdown else ""
        )

    # Generic fallback: return a short summary
    import json
    return f"Here is the data retrieved:\n\n```\n{json.dumps(result, indent=2)[:1500]}\n```"


# ── Admin report ──────────────────────────────────────────────────────────────

@app.post("/admin/report")
async def admin_report(request: Request,
                       report_type: str, format: str = "pdf",
                       month: str | None = None,
                       start_date: str | None = None,
                       end_date: str | None = None):
    """
    Generate a PDF or Excel report directly from Firestore data.

    Query params:
        report_type: inventory | issuance | maintenance | vehicles | bookings
        format:      pdf | excel  (default: pdf)
        month:       optional month filter, e.g. "March 2026"
                     (issuance, maintenance, bookings only)
        start_date:  optional range start, e.g. "2026-03-01" or "March 1, 2026"
                     Takes priority over month when set.
        end_date:    optional range end, e.g. "2026-03-31" or "March 31, 2026"

    JSON body (optional):
        A flat dict of additional filters, e.g.
            {"group": "Lubricants", "status": "Low"}
        Valid keys per report type are defined in REPORT_FILTERS.
        Unknown keys are silently ignored.
    """
    try:
        import io
        from report_generator import build_report, REPORT_CONFIG

        # Read optional JSON body as filters dict
        filters: dict | None = None
        try:
            body = await request.json()
            if isinstance(body, dict) and body:
                filters = body
        except Exception:
            pass  # no body or not JSON — treat as no filters


        if report_type not in REPORT_CONFIG:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown report_type '{report_type}'. "
                       f"Use: {', '.join(REPORT_CONFIG.keys())}"
            )
        fmt = format.lower().replace("xlsx", "excel")
        if fmt not in ("pdf", "excel"):
            raise HTTPException(status_code=400, detail="format must be 'pdf' or 'excel'")

        data  = build_report(report_type, fmt,
                             month=month or None,
                             start_date=start_date or None,
                             end_date=end_date or None,
                             filters=filters or None)
        title = REPORT_CONFIG[report_type]["title"].replace(" ", "_")

        # Build filename suffix
        if start_date or end_date:
            _sd = (start_date or "").replace(" ", "_")
            _ed = (end_date or "").replace(" ", "_")
            suffix = f"_{_sd}_to_{_ed}" if _sd and _ed else f"_{_sd or _ed}"
            title = f"{title}{suffix}"
        elif month:
            safe_month = month.replace(" ", "_")
            title = f"{title}_{safe_month}"

        if fmt == "pdf":
            media_type = "application/pdf"
            filename   = f"{title}.pdf"
        else:
            media_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            filename   = f"{title}.xlsx"

        return StreamingResponse(
            io.BytesIO(data),
            media_type=media_type,
            headers={"Content-Disposition": f'attachment; filename="{filename}"'},
        )

    except HTTPException:
        raise
    except ValueError as e:
        # build_report raises ValueError for bad filters / no records / future dates
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        traceback.print_exc()
        err_str = str(e).lower()
        # Firestore / gRPC quota exceeded (ResourceExhausted / 429)
        if "quota exceeded" in err_str or "resource_exhausted" in err_str or "429" in err_str:
            raise HTTPException(
                status_code=503,
                detail=(
                    "The database is temporarily unavailable due to a quota limit "
                    "(Firestore free-tier). Please wait a moment and try again."
                ),
            )
        raise HTTPException(status_code=500, detail=str(e))


# ── Customer chat ─────────────────────────────────────────────────────────────

# ── Customer system prompt — SLIM base (~600 tokens) ─────────────────────────
# The full USER MANUAL is stored separately in CUSTOMER_MANUAL_CONTEXT and
# injected into the system prompt ONLY when the query is about app/website usage.
# For data queries (vehicles, history, bookings, pricing) it is NOT sent,
# saving ~900–1,000 input tokens per call.

CUSTOMER_MANUAL_CONTEXT = """
CALTEX AUTOPRO — USER MANUAL (CUSTOMER SECTIONS)

Caltex AutoPro is an automotive service management system for JA Noble Enterprise INC,
Caltex San Pedro, Laguna. It has a web app and a mobile app (Android/iOS).

GETTING STARTED: Visit the site in Chrome/Firefox/Edge/Safari. Log in with email+password
or Google. Register via Sign Up (Full Name, Email, Password). Use "Forgot Password?" to
reset via email.

WEBSITE CUSTOMER PORTAL: Dashboard shows your vehicles and PMS status (Active, Maintenance,
PMS Overdue, Due This Week, Due Soon). Click any vehicle card for service history.
PMS History: full maintenance records, search/filter, total cost tracking.
Book Service: schedule an appointment.

MOBILE APP: Dashboard with vehicle PMS status indicators (Active, PMS Due Soon, Overdue).
PMS History Tab (history icon, bottom right): tap a vehicle to see completed services,
mechanic, materials, cost. Smart AI: robot button at the bottom. Bookings tab: all
pending/confirmed/completed appointments. Book Service via bottom navigation.

PROFILE: Tap avatar (top right) → view name, email, role. Edit Profile to update name
or photo. Change Password: enter current + new. Notifications: Profile → Notifications to
toggle PMS Overdue, Due This Week, Due Soon, Service Updates alerts.

NOTIFICATIONS: Bell icon shows unread count. Tap to view/mark read. Push notifications
via OneSignal (mobile) — enable in phone settings and app preferences.

FAQ:
- Can't log in? Check email/password or use Forgot Password.
- No push notifications? Enable in phone settings + app preferences.
- Vehicle shows "Overdue" after service? Ensure service marked Completed, frequency set, last date updated.
- How to check service history? Website: PMS History tab. Mobile: PMS History (bottom right).
- How to book? Mobile: Book Service in bottom nav. Pick vehicle, services, date, confirm.
- How to view bookings? Tap Bookings tab / My Bookings.
- Profile photo? Tap avatar → Profile → tap avatar photo → gallery.
- What is "Due Soon"? Next scheduled maintenance is approaching — plan a service appointment.
- Service Frequency? Number of months between recommended maintenance services.

Contact & Support: caltexautopro2026@gmail.com
"""

_MANUAL_KEYWORDS = re.compile(
    r"\b(how\s+(do|can|to|would)\s+i|where\s+(is|can|do)|how\s+to\s+use|"
    r"how\s+do\s+i\s+(book|log\s*in|sign\s*up|register|change\s+password|"
    r"view\s+(my\s+)?(booking|notif|profile|history|vehicle))|"
    r"log\s*in|sign\s*in|sign\s*up|register|forgot\s+password|"
    r"push\s+notification|notification\s+setting|"
    r"where\s+(is|are|can\s+i\s+find)\s+the|"
    r"profile\s+photo|change\s+my\s+photo|edit\s+profile|"
    r"mobile\s+app|website|app\s+(feature|function|button|screen|tab)|"
    r"what\s+does\s+(the\s+app|due\s+soon|overdue|pms\s+status|service\s+freq)|"
    r"what\s+is\s+(the\s+app|due\s+soon|service\s+freq|pms))",
    re.IGNORECASE,
)


def _build_customer_system_prompt(message: str) -> str:
    """
    Build the system prompt for a customer request.

    For DATA queries (vehicles, history, bookings, pricing) — return the slim
    base prompt only (~600 tokens).

    For HOW-TO / APP-USAGE queries — append the USER MANUAL section (~300 tokens,
    trimmed from the original ~1,000-token version). This avoids sending ~700–900
    extra tokens on every single data request.
    """
    base = """You are the friendly vehicle assistant for a Caltex AutoPro customer at JA Noble Enterprise Inc., Caltex San Pedro, Laguna.

Your personality: warm, helpful, and conversational. Keep answers concise but complete. Use a natural, human tone.

STRICT SCOPE RESTRICTION — HIGHEST PRIORITY:
You ONLY answer questions about:
- The customer's own registered vehicles and PMS status
- Their completed service history and costs
- Their service bookings and appointments
- Service offerings and pricing from this shop
- How to use the Caltex AutoPro mobile app or website

If asked ANYTHING outside this scope — sports, news, general knowledge, coding, math, weather, geography, or any non-system topic — respond ONLY:
"I can only answer questions related to the Automotive Service and Inventory Management System."

PRIVACY & DATA ACCESS — ABSOLUTE RULES:
1. NEVER show another customer's data. If asked about another person, respond ONLY:
   "I can only show information for your own account."
2. NEVER show inventory, stock levels, supplier data, issuances, deliveries, or admin data.
   If asked, respond ONLY: "I can only answer questions related to the Automotive Service and Inventory Management System."
3. NEVER generate PDF or Excel reports. If asked, respond ONLY:
   "I can only answer questions related to the Automotive Service and Inventory Management System."
4. "all MY vehicles" / "list my vehicles" = customer-scoped → always call get_my_vehicles.
   Only refuse if the query clearly asks for system-wide data across all customers.
5. Symbols/garbage-only messages → "I didn't quite catch that. Could you rephrase your question about your vehicles, bookings, or services?"

RULES:
1. Only access data belonging to this customer. Call tools for data — never invent records.
2. If a tool returns no data, say so warmly.
3. Never show admin-only data (stock, deliveries, issuances).
4. For cost estimates, always call estimate_service_cost — do not guess prices.
5. Use conversation history for follow-up questions.
6. If history is empty and user asks "what was my previous question?" → respond ONLY:
   "There's no previous conversation in this session. Feel free to ask me anything about your vehicles, bookings, or services!"
7. If a user references another person's data (Juan Dela Cruz, another customer, bookings of [name]), respond ONLY:
   "I can only show information for your own account."
8. Inventory/warehouse/report queries → respond ONLY:
   "I can only answer questions related to the Automotive Service and Inventory Management System."
9. Reformatting follow-ups ("make it a list", "simplify") → reformat previous answer, NO tool calls.
10. If a tool returns {"error": "QUOTA_EXCEEDED"} or any error containing "quota" or "QUOTA_EXCEEDED",
    respond ONLY: "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes."
    Do NOT guess or invent any data values.

SERVICE HISTORY (when get_my_service_history returns data):
- Open: "Here's your service history! You have [N] completed record[s] with a total spend of [total]."
- Number each job: **[N]. [Date] — [Plate]** → Services / Materials (omit if empty) / Cost
- More than 10 jobs → show 10 most recent, note "Showing your 10 most recent records."
- No jobs → "It looks like you don't have any completed service records on file yet. Once your first service is completed at our shop, it will appear here!"

VEHICLES (when get_my_vehicles returns data):
- "Here are your registered vehicles:" then for each: **[Plate] — [Desc]** → Status / Last Service / Frequency
- Close with a brief note about any overdue or due-soon vehicles.

TOOL MAPPING:
- "my vehicles", "my fleet", "my cars", "fleet summary" → get_my_vehicles
- "service history", "past services", "spent", "pms history", "maintenance records" → get_my_service_history
- "PMS", "next service", "overdue", "due soon", "pms status" → get_my_pms_status
- "my bookings", "my appointments", "upcoming service" → get_my_bookings
- "how much is", "price of", "cost of", "service prices", "services offered" → get_service_prices
- "estimate", "how much would X and Y cost" → estimate_service_cost

WHEN TOOL RETURNS EMPTY DATA:
- get_service_prices returns total_services=0 → say: "I wasn't able to find pricing information in our system at the moment. Please contact us at caltexautopro2026@gmail.com or visit the shop for current service rates."
- get_my_vehicles returns total_vehicles=0 → say: "You don't have any registered vehicles on file yet."
- get_my_service_history returns total_jobs=0 → say the standard "no completed service records" message.
- Any tool returns {"error": "QUOTA_EXCEEDED"} → say: "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes."
"""
    if _MANUAL_KEYWORDS.search(message):
        return base + "\n\n" + CUSTOMER_MANUAL_CONTEXT
    return base


# Keep the old name so existing code that references CUSTOMER_SYSTEM_PROMPT
# still works (used in _run_customer_chat to build per-request prompt).
# _run_customer_chat already calls _build_customer_system_prompt() directly.
CUSTOMER_SYSTEM_PROMPT = _build_customer_system_prompt("")  # fallback reference only


def _run_customer_chat(message: str, customer_uid: str, customer_name: str,
                       history: list[dict], intent: str = UNKNOWN) -> dict:
    """
    Core customer LLM loop.

    Before calling the LLM:
      1. Check if the intent is DATABASE_LOOKUP / DATABASE_CALCULATION.
         If so, call the appropriate customer tool directly and return a
         template response — 0 LLM tokens.
      2. Otherwise select model (8B default, 70B only for COMPLEX_ANALYSIS)
         and run the normal tool-calling loop.

    Customer identity (customer_uid, customer_name) is always injected
    server-side.  The LLM cannot override these values.
    """
    import json
    from groq import Groq, BadRequestError, RateLimitError, AuthenticationError
    from config import settings
    from customer_tools import CUSTOMER_TOOL_SCHEMAS, CUSTOMER_TOOL_FUNCTIONS
    import time as _time

    # ── Step 1: direct DB path for simple lookups (0 LLM tokens) ─────────────
    direct = _customer_direct_lookup(message, customer_uid, customer_name, intent)
    if direct is not None:
        token_tracker.record(
            user_id=customer_uid,
            role="customer",
            model="none",
            intent=intent,
            input_tokens=0,
            output_tokens=0,
        )
        return direct

    # ── Step 1b: out-of-scope pre-check (0 LLM tokens) ───────────────────────
    # Block admin/inventory/report queries and other off-topic messages before
    # reaching the LLM — this prevents 500 errors from bad Groq calls.
    _OUT_OF_SCOPE_RE = re.compile(
        r"\b(inventory|stock\s+level|stock\s+status|reorder|issuance|"
        r"supplier|delivery|deliveries|warehouse|purchase\s+order|"
        r"generate\s+(a\s+)?(report|pdf|excel|summary)|"
        r"inventory\s+report|maintenance\s+report|service\s+report|"
        r"all\s+(customers?|users?|accounts?)|"
        r"other\s+customer|another\s+customer|"
        r"(weather|news|sports|politics|geography|math|coding|programming|"
        r"calculate|formula|recipe|joke|game|movie|music))\b",
        re.IGNORECASE,
    )
    if _OUT_OF_SCOPE_RE.search(message):
        return {
            "reply": "I can only answer questions related to your vehicles, service history, bookings, and service pricing for the Caltex AutoPro system.",
            "tool_calls": [],
            "model": "none",
            "intent": intent,
        }

    # ── Step 2: select model ──────────────────────────────────────────────────
    chosen_model = (settings.GROQ_MODEL_SECONDARY
                    if intent == COMPLEX_ANALYSIS
                    else settings.GROQ_MODEL_PRIMARY)

    def _call(msgs, tools=None):
        """Call Groq with the selected model."""
        from client import RateLimitedError as _RLE, InvalidApiKeyError as _IKE
        api_key = settings.GROQ_API_KEY
        if not api_key:
            raise _IKE(
                "No Groq API key configured. "
                "Set GROQ_API_KEY in the Render environment variables."
            )
        try:
            client = Groq(api_key=api_key)
            kwargs: dict = {
                "model":      chosen_model,
                "messages":   msgs,
                "max_tokens": settings.GROQ_MAX_OUTPUT_TOKENS,
            }
            if tools:
                kwargs["tools"] = tools
            return client.chat.completions.create(**kwargs)
        except AuthenticationError as exc:
            raise _IKE(
                "The Groq API key is invalid or has been revoked. "
                "Please update GROQ_API_KEY in the Render environment variables."
            ) from exc
        except RateLimitError as exc:
            raise _RLE(
                "The AI service has reached its daily usage limit (Groq free tier). "
                "Please try again later."
            ) from exc

    def _strip_null(raw: str) -> dict:
        if not raw or not raw.strip():
            return {}
        try:
            args = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        if not isinstance(args, dict):
            return {}
        return {k: v for k, v in args.items() if v is not None and v != ""}

    messages = [{"role": "system", "content": _build_customer_system_prompt(message)}]
    trimmed = history[-settings.GROQ_MAX_HISTORY_MSGS:] if len(history) > settings.GROQ_MAX_HISTORY_MSGS else history
    messages.extend(trimmed)
    messages.append({"role": "user", "content": message})

    tool_log    = []
    final_reply = ""
    t0 = _time.time()

    # Detect pricing queries to nudge the model if it stalls
    import re as _re
    _is_pricing_query = bool(_re.search(
        r"how\s+much\s+is|price\s+of|cost\s+of|how\s+much.*service|"
        r"service\s+price|pricing|how\s+much\s+does|how\s+much\s+would|"
        r"estimate.*cost|cost.*estimate",
        message, _re.IGNORECASE
    ))

    last_response = None
    for _turn in range(5):
        try:
            response = _call(messages, tools=CUSTOMER_TOOL_SCHEMAS)
            last_response = response
        except BadRequestError as e:
            import logging as _log
            _log.getLogger(__name__).warning("Customer Groq BadRequestError: %s", e)
            try:
                fb = _call(messages)
                last_response = fb
                _record_customer_usage(fb, chosen_model, intent, customer_uid,
                                       True, _time.time() - t0)
                return {
                    "reply": fb.choices[0].message.content
                             or "I couldn't retrieve that information. Please try rephrasing.",
                    "tool_calls": tool_log,
                    "model": chosen_model,
                    "intent": intent,
                }
            except Exception:
                return {
                    "reply": "I couldn't retrieve that information. Please try rephrasing.",
                    "tool_calls": tool_log,
                    "model": chosen_model,
                    "intent": intent,
                }
        msg  = response.choices[0].message
        asst: dict = {"role": "assistant", "content": msg.content or ""}
        if msg.tool_calls:
            asst["tool_calls"] = [tc.model_dump() for tc in msg.tool_calls]
        messages.append(asst)

        if not msg.tool_calls:
            if _is_pricing_query and _turn == 0 and not tool_log:
                messages.append({
                    "role": "user",
                    "content": (
                        "Please call the get_service_prices tool now to retrieve "
                        "the actual price from the database. Do not guess."
                    ),
                })
                continue
            final_reply = msg.content or ""
            _record_customer_usage(response, chosen_model, intent, customer_uid,
                                   True, _time.time() - t0)
            break

        for call in msg.tool_calls:
            fn_name = call.function.name
            fn_args = _strip_null(call.function.arguments or "")
            fn      = CUSTOMER_TOOL_FUNCTIONS.get(fn_name)

            if fn is None:
                result = {"error": f"Unknown tool '{fn_name}'"}
            else:
                try:
                    fn_args.pop("customer_uid", None)
                    fn_args.pop("customer_name", None)
                    result = fn(
                        customer_uid=customer_uid,
                        customer_name=customer_name,
                        **fn_args,
                    )
                except Exception as e:
                    result = {"error": str(e)}

            tool_log.append({"tool": fn_name, "args": fn_args, "result": result})

            result_json = json.dumps(result)
            max_chars   = settings.GROQ_MAX_TOOL_RESULT_CHARS
            if len(result_json) > max_chars:
                result_json = result_json[:max_chars] + \
                    '... [TRUNCATED — summarise from data shown]"}'

            messages.append({
                "role":         "tool",
                "tool_call_id": call.id,
                "content":      result_json,
            })
    else:
        final_reply = "Sorry, I had trouble completing that request. Please try again."
        if last_response:
            _record_customer_usage(last_response, chosen_model, intent, customer_uid,
                                   False, _time.time() - t0)

    return {
        "reply": final_reply,
        "tool_calls": tool_log,
        "model": chosen_model,
        "intent": intent,
    }


def _customer_direct_lookup(message: str, customer_uid: str,
                            customer_name: str, intent: str) -> dict | None:
    """
    Attempt to answer a customer DB query entirely without calling the LLM.

    Returns a dict with reply + tool_calls if a direct answer was built,
    or None to fall through to the LLM loop.

    Only handles DATABASE_LOOKUP and DATABASE_CALCULATION intents.
    Authorization is enforced by the customer_tools functions.
    """
    if intent not in (DATABASE_LOOKUP, DATABASE_CALCULATION):
        return None

    msg_l = message.lower()
    from customer_tools import (
        get_my_vehicles, get_my_service_history,
        get_my_pms_status, get_my_bookings, get_service_prices,
    )

    # ── My vehicles ───────────────────────────────────────────────────────────
    if re.search(
        r"\b(my\s+(vehicles?|cars?|fleet|truck|van|suv)"
        r"|list\s+(my\s+)?(vehicles?|cars?|fleet)"
        r"|show\s+(my\s+)?(vehicles?|cars?|fleet)"
        r"|how\s+many\s+(vehicles?|cars?)\s+(do\s+i|i\s+have))\b",
        msg_l,
    ):
        result = get_my_vehicles(customer_uid=customer_uid, customer_name=customer_name)
        if result.get("error") == "QUOTA_EXCEEDED":
            return {
                "reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.",
                "tool_calls": [{"tool": "get_my_vehicles", "args": {}, "result": result}],
                "model": "none",
                "intent": intent,
            }
        if result.get("error"):
            return {
                "reply": "I'm having trouble retrieving your vehicles right now. Please try again in a moment.",
                "tool_calls": [{"tool": "get_my_vehicles", "args": {}, "result": result}],
                "model": "none",
                "intent": intent,
            }
        total = result.get("total_vehicles", 0)
        if total == 0:
            reply = "You don't have any registered vehicles on file yet."
        else:
            vehicles = result.get("vehicles", [])
            lines = []
            for v in vehicles:
                status = v.get("status", "Active")
                last   = v.get("lastSvcDate", "")
                line   = f"**{v.get('plate','')} — {v.get('desc','')}**\nStatus: {status}"
                if last:
                    line += f" | Last Service: {last}"
                lines.append(line)
            overdue  = [v for v in vehicles if v.get("status") == "Overdue"]
            due_soon = [v for v in vehicles if v.get("status") in ("Due Soon", "Due This Week")]
            header   = f"Here are your **{total}** registered vehicle(s):\n\n"
            body     = "\n\n".join(lines)
            footer   = ""
            if overdue:
                footer += f"\n\n⚠️ **{len(overdue)} vehicle(s) overdue** for maintenance."
            if due_soon:
                footer += f"\n\n🔔 **{len(due_soon)} vehicle(s) due soon** — consider scheduling a service."
            reply = header + body + footer
        return {
            "reply": reply,
            "tool_calls": [{"tool": "get_my_vehicles", "args": {}, "result": result}],
            "model": "none",
            "intent": intent,
        }

    # ── My service history (latest / last service) ────────────────────────────
    if re.search(
        r"\b(my\s+service\s+history|my\s+(pms|maintenance)\s+history"
        r"|past\s+services?|service\s+records?|completed\s+services?"
        r"|when\s+(was|is)\s+(my\s+)?(last|latest)\s+(service|oil|maintenance|pms))\b",
        msg_l,
    ):
        result = get_my_service_history(customer_uid=customer_uid, customer_name=customer_name)
        if result.get("error") == "QUOTA_EXCEEDED":
            return {
                "reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.",
                "tool_calls": [{"tool": "get_my_service_history", "args": {}, "result": result}],
                "model": "none",
                "intent": intent,
            }
        if result.get("error"):
            return {
                "reply": "I'm having trouble retrieving your service history right now. Please try again in a moment.",
                "tool_calls": [{"tool": "get_my_service_history", "args": {}, "result": result}],
                "model": "none",
                "intent": intent,
            }
        total = result.get("total_jobs", 0)
        if total == 0:
            reply = ("It looks like you don't have any completed service records on file yet. "
                     "Once your first service is completed at our shop, it will appear here!")
        else:
            jobs     = result.get("jobs", [])
            shown    = jobs[:10]
            total_c  = result.get("total_cost", "₱0.00")
            header   = f"Here's your service history! You have **{total}** completed record(s) with a total spend of **{total_c}**.\n\n"
            lines    = []
            for i, j in enumerate(shown, 1):
                svcs = ", ".join(j.get("services", [])) or "—"
                lines.append(
                    f"**{i}. {j.get('date','')} — {j.get('plate','')}**\n"
                    f"Services: {svcs}\nCost: {j.get('cost','—')}"
                )
            body  = "\n\n".join(lines)
            tail  = f"\n\n*Showing your 10 most recent records.*" if total > 10 else ""
            reply = header + body + tail
        return {
            "reply": reply,
            "tool_calls": [{"tool": "get_my_service_history", "args": {}, "result": result}],
            "model": "none",
            "intent": intent,
        }

    # ── My bookings ───────────────────────────────────────────────────────────
    if re.search(
        r"\b(my\s+(bookings?|appointments?)"
        r"|show\s+(my\s+)?(bookings?|appointments?)"
        r"|upcoming\s+(service|appointment|booking)"
        r"|did\s+i\s+(book|schedule))\b",
        msg_l,
    ):
        result = get_my_bookings(customer_uid=customer_uid, customer_name=customer_name)
        if result.get("error") == "QUOTA_EXCEEDED":
            return {
                "reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.",
                "tool_calls": [{"tool": "get_my_bookings", "args": {}, "result": result}],
                "model": "none",
                "intent": intent,
            }
        if result.get("error"):
            return {
                "reply": "I'm having trouble retrieving your bookings right now. Please try again in a moment.",
                "tool_calls": [{"tool": "get_my_bookings", "args": {}, "result": result}],
                "model": "none",
                "intent": intent,
            }
        total = result.get("total", 0)
        if total == 0:
            reply = "You don't have any service bookings on file."
        else:
            bookings  = result.get("bookings", [])
            shown     = bookings[:10]
            pending   = result.get("pending", 0)
            confirmed = result.get("confirmed", 0)
            header    = f"You have **{total}** booking(s)"
            if pending or confirmed:
                header += f" ({pending} pending, {confirmed} confirmed/in-progress)"
            header += ":\n\n"
            lines  = []
            for b in shown:
                lines.append(
                    f"**{b.get('date','')} {b.get('time','')} — {b.get('plate','')}**\n"
                    f"Services: {b.get('services','—')} | Status: {b.get('status','—')}"
                )
            reply = header + "\n\n".join(lines)
        return {
            "reply": reply,
            "tool_calls": [{"tool": "get_my_bookings", "args": {}, "result": result}],
            "model": "none",
            "intent": intent,
        }

    # ── Service prices (full pricing lookup — by name or all) ─────────────────
    if re.search(
        r"\b(how\s+much\s+(is|for|does|would)|price\s+of|cost\s+of|"
        r"how\s+much.*service|service\s+price|pricing|"
        r"how\s+much\s+does|how\s+much\s+would|estimate.*cost|cost.*estimate|"
        r"how\s+many\s+services?|list\s+(all\s+)?services?|"
        r"services?\s+(offered|available|you\s+offer)|what\s+services?)\b",
        msg_l,
    ):
        # Try to extract a specific service keyword from the message
        import re as _re2
        _svc_kw = None
        _kw_match = _re2.search(
            r"how\s+much\s+(?:is|for|does)?\s+(?:a\s+|an\s+|the\s+)?(.+?)(?:\s+(?:service|cost|price|fee))?\s*\??$",
            msg_l,
        )
        if _kw_match:
            _candidate = _kw_match.group(1).strip()
            # Only use as keyword if it looks like a service name (not a generic word)
            if len(_candidate) >= 3 and _candidate not in (
                "service", "services", "price", "prices", "cost", "costs", "it", "that"
            ):
                _svc_kw = _candidate

        result = get_service_prices(
            customer_uid=customer_uid,
            customer_name=customer_name,
            service_name=_svc_kw,
        )
        if result.get("error") == "QUOTA_EXCEEDED":
            return {
                "reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.",
                "tool_calls": [{"tool": "get_service_prices", "args": {}, "result": result}],
                "model": "none",
                "intent": intent,
            }
        if result.get("error"):
            return {
                "reply": (
                    "I wasn't able to retrieve service pricing right now. "
                    "Please contact us at caltexautopro2026@gmail.com or visit the shop for current rates."
                ),
                "tool_calls": [{"tool": "get_service_prices", "args": {}, "result": result}],
                "model": "none",
                "intent": intent,
            }
        services = result.get("services", [])
        total    = result.get("total_services", 0)
        if total == 0:
            if _svc_kw:
                reply = (
                    f"I couldn't find a service matching **\"{_svc_kw}\"** in our catalog. "
                    f"You can ask me to *list all services* to see everything we offer, "
                    f"or contact us at caltexautopro2026@gmail.com for details."
                )
            else:
                reply = (
                    "I wasn't able to find pricing information in our system at the moment. "
                    "Please contact us at caltexautopro2026@gmail.com or visit the shop for current rates."
                )
        elif _svc_kw and len(services) <= 5:
            # Specific service lookup — show inline results
            lines = [f"- **{s['name']}**: {s['cost']}" for s in services]
            reply = (
                f"Here's the pricing for services matching **\"{_svc_kw}\"**:\n\n"
                + "\n".join(lines)
            )
        else:
            # Full catalog or many results
            shown = services[:20]
            lines = [f"- **{s['name']}**: {s['cost']}" for s in shown]
            tail  = f"\n\n*Showing {len(shown)} of {total} services.*" if total > 20 else ""
            reply = (
                f"Here are our available services and prices ({total} total):\n\n"
                + "\n".join(lines) + tail
            )
        return {
            "reply": reply,
            "tool_calls": [{"tool": "get_service_prices", "args": {"service_name": _svc_kw}, "result": result}],
            "model": "none",
            "intent": intent,
        }

    # No direct match — fall through to LLM
    return None


def _record_customer_usage(response, model: str, intent: str,
                           customer_uid: str, success: bool,
                           elapsed_s: float) -> None:
    """Extract token counts from a Groq response and record them."""
    try:
        usage = getattr(response, "usage", None)
        if usage:
            token_tracker.record(
                user_id=customer_uid,
                role="customer",
                model=model,
                intent=intent,
                input_tokens=getattr(usage, "prompt_tokens", 0),
                output_tokens=getattr(usage, "completion_tokens", 0),
                response_ms=elapsed_s * 1000,
                success=success,
            )
    except Exception:
        pass


@app.post("/customer/chat", response_model=ChatResponse)
def customer_chat_endpoint(req: CustomerChatRequest):
    """
    Customer AI chat with server-side conversational memory.
    Scoped strictly to the logged-in customer's own data.

    Flow:
      1. Validate customer_uid and customer_name.
      2. Classify intent using deterministic rules (0 tokens).
      3. Try direct DB path for DATABASE_LOOKUP/CALCULATION (0 LLM tokens).
      4. If LLM needed: select model (8B default, 70B for COMPLEX_ANALYSIS).
      5. Run tool-calling loop.
      6. Record token usage.
      7. Return reply + session_id.
    """
    if not req.customer_uid or not req.customer_name:
        raise HTTPException(
            status_code=400,
            detail="customer_uid and customer_name are required",
        )

    if not req.message or not req.message.strip():
        session_id = req.session_id or f"customer-{req.customer_uid}"
        return ChatResponse(
            reply="Please type a question about your vehicles, bookings, or services.",
            session_id=session_id,
        )

    import unicodedata as _ucd
    _stripped = req.message.strip()
    _meaningful_chars = sum(
        1 for c in _stripped
        if _ucd.category(c).startswith(('L', 'N'))
    )
    if len(_stripped) > 0 and _meaningful_chars == 0:
        session_id = req.session_id or f"customer-{req.customer_uid}"
        return ChatResponse(
            reply="I didn't understand that. Please type a question about your vehicles, bookings, or services.",
            session_id=session_id,
        )

    session_id = req.session_id or f"customer-{req.customer_uid}"

    try:
        server_history    = get_history(session_id)
        effective_history = _merge_history(server_history, req.history)

        # Classify intent (deterministic, 0 tokens)
        intent = classify_intent(req.message)

        result = _run_customer_chat(
            message=req.message,
            customer_uid=req.customer_uid,
            customer_name=req.customer_name,
            history=effective_history,
            intent=intent,
        )
        reply = result["reply"]

        append_turn(session_id, req.message, reply)

        return ChatResponse(
            reply=reply,
            session_id=session_id,
            tool_calls=result["tool_calls"],
        )

    except Exception as e:
        if _is_rate_limit(e):
            rl = _rate_limit_reply(str(e))
            token_tracker.record(
                user_id=req.customer_uid, role="customer",
                model=_settings.GROQ_MODEL_PRIMARY, intent="UNKNOWN",
                input_tokens=0, output_tokens=0,
                success=False, rate_limited=True,
            )
            return ChatResponse(
                reply=rl["reply"],
                session_id=session_id,
                rate_limited=True,
                reset_in=rl["reset_in"],
            )
        if _is_invalid_key(e):
            ik = _invalid_key_reply()
            return ChatResponse(
                reply=ik["reply"],
                session_id=session_id,
            )
        traceback.print_exc()
        # Return a friendly message instead of a 500 error
        return ChatResponse(
            reply="I'm having trouble processing your request right now. Please try again in a moment, or contact us at caltexautopro2026@gmail.com if the issue persists.",
            session_id=session_id,
        )


# ── Shared helpers ────────────────────────────────────────────────────────────

def _merge_history(server: list[dict], client: list[dict] | None) -> list[dict]:
    """
    Merge server-side stored history with optional client-supplied history.

    Strategy:
    - Server history is the authoritative long-term memory.
    - If the client sends history too, we use whichever is longer, preferring
      server history on tie.
    - Strips any messages missing a 'role' key (Groq rejects them).
    - Caps at GROQ_MAX_HISTORY_MSGS (default 6) to keep context windows and
      token consumption manageable. 6 messages = 3 turns — enough for
      follow-up questions while saving tokens vs larger caps.
    """
    clean_server = [m for m in server if isinstance(m, dict) and "role" in m]
    clean_client = [m for m in (client or []) if isinstance(m, dict) and "role" in m]

    base = clean_server if len(clean_server) >= len(clean_client) else clean_client

    limit = _settings.GROQ_MAX_HISTORY_MSGS
    return base[-limit:] if len(base) > limit else base

