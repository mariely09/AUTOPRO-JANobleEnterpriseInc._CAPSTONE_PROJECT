import traceback
import uuid
import re
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from schemas import ChatRequest, ChatResponse, CustomerChatRequest, SessionInfoResponse
from client import chat as llm_chat, AllKeysRateLimitedError as _AllKeysRateLimitedError
from intent_classifier import classify_and_run
from session_store import (
    get_history, append_turn, clear_session, session_info, active_session_count
)
from config import settings as _settings  # for token-limit constants in _merge_history

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
    )


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
    Admin AI chat with server-side conversational memory.

    Flow:
      1. Resolve or create a session_id.
      2. Load stored history for that session from the in-memory store.
      3. Merge with any client-supplied history (client history takes precedence
         for the current turn; server history provides the long-term context).
      4. Run the fast classifier, then the LLM tool-calling loop.
      5. Append the new user/assistant pair to the session store.
      6. Return the reply AND the session_id so the client sends it back next time.
    """
    # 1. Resolve session
    session_id = req.session_id or str(uuid.uuid4())

    try:
        # 2. Load server-side history
        server_history = get_history(session_id)

        # 3. Build effective history: server history is the base; any client-supplied
        #    history (legacy clients) is appended after deduplication.
        effective_history = _merge_history(server_history, req.history)

        # 4. Run the fast classifier first (cheaper path for obvious queries)
        fast_path = classify_and_run(req.message)
        if fast_path:
            phrasing_prompt = (
                f"The user asked: \"{req.message}\"\n\n"
                f"Here is the exact data retrieved from the database:\n{fast_path['result']}\n\n"
                f"Answer the user's question using ONLY this data. "
                f"Do not recalculate anything."
            )
            result = llm_chat(phrasing_prompt, history=effective_history)
            reply = result["reply"]
            tool_calls_out = [fast_path]
        else:
            result = llm_chat(req.message, history=effective_history)
            reply = result["reply"]
            tool_calls_out = result["tool_calls"]

        # 5. Persist this exchange to the session store
        append_turn(session_id, req.message, reply)

        return ChatResponse(
            reply=reply,
            session_id=session_id,
            tool_calls=tool_calls_out,
        )

    except Exception as e:
        if _is_rate_limit(e):
            rl = _rate_limit_reply(str(e))
            return ChatResponse(
                reply=rl["reply"],
                session_id=session_id,
                rate_limited=True,
                reset_in=rl["reset_in"],
            )
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


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
"""
    if _MANUAL_KEYWORDS.search(message):
        return base + "\n\n" + CUSTOMER_MANUAL_CONTEXT
    return base


# Keep the old name so existing code that references CUSTOMER_SYSTEM_PROMPT
# still works (used in _run_customer_chat to build per-request prompt).
# _run_customer_chat already calls _build_customer_system_prompt() directly.
CUSTOMER_SYSTEM_PROMPT = _build_customer_system_prompt("")  # fallback reference only


def _run_customer_chat(message: str, customer_uid: str, customer_name: str,
                       history: list[dict]) -> dict:
    """Core customer LLM loop — direct Groq call, no key rotation."""
    import json
    from groq import Groq, BadRequestError, RateLimitError
    from config import settings
    from customer_tools import CUSTOMER_TOOL_SCHEMAS, CUSTOMER_TOOL_FUNCTIONS

    def _call(msgs, tools=None):
        """Call Groq directly using GROQ_API_KEY from config."""
        from client import RateLimitedError as _RLE
        api_key = settings.GROQ_API_KEY
        if not api_key:
            raise _RLE("No Groq API key configured. Set GROQ_API_KEY in .env.")
        try:
            client = Groq(api_key=api_key)
            kwargs: dict = {
                "model":      settings.GROQ_MODEL,
                "messages":   msgs,
                "max_tokens": settings.GROQ_MAX_OUTPUT_TOKENS,
            }
            if tools:
                kwargs["tools"] = tools
            return client.chat.completions.create(**kwargs)
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
    # ── Trim history to GROQ_MAX_HISTORY_MSGS before building the payload ──
    trimmed = history[-settings.GROQ_MAX_HISTORY_MSGS:] if len(history) > settings.GROQ_MAX_HISTORY_MSGS else history
    messages.extend(trimmed)
    messages.append({"role": "user", "content": message})

    tool_log    = []
    final_reply = ""

    for _ in range(5):
        try:
            response = _call(messages, tools=CUSTOMER_TOOL_SCHEMAS)
        except BadRequestError as e:
            import logging
            logging.warning("Customer Groq BadRequestError: %s", e)
            try:
                fb = _call(messages)
                return {
                    "reply": fb.choices[0].message.content
                             or "I couldn't retrieve that information. Please try rephrasing.",
                    "tool_calls": tool_log,
                }
            except Exception:
                return {
                    "reply": "I couldn't retrieve that information. Please try rephrasing.",
                    "tool_calls": tool_log,
                }
        msg  = response.choices[0].message
        asst: dict = {"role": "assistant", "content": msg.content or ""}
        if msg.tool_calls:
            asst["tool_calls"] = [tc.model_dump() for tc in msg.tool_calls]
        messages.append(asst)

        if not msg.tool_calls:
            final_reply = msg.content or ""
            break

        for call in msg.tool_calls:
            fn_name = call.function.name
            fn_args = _strip_null(call.function.arguments or "")
            fn      = CUSTOMER_TOOL_FUNCTIONS.get(fn_name)

            if fn is None:
                result = {"error": f"Unknown tool '{fn_name}'"}
            else:
                try:
                    # Always inject the authenticated customer identity.
                    # Remove any customer_uid / customer_name the LLM may have
                    # attempted to pass — they are session-controlled, not LLM-controlled.
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

            # ── Cap tool result before feeding back to the LLM ───────────────
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

    return {"reply": final_reply, "tool_calls": tool_log}


@app.post("/customer/chat", response_model=ChatResponse)
def customer_chat_endpoint(req: CustomerChatRequest):
    """
    Customer AI chat with server-side conversational memory.
    Scoped strictly to the logged-in customer's own data.

    Requires:
        message:       the customer's question
        customer_uid:  Firebase Auth UID
        customer_name: display name (matched against Firestore owner field)
        session_id:    optional; auto-generated and returned if omitted
        history:       optional client-side history (merged with server memory)
    """
    if not req.customer_uid or not req.customer_name:
        raise HTTPException(
            status_code=400,
            detail="customer_uid and customer_name are required",
        )

    # Reject empty or whitespace-only messages before they hit the LLM
    if not req.message or not req.message.strip():
        session_id = req.session_id or f"customer-{req.customer_uid}"
        return ChatResponse(
            reply="Please type a question about your vehicles, bookings, or services.",
            session_id=session_id,
        )

    # Reject messages that contain only non-alphanumeric symbols / garbage characters
    import unicodedata as _ucd
    _stripped = req.message.strip()
    _meaningful_chars = sum(
        1 for c in _stripped
        if _ucd.category(c).startswith(('L', 'N'))  # letters or digits
    )
    if len(_stripped) > 0 and _meaningful_chars == 0:
        session_id = req.session_id or f"customer-{req.customer_uid}"
        return ChatResponse(
            reply="I didn't understand that. Please type a question about your vehicles, bookings, or services.",
            session_id=session_id,
        )

    # Use customer_uid as the natural session key so each customer
    # automatically has their own persistent memory across devices/sessions.
    session_id = req.session_id or f"customer-{req.customer_uid}"

    try:
        server_history    = get_history(session_id)
        effective_history = _merge_history(server_history, req.history)

        # NOTE: Do NOT call classify_and_run() here — that fast-path is admin-only
        # and exposes inventory/fleet/booking data for all customers.
        # Customer queries always go through _run_customer_chat() which enforces
        # the CUSTOMER_SYSTEM_PROMPT scope restrictions and per-customer filtering.
        result = _run_customer_chat(
            message=req.message,
            customer_uid=req.customer_uid,
            customer_name=req.customer_name,
            history=effective_history,
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
            return ChatResponse(
                reply=rl["reply"],
                session_id=session_id,
                rate_limited=True,
                reset_in=rl["reset_in"],
            )
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


# ── Shared helpers ────────────────────────────────────────────────────────────

def _merge_history(server: list[dict], client: list[dict] | None) -> list[dict]:
    """
    Merge server-side stored history with optional client-supplied history.

    Strategy:
    - Server history is the authoritative long-term memory.
    - If the client sends history too, we use whichever is longer, preferring
      server history on tie.
    - Strips any messages missing a 'role' key (Groq rejects them).
    - Caps at GROQ_MAX_HISTORY_MSGS (default 10) to keep context windows and
      token consumption manageable. This was previously hard-coded to 30 messages
      (15 turns). 10 messages = 5 turns — enough for follow-up questions while
      saving up to 4,000 input tokens per request.
    """
    clean_server = [m for m in server if isinstance(m, dict) and "role" in m]
    clean_client = [m for m in (client or []) if isinstance(m, dict) and "role" in m]

    base = clean_server if len(clean_server) >= len(clean_client) else clean_client

    limit = _settings.GROQ_MAX_HISTORY_MSGS
    return base[-limit:] if len(base) > limit else base


# ── AI Settings / API Key Management endpoints ───────────────────────────────
# These endpoints are called by the Flask website acting as a proxy.
# All write operations (add/update/delete) require an admin token passed in the
# X-Admin-Token header.  The token is compared against AI_ADMIN_TOKEN env var.

import os as _os
from fastapi import Header as _Header
from typing import Optional as _Optional

_ADMIN_TOKEN = _os.getenv("AI_ADMIN_TOKEN", "caltex-admin-ai-2026")


def _check_admin(x_admin_token: str = ""):
    if x_admin_token != _ADMIN_TOKEN:
        raise HTTPException(status_code=403, detail="Admin access required.")


# ── Status ──────────────────────────────────────────────────────────────────

@app.get("/ai-settings/status")
def ai_settings_status():
    """Return current AI service status and key table (masked).
    Always reloads from Firestore so the response is never stale across
    Render workers or after a cold start.
    """
    from api_key_manager import get_manager
    manager = get_manager()
    manager.load_from_firestore()   # always fresh — Firestore is the source of truth
    return manager.get_status()


# ── Event log ────────────────────────────────────────────────────────────────

@app.get("/ai-settings/logs")
def ai_settings_logs():
    """Return recent AI events (newest first)."""
    from api_key_manager import get_manager
    return {"logs": get_manager().get_event_log()}


# ── Key management ───────────────────────────────────────────────────────────

@app.post("/ai-settings/keys")
async def add_api_key(request: Request,
                      x_admin_token: _Optional[str] = _Header(default="")):
    """Add a new Groq API key."""
    _check_admin(x_admin_token)
    data = await request.json()
    plain_key    = (data.get("api_key") or "").strip()
    account_name = (data.get("account_name") or "").strip()
    status       = data.get("status", "active")

    if not plain_key:
        raise HTTPException(status_code=400, detail="api_key is required.")
    if not account_name:
        raise HTTPException(status_code=400, detail="account_name is required.")

    from api_key_manager import get_manager
    try:
        result = get_manager().add_key(plain_key, account_name, status)
        return {"success": True, **result}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.put("/ai-settings/keys/{key_id}")
async def update_api_key(key_id: str, request: Request,
                         x_admin_token: _Optional[str] = _Header(default="")):
    """Update an existing API key (account name, value, or status)."""
    _check_admin(x_admin_token)
    data = await request.json()
    plain_key    = (data.get("api_key") or "").strip() or None
    account_name = (data.get("account_name") or "").strip() or None
    status       = data.get("status") or None

    from api_key_manager import get_manager
    result = get_manager().update_key(key_id, account_name=account_name,
                                      plain_key=plain_key, status=status)
    return {"success": True, **result}


@app.delete("/ai-settings/keys/{key_id}")
def delete_api_key(key_id: str,
                   x_admin_token: _Optional[str] = _Header(default="")):
    """Delete an API key."""
    _check_admin(x_admin_token)
    from api_key_manager import get_manager
    result = get_manager().delete_key(key_id)
    return {"success": True, **result}


@app.post("/ai-settings/keys/test")
async def test_api_key(request: Request,
                       x_admin_token: _Optional[str] = _Header(default="")):
    """Test a Groq API key connection without saving it."""
    _check_admin(x_admin_token)
    data = await request.json()
    plain_key = (data.get("api_key") or "").strip()
    if not plain_key:
        raise HTTPException(status_code=400, detail="api_key is required.")
    from api_key_manager import get_manager
    result = get_manager().test_key(plain_key)
    return {"success": True, **result}


# ── Rotation settings ─────────────────────────────────────────────────────────

@app.put("/ai-settings/rotation")
async def update_rotation_settings(
        request: Request,
        x_admin_token: _Optional[str] = _Header(default="")):
    """Update rotation configuration (enable/disable, cooldown, retries)."""
    _check_admin(x_admin_token)
    data = await request.json()

    rotation_enabled = data.get("rotation_enabled")  # bool or None
    cooldown_seconds = data.get("cooldown_seconds")   # int or None
    max_retries      = data.get("max_retries")        # int or None

    # Coerce types
    if rotation_enabled is not None:
        rotation_enabled = bool(rotation_enabled)
    if cooldown_seconds is not None:
        cooldown_seconds = int(cooldown_seconds)
    if max_retries is not None:
        max_retries = int(max_retries)

    from api_key_manager import get_manager
    result = get_manager().save_rotation_settings(
        rotation_enabled=rotation_enabled,
        cooldown_seconds=cooldown_seconds,
        max_retries=max_retries,
    )
    return {"success": True, **result}


# ── Reload keys from Firestore ────────────────────────────────────────────────

@app.post("/ai-settings/reload")
def reload_keys(x_admin_token: _Optional[str] = _Header(default="")):
    """Force-reload all API keys from Firestore into memory."""
    _check_admin(x_admin_token)
    from api_key_manager import get_manager
    get_manager().load_from_firestore()
    return {"success": True, "message": "Keys reloaded from Firestore."}
