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
from input_normalizer import normalize as _normalize_input
from model_router import (
    classify_intent, classify_customer_intent, select_model, needs_llm,
    DATABASE_LOOKUP, DATABASE_CALCULATION, GENERAL_AI_QUESTION,
    COMPLEX_ANALYSIS, REPORT_GENERATION, UNKNOWN,
    # Customer intents
    MY_VEHICLES, MY_SERVICE_HISTORY, MY_BOOKINGS,
    SERVICE_RECOMMENDATION, SERVICE_PRICES, CUSTOMER_MATERIALS,
    SERVICE_COST, MAINTENANCE_REMINDER,
    BOOK_SERVICE, UPDATE_BOOKING, CANCEL_BOOKING,
    GENERAL_SERVICE_INFORMATION, GENERAL_CUSTOMER_SUPPORT, GENERAL_CONVERSATION,
)
from session_store import (
    get_history, append_turn, clear_session, session_info, active_session_count
)
from config import settings as _settings  # for token-limit constants in _merge_history
import token_tracker
import usage_limiter
import cache_manager

app = FastAPI(
    title="Caltex AutoPro AI",
    description="AI assistant with server-side conversational memory",
)

# -- CORS ----------------------------------------------------------------------
# Required so the Flutter web app (running in a browser) can call this API
# directly. Also covers the Flutter mobile web build and any other web clients.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],       # allow all origins (API uses session keys, not cookies)
    allow_methods=["*"],       # GET, POST, DELETE, OPTIONS, etc.
    allow_headers=["*"],       # Content-Type, Authorization, etc.
    allow_credentials=False,   # must be False when allow_origins is "*"
)


# -- Rate-limit helper ---------------------------------------------------------

def _parse_rate_limit_reset(error_message: str) -> str:
    """
    Extract the reset time from a Groq RateLimitError message.
    e.g. 'Please try again in 15m46.944s'  ->  'about 15 minutes'
         'Please try again in 1h30m.'      ->  'about 1 hour and 30 minutes'
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
            f"Warning: The AI service has reached its daily usage limit (Groq free tier).\n\n"
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
        or "model_not_found" in exc_str
        or "does not exist" in exc_str
        or "no access to it" in exc_str
    )


def _invalid_key_reply() -> dict:
    """Build a structured response for an invalid/revoked API key or missing model."""
    return {
        "rate_limited": False,
        "reply": (
            "The AI service is currently unavailable due to a configuration issue "
            "(invalid API key or unsupported model). "
            "Please contact the system administrator."
        ),
    }


# -- Health --------------------------------------------------------------------

@app.get("/health")
def health():
    return {
        "status":          "ok",
        "role":            "admin",
        "active_sessions": active_session_count(),
        "limits": {
            "customer_daily_tokens":   usage_limiter.CUSTOMER_DAILY_TOKEN_LIMIT,
            "customer_daily_requests": usage_limiter.CUSTOMER_DAILY_REQUEST_LIMIT,
            "admin_daily_tokens":      usage_limiter.ADMIN_DAILY_TOKEN_LIMIT,
            "admin_daily_requests":    usage_limiter.ADMIN_DAILY_REQUEST_LIMIT,
        },
    }


# -- Usage / quota endpoints ---------------------------------------------------

@app.get("/usage/customer/{customer_uid}")
def get_customer_usage(customer_uid: str):
    """Return today's AI usage stats for a specific customer (for the UI quota banner)."""
    return usage_limiter.get_user_usage(customer_uid, role="customer")


@app.get("/usage/admin")
def get_admin_usage():
    """Return today's aggregate AI usage stats for the admin."""
    return usage_limiter.get_all_usage()


@app.get("/usage/log")
def get_usage_log(n: int = 50):
    """
    Admin AI usage monitoring: recent per-request token logs (no content).
    Records user id, role, model, intent, input/output/total tokens,
    latency, success — from actual Groq usage data when available.
    """
    return {
        "summary": token_tracker.get_daily_summary(),
        "recent": token_tracker.get_recent_log(max(1, min(n, 200))),
        "answer_cache": __import__("answer_cache").stats(),
    }


@app.get("/cache/stats")
def get_cache_stats():
    """Return current Firestore cache state (admin debug endpoint)."""
    return cache_manager.get_stats()


@app.post("/cache/invalidate")
def invalidate_cache(key: str | None = None):
    """Force-invalidate the Firestore cache (admin use only). Pass key= to target one entry."""
    cache_manager.invalidate(key)
    return {"success": True, "invalidated": key or "all"}


@app.get("/debug/item-master")
def debug_item_master():
    """
    Diagnostic endpoint  -  shows what's in the item_master Firestore collection.
    Use this when the service catalog appears empty in the AI assistant.
    Returns the first 100 documents with their name, type, group, and cost fields.
    """
    try:
        from firestore_client import get_db
        db = get_db()
        docs = list(db.collection("item_master").limit(100).stream())
        items = []
        for doc in docs:
            d = doc.to_dict()
            items.append({
                "id":    doc.id,
                "name":  d.get("name", ""),
                "type":  d.get("type", "MISSING"),
                "group": d.get("group", ""),
                "cost":  d.get("cost", ""),
                "num":   d.get("num", ""),
            })
        type_counts: dict = {}
        for it in items:
            t = it["type"] or "MISSING"
            type_counts[t] = type_counts.get(t, 0) + 1
        return {
            "total_docs": len(items),
            "type_breakdown": type_counts,
            "items": items,
        }
    except Exception as exc:
        return {"error": str(exc)}


# -- Session management --------------------------------------------------------

@app.get("/session/{session_id}", response_model=SessionInfoResponse)
def get_session_info(session_id: str):
    """Return metadata about a session (number of stored turns, last active)."""
    return session_info(session_id)


@app.delete("/session/{session_id}")
def delete_session(session_id: str):
    """Clear all stored history for a session."""
    clear_session(session_id)
    return {"success": True, "session_id": session_id, "message": "Session cleared"}


# -- Admin chat ----------------------------------------------------------------

@app.post("/admin/chat", response_model=ChatResponse)
def admin_chat(req: ChatRequest):
    """
    Admin AI chat with server-side conversational memory and model routing.

    Flow:
      1. Resolve or create a session_id.
      2. Check admin daily usage limit (high/unlimited by default).
      3. Classify intent using deterministic rules (zero tokens).
      4. Try the admin fast-path classifier for obvious DB queries.
          -  If matched and intent is DATABASE_LOOKUP/CALCULATION: return the
           data directly with a template reply (0 LLM tokens).
          -  If matched but still needs phrasing: call 8B with data already fetched.
      5. Otherwise: full LLM tool-calling loop with selected model.
      6. Record token usage against the admin's daily limit.
      7. Append exchange to session store.
      8. Return reply + session_id.
    """
    session_id = req.session_id or str(uuid.uuid4())
    admin_id   = session_id[:20]   # stable identifier for usage tracking

    try:
        # -- Step 2: daily usage check -----------------------------------------
        limit_check = usage_limiter.check_limit(admin_id, role="admin")
        if not limit_check["allowed"]:
            return ChatResponse(
                reply=limit_check["reason"],
                session_id=session_id,
                rate_limited=True,
                reset_in="midnight",
            )

        server_history    = get_history(session_id)
        effective_history = _merge_history(server_history, req.history)

        # -- Step 3: intent classification (deterministic, 0 tokens) ----------
        intent      = classify_intent(req.message)
        chosen_model = select_model(intent)

        # -- Step 4: admin fast-path (pre-fetches DB data before any LLM call) -
        fast_path = classify_and_run(req.message)

        if fast_path:
            if intent in (DATABASE_LOOKUP, DATABASE_CALCULATION):
                reply = _format_admin_db_reply(req.message, fast_path["result"])
                append_turn(session_id, req.message, reply)
                # Zero LLM tokens  -  record request count only
                token_tracker.record(
                    user_id=admin_id,
                    role="admin",
                    model="none",
                    intent=intent,
                    input_tokens=0,
                    output_tokens=0,
                )
                usage_limiter.record_usage(admin_id, "admin", 0, 0)
                return ChatResponse(
                    reply=reply,
                    session_id=session_id,
                    tool_calls=[fast_path],
                )

            phrasing_prompt = (
                f"The user asked: \"{req.message}\"\n\n"
                f"Here is the exact data retrieved from the database:\n"
                f"{fast_path['result']}\n\n"
                f"Answer the user's question using ONLY this data. "
                f"Be concise. Do not recalculate anything."
            )
            result = llm_chat(
                phrasing_prompt,
                history=effective_history,
                model=_settings.GROQ_MODEL_PRIMARY,
                intent=intent,
                user_id=admin_id,
            )
            reply = result["reply"]
            tool_calls_out = [fast_path]
        else:
            result = llm_chat(
                req.message,
                history=effective_history,
                model=chosen_model,
                intent=intent,
                user_id=admin_id,
            )
            reply = result["reply"]
            tool_calls_out = result["tool_calls"]

        # -- Record usage against daily limit ----------------------------------
        _record_llm_usage_admin(result, admin_id)

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
                user_id=admin_id, role="admin",
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


def _record_llm_usage_admin(result: dict, admin_id: str) -> None:
    """Extract token counts from an LLM result dict and record them for the admin."""
    try:
        # token_tracker.record is already called inside client.py (_record_usage).
        # We only need to update usage_limiter here so the per-user daily cap is tracked.
        # Estimate from token_tracker's last entry since client.py doesn't return counts.
        summary = token_tracker.get_daily_summary()
        by_model = summary.get("by_model", {})
        # Sum all model tokens recorded today for the admin session
        total_today = summary.get("total_tokens", 0)
        _ = total_today  # used indirectly via usage_limiter below

        # We approximate: record 1 request with 0 extra tokens since token_tracker
        # already captured the exact counts; usage_limiter just needs the request bump.
        usage_limiter.record_usage(admin_id, "admin", 0, 0)
    except Exception:
        pass


def _format_admin_db_reply(message: str, result: dict) -> str:
    """
    Build a direct template response for admin DATABASE_LOOKUP requests.
    No LLM involved  -  zero tokens consumed.
    """
    msg_l = _normalize_input(message) or message.lower()

    # Low stock
    if "low" in msg_l and "stock" in msg_l or "reorder" in msg_l or "restock" in msg_l:
        count = result.get("low_stock_count", len(result.get("items", [])))
        if count == 0:
            return "All items are currently at acceptable stock levels. No items are below the reorder point."
        items = result.get("items", [])[:10]
        lines = [f"**{it['name']}**  -  Stock: {it['stock']} {it['uom']} (Reorder: {it['reorder']})"
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
            + (f"  -  {breakdown}" if breakdown else "")
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

    # Inventory / stock list
    if "inventory" in msg_l or "stock" in msg_l or "items" in msg_l:
        total = result.get("total_items", len(result.get("items", [])))
        items = result.get("items", [])
        low   = sum(1 for it in items if (it.get("status") or "").lower() == "low")
        lines = [
            f"**{it['name']}**  -  Stock: {it['stock']} {it.get('uom','')}"
            for it in items[:10]
        ]
        tail = f"\n\n*...and {total - 10} more items.*" if total > 10 else ""
        return (
            f"Here are **{total}** inventory item(s)"
            + (f" ({low} flagged Low)." if low else ".")
            + "\n\n" + "\n".join(lines) + tail
        )

    # Generic fallback: return a short summary
    import json
    return f"Here is the data retrieved:\n\n```\n{json.dumps(result, indent=2)[:1500]}\n```"


# -- Admin report --------------------------------------------------------------

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
            pass  # no body or not JSON  -  treat as no filters


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


# -- Customer chat -------------------------------------------------------------

CUSTOMER_MANUAL_CONTEXT = """
CALTEX AUTOPRO  -  USER MANUAL (CUSTOMER SECTIONS)

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

PROFILE: Tap avatar (top right)  ->  view name, email, role. Edit Profile to update name
or photo. Change Password: enter current + new. Notifications: Profile  ->  Notifications to
toggle PMS Overdue, Due This Week, Due Soon, Service Updates alerts.

NOTIFICATIONS: Bell icon shows unread count. Tap to view/mark read. Push notifications
via OneSignal (mobile)  -  enable in phone settings and app preferences.

FAQ:
- Can't log in? Check email/password or use Forgot Password.
- No push notifications? Enable in phone settings + app preferences.
- Vehicle shows "Overdue" after service? Ensure service marked Completed, frequency set, last date updated.
- How to check service history? Website: PMS History tab. Mobile: PMS History (bottom right).
- How to book? Mobile: Book Service in bottom nav. Pick vehicle, services, date, confirm.
- How to view bookings? Tap Bookings tab / My Bookings.
- Profile photo? Tap avatar  ->  Profile  ->  tap avatar photo  ->  gallery.
- What is "Due Soon"? Next scheduled maintenance is approaching  -  plan a service appointment.
- Service Frequency? Number of months between recommended maintenance services.
- Can I reschedule? Yes  -  ask the AI assistant to reschedule and provide your booking ID, new date, and time.
- Can I cancel? Yes  -  ask the AI assistant to cancel and provide your booking ID.

Contact & Support: caltexautopro2026@gmail.com
"""

# -- Out-of-scope patterns (customer chat) — compiled once at module level ----
_OUT_OF_SCOPE_RE = re.compile(
    r"\b(inventory|stock\s+level|stock\s+status|stock\s+is\s+low|"
    r"low\s+stock|running\s+low|almost\s+out|nearly\s+out|"
    r"reorder|restock\w*|replenish\w*|issuance|"
    r"supplier|delivery|deliveries|warehouse|purchase\s+order|"
    r"how\s+many.*(in\s+stock|stock\s+level|bottles|pieces|units)"
    r"|generate\s+(a\s+)?(report|pdf|excel|summary)|"
    r"inventory\s+report|maintenance\s+report|service\s+report|"
    r"all\s+(customers?|users?|accounts?)|"
    r"other\s+customer|another\s+customer|"
    r"(weather|news|sports|politics|geography|math|coding|programming|"
    r"calculate|formula|recipe|joke|game|movie|music))\b",
    re.IGNORECASE,
)
# Special case: stock quantity questions must be blocked even if phrased nicely
_STOCK_QTY_RE = re.compile(
    r"\b(how\s+many\s+(bottles?|liters?|litres?|pieces?|units?|cans?|drums?)"
    r"|how\s+much\s+.*(in\s+stock|stock|inventory)"
    r"|current\s+stock|stock\s+quantity|quantity\s+(of|in)|in\s+stock)\b",
    re.IGNORECASE,
)

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
    Includes the user manual only for how-to/app-usage queries to save tokens.
    """
    base = """You are the friendly vehicle/service assistant for a Caltex AutoPro customer (JA Noble Enterprise Inc., Caltex San Pedro, Laguna). Warm, concise, natural tone.

SCOPE — only: customer's own vehicles/PMS status, their service history & costs, their bookings (create/reschedule/cancel), shop services & pricing, customer-visible materials, maintenance recommendations from their data, app/website how-to. Anything else (news, sports, general knowledge, coding, math, weather) → respond ONLY: "I can only answer questions related to the Automotive Service and Inventory Management System."

PRIVACY (absolute):
- Another person's data → ONLY: "I can only show information for your own account."
- NEVER reveal stock quantities, reorder points, suppliers, purchase costs, issuances, deliveries, staff lists, or reports (PDF/Excel). → scope refusal sentence above.
- "my vehicles" is always customer-scoped → call get_my_vehicles.
- Garbage/symbols-only → "I didn't quite catch that. Could you rephrase your question about your vehicles, bookings, or services?"

BOOKING WORKFLOW:
1. Collect ALL required info BEFORE create_customer_booking: plate (their registered vehicle — get_my_vehicles if unknown), service(s) (get_service_prices if uncertain), date, time. Don't re-ask what history already provided.
2. No date given → call suggest_booking_date first; present conversationally ("Based on your last service on [date], I recommend around [date]...").
3. ALWAYS check_booking_availability BEFORE create_customer_booking.
4. NEVER claim success until create_customer_booking returns success=True. On error, give the specific reason + alternatives.
5. Reschedule/cancel: get booking_id via get_my_bookings, then update_my_booking / cancel_my_booking. Never touch another customer's booking.
6. On success confirm: ✅ booking ID, vehicle, service(s), date, time + "pending confirmation" next steps.

RULES:
- Only this customer's data; call tools for data — never invent records.
- Maintenance questions → get_service_recommendations; state recommendations are from recorded data, not guaranteed; never invent schedules.
- Cost estimates → estimate_service_cost (never guess prices).
- "what was my previous question?" with empty history → "There's no previous conversation in this session. Feel free to ask me anything about your vehicles, bookings, or services!"
- Reformat follow-ups ("make it a list") → reformat previous answer, NO tool calls.
- Tool {"error":"QUOTA_EXCEEDED"} → "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes."
- Tool {"error":"ACCESS_DENIED"} → "I can only show information for your own account."

TOOL MAPPING: my vehicles/fleet/cars→get_my_vehicles; service history/past services/spent/pms history→get_my_service_history; what maintenance do I need/is my car due/PMS status/due soon→get_service_recommendations; my bookings/upcoming service→get_my_bookings; prices/how much is/services offered→get_service_prices ("all"/"complete list"→NO filter); materials/products/oil prices→get_customer_materials ("all"→NO filter); suggest a date/when should I book→suggest_booking_date; book a service→booking workflow above; reschedule→update_my_booking; cancel→cancel_my_booking; estimate cost→estimate_service_cost.

DISPLAY:
- "all services/prices" → call with NO filter, show EVERYTHING grouped by category (e.g. "**Lubricant Services:**\n• Change Oil - ₱500.00"), never say the list is too long.
- Materials: show name/group/UOM/customer price only — NEVER stock quantities or supplier info, even if asked.
- Service history format: "Here's your service history! You have [N] completed record(s) with a total spend of [total]." then **[N]. [Date] - [Plate]** / Services / Materials / Cost; >10 jobs → 10 most recent + note; none → warm no-records message.
- Vehicles format: "Here are your registered vehicles:" then **[Plate] - [Desc]** / Status / Last Service / Frequency; close with overdue/due-soon note.
- Empty results: no vehicles→"You don't have any registered vehicles on file yet."; no bookings→"You don't have any service bookings on file."; prices empty+catalog empty→"Our service pricing catalog hasn't been set up yet. Please contact us at caltexautopro2026@gmail.com or visit the shop for current rates."; price keyword no match→suggest "list all services"; materials no match→"I couldn't find that material/product in our catalog."
"""
    if _MANUAL_KEYWORDS.search(message):
        return base + "\n\n" + CUSTOMER_MANUAL_CONTEXT
    return base


CUSTOMER_SYSTEM_PROMPT = _build_customer_system_prompt("")  # fallback reference only


def _run_customer_chat(message: str, customer_uid: str, customer_name: str,
                       history: list[dict], intent: str = UNKNOWN) -> dict:
    """
    Core customer LLM loop.

    Tries the direct-DB path first (0 LLM tokens) for recognized intents.
    Falls back to the full LLM tool-calling loop otherwise.

    Security: customer_uid and customer_name are ALWAYS injected server-side.
    The LLM cannot override them through tool arguments.
    """
    import json
    from groq import Groq, BadRequestError, RateLimitError, AuthenticationError
    from config import settings
    from customer_tools import CUSTOMER_TOOL_SCHEMAS, CUSTOMER_TOOL_FUNCTIONS
    import time as _time

    # -- Step 1: out-of-scope pre-check (0 LLM tokens, 0 Firestore reads) -----
    # Must run BEFORE the direct-DB path: ambiguous DB intents (e.g. stock
    # questions mapped to MY_SERVICE_HISTORY) must never trigger a Firestore
    # read or a wrong answer.
    # Normalize for blocking checks only (typo'd scope probes like "inventry")
    _norm_message = _normalize_input(message) or message
    if _OUT_OF_SCOPE_RE.search(_norm_message) or _STOCK_QTY_RE.search(_norm_message):
        return {
            "reply": "I can only answer questions related to your vehicles, service history, bookings, and service pricing for the Caltex AutoPro system.",
            "tool_calls": [],
            "model": "none",
            "intent": intent,
        }

    # -- Step 1c: direct DB path for simple lookups (0 LLM tokens) ------------
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
        usage_limiter.record_usage(customer_uid, "customer", 0, 0)
        return direct

    # -- Step 1d: answer cache for repeated NON-PERSONAL questions ------------
    # Only general-educational intents are cached (never personal data).
    if intent in (GENERAL_AI_QUESTION, GENERAL_SERVICE_INFORMATION):
        import answer_cache
        cached = answer_cache.get(message)
        if cached is not None:
            token_tracker.record(
                user_id=customer_uid, role="customer", model="cache",
                intent=intent, input_tokens=0, output_tokens=0,
            )
            usage_limiter.record_usage(customer_uid, "customer", 0, 0)
            return {"reply": cached, "tool_calls": [], "model": "cache", "intent": intent}

    # -- Step 2: select model --------------------------------------------------
    chosen_model = (settings.GROQ_MODEL_SECONDARY
                    if intent == COMPLEX_ANALYSIS
                    else settings.GROQ_MODEL_PRIMARY)

    def _call(msgs, tools=None):
        from client import RateLimitedError as _RLE, InvalidApiKeyError as _IKE
        api_key = settings.GROQ_API_KEY
        if not api_key:
            raise _IKE("No Groq API key configured.")
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
            raise _IKE("The Groq API key is invalid or has been revoked.") from exc
        except RateLimitError as exc:
            raise _RLE("The AI service has reached its daily usage limit.") from exc
        except Exception as exc:
            _s = str(exc).lower()
            if ("model_not_found" in _s or "does not exist" in _s
                    or "404" in _s or "no access to it" in _s):
                raise _IKE(
                    f"The AI model '{chosen_model}' is no longer available on Groq."
                ) from exc
            raise

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

    from input_guard import truncate_message, build_request_context

    # Oversized-input guard — never send pasted documents to the model whole.
    safe_message = truncate_message(message, settings.MAX_INPUT_CHARS)

    # Per-request token budget: system prompt + sanitized history + message,
    # trimmed deterministically before any Groq call.
    messages, _budget_stats = build_request_context(
        _build_customer_system_prompt(safe_message),
        history,
        safe_message,
        history_max_msgs=settings.GROQ_MAX_HISTORY_MSGS,
        history_msg_max_chars=settings.HISTORY_MSG_MAX_CHARS,
        budget_tokens=settings.CUSTOMER_MAX_REQUEST_TOKENS,
    )
    message = safe_message

    tool_log    = []
    final_reply = ""
    t0 = _time.time()

    # Nudge model for pricing queries that stall
    _is_pricing_query = bool(re.search(
        r"how\s+much\s+(is|for|does|would)|price\s+of|service\s+price|pricing",
        message, re.IGNORECASE,
    ))

    last_response = None
    for _turn in range(6):
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
            # Cache the answer for identical future non-personal questions
            if intent in (GENERAL_AI_QUESTION, GENERAL_SERVICE_INFORMATION):
                try:
                    import answer_cache
                    answer_cache.put(message, final_reply)
                except Exception:
                    pass
            break

        for call in msg.tool_calls:
            fn_name = call.function.name
            fn_args = _strip_null(call.function.arguments or "")
            fn      = CUSTOMER_TOOL_FUNCTIONS.get(fn_name)

            if fn is None:
                result = {"error": f"Unknown tool '{fn_name}'"}
            else:
                try:
                    # Security: ALWAYS remove any uid/name the LLM may have injected
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
                    '... [TRUNCATED  -  summarise from data shown]"}'

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
        "reply":      final_reply,
        "tool_calls": tool_log,
        "model":      chosen_model,
        "intent":     intent,
    }


def _customer_direct_lookup(message: str, customer_uid: str,
                            customer_name: str, intent: str) -> dict | None:
    """
    Answer a customer DB query entirely without calling the LLM (0 tokens).
    Returns dict with reply + tool_calls if handled, or None to fall through.
    Authorization is enforced by the customer_tools functions.
    """
    # Only handle data-retrieval intents in the direct path
    _DIRECT_INTENTS = {
        MY_VEHICLES, MY_SERVICE_HISTORY, MY_BOOKINGS,
        SERVICE_PRICES, SERVICE_COST, MAINTENANCE_REMINDER,
        SERVICE_RECOMMENDATION,
        # Also catch legacy generic intents that map to customer data
        DATABASE_LOOKUP, DATABASE_CALCULATION,
    }
    if intent not in _DIRECT_INTENTS:
        return None

    msg_l = _normalize_input(message) or message.lower()
    from customer_tools import (
        get_my_vehicles, get_my_service_history,
        get_service_recommendations, get_my_bookings,
        get_service_prices,
    )

    # -- MY_VEHICLES -----------------------------------------------------------
    if intent == MY_VEHICLES or re.search(
        r"(my\s+(vehicles?|cars?|fleet|truck|van|suv)"
        r"|list\s+(my\s+)?(vehicles?|cars?|fleet)"
        r"|show\s+(my\s+)?(vehicles?|cars?|fleet)"
        r"|how\s+many\s+(vehicles?|cars?)\s+(do\s+i|i\s+have)"
        r"|plate\s+number|my\s+plate"
        r"|registered\s+(vehicles?|cars?)|vehicles?\s+registered\s+to\s+me)",
        msg_l,
    ):
        result = get_my_vehicles(customer_uid=customer_uid, customer_name=customer_name)
        if result.get("error") == "QUOTA_EXCEEDED":
            return {"reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.", "tool_calls": [{"tool": "get_my_vehicles", "args": {}, "result": result}], "model": "none", "intent": intent}
        if result.get("error"):
            return {"reply": "I'm having trouble retrieving your vehicles right now. Please try again.", "tool_calls": [{"tool": "get_my_vehicles", "args": {}, "result": result}], "model": "none", "intent": intent}
        total = result.get("total_vehicles", 0)
        if total == 0:
            reply = "You don't have any registered vehicles on file yet."
        else:
            vehicles = result.get("vehicles", [])
            lines    = []
            for v in vehicles:
                status = v.get("status", "Active")
                last   = v.get("lastSvcDate", "")
                make_model = ""
                if v.get("make") or v.get("model"):
                    make_model = f" ({v.get('make','')} {v.get('model','')})".strip()
                line = f"**{v.get('plate','')}  -  {v.get('desc','')}{make_model}**\nStatus: {status}"
                if last:
                    line += f" | Last Service: {last}"
                lines.append(line)
            overdue  = [v for v in vehicles if v.get("status") == "Overdue"]
            due_soon = [v for v in vehicles if v.get("status") in ("Due Soon", "Due This Week")]
            header   = f"Here are your **{total}** registered vehicle(s):\n\n"
            body     = "\n\n".join(lines)
            footer   = ""
            if overdue:
                footer += f"\n\nWarning: **{len(overdue)} vehicle(s) overdue** for maintenance."
            if due_soon:
                footer += f"\n\n **{len(due_soon)} vehicle(s) due soon**  -  consider scheduling a service."
            reply = header + body + footer
        return {"reply": reply, "tool_calls": [{"tool": "get_my_vehicles", "args": {}, "result": result}], "model": "none", "intent": intent}

    # -- MY_SERVICE_HISTORY ----------------------------------------------------
    if intent == MY_SERVICE_HISTORY or re.search(
        r"\b(my\s+service\s+history|my\s+(pms|maintenance)\s+history"
        r"|past\s+services?|service\s+records?|completed\s+services?"
        r"|service\s+history\s+per\s+(car|vehicle)"
        r"|show\s+(all\s+)?my\s+service"
        r"|when\s+(was|is)\s+(my\s+)?(last|latest)\s+(service|oil|maintenance|pms))\b",
        msg_l,
    ):
        result = get_my_service_history(customer_uid=customer_uid, customer_name=customer_name)
        if result.get("error") == "QUOTA_EXCEEDED":
            return {"reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.", "tool_calls": [{"tool": "get_my_service_history", "args": {}, "result": result}], "model": "none", "intent": intent}
        if result.get("error"):
            return {"reply": "I'm having trouble retrieving your service history right now. Please try again.", "tool_calls": [{"tool": "get_my_service_history", "args": {}, "result": result}], "model": "none", "intent": intent}
        total   = result.get("total_jobs", 0)
        total_c = result.get("total_cost", "₱0.00")
        if total == 0:
            reply = ("It looks like you don't have any completed service records on file yet. "
                     "Once your first service is completed at our shop, it will appear here!")
        else:
            by_vehicle = result.get("by_vehicle", {})
            if by_vehicle and len(by_vehicle) > 1:
                header   = (f"Here's your complete service history across **{len(by_vehicle)} vehicle(s)**  -  "
                            f"**{total}** completed record(s), total spend **{total_c}**.\n\n")
                sections = []
                for plate_key, plate_jobs in by_vehicle.items():
                    plate_total = sum(j.get("cost_raw", 0) for j in plate_jobs)
                    plate_cost  = f"₱{plate_total:,.2f}" if plate_total else " - "
                    section     = f"**{plate_key}**  -  {len(plate_jobs)} record(s), subtotal {plate_cost}\n"
                    job_lines   = []
                    for j in plate_jobs[:10]:
                        svcs = ", ".join(j.get("services", [])) or " - "
                        job_lines.append(f"   * {j.get('date','')} | {svcs} | {j.get('cost',' - ')}")
                    section += "\n".join(job_lines)
                    if len(plate_jobs) > 10:
                        section += f"\n  *(+{len(plate_jobs)-10} more records)*"
                    sections.append(section)
                reply = header + "\n\n".join(sections)
            else:
                jobs   = result.get("jobs", [])
                shown  = jobs[:10]
                header = f"Here's your service history! You have **{total}** completed record(s) with a total spend of **{total_c}**.\n\n"
                lines  = []
                for i, j in enumerate(shown, 1):
                    svcs = ", ".join(j.get("services", [])) or " - "
                    mats = ", ".join(j.get("materials", [])) or ""
                    line = (f"**{i}. {j.get('date','')}  -  {j.get('plate','')}**\n"
                            f"Services: {svcs}")
                    if mats:
                        line += f"\nMaterials: {mats}"
                    line += f"\nCost: {j.get('cost',' - ')}"
                    lines.append(line)
                body  = "\n\n".join(lines)
                tail  = "\n\n*Showing your 10 most recent records.*" if total > 10 else ""
                reply = header + body + tail
        return {"reply": reply, "tool_calls": [{"tool": "get_my_service_history", "args": {}, "result": result}], "model": "none", "intent": intent}

    # -- MY_BOOKINGS -----------------------------------------------------------
    if intent == MY_BOOKINGS or re.search(
        r"\b(my\s+(bookings?|appointments?)"
        r"|show\s+(my\s+)?(bookings?|appointments?)"
        r"|upcoming\s+(service|appointment|booking)"
        r"|did\s+i\s+(book|schedule))\b",
        msg_l,
    ):
        upcoming = "upcoming" in msg_l or "next" in msg_l
        result   = get_my_bookings(customer_uid=customer_uid, customer_name=customer_name,
                                   upcoming_only=upcoming)
        if result.get("error") == "QUOTA_EXCEEDED":
            return {"reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.", "tool_calls": [{"tool": "get_my_bookings", "args": {}, "result": result}], "model": "none", "intent": intent}
        if result.get("error"):
            return {"reply": "I'm having trouble retrieving your bookings right now. Please try again.", "tool_calls": [{"tool": "get_my_bookings", "args": {}, "result": result}], "model": "none", "intent": intent}
        total = result.get("total", 0)
        if total == 0:
            if upcoming:
                reply = "You don't have any upcoming service bookings."
            else:
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
            lines = []
            for b in shown:
                bid = b.get("booking_id", "")
                bid_str = f"\nBooking ID: `{bid}`" if bid else ""
                lines.append(
                    f"**{b.get('date','')} {b.get('time','')}  -  {b.get('plate','')}**\n"
                    f"Services: {b.get('services',' - ')} | Status: {b.get('status',' - ')}"
                    f"{bid_str}"
                )
            reply = header + "\n\n".join(lines)
        return {"reply": reply, "tool_calls": [{"tool": "get_my_bookings", "args": {}, "result": result}], "model": "none", "intent": intent}

    # -- SERVICE_RECOMMENDATION / MAINTENANCE_REMINDER -------------------------
    if intent in (SERVICE_RECOMMENDATION, MAINTENANCE_REMINDER) or re.search(
        r"\b(is\s+my\s+car\s+due|maintenance\s+(due|reminder|schedule|needed)"
        r"|what\s+maintenance\s+do\s+i\s+need|when\s+should\s+i\s+(get|service)"
        r"|overdue\s+maintenance|pms\s+(overdue|due|schedule))\b",
        msg_l,
    ):
        result = get_service_recommendations(customer_uid=customer_uid, customer_name=customer_name)
        if result.get("error") == "QUOTA_EXCEEDED":
            return {"reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.", "tool_calls": [{"tool": "get_service_recommendations", "args": {}, "result": result}], "model": "none", "intent": intent}
        if result.get("error"):
            return {"reply": "I'm having trouble retrieving your maintenance information right now. Please try again.", "tool_calls": [{"tool": "get_service_recommendations", "args": {}, "result": result}], "model": "none", "intent": intent}
        total   = result.get("total_vehicles", 0)
        if total == 0:
            reply = "You don't have any registered vehicles on file, so I can't provide maintenance recommendations yet."
        else:
            vehicles = result.get("vehicles", [])
            overdue  = result.get("overdue", 0)
            due_soon = result.get("due_soon", 0)
            on_track = result.get("on_track", 0)
            header   = f"Here are the maintenance recommendations for your **{total}** vehicle(s):\n\n"
            lines    = []
            for v in vehicles:
                lines.append(
                    f"**{v.get('plate','')}  -  {v.get('desc','')}**\n"
                    f"{v.get('recommendation','No data available.')}"
                )
            disclaimer = f"\n\n*{result.get('disclaimer','')}*" if result.get("disclaimer") else ""
            book_prompt = ""
            if overdue > 0 or due_soon > 0:
                book_prompt = "\n\n->  Would you like to **book a service appointment**? Just say \"I want to book a service\" and I'll help you schedule one."
            reply = header + "\n\n".join(lines) + disclaimer + book_prompt
        return {"reply": reply, "tool_calls": [{"tool": "get_service_recommendations", "args": {}, "result": result}], "model": "none", "intent": intent}

    # -- SERVICE_PRICES --------------------------------------------------------
    if intent == SERVICE_PRICES or re.search(
        r"\b(how\s+much\s+(is|for|does|would)|price\s+(of|for)|"
        r"service\s+price[s]?|how\s+many\s+services?|list\s+(all\s+)?services?|"
        r"services?\s+(offered|available|you\s+offer)|what\s+services?\b)",
        msg_l,
    ):
        import re as _re2
        _svc_kw  = None
        _kw_match = _re2.search(
            r"how\s+much\s+(?:is|for|does)?\s+(?:a\s+|an\s+|the\s+)?(.+?)(?:\s+(?:service|cost|price|fee))?\s*\??$",
            msg_l,
        )
        if _kw_match:
            _candidate = _kw_match.group(1).strip()
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
            return {"reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.", "tool_calls": [{"tool": "get_service_prices", "args": {"service_name": _svc_kw}, "result": result}], "model": "none", "intent": intent}
        if result.get("error"):
            return {"reply": "I wasn't able to retrieve service pricing right now. Please contact us at caltexautopro2026@gmail.com or visit the shop.", "tool_calls": [{"tool": "get_service_prices", "args": {"service_name": _svc_kw}, "result": result}], "model": "none", "intent": intent}
        services     = result.get("services", [])
        total        = result.get("total_services", 0)
        catalog_size = result.get("catalog_size", -1)

        if total == 0:
            if catalog_size == 0:
                reply = (
                    "Our service pricing catalog hasn't been set up yet. "
                    "Please contact us at caltexautopro2026@gmail.com or visit the shop for current rates."
                )
            elif _svc_kw:
                reply = (
                    f"I couldn't find a service matching **\"{_svc_kw}\"** in our catalog. "
                    f"Try asking *\"list all services\"* to see everything we offer, "
                    f"or contact us at caltexautopro2026@gmail.com for details."
                )
            else:
                reply = (
                    "I wasn't able to find pricing information in our system. "
                    "Please contact us at caltexautopro2026@gmail.com."
                )
        elif _svc_kw and len(services) <= 8:
            # Focused keyword match — show inline with the keyword
            lines = [f"- **{s['name']}**: {s['cost']}" for s in services]
            reply = (
                f"Here's the pricing for services matching **\"{_svc_kw}\"**:\n\n"
                + "\n".join(lines)
            )
        elif _svc_kw:
            # Many results for a keyword (e.g. "oil" returns 16 items)
            shown = services[:20]
            lines = [f"- **{s['name']}**: {s['cost']}" for s in shown]
            tail  = f"\n\n*Showing {len(shown)} of {total} related services.*" if total > 20 else ""
            reply = (
                f"Here are the services related to **\"{_svc_kw}\"** ({total} total):\n\n"
                + "\n".join(lines) + tail
            )
        else:
            # Full catalog listing
            shown = services[:20]
            lines = [f"- **{s['name']}**: {s['cost']}" for s in shown]
            tail  = f"\n\n*Showing {len(shown)} of {total} services. Ask about a specific service for more details.*" if total > 20 else ""
            reply = (
                f"Here are our available services and prices ({total} total):\n\n"
                + "\n".join(lines) + tail
            )
        return {"reply": reply, "tool_calls": [{"tool": "get_service_prices", "args": {"service_name": _svc_kw}, "result": result}], "model": "none", "intent": intent}

    # No direct match  -  fall through to LLM
    return None


def _record_customer_usage(response, model: str, intent: str,
                           customer_uid: str, success: bool,
                           elapsed_s: float) -> None:
    try:
        usage = getattr(response, "usage", None)
        if usage:
            input_t  = getattr(usage, "prompt_tokens",     0)
            output_t = getattr(usage, "completion_tokens", 0)
            token_tracker.record(
                user_id=customer_uid,
                role="customer",
                model=model,
                intent=intent,
                input_tokens=input_t,
                output_tokens=output_t,
                response_ms=elapsed_s * 1000,
                success=success,
            )
            usage_limiter.record_usage(customer_uid, "customer", input_t, output_t)
    except Exception:
        pass


@app.post("/customer/chat", response_model=ChatResponse)
def customer_chat_endpoint(req: CustomerChatRequest):
    """
    Customer AI chat  -  scoped strictly to the logged-in customer's own data.

    Flow:
      1. Validate customer_uid and customer_name (required  -  auth enforcement).
      2. Check customer daily usage limit.
      3. Classify intent using customer-specific deterministic rules (0 tokens).
      4. Try direct DB path for data retrieval intents (0 LLM tokens).
      5. Out-of-scope pre-check (blocks inventory/report/off-topic before LLM).
      6. Full LLM tool-calling loop if needed (customer_tools only, UID injected).
      7. Record token usage.
      8. Return reply + session_id.

    Security:
      - customer_uid is NEVER taken from the LLM or message content.
      - Every tool independently enforces the customer_uid filter.
      - Cross-customer data access is impossible via tool arguments.
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
        1 for c in _stripped if _ucd.category(c).startswith(('L', 'N'))
    )
    if len(_stripped) > 0 and _meaningful_chars == 0:
        session_id = req.session_id or f"customer-{req.customer_uid}"
        return ChatResponse(
            reply="I didn't understand that. Please type a question about your vehicles, bookings, or services.",
            session_id=session_id,
        )

    session_id = req.session_id or f"customer-{req.customer_uid}"

    try:
        # -- Step 2: daily usage limit -----------------------------------------
        limit_check = usage_limiter.check_limit(req.customer_uid, role="customer")
        if not limit_check["allowed"]:
            token_tracker.record(
                user_id=req.customer_uid, role="customer",
                model="none", intent="LIMIT_EXCEEDED",
                input_tokens=0, output_tokens=0, success=False,
            )
            return ChatResponse(
                reply=limit_check["reason"],
                session_id=session_id,
                rate_limited=True,
                reset_in="midnight",
            )

        server_history    = get_history(session_id)
        effective_history = _merge_history(server_history, req.history)

        # -- Step 3: customer intent classification (deterministic, 0 tokens) --
        intent = classify_customer_intent(req.message)

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
        return ChatResponse(
            reply="I'm having trouble processing your request right now. Please try again in a moment, or contact us at caltexautopro2026@gmail.com if the issue persists.",
            session_id=session_id,
        )


# -- Shared helpers ------------------------------------------------------------


def _merge_history(server: list[dict], client: list[dict] | None) -> list[dict]:
    """
    Merge server-side stored history with optional client-supplied history.

    Strategy:
    - Server history is the authoritative long-term memory.
    - If the client sends history too, use whichever is longer, preferring
      server history on tie.
    - Strips any messages missing a 'role' key (Groq rejects them).
    - Caps at GROQ_MAX_HISTORY_MSGS (default 6) to keep context windows and
      token consumption manageable.
    """
    clean_server = [m for m in server if isinstance(m, dict) and "role" in m]
    clean_client = [m for m in (client or []) if isinstance(m, dict) and "role" in m]

    base = clean_server if len(clean_server) >= len(clean_client) else clean_client

    limit = _settings.GROQ_MAX_HISTORY_MSGS
    return base[-limit:] if len(base) > limit else base
