"""
usage_limiter.py — Daily AI token/request limits per user role.

REDESIGNED for Cloud Run correctness + read efficiency:

  • Quota day boundaries follow ASIA/MANILA (ZoneInfo), not the server clock.
  • Counters persist in Firestore (ai_usage_daily/{uid}_{YYYY-MM-DD}) so they
    survive instance restarts and are shared across Cloud Run instances.
    NOTE: writes go to Firestore; READS for the current day are served from an
    in-memory mirror to avoid a Firestore read on every chat request.  After a
    cold start the mirror is empty, so the first check of the day performs one
    read; after that, reads are free and only writes hit Firestore.
  • Limits are env-configurable (0 = unlimited for that role/dimension).
  • check_limit() runs BEFORE any Groq call; record_usage() after it.
  • Quota is keyed by the authenticated user id — refresh/relogin/new
    sessions/devices cannot bypass it.
"""

import os
import threading
import logging
from datetime import date, datetime, timedelta, timezone as _dt_timezone
from collections import defaultdict

logger = logging.getLogger(__name__)

# ── Timezone: quota resets at the start of the Philippine calendar day ────────
# Asia/Manila is UTC+8 year-round (no DST), so a fixed offset is exact here and
# avoids a hard dependency on the tzdata OS database (missing on some Windows
# minimal environments).  Linux/Cloud Run containers satisfy both paths.
_MANILA_OFFSET = _dt_timezone(timedelta(hours=8))


def _manila_now() -> datetime:
    return datetime.now(_MANILA_OFFSET)


def _manila_today() -> date:
    """Current calendar date in Asia/Manila."""
    return _manila_now().date()


def _next_manila_midnight_str() -> str:
    """Human-readable time of the next quota reset (Asia/Manila)."""
    now   = _manila_now()
    reset = (now.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1))
    return reset.strftime("%B %d, %Y at 12:00 AM (PH time)")

# ── Configurable limits (env-overridable, 0 = unlimited) ─────────────────────
CUSTOMER_DAILY_TOKEN_LIMIT:   int = int(os.getenv("CUSTOMER_DAILY_TOKEN_LIMIT",   "100000"))
CUSTOMER_DAILY_REQUEST_LIMIT: int = int(os.getenv("CUSTOMER_DAILY_REQUEST_LIMIT", "50"))
ADMIN_DAILY_TOKEN_LIMIT:      int = int(os.getenv("ADMIN_DAILY_TOKEN_LIMIT",      "200000"))  # high but finite; 0 = unlimited
ADMIN_DAILY_REQUEST_LIMIT:    int = int(os.getenv("ADMIN_DAILY_REQUEST_LIMIT",    "200"))   # 0 = unlimited

# ── Firestore persistence ─────────────────────────────────────────────────────
_PERSIST = os.getenv("AI_QUOTA_PERSIST", "1") not in ("0", "false", "False")
_COLLECTION = "ai_usage_daily"

_lock: threading.Lock = threading.Lock()
_mirror_date: date | None = None
# user_id → {"tokens": int, "requests": int, "role": str, "dirty": bool}
_mirror: dict[str, dict] = defaultdict(lambda: {"tokens": 0, "requests": 0, "role": "customer", "dirty": False})


def _day_key(user_id: str) -> str:
    return f"{user_id}_{_manila_today().isoformat()}"


def _reset_if_new_day() -> None:
    """Swap the in-memory mirror when the Manila calendar day changes."""
    global _mirror_date
    today = _manila_today()
    if _mirror_date != today:
        _mirror_date = today
        _mirror.clear()
        logger.info("usage_limiter: daily counters reset for %s (Asia/Manila)", today.isoformat())


def _load_user(user_id: str) -> dict:
    """
    Ensure the mirror entry for *user_id* reflects today's persisted counters.
    One Firestore read per user per day (only when not already in the mirror).
    """
    global _mirror_date
    if _mirror_date is None:
        _reset_if_new_day()
    entry = _mirror.get(user_id)
    if entry is not None and not entry.get("dirty"):
        return entry
    # Only hydrate from Firestore if this user hasn't been loaded today
    if entry is not None and entry.get("loaded"):
        return entry
    if not _PERSIST:
        _mirror[user_id].setdefault("loaded", True)
        return _mirror[user_id]
    try:
        from firestore_client import get_db
        db = get_db()
        snap = db.collection(_COLLECTION).document(_day_key(user_id)).get()
        loaded = {"tokens": 0, "requests": 0, "role": "customer", "dirty": False, "loaded": True}
        if snap.exists:
            d = snap.to_dict() or {}
            loaded["tokens"]   = int(d.get("tokens", 0) or 0)
            loaded["requests"] = int(d.get("requests", 0) or 0)
            loaded["role"]     = d.get("role", "customer")
        _mirror[user_id] = loaded
        return loaded
    except Exception as exc:
        logger.warning("usage_limiter: persistence unavailable (%s) — memory-only mode", exc)
        e = _mirror.get(user_id)
        if e is None:
            e = {"tokens": 0, "requests": 0, "role": "customer", "dirty": False, "loaded": True}
            _mirror[user_id] = e
        e["loaded"] = True
        return e


def _persist_user(user_id: str, entry: dict) -> None:
    """Write the user's counters for today to Firestore (best-effort)."""
    if not _PERSIST:
        return
    try:
        from firestore_client import get_db
        db = get_db()
        db.collection(_COLLECTION).document(_day_key(user_id)).set({
            "tokens":    entry["tokens"],
            "requests":  entry["requests"],
            "role":      entry["role"],
            "updatedAt": _manila_now().isoformat(),
        }, merge=True)
        entry["dirty"] = False
    except Exception as exc:
        logger.warning("usage_limiter: persist failed for %s: %s", user_id, exc)


def _limits_for(role: str, bypass_token_limit: bool = False) -> tuple[int, int]:
    """
    Token limit resolution for a role:
      customer: admin runtime override (ai_settings) wins when set (>0),
                otherwise the env-configured default.
      admin:    env-configured value (not admin-overridable at runtime).
    bypass_token_limit=True (developer/test access) removes the token cap
    entirely (0 = unlimited) while still enforcing the request-rate cap.
    """
    if role == "customer":
        token_limit = CUSTOMER_DAILY_TOKEN_LIMIT
        try:
            import ai_settings
            override = ai_settings.customer_token_limit()
            if override > 0:
                token_limit = override
        except Exception:
            pass
        if bypass_token_limit:
            token_limit = 0
        return token_limit, CUSTOMER_DAILY_REQUEST_LIMIT
    return ADMIN_DAILY_TOKEN_LIMIT, ADMIN_DAILY_REQUEST_LIMIT


# ── Public API ────────────────────────────────────────────────────────────────

def check_limit(user_id: str, role: str, bypass_token_limit: bool = False) -> dict:
    """
    Check whether a user is within their daily limit BEFORE the LLM call.
    Zero Firestore reads when the user is already in today's mirror.

    bypass_token_limit=True marks a developer/test user whose account the
    admin has exempted from the customer token quota (rate cap still applies).
    """
    with _lock:
        _reset_if_new_day()
        entry = _load_user(user_id)
        entry["role"] = role

        token_limit, request_limit = _limits_for(role, bypass_token_limit)
        tokens_used, requests_used = entry["tokens"], entry["requests"]

        if token_limit > 0 and tokens_used >= token_limit:
            logger.info("usage_limiter: BLOCKED user_id=%s role=%s tokens=%d limit=%d",
                        user_id, role, tokens_used, token_limit)
            return _blocked(role, "token", tokens_used, requests_used, token_limit, request_limit)
        if request_limit > 0 and requests_used >= request_limit:
            logger.info("usage_limiter: BLOCKED user_id=%s role=%s requests=%d limit=%d",
                        user_id, role, requests_used, request_limit)
            return _blocked(role, "request", tokens_used, requests_used, token_limit, request_limit)

        return {
            "allowed": True, "reason": "",
            "tokens_used": tokens_used, "requests_used": requests_used,
            "token_limit": token_limit, "request_limit": request_limit,
        }


def _blocked(role, kind, tokens_used, requests_used, token_limit, request_limit) -> dict:
    reset_at = _next_manila_midnight_str()
    if kind == "token":
        reason = (f"You've reached your daily AI usage limit of {token_limit:,} tokens. "
                  f"Your limit resets automatically at {reset_at}. Please try again tomorrow.")
    else:
        reason = (f"You've reached your daily AI request limit of {request_limit} requests. "
                  f"Your limit resets automatically at {reset_at}. Please try again tomorrow.")
    return {
        "allowed": False, "reason": reason,
        "tokens_used": tokens_used, "requests_used": requests_used,
        "token_limit": token_limit, "request_limit": request_limit,
    }


def record_usage(user_id: str, role: str, input_tokens: int, output_tokens: int) -> None:
    """Add actual token counts after the LLM call completes, then persist."""
    total = input_tokens + output_tokens
    with _lock:
        _reset_if_new_day()
        entry = _load_user(user_id)
        entry["role"]     = role
        entry["tokens"]  += total
        entry["requests"] += 1
        entry["dirty"]    = True
        entry["loaded"]   = True
    # Persist outside the lock (I/O); best-effort
    _persist_user(user_id, entry)

    logger.debug("usage_limiter: recorded user_id=%s role=%s +%d tokens (day total=%d)",
                 user_id, role, total, entry["tokens"])


def get_user_usage(user_id: str, role: str = "customer",
                   bypass_token_limit: bool = False) -> dict:
    """Today's usage stats for a specific user (frontend quota banner)."""
    with _lock:
        _reset_if_new_day()
        entry = _load_user(user_id)
        token_limit, request_limit = _limits_for(role, bypass_token_limit)
        return {
            "user_id": user_id, "role": role,
            "date": _manila_today().isoformat(),
            "tokens_used": entry["tokens"], "requests_used": entry["requests"],
            "token_limit": token_limit, "request_limit": request_limit,
            "tokens_remaining":   max(0, token_limit - entry["tokens"]) if token_limit > 0 else None,
            "requests_remaining": max(0, request_limit - entry["requests"]) if request_limit > 0 else None,
            "resets_at": _next_manila_midnight_str(),
        }


def get_all_usage() -> dict:
    """Today's usage for ALL users (admin dashboard; memory mirror only)."""
    with _lock:
        _reset_if_new_day()
        return {
            "date": _manila_today().isoformat(),
            "timezone": "Asia/Manila",
            "users": {uid: {k: v for k, v in e.items() if k != "dirty"} for uid, e in _mirror.items()},
            "limits": {
                "customer": {"tokens": CUSTOMER_DAILY_TOKEN_LIMIT, "requests": CUSTOMER_DAILY_REQUEST_LIMIT},
                "admin":    {"tokens": ADMIN_DAILY_TOKEN_LIMIT,    "requests": ADMIN_DAILY_REQUEST_LIMIT},
            },
        }


def _admin_ai_usage_note() -> None:  # pragma: no cover — documentation hook
    """
    Admin usage dashboard reads the in-memory mirror via get_all_usage().
    Multi-instance deployments should read the ai_usage_daily collection
    directly (one range query on the day prefix) rather than per-user reads.
    """
