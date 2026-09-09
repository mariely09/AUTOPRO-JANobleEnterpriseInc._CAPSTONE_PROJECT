"""
answer_cache.py — TTL cache for repeated NON-PERSONAL questions.

Only general-educational answers (intent GENERAL_AI_QUESTION) are cached.
Personal answers (vehicles, bookings, history) are NEVER cached here —
the key would have to include the user id and stale personal data is a
correctness risk, so we simply don't cache them.

Effect: a repeated "What is an oil change?" costs ZERO Groq tokens.
Thread-safe, bounded size, short TTL so content stays fresh.
"""
import hashlib
import threading
import time

_TTL_SECONDS      = 600      # 10 minutes
_MAX_ENTRIES      = 200

_lock = threading.Lock()
_store: dict[str, tuple[float, str]] = {}   # key → (expires_at, reply)


def _norm_key(message: str) -> str:
    """Normalize a question into a cache key (case/punct/whitespace-insensitive)."""
    import re
    t = re.sub(r"[^a-z0-9\s]", " ", message.lower())
    t = re.sub(r"\s+", " ", t).strip()
    return hashlib.sha1(t.encode("utf-8")).hexdigest()


def get(message: str) -> str | None:
    """Return the cached reply for this exact (normalized) question, or None."""
    key = _norm_key(message)
    with _lock:
        entry = _store.get(key)
        if entry is None:
            return None
        expires_at, reply = entry
        if time.monotonic() > expires_at:
            del _store[key]
            return None
        return reply


def put(message: str, reply: str) -> None:
    """Cache a non-personal reply (best-effort, bounded)."""
    if not message or not reply:
        return
    key  = _norm_key(message)
    now  = time.monotonic()
    with _lock:
        # Bound the cache: drop the oldest entry when full
        if len(_store) >= _MAX_ENTRIES:
            oldest = min(_store.items(), key=lambda kv: kv[1][0])
            del _store[oldest[0]]
        _store[key] = (now + _TTL_SECONDS, reply)


def stats() -> dict:
    with _lock:
        now = time.monotonic()
        live = sum(1 for exp, _ in _store.values() if exp > now)
        return {"entries": live, "max_entries": _MAX_ENTRIES, "ttl_s": _TTL_SECONDS}
