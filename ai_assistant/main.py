import traceback
import uuid
import re as _re
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from schemas import ChatRequest, ChatResponse, CustomerChatRequest, SessionInfoResponse
from client import chat as llm_chat
from intent_classifier import classify_and_run
from session_store import (
    get_history, append_turn, clear_session, session_info, active_session_count
)

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
    hours   = _re.search(r'in\s+(\d+)h', error_message)
    minutes = _re.search(r'in\s+(?:\d+h\s*)?(\d+)m', error_message)

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
    cls_name = type(exc).__name__.lower()
    exc_str  = str(exc).lower()
    return (
        "ratelimit" in cls_name
        or "rate_limit" in cls_name
        or "429" in exc_str
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

CUSTOMER_SYSTEM_PROMPT = """You are the vehicle assistant for a Caltex AutoPro customer (JA Noble Enterprise Inc., Caltex San Pedro, Laguna).

STRICT SCOPE RESTRICTION — HIGHEST PRIORITY:
You ONLY answer questions about:
- The customer's own registered vehicles and PMS status
- Their completed service history and costs
- Their service bookings and appointments
- Service offerings and pricing from this shop
- How to use the Caltex AutoPro mobile app or website (see USER MANUAL below)

If a customer asks ANYTHING outside this scope — sports, news, history, general knowledge,
coding, math, weather, entertainment, or any other non-system topic —
respond with ONLY this exact text, nothing more:
"I can only answer questions related to the Automotive Service and Inventory Management System."

Do NOT elaborate, apologize, or add anything else. Just that one sentence.

═══════════════════════════════════════════════════
  CALTEX AUTOPRO — USER MANUAL (CUSTOMER SECTIONS)
═══════════════════════════════════════════════════

SYSTEM OVERVIEW
───────────────
Caltex AutoPro is an automotive service management system for JA Noble Enterprise INC,
Caltex San Pedro, Laguna. It has a web app and a mobile app (Android/iOS).
Three roles: Admin, Staff, Customer.

1. GETTING STARTED
──────────────────
Accessing the Website: Open browser and navigate to the Caltex AutoPro URL.
Supported browsers: Chrome, Firefox, Edge, Safari.

Logging In:
  1. Enter your email address and password, then click Sign In.
  2. Or click "Sign in with Google" for Google authentication.
  The system redirects to your dashboard based on your role.

Creating an Account (Customer Registration):
  1. Click Sign Up on the login page.
  2. Fill in Full Name, Email, and Password.
  3. Confirm your password, then click Create Account.
  4. You can log in immediately after registration.

Forgot Password:
  1. Click "Forgot Password?" on the login page.
  2. Enter your registered email address.
  3. A password reset link will be sent to your email.
  4. Follow the link to set a new password.

Mobile App — Login:
  1. Enter Email and Password, then tap Sign In.
  2. Or use Sign in with Google.
  The app redirects to your dashboard based on your role.

Mobile App — Registration:
  1. Tap Create Account.
  2. Fill in Full Name, Email, Password, Confirm Password.
  3. Tap Register.

2. WEBSITE — CUSTOMER PORTAL
─────────────────────────────
Dashboard: Displays your vehicles and their status:
  - Total Vehicles — number of your registered vehicles
  - Active — vehicles in good standing
  - Maintenance — vehicles currently being serviced
  - PMS Overdue — vehicles past their maintenance due date
  - Due This Week — vehicles due for service this week
  - Due Soon — vehicles approaching their service date
  - Vehicle Cards — click any vehicle to view full details including service history.

PMS History: View the complete maintenance history for your vehicles:
  - Service Records: date, services performed, materials used, costs
  - Search & Filter: find specific service records
  - Total Cost Tracking: cumulative maintenance expenses

Smart AI Assistant: A chatbot widget that answers questions about your fleet:
  - "What's the status of my vehicles?"
  - "When is my next PMS due?"
  - "Show my maintenance history"
  - "Give me a fleet summary"

Book Service: Schedule a maintenance appointment through the booking system.

3. MOBILE APP — CUSTOMER
─────────────────────────
Dashboard: View your vehicles with PMS status indicators:
  - Active — vehicle in good standing
  - PMS Due Soon — approaching maintenance date
  - Overdue — past maintenance due date
  Vehicle cards show plate number, description, odometer, last service date, current status.

PMS History Tab (history icon at bottom right):
  Tap any vehicle card to see a full list of completed services including date, mechanic,
  services rendered, materials used, and total cost.

Smart Reports AI (center robot button at the bottom):
  Ask about your vehicles, check which are overdue or due soon, get a service history summary.

Bookings: Tap the Bookings tab or My Bookings in the bottom navigation to see all
  pending, confirmed, and completed appointments.

Book Service: Select your vehicle, choose services, pick a preferred date and time,
  then confirm the booking.

Notifications: Receive alerts about your vehicles:
  - PMS overdue reminders
  - PMS due soon notifications
  - Service completion updates

4. PROFILE & ACCOUNT SETTINGS
──────────────────────────────
Viewing Your Profile:
  Tap your avatar (top right) to view your name, email, and role.

Editing Profile:
  1. Tap Edit Profile.
  2. Update your Name or Profile Photo (tap avatar to open gallery and select image).
  3. Save changes.

Changing Password:
  1. Navigate to Change Password.
  2. Enter Current Password, then new password and confirm.
  3. Tap Update Password.

Notification Settings:
  Go to Profile → Notifications to toggle alert preferences.
  Available alerts for customers:
    - PMS Overdue — when your vehicles are past due
    - PMS Due This Week — weekly PMS reminders
    - PMS Due Soon — upcoming maintenance alerts
    - Service Updates — status changes on your services

5. NOTIFICATIONS & ALERTS
──────────────────────────
In-App Notifications:
  - Bell icon shows unread count badge.
  - Tap bell to view all notifications with timestamps.
  - Tap any notification to mark it as read.

Push Notifications (Mobile):
  Real-time alerts via OneSignal for:
  - PMS reminders (when vehicles are due or overdue)
  - Service status changes (when your service is started or completed)

  To receive push notifications:
  - Ensure notifications are enabled in your phone settings.
  - Turn on alert preferences in Profile → Notifications.
  - Maintain an active internet connection.

6. TROUBLESHOOTING & FAQ
─────────────────────────
Q: I can't log in. What should I do?
A: Verify your email and password. Use "Forgot Password" to reset credentials.
   If your account was deactivated, contact the admin.

Q: I'm not receiving push notifications on mobile.
A: Enable notifications in phone settings. Check alert preferences in the app.
   Ensure you have an active internet connection.

Q: A vehicle shows "PMS Overdue" but it was recently serviced.
A: Make sure the service was marked as Completed (not just Ongoing).
   Verify the vehicle's Service Frequency is set correctly.
   Check that the Last Service Date was updated after completion.

Q: How do I check my service history?
A: On the website, go to PMS History. On the mobile app, tap the PMS History tab
   (history icon at the bottom right).

Q: How do I book a service appointment?
A: On mobile, tap the Book Service option from the bottom navigation or dashboard.
   Select your vehicle, choose services, pick a date and time, then confirm.

Q: How do I view my bookings?
A: Tap the Bookings tab or navigate to My Bookings from the bottom navigation.

Q: How do I change my profile photo?
A: Tap your profile avatar (top right). On the Profile page, tap your avatar photo
   to open the gallery and select a new image.

Q: Why is my vehicle showing "Overdue"?
A: The next PMS due date has passed based on the last service date and service
   frequency. Contact the service center to schedule maintenance.

Q: What does "Due Soon" mean?
A: Your vehicle's next scheduled maintenance is approaching. Plan a service appointment soon.

Q: What is "Service Frequency"?
A: The number of months between recommended maintenance services for your vehicle.

7. SYSTEM REQUIREMENTS
───────────────────────
Website: Chrome 90+, Firefox 88+, Edge 90+, Safari 14+. JavaScript enabled.
Mobile App: Android 6.0+ or iOS 13.0+. Camera access for barcode scanning.
            Internet connection required. Push notification permissions recommended.

Contact & Support: caltexautopro2026@gmail.com

═══════════════════════════════════════════════════

Rules for in-scope questions:
1. Only access data belonging to the logged-in customer. Never reveal other customers' data.
2. Never show stock levels, supplier data, issuances, deliveries, or any admin-only data.
3. Never generate or offer PDF/Excel reports.
4. Always call the appropriate tool before answering data questions. Never invent numbers, dates, or records.
5. If a tool returns no data, say so plainly.
6. Be warm, helpful, and conversational.
7. For cost estimates, always call estimate_service_cost — do not guess prices.
8. For "how to use the app/website", account, login, notifications, or profile questions,
   answer directly from the USER MANUAL above — no tool call needed.
9. Use conversation history to understand follow-up questions.

CRITICAL — Reformatting follow-ups:
If the user says "make it a list", "number them", "simplify" or similar,
DO NOT call any tools. Simply reformat your PREVIOUS answer.

Keyword mappings:
- "my vehicles", "my fleet", "my cars" → get_my_vehicles
- "service history", "past services", "how much have I spent" → get_my_service_history
- "PMS", "next service", "overdue", "due soon" → get_my_pms_status
- "my bookings", "appointments", "upcoming service" → get_my_bookings
- "how much is", "price of", "cost of", "service prices" → get_service_prices or estimate_service_cost
- "estimate", "how much would it cost" → estimate_service_cost
- "how do I", "how to", "what is", "where is", "how can I", "where can I" (app/website usage)
  → answer from USER MANUAL above, no tool call needed
"""


def _run_customer_chat(message: str, customer_uid: str, customer_name: str,
                       history: list[dict]) -> dict:
    """Core customer LLM loop with tool-calling and automatic key rotation."""
    import json
    from groq import Groq, BadRequestError, RateLimitError
    from config import settings
    from customer_tools import CUSTOMER_TOOL_SCHEMAS, CUSTOMER_TOOL_FUNCTIONS
    from api_key_manager import get_manager

    manager = get_manager()

    def _make_client() -> Groq:
        key = manager.get_current_key() or settings.GROQ_API_KEY
        return Groq(api_key=key)

    def _call(msgs, tools=None, _attempt: int = 0):
        """Call Groq with automatic rotation on rate-limit."""
        max_attempts = max(1, manager._max_retries)
        last_key_id  = manager.get_current_key_id()
        current_key  = manager.get_current_key() or settings.GROQ_API_KEY
        last_exc: Exception | None = None

        for attempt in range(max_attempts):
            try:
                client = Groq(api_key=current_key)
                kwargs = {"model": settings.GROQ_MODEL, "messages": msgs}
                if tools:
                    kwargs["tools"] = tools
                return client.chat.completions.create(**kwargs)
            except RateLimitError as exc:
                last_exc = exc
                if not manager._rotation_enabled:
                    raise
                next_key = manager.rotate_on_rate_limit(failed_key_id=last_key_id)
                if next_key is None:
                    raise RateLimitError(
                        "All API keys are currently rate-limited. "
                        "Please try again in a few minutes."
                    ) from exc
                last_key_id  = manager.get_current_key_id()
                current_key  = next_key

        if last_exc:
            raise last_exc
        raise RateLimitError("All Groq API key rotation retries exhausted.")

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

    messages = [{"role": "system", "content": CUSTOMER_SYSTEM_PROMPT}]
    messages.extend(history)
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
                    result = fn(
                        customer_uid=customer_uid,
                        customer_name=customer_name,
                        **fn_args,
                    )
                except Exception as e:
                    result = {"error": str(e)}

            tool_log.append({"tool": fn_name, "args": fn_args, "result": result})
            messages.append({
                "role":         "tool",
                "tool_call_id": call.id,
                "content":      json.dumps(result),
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

    # Use customer_uid as the natural session key so each customer
    # automatically has their own persistent memory across devices/sessions.
    session_id = req.session_id or f"customer-{req.customer_uid}"

    try:
        server_history   = get_history(session_id)
        effective_history = _merge_history(server_history, req.history)

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
    - If the client sends history too (legacy / transitional clients), we use
      whichever is longer, preferring server history on tie.
    - Strips any messages missing a 'role' key (Groq rejects them).
    - Caps at 30 messages (15 turns) to keep context windows manageable.
    """
    clean_server = [m for m in server if isinstance(m, dict) and "role" in m]
    clean_client = [m for m in (client or []) if isinstance(m, dict) and "role" in m]

    # Use the longer source — server history wins on tie
    base = clean_server if len(clean_server) >= len(clean_client) else clean_client

    # Cap at 30 messages (keep most recent)
    return base[-30:] if len(base) > 30 else base


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
