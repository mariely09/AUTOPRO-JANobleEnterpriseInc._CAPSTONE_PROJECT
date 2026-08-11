"""
token_tracker.py — In-memory token usage monitoring.

Records every Groq LLM call:
  - user_id / user_role
  - model used
  - intent / request type
  - input + output + total tokens
  - response time
  - success/failure

No prompt content or raw database data is stored — only counts and metadata.

Thread-safe via threading.Lock.  Resets automatically at midnight (lazy reset
on the first call of a new calendar day).
"""
import threading
import time
from collections import defaultdict
from datetime import date, datetime


_lock = threading.Lock()

# ── Daily counters (reset at midnight) ───────────────────────────────────────
_today_date: date = date.today()

# Usage by dimension
_daily: dict = {
    "input_tokens":  0,
    "output_tokens": 0,
    "total_tokens":  0,
    "requests":      0,
    "errors":        0,
}
_by_model:  dict = defaultdict(lambda: {"input": 0, "output": 0, "total": 0, "requests": 0})
_by_role:   dict = defaultdict(lambda: {"input": 0, "output": 0, "total": 0, "requests": 0})
_by_user:   dict = defaultdict(lambda: {"input": 0, "output": 0, "total": 0, "requests": 0})
_by_intent: dict = defaultdict(lambda: {"input": 0, "output": 0, "total": 0, "requests": 0})

# Recent call log (last 200 entries, no raw content)
_MAX_LOG = 200
_log: list[dict] = []

# Response-time tracking
_total_response_ms = 0.0
_rate_limit_events = 0


def _reset_if_new_day() -> None:
    """Lazy daily reset — called inside the lock before every read/write."""
    global _today_date, _total_response_ms, _rate_limit_events
    today = date.today()
    if today != _today_date:
        _today_date = today
        _daily.update({"input_tokens": 0, "output_tokens": 0,
                        "total_tokens": 0, "requests": 0, "errors": 0})
        _by_model.clear()
        _by_role.clear()
        _by_user.clear()
        _by_intent.clear()
        _total_response_ms = 0.0
        _rate_limit_events = 0


# ── Public API ────────────────────────────────────────────────────────────────

def record(
    *,
    user_id:        str,
    role:           str,           # "admin" | "customer"
    model:          str,
    intent:         str,           # e.g. DATABASE_LOOKUP, GENERAL_AI_QUESTION, …
    input_tokens:   int,
    output_tokens:  int,
    response_ms:    float  = 0.0,
    success:        bool   = True,
    rate_limited:   bool   = False,
) -> None:
    """Record one LLM call.  Call this AFTER the Groq API returns."""
    global _total_response_ms, _rate_limit_events
    total = input_tokens + output_tokens

    with _lock:
        _reset_if_new_day()

        _daily["input_tokens"]  += input_tokens
        _daily["output_tokens"] += output_tokens
        _daily["total_tokens"]  += total
        _daily["requests"]      += 1
        if not success:
            _daily["errors"] += 1

        _by_model[model]["input"]    += input_tokens
        _by_model[model]["output"]   += output_tokens
        _by_model[model]["total"]    += total
        _by_model[model]["requests"] += 1

        _by_role[role]["input"]    += input_tokens
        _by_role[role]["output"]   += output_tokens
        _by_role[role]["total"]    += total
        _by_role[role]["requests"] += 1

        _by_user[user_id]["input"]    += input_tokens
        _by_user[user_id]["output"]   += output_tokens
        _by_user[user_id]["total"]    += total
        _by_user[user_id]["requests"] += 1

        _by_intent[intent]["input"]    += input_tokens
        _by_intent[intent]["output"]   += output_tokens
        _by_intent[intent]["total"]    += total
        _by_intent[intent]["requests"] += 1

        _total_response_ms += response_ms
        if rate_limited:
            _rate_limit_events += 1

        entry = {
            "ts":         datetime.utcnow().isoformat(timespec="seconds") + "Z",
            "user_id":    user_id,
            "role":       role,
            "model":      model,
            "intent":     intent,
            "input":      input_tokens,
            "output":     output_tokens,
            "total":      total,
            "resp_ms":    round(response_ms),
            "success":    success,
            "rate_limited": rate_limited,
        }
        _log.append(entry)
        if len(_log) > _MAX_LOG:
            del _log[0]


def get_daily_summary() -> dict:
    """Return a snapshot of today's usage statistics."""
    with _lock:
        _reset_if_new_day()
        requests = _daily["requests"]
        avg_tokens = (
            round(_daily["total_tokens"] / requests)
            if requests else 0
        )
        avg_resp_ms = (
            round(_total_response_ms / requests)
            if requests else 0
        )
        return {
            "date":              _today_date.isoformat(),
            "input_tokens":      _daily["input_tokens"],
            "output_tokens":     _daily["output_tokens"],
            "total_tokens":      _daily["total_tokens"],
            "requests":          requests,
            "errors":            _daily["errors"],
            "avg_tokens_per_req": avg_tokens,
            "avg_response_ms":   avg_resp_ms,
            "rate_limit_events": _rate_limit_events,
            "by_model":          {k: dict(v) for k, v in _by_model.items()},
            "by_role":           {k: dict(v) for k, v in _by_role.items()},
            "by_intent":         {k: dict(v) for k, v in _by_intent.items()},
        }


def get_recent_log(n: int = 50) -> list[dict]:
    """Return the last *n* log entries (no raw prompt/response content)."""
    with _lock:
        return list(_log[-n:])
