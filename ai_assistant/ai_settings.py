"""
ai_settings.py — Admin-controlled runtime AI settings.

A single Firestore document (ai_settings/global) stores the admin's choices
made on  Profile → Settings → AI Usage Controls. Everything defaults to the
previous behavior, so the system works with no document at all.

Settings:
  customer_ai_enabled        — master pause for the Customer AI Assistant.
  customer_token_limit       — 0 = use the env default; >0 overrides it.
  dev_access_enabled         — allow developer/test users to use the Customer AI.
  dev_bypass_token_limit     — dev/test users skip the customer token quota.
  dev_access_while_paused    — dev/test users can chat while customer AI is paused.

A process-level cache (30 s TTL) keeps the per-request cost at zero Firestore
reads in steady state; a single read at most every 30 s across all instances.
The admin UI always busts the cache after saving so changes apply immediately.
"""

import logging
import os
import threading
import time

logger = logging.getLogger(__name__)

_COLLECTION = "ai_settings"
_DOC_ID     = "global"
_CACHE_TTL  = 30.0  # seconds

_lock  = threading.Lock()
_cache: dict | None = None
_cache_at: float = 0.0

# AI_SETTINGS_PERSIST=0 keeps everything in memory (tests / dev without
# Firestore credentials). Production default persists to Firestore.
_PERSIST = os.getenv("AI_SETTINGS_PERSIST", "1") not in ("0", "false", "False")

DEFAULTS: dict = {
    "customer_ai_enabled":     True,
    "customer_token_limit":    0,      # 0 = use CUSTOMER_DAILY_TOKEN_LIMIT env
    "dev_access_enabled":      False,
    "dev_bypass_token_limit":  False,
    "dev_access_while_paused": False,
}


def _collection_ref():
    from firestore_client import get_db
    return get_db().collection(_COLLECTION)


def _load() -> dict:
    """Return the merged settings dict (cache-first; zero reads in steady state)."""
    global _cache, _cache_at
    now = time.time()
    if _cache is not None and (now - _cache_at) < _CACHE_TTL:
        return _cache
    with _lock:
        # Double-checked: another thread may have refreshed while we waited.
        now = time.time()
        if _cache is not None and (now - _cache_at) < _CACHE_TTL:
            return _cache
        merged = dict(DEFAULTS)
        try:
            if not _PERSIST:
                _cache    = merged
                _cache_at = time.time()
                return merged
            snap = _collection_ref().document(_DOC_ID).get()
            if snap.exists:
                d = snap.to_dict() or {}
                for k in DEFAULTS:
                    if k in d and d[k] is not None:
                        merged[k] = d[k]
                # Guard against a nonsense limit (negative or non-int)
                try:
                    merged["customer_token_limit"] = max(0, int(merged["customer_token_limit"]))
                except (TypeError, ValueError):
                    merged["customer_token_limit"] = 0
        except Exception as exc:
            logger.warning("ai_settings: load failed (%s) — using defaults", exc)
        _cache    = merged
        _cache_at = time.time()
        return merged


def get_settings() -> dict:
    """Public accessor — returns a copy so callers cannot mutate the cache."""
    return dict(_load())


def save_settings(updates: dict) -> dict:
    """
    Persist admin changes and bust the cache. Only whitelisted keys are
    written; unknown keys are ignored (defensive against API misuse).
    """
    global _cache, _cache_at
    clean = {}
    for k in DEFAULTS:
        if k not in updates:
            continue
        v = updates[k]
        if k == "customer_token_limit":
            try:
                v = max(0, int(v))
            except (TypeError, ValueError):
                continue
        elif k in ("customer_ai_enabled", "dev_access_enabled",
                   "dev_bypass_token_limit", "dev_access_while_paused"):
            v = bool(v)
        clean[k] = v

    with _lock:
        if _PERSIST:
            _collection_ref().document(_DOC_ID).set(
                {**clean, "updatedAt": time.time()}, merge=True
            )
            # Bust cache so the next check re-reads immediately.
            _cache    = None
            _cache_at = 0.0
        else:
            # Memory-only mode: apply onto the cached/default state.
            base = dict(_cache) if _cache is not None else dict(DEFAULTS)
            base.update(clean)
            _cache    = base
            _cache_at = time.time()
    logger.info("ai_settings: saved %s", sorted(clean.keys()))
    return get_settings()


def is_customer_ai_enabled() -> bool:
    return bool(_load().get("customer_ai_enabled", True))


def customer_token_limit() -> int:
    """0 means 'no admin override' — usage_limiter falls back to its env value."""
    return int(_load().get("customer_token_limit", 0) or 0)


def dev_access_allowed(paused: bool) -> bool:
    """Whether developer/test users may use the Customer AI right now."""
    s = _load()
    if not s.get("dev_access_enabled", False):
        return False
    if paused and not s.get("dev_access_while_paused", False):
        return False
    return True


def dev_bypasses_token_limit() -> bool:
    s = _load()
    return bool(s.get("dev_access_enabled", False) and s.get("dev_bypass_token_limit", False))


def clear_cache_for_tests() -> None:
    global _cache, _cache_at
    with _lock:
        _cache    = None
        _cache_at = 0.0


def is_persisted() -> bool:
    return os.getenv("AI_SETTINGS_PERSIST", "1") not in ("0", "false", "False")
