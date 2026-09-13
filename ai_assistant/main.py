import traceback
import uuid
import re
import time
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
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
import ai_settings
import cache_manager
from reasoning_utils import strip_reasoning as _strip_reasoning

app = FastAPI(
    title="AutoPro AI",
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
        # Match Groq's exact rate-limit phrases — intentionally narrow to avoid
        # catching InvalidApiKeyError or model-not-found messages that happen
        # to contain generic words like "token" and "limit".
        or "rate_limit_exceeded" in exc_str
        or "rate limit exceeded" in exc_str
        or "request too large" in exc_str
        or "too large for model" in exc_str
        # Firestore free-tier quota (ResourceExhausted / 429 from gRPC)
        or "quota exceeded" in exc_str
        or "resource_exhausted" in exc_str
        or "resourceexhausted" in exc_str
    )


def _is_invalid_key(exc: Exception) -> bool:
    """
    Return True if the exception is a Groq authentication / invalid-key error.

    NOTE: model-not-found (404) errors are intentionally NOT matched here.
    client.py already wraps those as InvalidApiKeyError with a specific message,
    so isinstance() catches them. Adding raw string checks for "model_not_found"
    or "does not exist" risks catching unrelated exceptions and masking the real
    error with the generic config-issue reply.
    """
    from client import InvalidApiKeyError
    if isinstance(exc, InvalidApiKeyError):
        return True
    cls_name = type(exc).__name__.lower()
    exc_str  = str(exc).lower()
    return (
        "authentication" in cls_name
        or "invalidapikey" in cls_name
        or "authenticationerror" in cls_name
        or "401" in exc_str
        or "invalid api key" in exc_str
        or "invalid_api_key" in exc_str
        or "revoked" in exc_str
        or "unauthorized" in exc_str
    )


def _invalid_key_reply(exc: Exception | None = None) -> dict:
    """
    Build a structured response for an invalid/revoked API key or missing model.
    Logs the underlying exception (without the key value) so the real cause is
    visible in server logs during development.
    """
    import logging as _log
    _log.getLogger(__name__).error(
        "AI config error → returning config-issue reply to client. "
        "Cause: %s: %s",
        type(exc).__name__ if exc else "unknown",
        exc if exc else "(no exception provided)",
    )
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


# -- Admin AI Usage Controls (Profile → Settings → AI Usage Controls) ----------

@app.get("/ai-settings")
def get_ai_settings():
    """
    Current runtime AI settings + a usage overview for the admin controls page.
    Called through the Flask proxy (which restricts it to admin clients).
    """
    settings_now = ai_settings.get_settings()

    # Usage overview — today's per-user counters (in-memory mirror, 0 reads).
    overview = usage_limiter.get_all_usage()
    customers = {uid: e for uid, e in overview.get("users", {}).items()
                 if e.get("role") == "customer"}
    override   = settings_now.get("customer_token_limit", 0)
    eff_limit  = override if override > 0 else usage_limiter.CUSTOMER_DAILY_TOKEN_LIMIT
    at_limit   = 0
    if eff_limit > 0:
        at_limit = sum(1 for e in customers.values()
                       if int(e.get("tokens", 0)) >= eff_limit)

    return {
        "settings": settings_now,
        "overview": {
            "customer_tokens_used":   sum(int(e.get("tokens", 0)) for e in customers.values()),
            "customer_token_limit":   eff_limit,
            "customers_at_limit":     at_limit,
            "customer_ai_status":     "Active" if settings_now.get("customer_ai_enabled", True) else "Paused",
            "next_reset":             usage_limiter._next_manila_midnight_str(),
            "token_reset_hour":       int(settings_now.get("token_reset_hour", 0) or 0),
            "active_customers_today": len(customers),
        },
    }


class AiSettingsUpdate(BaseModel):
    customer_ai_enabled:     bool | None = None
    pause_reason:            str | None = None   # shown in customer chat when paused
    customer_token_limit:    int | None = None
    token_reset_hour:        int | None = None   # 0-23 Manila time; 0 = midnight
    dev_access_enabled:      bool | None = None
    dev_bypass_token_limit:  bool | None = None
    dev_access_while_paused: bool | None = None


@app.put("/ai-settings")
def put_ai_settings(update: AiSettingsUpdate):
    """Persist admin changes from the AI Usage Controls page."""
    updates = {k: v for k, v in update.model_dump().items() if v is not None}
    if not updates:
        raise HTTPException(status_code=400, detail="No valid settings provided.")
    saved = ai_settings.save_settings(updates)
    return {"success": True, "settings": saved}


@app.get("/ai-settings/public")
def get_ai_settings_public():
    """
    Unauthenticated endpoint consumed by the customer chat screen to determine
    whether the admin has paused the AI and, if so, why.
    Only exposes the minimum required fields — no usage stats, no token limits.
    """
    s = ai_settings.get_settings()
    enabled = bool(s.get("customer_ai_enabled", True))
    reason  = str(s.get("pause_reason", "") or "")
    return {
        "customer_ai_enabled": enabled,
        "pause_reason": reason if not enabled else "",
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
      1. Validate message (empty / symbols-only → 422).
      2. Resolve or create a session_id.
      3. Check admin daily usage limit (high/unlimited by default).
      4. Classify intent using deterministic rules (zero tokens).
      5. Try the admin fast-path classifier:
           - blocked (out-of-scope / prompt-injection / future-prediction):
               return deterministic refusal (0 LLM tokens).
           - arithmetic / reorder-point / remaining-stock:
               return Python-computed answer (0 LLM tokens).
           - DB lookup (DATABASE_LOOKUP/CALCULATION):
               return template reply from pre-fetched DB data (0 LLM tokens).
           - other fast-path: call 8B once with data already fetched.
      6. Otherwise: full LLM tool-calling loop with selected model.
      7. Record token usage against the admin's daily limit.
      8. Append exchange to session store.
      9. Return reply + session_id.
    """
    # -- Step 1: empty / symbols-only input validation -------------------------
    if not req.message or not req.message.strip():
        raise HTTPException(
            status_code=422,
            detail="message must not be empty.",
        )
    import unicodedata as _ucd
    _stripped = req.message.strip()
    _meaningful = sum(1 for c in _stripped if _ucd.category(c).startswith(('L', 'N')))
    if len(_stripped) > 0 and _meaningful == 0:
        # Pure symbols / punctuation — return a graceful message rather than
        # crashing, consistent with the customer endpoint behaviour.
        session_id = req.session_id or str(uuid.uuid4())
        return ChatResponse(
            reply="I didn't quite catch that. Please type a question about the system.",
            session_id=session_id,
        )

    session_id = req.session_id or str(uuid.uuid4())
    admin_id   = session_id[:20]   # stable identifier for usage tracking

    import perf_metrics
    _perf = perf_metrics.push(admin_id, "admin", "?")
    try:
        # -- Step 3: daily usage check -----------------------------------------
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

        # -- Step 4: intent classification (deterministic, 0 tokens) ----------
        with perf_metrics.stage("intent"):
            intent = classify_intent(req.message)
        _perf["intent"] = intent
        with perf_metrics.stage("context"):
            chosen_model = select_model(intent)

        # -- Step 5: admin fast-path (pre-fetches DB data before any LLM call) -
        with perf_metrics.stage("firestore"):
            fast_path = classify_and_run(req.message)

        if fast_path:
            fp_intent = fast_path.get("intent", "")
            fp_result = fast_path.get("result", {})

            # ── Blocked intents: out-of-scope, prompt-injection, future-prediction
            if fp_intent in ("out_of_scope", "prompt_injection_blocked",
                             "future_prediction_refused"):
                reply = fp_result.get("reply",
                    "I can only answer questions related to the Automotive "
                    "Service and Inventory Management System.")
                append_turn(session_id, req.message, reply)
                token_tracker.record(
                    user_id=admin_id, role="admin", model="none",
                    intent=fp_intent, input_tokens=0, output_tokens=0,
                )
                usage_limiter.record_usage(admin_id, "admin", 0, 0)
                return ChatResponse(
                    reply=reply,
                    session_id=session_id,
                    tool_calls=[fast_path],
                )

            # ── Arithmetic fast-paths: reorder point, remaining stock, pure math
            if fp_intent in ("reorder_point_calculation",
                             "remaining_stock_calculation",
                             "arithmetic_calculation"):
                reply = _format_admin_calc_reply(req.message, fp_result)
                append_turn(session_id, req.message, reply)
                token_tracker.record(
                    user_id=admin_id, role="admin", model="none",
                    intent=fp_intent, input_tokens=0, output_tokens=0,
                )
                usage_limiter.record_usage(admin_id, "admin", 0, 0)
                return ChatResponse(
                    reply=reply,
                    session_id=session_id,
                    tool_calls=[fast_path],
                )

            # ── DB lookups
            if intent in (DATABASE_LOOKUP, DATABASE_CALCULATION):
                reply = _format_admin_db_reply(req.message, fp_result)
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
                f"{fp_result}\n\n"
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
        _perf["intent"] = str(e)[:60]
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
            ik = _invalid_key_reply(e)
            return ChatResponse(
                reply=ik["reply"],
                session_id=session_id,
            )
        traceback.print_exc()
        return ChatResponse(
            reply="I'm having trouble processing your request right now. Please try again in a moment.",
            session_id=session_id,
        )
    finally:
        if _perf.get("intent") in (None, "?"):
            _perf["intent"] = "UNKNOWN"
        perf_metrics.log_summary(_perf)
        perf_metrics.pop()


def _format_admin_calc_reply(message: str, result: dict) -> str:
    """
    Format a Python-computed arithmetic / formula result as a conversational reply.
    Used for fast-path arithmetic answers (0 LLM tokens).
    """
    intent = result.get("calculated_by", "python")
    msg_l  = (_normalize_input(message) or message).lower()

    # ── Reorder point ─────────────────────────────────────────────────────────
    if "reorder_point" in result:
        rp  = result["reorder_point"]
        adu = result.get("average_daily_usage", "?")
        lt  = result.get("lead_time_days", "?")
        ss  = result.get("safety_stock", "?")
        return (
            f"The reorder point is **{rp:.0f} units**.\n\n"
            f"**Formula:** Reorder Point = (Average Daily Usage × Lead Time) + Safety Stock\n\n"
            f"**Calculation:** ({adu:.0f} × {lt:.0f}) + {ss:.0f} = **{rp:.0f} units**\n\n"
            f"This means you should place a new order when stock reaches {rp:.0f} units to avoid stockouts."
        )

    # ── Remaining stock ───────────────────────────────────────────────────────
    if "remaining" in result:
        initial   = result.get("initial_stock", 0)
        issued    = result.get("issued", 0)
        remaining = result.get("remaining", 0)
        return (
            f"After issuing **{issued:.0f} units** from **{initial:.0f} units** in stock, "
            f"there are **{remaining:.0f} units remaining**.\n\n"
            f"*Calculation verified by Python — not estimated by the AI.*"
        )

    # ── Pure arithmetic ───────────────────────────────────────────────────────
    if "answer" in result:
        answer = result["answer"]
        calc   = result.get("calculation", f"= {answer}")
        return (
            f"The answer is **{answer}**.\n\n"
            f"*Calculation: {calc} — computed by Python, not estimated.*"
        )

    # ── Fallback ──────────────────────────────────────────────────────────────
    import json as _j
    return "Here is the calculated result:\n\n```\n" + _j.dumps(result, indent=2)[:800] + "\n```"



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
    Build a conversational response for admin DATABASE_LOOKUP / DATABASE_CALCULATION
    requests answered via the fast-path (zero LLM tokens consumed).

    Tone: concise, natural, sentence-based — not a raw data dump.
    Bold is used only for key numbers and proper names, not for every label.
    """
    msg_l = _normalize_input(message) or message.lower()

    # ── Low-stock / reorder ───────────────────────────────────────────────────
    if ("low" in msg_l and "stock" in msg_l) or "reorder" in msg_l or "restock" in msg_l:
        count = result.get("low_stock_count", len(result.get("items", [])))
        if count == 0:
            return "Good news — all items are currently at acceptable stock levels. Nothing is below the reorder point right now."
        items = result.get("items", [])[:10]
        lines = [
            f"• **{it['name']}** — {it['stock']} {it['uom']} remaining (reorder at {it['reorder']})"
            for it in items
        ]
        tail = f"\n\n*...and {count - 10} more item(s) below reorder point.*" if count > 10 else ""
        intro = (f"There {'is' if count == 1 else 'are'} **{count}** item{'s' if count != 1 else ''} "
                 f"at or below the reorder point:")
        return intro + "\n\n" + "\n".join(lines) + tail

    # ── User / customer count ─────────────────────────────────────────────────
    if any(k in msg_l for k in ("how many", "count", "users", "customers", "staff")):
        total = result.get("total_users", 0)
        by_role = result.get("by_role", {})
        if by_role:
            parts = [f"**{v}** {k}{'s' if v != 1 else ''}" for k, v in by_role.items()]
            breakdown = " and ".join(parts) if len(parts) <= 2 else ", ".join(parts[:-1]) + f", and {parts[-1]}"
            return f"There are **{total}** registered user{'s' if total != 1 else ''} in the system — {breakdown}."
        return f"There are **{total}** registered user{'s' if total != 1 else ''} in the system."

    # ── Vehicles ──────────────────────────────────────────────────────────────
    if "vehicle" in msg_l or "fleet" in msg_l:
        total = result.get("total_vehicles", 0)
        by_status = result.get("by_status", {})
        if by_status:
            parts = [f"**{v}** {k}" for k, v in by_status.items()]
            breakdown = ", ".join(parts)
            return (f"There {'is' if total == 1 else 'are'} **{total}** registered "
                    f"vehicle{'s' if total != 1 else ''} in the fleet — {breakdown}.")
        return (f"There {'is' if total == 1 else 'are'} **{total}** registered "
                f"vehicle{'s' if total != 1 else ''} in the fleet.")

    # ── Maintenance summary ───────────────────────────────────────────────────
    if "maintenance" in msg_l or "repair" in msg_l or "summary" in msg_l:
        total = result.get("total_jobs", 0)
        by_status = result.get("by_status", {})
        total_cost = result.get("total_cost", 0)
        if by_status:
            parts = [f"**{v}** {k}" for k, v in by_status.items()]
            breakdown = ", ".join(parts)
            base = (f"There {'is' if total == 1 else 'are'} **{total}** maintenance "
                    f"job{'s' if total != 1 else ''} on record — {breakdown}.")
        else:
            base = (f"There {'is' if total == 1 else 'are'} **{total}** maintenance "
                    f"job{'s' if total != 1 else ''} on record.")
        cost_note = f" The total recorded cost is **₱{total_cost:,.2f}**." if total_cost else ""
        return base + cost_note

    # ── Bookings ──────────────────────────────────────────────────────────────
    if "booking" in msg_l or "appointment" in msg_l:
        total = result.get("total_bookings", 0)
        by_status = result.get("by_status", {})
        if total == 0:
            return "There are no service bookings in the system yet."
        if by_status:
            parts = [f"**{v}** {k}" for k, v in by_status.items()]
            breakdown = ", ".join(parts)
            return (f"There {'is' if total == 1 else 'are'} **{total}** service "
                    f"booking{'s' if total != 1 else ''} in the system — {breakdown}.")
        return (f"There {'is' if total == 1 else 'are'} **{total}** service "
                f"booking{'s' if total != 1 else ''} in the system.")

    # ── System summary (dashboard) ────────────────────────────────────────────
    if "maintenance" in result and "bookings" in result and "vehicles" in result:
        m = result.get("maintenance", {})
        b = result.get("bookings", {})
        v = result.get("vehicles", {})
        parts = []
        if v.get("total_vehicles"):
            parts.append(f"**{v['total_vehicles']}** registered vehicle{'s' if v['total_vehicles'] != 1 else ''}")
        if m.get("total_jobs"):
            parts.append(f"**{m['total_jobs']}** maintenance job{'s' if m['total_jobs'] != 1 else ''} on record")
        if b.get("total_bookings"):
            parts.append(f"**{b['total_bookings']}** service booking{'s' if b['total_bookings'] != 1 else ''}")
        if not parts:
            return "The system currently has no recorded data across vehicles, maintenance, or bookings."
        return "Here is a summary of the current system data:\n\n" + "\n".join(f"• {p}" for p in parts)

    # ── Issuances ─────────────────────────────────────────────────────────────
    if "issuances" in msg_l or "issued" in msg_l:
        rows = result.get("issuances", result.get("rows", []))
        total = result.get("total_issuances", len(rows))
        if total == 0:
            return "No issuance records found for the specified criteria."
        import json as _j
        sample = rows[:5]
        lines = []
        for row in sample:
            name = row.get("itemName") or row.get("name", "?")
            qty  = row.get("qty", row.get("quantity", "?"))
            date = row.get("date", row.get("issuedAt", "?"))
            lines.append(f"• **{name}** — {qty} units  ({date})")
        tail = f"\n\n*...and {total - 5} more record(s).*" if total > 5 else ""
        return (f"There {'is' if total == 1 else 'are'} **{total}** issuance record"
                f"{'s' if total != 1 else ''}:\n\n" + "\n".join(lines) + tail)

    # ── Inventory / stock list ────────────────────────────────────────────────
    if "inventory" in msg_l or "stock" in msg_l or "items" in msg_l:
        total = result.get("total_items", len(result.get("items", [])))
        items = result.get("items", [])
        low   = sum(1 for it in items if (it.get("status") or "").lower() == "low")
        if total == 0:
            return "The inventory is currently empty — no items are on record."
        lines = [
            f"• **{it['name']}** — {it['stock']} {it.get('uom', '')} "
            f"{'⚠️ Low' if (it.get('status') or '').lower() == 'low' else ''}"
            for it in items[:10]
        ]
        tail = f"\n\n*...and {total - 10} more item(s). Ask for a specific item or group to narrow results.*" if total > 10 else ""
        low_note = f" ({low} item{'s' if low != 1 else ''} flagged low)" if low else ""
        intro = f"Here are **{total}** inventory item{low_note}:" if total > 1 else f"Here is the inventory item{low_note}:"
        return intro + "\n\n" + "\n".join(lines) + tail

    # ── Generic fallback ──────────────────────────────────────────────────────
    import json as _json
    return "Here's what I found:\n\n```\n" + _json.dumps(result, indent=2)[:1500] + "\n```"


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
AUTOPRO  -  USER MANUAL (CUSTOMER SECTIONS)

AutoPro is an automotive service management system for JA Noble Enterprise INC,
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

Contact & Support: janobleenterpriseinc.autopro@gmail.com
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
    base = """You are the friendly vehicle/service assistant for an AutoPro customer (JA Noble Enterprise Inc., Caltex San Pedro, Laguna). Warm, concise, natural tone.

SCOPE — only: customer's own vehicles/PMS status, their service history & costs, their bookings (create/reschedule/cancel), shop services & pricing, customer-visible materials, maintenance recommendations from their data, app/website how-to, AND general automotive education (oil types, parts, repairs, maintenance tips, car-care how-tos). Anything else → respond ONLY: "I can only answer questions related to the Automotive Service and Inventory Management System."

PRIVACY (absolute):
- Another person's data → ONLY: "I can only show information for your own account."
- NEVER reveal stock quantities, reorder points, suppliers, purchase costs, issuances, deliveries, staff lists, or reports (PDF/Excel). → scope refusal sentence above.
- "my vehicles" is always customer-scoped → call get_my_vehicles.
- Garbage/symbols-only → "I didn't quite catch that. Could you rephrase your question about your vehicles, bookings, or services?"

BOOKING WORKFLOW:
1. Collect ALL required info BEFORE create_customer_booking: plate (get_my_vehicles if unknown), service(s) (get_service_prices if uncertain), date, time. Don't re-ask what history already provided.
2. No date given → call suggest_booking_date first; present conversationally.
3. ALWAYS check_booking_availability BEFORE create_customer_booking.
4. NEVER claim success until create_customer_booking returns success=True. On error, give the specific reason + alternatives.
5. Reschedule/cancel: get booking_id via get_my_bookings, then update_my_booking / cancel_my_booking. Never touch another customer's booking.
6. On success confirm: ✅ booking ID, vehicle, service(s), date, time + status — tell the customer to check **My Bookings**, then ask "Would you like to book another service?".

RULES:
- Only this customer's data; call tools for data — never invent records, prices, or schedules.
- Maintenance questions → get_service_recommendations; state recommendations are from recorded data, not guaranteed.
- Cost estimates → estimate_service_cost (never guess prices). Customers pay for SERVICES ONLY — do NOT include materials in cost totals or breakdowns. Single service: show price directly. Multiple services: list each with its price then show the combined total. Never mention material costs in price responses.
- "what was my previous question?" with empty history → "There's no previous conversation in this session. Feel free to ask me anything about your vehicles, bookings, or services!"
- Reformat follow-ups ("make it a list") → reformat previous answer, NO tool calls.
- Tool {"error":"QUOTA_EXCEEDED"} → "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes."
- Tool {"error":"ACCESS_DENIED"} → "I can only show information for your own account."

TOOL MAPPING: my vehicles/fleet/cars→get_my_vehicles; service history/past services/spent/pms history→get_my_service_history; what maintenance do I need/is my car due/PMS status/due soon→get_service_recommendations; my bookings/upcoming service→get_my_bookings; prices/how much is/services offered/list services→get_service_prices (NO filter for "all services"); materials needed for a service→get_customer_materials with that service's keyword (fallback estimate_service_cost); how much including materials/estimate total cost→estimate_service_cost; suggest a date/when should I book/earliest schedule→booking workflow; book a service→booking workflow; reschedule→update_my_booking; cancel→cancel_my_booking.

DISPLAY:
- "list all services/available services" → get_service_prices with NO filter, show EVERY service grouped by category. NEVER mix materials into a services list.
- Named service price ("how much is oil change?") → show the service price only. Do NOT mention materials.
- "materials needed for [service]" → get_customer_materials with that keyword; if zero results → estimate_service_cost for the historical pattern. NEVER invent material names; if no data exists, say so explicitly.
- Cost estimate (single service) → show: "The [Service] is ₱[price]." — no materials mentioned.
- Cost estimate (multiple services) → list each service with its price, then "Total: ₱[sum]." — no materials.
- Materials: show name/group/UOM/customer price only — NEVER stock quantities or supplier info, even if asked.
- Service history: lead with "You have [N] completed record(s), total spend [total]."; then **[N]. [Date] - [Plate]** / Services / Materials / Cost; >10 jobs → 10 most recent + note; none → warm no-records message.
- Vehicles: "Here are your registered vehicles:" then **[Plate] - [Desc]** / Status / Last Service / Frequency; close with overdue/due-soon note.
- Empty results: no vehicles→"You don't have any registered vehicles on file yet."; no bookings→"You don't have any service bookings on file."; catalog empty→"Our service pricing catalog hasn't been set up yet. Please contact us at janobleenterpriseinc.autopro@gmail.com or visit the shop for current rates."; price keyword no match→suggest "list all services"; materials no match→"I couldn't find configured materials for [service]. No material data exists in the system yet."
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
    from client import create_with_optional_thinking_disable as _thinking_disable_create
    from config import settings
    from customer_tools import CUSTOMER_TOOL_SCHEMAS, CUSTOMER_TOOL_FUNCTIONS
    import time as _time

    # -- Step 1: authorization pre-check (0 LLM tokens, 0 Firestore reads) ----
    # Centralized access control (access_control.py): denies other-customer
    # data, inventory, issuance, admin reports, business analytics, and
    # off-topic requests BEFORE any Firestore read or LLM call — a denied
    # request can never leak data or fall back to the customer's own history.
    import access_control
    _denial = access_control.classify_denial(message)
    if _denial is not None:
        return {
            "reply": access_control.denial_message(_denial, message),
            "tool_calls": [],
            "model": "none",
            "intent": f"ACCESS_DENIED_{_denial}",
        }

    # -- Step 1a: prompt injection guard (0 tokens, 0 reads) ------------------
    # Runs before ALL other checks so crafted "ignore previous instructions"
    # payloads can never bypass scope or data-isolation controls.
    from intent_classifier import _PROMPT_INJECTION as _PI_RE
    _norm_for_injection = _normalize_input(message) or message
    if _PI_RE.search(message) or _PI_RE.search(_norm_for_injection):
        return {
            "reply": (
                "I can only answer questions related to your vehicles, "
                "service history, bookings, and service pricing for the AutoPro system."
            ),
            "tool_calls": [],
            "model": "none",
            "intent": "PROMPT_INJECTION_BLOCKED",
        }

    # -- Step 1b: out-of-scope pre-check (defense in depth) -------------------
    # Must run BEFORE the direct-DB path: ambiguous DB intents (e.g. stock
    # questions mapped to MY_SERVICE_HISTORY) must never trigger a Firestore
    # read or a wrong answer.
    # Normalize for blocking checks only (typo'd scope probes like "inventry")
    _norm_message = _normalize_input(message) or message
    # "Show my oil change history" legitimately contains "change oil" — the
    # customer is asking for THEIR OWN past records, not shop stock. Exempt
    # an own-history lookup from the stock/qty blocker only when the message
    # clearly asks about personal history AND is not a real stock probe
    # ("in stock", "stock level", "on hand").
    _own_history_lookup = bool(re.search(
        r"\b(my|mine)\b", _norm_message, re.IGNORECASE)) \
        and bool(re.search(r"\b(history|records?)\b", _norm_message, re.IGNORECASE)) \
        and not bool(re.search(
            r"\b(in\s+stock|stock\s+levels?|stock\s+status|on\s+hand|current\s+stock)",
            _norm_message, re.IGNORECASE))
    if _OUT_OF_SCOPE_RE.search(_norm_message) \
            or (_STOCK_QTY_RE.search(_norm_message) and not _own_history_lookup):
        return {
            "reply": "I can only answer questions related to your vehicles, service history, bookings, and service pricing for the AutoPro system.",
            "tool_calls": [],
            "model": "none",
            "intent": intent,
        }

    # -- Step 1b+: deterministic booking fast path (0 LLM tokens) -------------
    # Gathers plate/service/date/time for booking requests, asks ONLY for the
    # missing details, finds earliest available slots, and books via the
    # existing customer_tools (all ownership/availability checks preserved).
    # MAINTENANCE_REMINDER is included so "when will be the earliest schedule?"
    # / "when can I bring my car in?" queries reach booking_gather even if the
    # new _BOOK_SERVICE pattern doesn't catch a particular phrasing variant.
    if intent in (BOOK_SERVICE, UNKNOWN, SERVICE_RECOMMENDATION, MAINTENANCE_REMINDER):
        import booking_gather
        gathered = booking_gather.try_handle_booking(
            message, customer_uid, customer_name, history,
        )
        if gathered is not None:
            return gathered

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
        from client import RateLimitedError as _RLE, InvalidApiKeyError as _IKE, get_groq_client
        import logging as _log
        _clog = _log.getLogger(__name__)
        api_key = settings.GROQ_API_KEY
        if not api_key:
            raise _IKE("No Groq API key configured.")
        try:
            import perf_metrics
            with perf_metrics.groq_timer():
                client = get_groq_client(api_key)
                kwargs: dict = {
                    "model":      chosen_model,
                    "messages":   msgs,
                    "max_tokens": _out_tokens[0],
                }
                if tools:
                    kwargs["tools"] = tools
                resp = _thinking_disable_create(client, kwargs)
            try:
                u = resp.usage
                perf_metrics.record_usage(getattr(u, "prompt_tokens", 0) or 0,
                                          getattr(u, "completion_tokens", 0) or 0)
            except Exception:
                pass
            return resp
        except AuthenticationError as exc:
            _clog.error(
                "Customer chat — Groq AuthenticationError (HTTP 401). "
                "Raw error: %s", exc,
            )
            raise _IKE("The Groq API key is invalid or has been revoked.") from exc
        except RateLimitError as exc:
            _clog.warning("Customer chat — Groq RateLimitError (HTTP 429): %s", exc)
            raise _RLE("The AI service has reached its daily usage limit.") from exc
        except Exception as exc:
            _s = str(exc).lower()
            if ("model_not_found" in _s or "does not exist" in _s
                    or "404" in _s or "no access to it" in _s):
                _clog.error(
                    "Customer chat — Groq model_not_found for model=%s. "
                    "Raw error: %s", chosen_model, exc,
                )
                raise _IKE(
                    f"The AI model '{chosen_model}' is no longer available on Groq."
                ) from exc
            # Log the real error before re-raising so it appears in server logs.
            _clog.error(
                "Customer chat — Groq API call failed (model=%s). %s: %s",
                chosen_model, type(exc).__name__, exc,
            )
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

    # Request-level memoization: identical tool calls within this one chat
    # turn reuse the first result instead of re-querying Firestore (spec #6).
    import request_cache
    _bucket = request_cache.begin_request()
    tool_fns = request_cache.memoize(CUSTOMER_TOOL_FUNCTIONS, _bucket)

    tool_log    = []
    final_reply = ""
    t0 = _time.time()
    _retried_empty = False
    _out_tokens = [settings.GROQ_MAX_OUTPUT_TOKENS]  # mutable: raised on empty-answer retry

    # Nudge model for pricing queries that stall
    _is_pricing_query = bool(re.search(
        r"how\s+much\s+(is|for|does|would)|price\s+of|service\s+price|pricing",
        message, re.IGNORECASE,
    ))

    last_response = None
    for _turn in range(max(1, settings.MAX_TOOL_LOOP_TURNS)):
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
                request_cache.end_request(_bucket)
                return {
                    "reply": _strip_reasoning(fb.choices[0].message.content or "")
                             or "I couldn't retrieve that information. Please try rephrasing.",
                    "tool_calls": tool_log,
                    "model": chosen_model,
                    "intent": intent,
                }
            except Exception:
                request_cache.end_request(_bucket)
                return {
                    "reply": "I couldn't retrieve that information. Please try rephrasing.",
                    "tool_calls": tool_log,
                    "model": chosen_model,
                    "intent": intent,
                }

        msg  = response.choices[0].message
        # Defense in depth: strip any <think>...</think> reasoning the model
        # emitted BEFORE it can reach the reply, session history, or caches.
        msg.content = _strip_reasoning(msg.content or "")
        asst: dict = {"role": "assistant", "content": msg.content or ""}
        if msg.tool_calls:
            asst["tool_calls"] = [tc.model_dump() for tc in msg.tool_calls]
        messages.append(asst)

        if not msg.tool_calls:
            # Empty-answer guard: with the thinking-disable parameter
            # unavailable, Qwen can burn the ENTIRE output budget on a
            # truncated <think> block and return an empty user-facing answer.
            # Retry once with a larger budget so the customer sees an answer.
            if not (msg.content or "").strip() and not _retried_empty:
                _retried_empty = True
                _out_tokens[0] = settings.GROQ_MAX_OUTPUT_TOKENS * 4
                messages.pop()  # drop the empty assistant turn
                continue
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
            fn      = tool_fns.get(fn_name)

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

    request_cache.end_request(_bucket)

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
    # ── Safety guard: never execute a direct DB lookup for a message that
    # access_control would deny.  This is a defence-in-depth check — Step 1
    # in _run_customer_chat already calls classify_denial, but intent routing
    # in model_router or a future change could theoretically slip a denied
    # query through to here.  Zero cost (pure regex, no I/O).
    import access_control as _ac
    _guard = _ac.classify_denial(message)
    if _guard is not None:
        return {
            "reply":      _ac.denial_message(_guard, message),
            "tool_calls": [],
            "model":      "none",
            "intent":     f"ACCESS_DENIED_{_guard}",
        }

    # Only handle data-retrieval intents in the direct path
    _DIRECT_INTENTS = {
        MY_VEHICLES, MY_SERVICE_HISTORY, MY_BOOKINGS,
        SERVICE_PRICES, SERVICE_COST, MAINTENANCE_REMINDER,
        SERVICE_RECOMMENDATION, CUSTOMER_MATERIALS,
        # DATABASE_LOOKUP is now only routed here when a self-reference
        # keyword is present (see model_router.classify_customer_intent).
        DATABASE_LOOKUP, DATABASE_CALCULATION,
    }
    if intent not in _DIRECT_INTENTS:
        return None

    msg_l = _normalize_input(message) or message.lower()
    from customer_tools import (
        get_my_vehicles, get_my_service_history,
        get_service_recommendations, get_my_bookings,
        get_service_prices, get_customer_materials,
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
            veh_word = "vehicle" if total == 1 else "vehicles"
            header   = f"You have **{total}** registered {veh_word}:\n\n"
            body     = "\n\n".join(lines)
            footer   = ""
            if overdue:
                ov_word = "vehicle is" if len(overdue) == 1 else "vehicles are"
                footer += f"\n\n⚠️ **{len(overdue)} {ov_word} overdue** for maintenance — please schedule a service soon."
            if due_soon:
                ds_word = "vehicle is" if len(due_soon) == 1 else "vehicles are"
                footer += f"\n\n🔔 **{len(due_soon)} {ds_word} due soon** — consider booking a service appointment."
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
                veh_count = len(by_vehicle)
                veh_word  = "vehicle" if veh_count == 1 else "vehicles"
                rec_word  = "record" if total == 1 else "records"
                header    = (f"Here's your complete service history across **{veh_count} {veh_word}** — "
                             f"**{total}** completed {rec_word} with a total spend of **{total_c}**.\n\n")
                sections = []
                for plate_key, plate_jobs in by_vehicle.items():
                    plate_total = sum(j.get("cost_raw", 0) for j in plate_jobs)
                    plate_cost  = f"₱{plate_total:,.2f}" if plate_total else " - "
                    section     = f"**{plate_key}**  -  {len(plate_jobs)} {'record' if len(plate_jobs) == 1 else 'records'}, subtotal {plate_cost}\n"
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
                header = f"Here's your service history! You have **{total}** completed {'record' if total == 1 else 'records'} with a total spend of **{total_c}**.\n\n"
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
                reply = "You don't have any upcoming service bookings right now."
            else:
                reply = "You don't have any service bookings on file yet."
        else:
            bookings  = result.get("bookings", [])
            shown     = bookings[:10]
            pending   = result.get("pending", 0)
            confirmed = result.get("confirmed", 0)
            bk_word   = "booking" if total == 1 else "bookings"
            header    = f"You have **{total}** service {bk_word}"
            if pending or confirmed:
                parts = []
                if pending:   parts.append(f"{pending} pending")
                if confirmed: parts.append(f"{confirmed} confirmed")
                header += f" ({', '.join(parts)})"
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
            veh_word = "vehicle" if total == 1 else "vehicles"
            header   = f"Here are the maintenance recommendations for your **{total}** {veh_word}:\n\n"
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

    # -- CUSTOMER_MATERIALS (materials/products for a service) -----------------
    # "List all materials needed for an Oil Change." / "what materials do i need"
    # Customers see ONLY name/group/UOM/price — never stock or supplier data.
    if intent == CUSTOMER_MATERIALS:
        # Extract the service/item keyword the materials question is about.
        # Patterns matched (in order of specificity):
        #   "materials needed for an Oil Change"
        #   "list all materials for Oil Change"
        #   "what materials do I need for oil change"
        #   "show me materials for Oil Change"
        #   "what do I need for an oil change"
        #   "what parts are used in oil change"
        _mat_kw = None
        _mat_patterns = [
            # "materials/parts needed/used/required for <service>"
            re.compile(
                r"(?:materials?|products?|parts?|items?)\s+"
                r"(?:needed|required|used|for)\s+"
                r"(?:for\s+)?(?:a\s+|an\s+|the\s+)?(.+?)\s*\??$",
                re.IGNORECASE,
            ),
            # "list all materials for <service>"
            re.compile(
                r"list\s+(?:all\s+)?(?:the\s+)?materials?\s+for\s+(?:a\s+|an\s+|the\s+)?(.+?)\s*\??$",
                re.IGNORECASE,
            ),
            # "show me materials for <service>" / "show materials for <service>"
            re.compile(
                r"show\s+(?:me\s+)?(?:the\s+)?materials?\s+(?:for|used\s+in|needed\s+for)\s+"
                r"(?:a\s+|an\s+|the\s+)?(.+?)\s*\??$",
                re.IGNORECASE,
            ),
            # "what do I need for <service>"
            re.compile(
                r"what\s+do\s+i\s+need\s+for\s+(?:a\s+|an\s+|the\s+)?(.+?)\s*\??$",
                re.IGNORECASE,
            ),
            # "for <service>" at end of sentence (when "material" already matched intent)
            re.compile(
                r"\bfor\s+(?:a\s+|an\s+|the\s+)?([a-z][a-z\s\-]{2,40}?)\s*\??$",
                re.IGNORECASE,
            ),
        ]
        for _pat in _mat_patterns:
            _m = _pat.search(msg_l)
            if _m:
                _cand = (_m.group(1) or "").strip().rstrip(".,?!")
                # Reject generic words that don't identify a real service
                if len(_cand) >= 3 and _cand not in (
                    "my vehicle", "my car", "it", "that", "this",
                    "service", "maintenance", "me", "a service", "an service",
                    "this service",
                ):
                    _mat_kw = _cand
                    break

        mat_result = get_customer_materials(
            customer_uid=customer_uid,
            customer_name=customer_name,
            material_name=_mat_kw,
        )
        if mat_result.get("error") == "QUOTA_EXCEEDED":
            return {"reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.", "tool_calls": [{"tool": "get_customer_materials", "args": {"material_name": _mat_kw}, "result": mat_result}], "model": "none", "intent": intent}
        if mat_result.get("error"):
            return {"reply": "I wasn't able to retrieve materials information right now. Please try again.", "tool_calls": [{"tool": "get_customer_materials", "args": {"material_name": _mat_kw}, "result": mat_result}], "model": "none", "intent": intent}
        mats        = mat_result.get("materials", [])
        total_mat   = len(mats)

        if total_mat == 0 and _mat_kw:
            # No catalog item matches directly for the given keyword.
            # Check whether the shop has a HISTORICAL materials pattern for a
            # matching service from completed jobs — never fabricate a list.
            from customer_tools import estimate_service_cost
            est = None
            # Try both word orders (e.g. "oil change" and "change oil")
            _kw_variants = [_mat_kw]
            _parts = _mat_kw.split()
            if len(_parts) == 2:
                _kw_variants.append(" ".join(reversed(_parts)))
            for _kv in _kw_variants:
                _est = estimate_service_cost(
                    customer_uid=customer_uid, customer_name=customer_name,
                    service_names=[_kv],
                )
                if _est.get("materials"):
                    est = _est
                    break
            if est and est.get("materials"):
                _svc_name = (est.get("matched") or [{}])[0].get("service", _mat_kw)
                _mlines = []
                for m in est["materials"]:
                    qty_str = f"{m['qty']} {m.get('uom', '') or 'unit'}".strip()
                    _mlines.append(
                        f"• **{m['material']}** — {qty_str} — {m['line_total']}"
                    )
                _missing = est.get("materials_missing_price")
                reply = (
                    f"Here are the materials typically used for **{_svc_name}** "
                    f"(based on completed service records):\n\n"
                    + "\n".join(_mlines)
                    + f"\n\n**Material Subtotal:** {est.get('material_subtotal', '—')}"
                )
                if est.get("service_charge"):
                    reply += f"\n**Service Charge:** {est['service_charge']}"
                if est.get("estimated_total"):
                    reply += f"\n**Estimated Total:** {est['estimated_total']}"
                reply += (
                    "\n\n*Quantities are based on previous jobs and may vary by vehicle. "
                    "The service charge and materials are billed separately.*"
                )
                if _missing:
                    reply += (
                        "\n\n*No price on file for: " + ", ".join(_missing)
                        + " — their cost is not included in the estimate.*"
                    )
                if est.get("materials_usage_note"):
                    reply += f"\n\n_{est['materials_usage_note']}_"
                return {"reply": reply, "tool_calls": [
                    {"tool": "estimate_service_cost",
                     "args": {"service_names": _kw_variants[:1]},
                     "result": est},
                ], "model": "none", "intent": intent}
            # No historical pattern found either
            reply = (
                f"I couldn't find configured materials for **\"{_mat_kw}\"** in our catalog. "
                "This may mean the materials haven't been linked to this service yet in the system. "
                "Ask for \"list all materials\" to see everything we offer, or contact us at "
                "janobleenterpriseinc.autopro@gmail.com for details."
            )
        elif total_mat == 0:
            reply = "I couldn't find any materials in our catalog right now. Please try again later."
        else:
            shown = mats[:20]
            lines = [
                f"• **{m['name']}** ({m.get('group', '') or 'General'}): "
                f"{m['customer_price']} / {m.get('uom', '') or 'unit'}"
                for m in shown
            ]
            tail = f"\n\n*Showing {len(shown)} of {total_mat} materials.*" if total_mat > 20 else ""
            if _mat_kw:
                header = f"Here are the materials related to **\"{_mat_kw}\"** ({total_mat} found):\n\n"
            else:
                header = f"Here are the materials we offer ({total_mat} total):\n\n"
            reply = (
                header + "\n".join(lines) + tail
                + "\n\n*Materials and the service charge are billed separately. "
                "Ask \"how much will everything cost\" for a full estimate.*"
            )
        return {"reply": reply, "tool_calls": [{"tool": "get_customer_materials", "args": {"material_name": _mat_kw}, "result": mat_result}], "model": "none", "intent": intent}

    # -- SERVICE_PRICES --------------------------------------------------------
    # TC2: "list all available services" → services only, grouped by category
    # TC5: "how much is an Oil Change service?" → named service price only,
    #       with a note that materials are billed separately
    if intent == SERVICE_PRICES or re.search(
        r"\b(how\s+much\s+(is|for|does|would)|price\s+(of|for)|"
        r"service\s+price[s]?|how\s+many\s+services?|list\s+(all\s+)?services?|"
        r"services?\s+(offered|available|you\s+offer)|what\s+services?\b|"
        r"available\s+services?|show\s+(me\s+)?(your\s+)?services?|"
        r"what\s+can\s+you\s+do\s+(to|for)\s+(my\s+)?(car|vehicle))\b",
        msg_l,
    ):
        import re as _re2
        _svc_kw  = None

        # Detect "including materials" / "with materials" → not a pure price
        # query; route to estimate_service_cost instead.
        _wants_total = bool(_re2.search(
            r"\b(including|with|plus|and)\s+(materials?|parts?|everything)\b"
            r"|\bestimated?\s+(total|cost)\b"
            r"|\btotal\s+(cost|price|estimate)\b",
            msg_l, _re2.IGNORECASE,
        ))
        if _wants_total:
            # Fall through to SERVICE_COST handler below by treating as None
            pass
        else:
            _kw_match = _re2.search(
                r"how\s+much\s+(?:is|for|does)?\s+(?:a\s+|an\s+|the\s+)?(.+?)"
                r"(?:\s+(?:service|cost|price|fee))?\s*\??$",
                msg_l,
            )
            if _kw_match:
                _candidate = _kw_match.group(1).strip()
                if len(_candidate) >= 3 and _candidate not in (
                    "service", "services", "price", "prices", "cost", "costs",
                    "it", "that", "a service",
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
                return {"reply": "I wasn't able to retrieve service pricing right now. Please contact us at janobleenterpriseinc.autopro@gmail.com or visit the shop.", "tool_calls": [{"tool": "get_service_prices", "args": {"service_name": _svc_kw}, "result": result}], "model": "none", "intent": intent}

            services     = result.get("services", [])
            total        = result.get("total_services", 0)
            catalog_size = result.get("catalog_size", -1)

            if total == 0:
                if catalog_size == 0:
                    reply = (
                        "Our service pricing catalog hasn't been set up yet. "
                        "Please contact us at janobleenterpriseinc.autopro@gmail.com "
                        "or visit the shop for current rates."
                    )
                elif _svc_kw:
                    reply = (
                        f"I couldn't find a service matching **\"{_svc_kw}\"** in our catalog. "
                        f"Try asking *\"list all services\"* to see everything we offer, "
                        f"or contact us at janobleenterpriseinc.autopro@gmail.com for details."
                    )
                else:
                    reply = (
                        "I wasn't able to find service pricing in our system. "
                        "Please contact us at janobleenterpriseinc.autopro@gmail.com."
                    )
            elif _svc_kw:
                # TC5 — named service: show service price clearly, note materials separate
                shown = services[:5]  # cap to avoid overwhelming for a single-service query
                lines = [f"• **{s['name']}**: {s['cost']}" for s in shown]
                tail  = (f"\n\n*{len(services) - 5} more matching service(s) found. "
                         "Ask \"list all services\" to see the full catalog.*") \
                        if len(services) > 5 else ""
                if len(shown) == 1:
                    reply = (
                        f"The **{shown[0]['name']}** service is **{shown[0]['cost']}**."
                    )
                else:
                    header = f"Here are the services matching **\"{_svc_kw}\"**:\n\n"
                    reply  = header + "\n".join(lines) + tail
            else:
                # TC2 — "list all services": show ONLY services, grouped by category
                # Group by the 'group' field (e.g. "AutoService", "Lubricants", etc.)
                from collections import defaultdict as _dd
                grouped: dict = _dd(list)
                for s in services:
                    grp = (s.get("group") or "Other Services").strip()
                    grouped[grp].append(s)

                sections = []
                for grp_name in sorted(grouped.keys()):
                    grp_svcs = grouped[grp_name]
                    lines = [f"• **{s['name']}** — {s['cost']}" for s in grp_svcs]
                    sections.append(f"**{grp_name}:**\n" + "\n".join(lines))

                header = f"Here are our **{total}** available {'service' if total == 1 else 'services'}:\n\n"
                reply  = header + "\n\n".join(sections)

            return {"reply": reply, "tool_calls": [{"tool": "get_service_prices", "args": {"service_name": _svc_kw}, "result": result}], "model": "none", "intent": intent}

    # -- SERVICE_COST (TC6) —  "how much will X cost including materials?" -----
    # Also handles: "estimate cost for X", "total cost with materials", etc.
    # Routes to estimate_service_cost which separates service charge from
    # materials and clearly shows service_charge + material_subtotal = total.
    if intent == SERVICE_COST or re.search(
        r"\b(how\s+much\s+will\s+.*(cost|be)"
        r"|including\s+(materials?|parts?|everything)"
        r"|estimated?\s+(total|cost|price)"
        r"|total\s+(cost|price|estimate)"
        r"|cost\s+(breakdown|including|with\s+materials?)"
        r"|estimate\s+(the\s+)?cost\s+for)\b",
        msg_l,
    ):
        from customer_tools import estimate_service_cost

        # Extract the service name from the message
        _est_svc = None
        _est_patterns = [
            # "how much will an Oil Change cost including materials"
            re.compile(
                r"how\s+much\s+will\s+(?:a\s+|an\s+|the\s+|my\s+)?(.+?)"
                r"\s+(?:cost|be)(?:\s+including|\s+with|\s+plus)?",
                re.IGNORECASE,
            ),
            # "estimate cost for an Oil Change"
            re.compile(
                r"estimate\s+(?:the\s+)?cost\s+for\s+(?:a\s+|an\s+|the\s+)?(.+?)\s*\??$",
                re.IGNORECASE,
            ),
            # "how much does an oil change cost"
            re.compile(
                r"how\s+much\s+(?:does|would|is)\s+(?:a\s+|an\s+|the\s+)?(.+?)"
                r"\s+(?:cost|be)\b",
                re.IGNORECASE,
            ),
            # "oil change including materials" — service before "including"
            re.compile(
                r"(.+?)\s+(?:including|with|plus)\s+(?:materials?|parts?)",
                re.IGNORECASE,
            ),
        ]
        for _ep in _est_patterns:
            _em = _ep.search(msg_l)
            if _em:
                _cand = _em.group(1).strip().rstrip(".,?!")
                _STOP = {
                    "it", "that", "this", "a service", "the service",
                    "service", "maintenance", "my oil", "my car",
                }
                if len(_cand) >= 3 and _cand not in _STOP:
                    _est_svc = _cand
                    break

        if not _est_svc:
            # No specific service named — ask which service
            return {
                "reply": (
                    "I'd be happy to give you a full cost estimate! "
                    "Which service would you like an estimate for? "
                    "(e.g. Oil Change, PMS, Brake Service)"
                ),
                "tool_calls": [],
                "model": "none",
                "intent": intent,
            }

        est = estimate_service_cost(
            customer_uid=customer_uid,
            customer_name=customer_name,
            service_names=[_est_svc],
        )
        if est.get("error") == "QUOTA_EXCEEDED":
            return {"reply": "Our database is temporarily unavailable due to a usage limit. Please try again in a few minutes.", "tool_calls": [{"tool": "estimate_service_cost", "args": {"service_names": [_est_svc]}, "result": est}], "model": "none", "intent": intent}
        if est.get("error"):
            return {"reply": "I wasn't able to retrieve pricing right now. Please try again.", "tool_calls": [{"tool": "estimate_service_cost", "args": {"service_names": [_est_svc]}, "result": est}], "model": "none", "intent": intent}

        matched = est.get("matched") or []
        if not matched:
            unmatched = est.get("unmatched") or [_est_svc]
            return {
                "reply": (
                    f"I couldn't find a service matching **\"{_est_svc}\"** in our catalog. "
                    "Try asking *\"list all services\"* to see what's available."
                ),
                "tool_calls": [{"tool": "estimate_service_cost", "args": {"service_names": [_est_svc]}, "result": est}],
                "model": "none",
                "intent": intent,
            }

        svc_name  = matched[0].get("service", _est_svc)
        # Build a service-only cost breakdown.
        # Materials are NOT included — customers are only charged for services.
        # When multiple services are requested, list each with its price and
        # show a combined total. For a single service, show it directly.

        if len(matched) == 1:
            # Single service — simple price display
            price = matched[0].get("cost", "—")
            reply = (
                f"The **{svc_name}** service is **{price}**."
            )
        else:
            # Multiple services — itemize and total
            lines = ["**Service Cost Estimate:**\n"]
            total_raw = 0.0
            for svc in matched:
                lines.append(f"• {svc['service']}: **{svc['cost']}**")
                # strip currency for summing
                import re as _re3
                raw = _re3.sub(r"[₱,\s]", "", svc.get("cost", "0"))
                try:
                    total_raw += float(raw)
                except ValueError:
                    pass
            lines.append(f"\n**Total: ₱{total_raw:,.2f}**")
            reply = "\n".join(lines)

        # Note about unmatched services if any
        unmatched = est.get("unmatched") or []
        if unmatched:
            reply += (
                f"\n\n*Note: I couldn't find pricing for: {', '.join(unmatched)}. "
                "Ask for the full service list to see all available options.*"
            )

        return {
            "reply": reply,
            "tool_calls": [{"tool": "estimate_service_cost", "args": {"service_names": [_est_svc]}, "result": est}],
            "model": "none",
            "intent": intent,
        }

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

    import perf_metrics
    _perf = perf_metrics.push(req.customer_uid, "customer", "?")
    try:
        # -- Step 1.5: admin runtime controls (ai_settings) ---------------------
        # customer_ai_enabled=False pauses the Customer AI for regular customers.
        # Developer/test accounts may be exempted via the admin's AI Usage
        # Controls (Profile → Settings → AI Usage Controls).
        import ai_settings
        _ai_enabled = ai_settings.is_customer_ai_enabled()
        _is_dev_user = False
        if not _ai_enabled:
            _is_dev_user = (
                (req.is_dev_user or False)
                and ai_settings.dev_access_allowed(paused=True)
            )
            if not _is_dev_user:
                perf_metrics.record_usage(0, 0)
                return ChatResponse(
                    reply=("The AI Assistant is temporarily unavailable. "
                           "Please try again later."),
                    session_id=session_id,
                    rate_limited=True,
                    reset_in="midnight",
                )
        elif req.is_dev_user and ai_settings.dev_access_allowed(paused=False):
            _is_dev_user = True

        # -- Step 2: daily usage limit -----------------------------------------
        _dev_bypass = _is_dev_user and ai_settings.dev_bypasses_token_limit()
        limit_check = usage_limiter.check_limit(
            req.customer_uid, role="customer", bypass_token_limit=_dev_bypass,
        )
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
        with perf_metrics.stage("intent"):
            intent = classify_customer_intent(req.message)
        _perf["intent"] = intent

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
            ik = _invalid_key_reply(e)
            return ChatResponse(
                reply=ik["reply"],
                session_id=session_id,
            )
        traceback.print_exc()
        return ChatResponse(
            reply="I'm having trouble processing your request right now. Please try again in a moment, or contact us at janobleenterpriseinc.autopro@gmail.com if the issue persists.",
            session_id=session_id,
        )
    finally:
        if _perf.get("intent") == "?":
            _perf["intent"] = "ERROR"
        perf_metrics.log_summary(_perf)
        perf_metrics.pop()


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


# -- Debug: Groq connectivity test --------------------------------------------

@app.get("/debug/test-groq")
def debug_test_groq():
    """
    Verify the complete Groq API request flow without sending a real chat message.

    Makes a minimal call (1 output token) to confirm:
      - GROQ_API_KEY is present and accepted by Groq
      - The configured model (GROQ_MODEL_PRIMARY) exists and is accessible
      - The SDK / network path is working end-to-end

    NEVER returns the raw API key — only the masked last-4 characters.
    Safe to call during development; not intended for production traffic checks.
    """
    import time as _time
    from api_key_manager import mask_key

    api_key   = _settings.GROQ_API_KEY
    model     = _settings.GROQ_MODEL_PRIMARY
    key_hint  = mask_key(api_key) if api_key else "(not set)"

    if not api_key:
        return {
            "ok":      False,
            "model":   model,
            "key":     key_hint,
            "error":   "GROQ_API_KEY is not set in the environment / .env file.",
            "elapsed_ms": 0,
        }

    t0 = _time.time()
    try:
        from client import get_groq_client
        client = get_groq_client(api_key)
        
        # Try with chat_template_kwargs first (new SDK), fallback without it
        try:
            resp = client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": "Reply with the single word: OK"}],
                max_tokens=5,
                chat_template_kwargs={"enable_thinking": False},
            )
        except TypeError as te:
            # Fallback for older Groq SDK versions that don't support chat_template_kwargs
            if "chat_template_kwargs" in str(te):
                resp = client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": "Reply with the single word: OK"}],
                    max_tokens=5,
                )
            else:
                raise
        
        elapsed_ms = round((_time.time() - t0) * 1000)
        content    = (resp.choices[0].message.content or "").strip()
        usage      = getattr(resp, "usage", None)
        return {
            "ok":           True,
            "model":        model,
            "key":          key_hint,
            "reply":        content,
            "prompt_tokens":     getattr(usage, "prompt_tokens",     None),
            "completion_tokens": getattr(usage, "completion_tokens", None),
            "elapsed_ms":   elapsed_ms,
        }
    except Exception as exc:
        import logging as _log
        _log.getLogger(__name__).error(
            "debug/test-groq failed. model=%s key=%s — %s: %s",
            model, key_hint, type(exc).__name__, exc,
        )
        elapsed_ms = round((_time.time() - t0) * 1000)
        return {
            "ok":         False,
            "model":      model,
            "key":        key_hint,
            "error_type": type(exc).__name__,
            # Surface the Groq error message so devs can see the real cause,
            # but never include the API key value itself.
            "error":      str(exc).replace(api_key, "***") if api_key in str(exc) else str(exc),
            "elapsed_ms": elapsed_ms,
        }
