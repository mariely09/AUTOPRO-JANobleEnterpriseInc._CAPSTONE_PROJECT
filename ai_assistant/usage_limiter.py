"""
usage_limiter.py — Daily AI token/request limits per user role.

Enforces configurable daily usage caps for customers and admins.
Resets automatically at midnight (lazy reset on first call of a new day).
Limits are stored in memory — they reset on server restart, which is
acceptable because the Groq free-tier quota also resets daily.

CONFIGURATION (edit the constants below or override via .env):
  CUSTOMER_DAILY_TOKEN_LIMIT   — max total tokens (input + output) per customer per day
  ADMIN_DAILY_TOKEN_LIMIT      — max total tokens for the admin (set high or 0 for unlimited)
  CUSTOMER_DAILY_REQUEST_LIMIT — max number of AI requests per customer per day (0 = unlimited)
  ADMIN_DAILY_REQUEST_LIMIT    — max number of AI requests for admin (0 = unlimited)

Set any limit to 0 to disable it (unlimited usage for that role/dimension).

Thread-safe via threading.Lock.
"""

import os
import threading
import logging
from datetime import date, datetime
from collections import defaultdict

logger = logging.getLogger(__name__)

# ── Configurable limits ───────────────────────────────────────────────────────
# Edit these or set the corresponding env vars.

# Customer: 20,000 tokens/day (~40 typical conversations of 500 tokens each)
CUSTOMER_DAILY_TOKEN_LIMIT:   int = int(os.getenv("CUSTOMER_DAILY_TOKEN_LIMIT",   "20000"))

# Customer: max 50 requests/day (prevents spam)
CUSTOMER_DAILY_REQUEST_LIMIT: int = int(os.getenv("CUSTOMER_DAILY_REQUEST_LIMIT", "50"))

# Admin: very high limit (effectively unlimited on Groq free tier)
# Set to 0 to make admin truly unlimited.
ADMIN_DAILY_TOKEN_LIMIT:      int = int(os.getenv("ADMIN_DAILY_TOKEN_LIMIT",      "0"))   # 0 = unlimited

# Admin: no request cap
ADMIN_DAILY_REQUEST_LIMIT:    int = int(os.getenv("ADMIN_DAILY_REQUEST_LIMIT",    "0"))   # 0 = unlimited

# Human-readable cap labels shown in the limit-reached message
_TOKEN_LABELS = {
    "customer": f"{CUSTOMER_DAILY_TOKEN_LIMIT:,}" if CUSTOMER_DAILY_TOKEN_LIMIT else "unlimited",
    "admin":    f"{ADMIN_DAILY_TOKEN_LIMIT:,}"    if ADMIN_DAILY_TOKEN_LIMIT    else "unlimited",
}

# ── Internal state ────────────────────────────────────────────────────────────

_lock       = threading.Lock()
_today_date = date.today()

# user_id → {"tokens": int, "requests": int, "role": str}
_usage: dict[str, dict] = defaultdict(lambda: {"tokens": 0, "requests": 0, "role": "customer"})


def _reset_if_new_day() -> None:
    """Lazy daily reset — called inside the lock before every read/write."""
    global _today_date
    today = date.today()
    if today != _today_date:
        _today_date = today
        _usage.clear()
        logger.info("usage_limiter: daily counters reset for %s", today.isoformat())


# ── Public API ────────────────────────────────────────────────────────────────

def check_limit(user_id: str, role: str) -> dict:
    """
    Check whether a user is within their daily limit BEFORE the LLM call.

    Returns:
        {
            "allowed": bool,           — True = proceed, False = blocked
            "reason":  str,            — empty if allowed; human-readable if blocked
            "tokens_used":   int,      — tokens consumed today by this user
            "requests_used": int,      — requests made today by this user
            "token_limit":   int,      — daily token cap (0 = unlimited)
            "request_limit": int,      — daily request cap (0 = unlimited)
        }
    """
    with _lock:
        _reset_if_new_day()

        entry = _usage[user_id]
        entry["role"] = role

        token_limit   = CUSTOMER_DAILY_TOKEN_LIMIT   if role == "customer" else ADMIN_DAILY_TOKEN_LIMIT
        request_limit = CUSTOMER_DAILY_REQUEST_LIMIT if role == "customer" else ADMIN_DAILY_REQUEST_LIMIT

        tokens_used   = entry["tokens"]
        requests_used = entry["requests"]

        # Check token cap (0 = unlimited)
        if token_limit > 0 and tokens_used >= token_limit:
            reset_at = _next_midnight_str()
            reason = (
                f"You've reached your daily AI usage limit of {token_limit:,} tokens. "
                f"Your limit resets automatically at midnight ({reset_at}). "
                f"Please try again tomorrow."
            )
            logger.info(
                "usage_limiter: BLOCKED user_id=%s role=%s tokens=%d limit=%d",
                user_id, role, tokens_used, token_limit,
            )
            return {
                "allowed":       False,
                "reason":        reason,
                "tokens_used":   tokens_used,
                "requests_used": requests_used,
                "token_limit":   token_limit,
                "request_limit": request_limit,
            }

        # Check request cap (0 = unlimited)
        if request_limit > 0 and requests_used >= request_limit:
            reset_at = _next_midnight_str()
            reason = (
                f"You've reached your daily AI request limit of {request_limit} requests. "
                f"Your limit resets automatically at midnight ({reset_at}). "
                f"Please try again tomorrow."
            )
            logger.info(
                "usage_limiter: BLOCKED user_id=%s role=%s requests=%d limit=%d",
                user_id, role, requests_used, request_limit,
            )
            return {
                "allowed":       False,
                "reason":        reason,
                "tokens_used":   tokens_used,
                "requests_used": requests_used,
                "token_limit":   token_limit,
                "request_limit": request_limit,
            }

        return {
            "allowed":       True,
            "reason":        "",
            "tokens_used":   tokens_used,
            "requests_used": requests_used,
            "token_limit":   token_limit,
            "request_limit": request_limit,
        }


def record_usage(user_id: str, role: str,
                 input_tokens: int, output_tokens: int) -> None:
    """
    Add the actual token counts after the LLM call completes.
    Called by the chat endpoints AFTER the LLM returns.
    """
    total = input_tokens + output_tokens
    with _lock:
        _reset_if_new_day()
        entry = _usage[user_id]
        entry["role"]     = role
        entry["tokens"]   += total
        entry["requests"] += 1

    logger.debug(
        "usage_limiter: recorded user_id=%s role=%s +%d tokens "
        "(day total=%d)", user_id, role, total, entry["tokens"],
    )


def get_user_usage(user_id: str, role: str = "customer") -> dict:
    """
    Return today's usage stats for a specific user.
    Safe to call from the frontend to show remaining quota.
    """
    with _lock:
        _reset_if_new_day()
        entry = _usage.get(user_id, {"tokens": 0, "requests": 0, "role": role})
        token_limit   = CUSTOMER_DAILY_TOKEN_LIMIT   if role == "customer" else ADMIN_DAILY_TOKEN_LIMIT
        request_limit = CUSTOMER_DAILY_REQUEST_LIMIT if role == "customer" else ADMIN_DAILY_REQUEST_LIMIT

        tokens_remaining = (
            max(0, token_limit - entry["tokens"]) if token_limit > 0 else None
        )
        requests_remaining = (
            max(0, request_limit - entry["requests"]) if request_limit > 0 else None
        )

        return {
            "user_id":            user_id,
            "role":               role,
            "date":               _today_date.isoformat(),
            "tokens_used":        entry["tokens"],
            "requests_used":      entry["requests"],
            "token_limit":        token_limit,
            "request_limit":      request_limit,
            "tokens_remaining":   tokens_remaining,
            "requests_remaining": requests_remaining,
            "resets_at":          _next_midnight_str(),
        }


def get_all_usage() -> dict:
    """Return today's usage for ALL users (admin dashboard use only)."""
    with _lock:
        _reset_if_new_day()
        return {
            "date": _today_date.isoformat(),
            "users": {
                uid: dict(entry)
                for uid, entry in _usage.items()
            },
            "limits": {
                "customer": {
                    "tokens":   CUSTOMER_DAILY_TOKEN_LIMIT,
                    "requests": CUSTOMER_DAILY_REQUEST_LIMIT,
                },
                "admin": {
                    "tokens":   ADMIN_DAILY_TOKEN_LIMIT,
                    "requests": ADMIN_DAILY_REQUEST_LIMIT,
                },
            },
        }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _next_midnight_str() -> str:
    """Return a human-readable string for when the daily reset occurs."""
    now   = datetime.now()
    reset = now.replace(hour=0, minute=0, second=0, microsecond=0)
    # Add 1 day
    from datetime import timedelta
    reset = reset + timedelta(days=1)
    return reset.strftime("%B %d, %Y at 12:00 AM")
