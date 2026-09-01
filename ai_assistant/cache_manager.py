"""
cache_manager.py — Shared in-memory cache for frequently-read Firestore data.

Caches public/shared data that does NOT change per-user:
  - item_master (services catalog + prices)  TTL: 10 minutes
  - stock_inventory (stock levels)           TTL: 5 minutes

Per-user data (vehicles, maintenance, bookings) is NOT cached here because:
  - It changes more often (e.g., after a booking is confirmed)
  - It is already filtered server-side; caching would require a per-user key

Thread-safe via threading.Lock.

Usage:
    from cache_manager import get_service_catalog, invalidate
"""

import threading
import time
import logging
from typing import Any

logger = logging.getLogger(__name__)

# ── TTL constants (seconds) ───────────────────────────────────────────────────
TTL_SERVICE_CATALOG = 600   # 10 minutes — services/prices rarely change
TTL_STOCK_INVENTORY = 300   # 5  minutes — stock changes more often
TTL_USER_LOOKUP     = 300   # 5  minutes — admin user lookup table
TTL_VEHICLE_LOOKUP  = 180   # 3  minutes — vehicle lookup table

# ── Internal store ────────────────────────────────────────────────────────────
_lock  = threading.Lock()
_store: dict[str, tuple[float, Any]] = {}   # key → (expires_at, data)


# ── Generic get/set ───────────────────────────────────────────────────────────

def _get(key: str) -> Any | None:
    """Return cached value or None if absent/expired."""
    with _lock:
        entry = _store.get(key)
        if entry is None:
            return None
        expires_at, data = entry
        if time.monotonic() > expires_at:
            del _store[key]
            return None
        return data


def _set(key: str, data: Any, ttl: int) -> None:
    """Store data under key with the given TTL in seconds."""
    with _lock:
        _store[key] = (time.monotonic() + ttl, data)


def invalidate(key: str | None = None) -> None:
    """
    Invalidate one cache entry by key, or flush ALL entries if key is None.
    Call this after a write operation (e.g., admin adds a new service).
    """
    with _lock:
        if key is None:
            _store.clear()
            logger.info("cache_manager: full cache invalidated")
        else:
            removed = _store.pop(key, None)
            if removed:
                logger.debug("cache_manager: invalidated key=%r", key)


# ── Service catalog (item_master, type=Service) ───────────────────────────────

_KEY_SERVICE_CATALOG = "service_catalog"


def get_service_catalog(db=None) -> list[dict] | None:
    """
    Return the cached service catalog, or None if the cache is cold/expired.
    If db is provided and cache is cold, fetches from Firestore and warms the cache.
    """
    cached = _get(_KEY_SERVICE_CATALOG)
    if cached is not None:
        logger.debug("cache_manager: service_catalog HIT (%d items)", len(cached))
        return cached

    if db is None:
        return None

    # Cache miss — fetch from Firestore
    logger.info("cache_manager: service_catalog MISS — fetching from Firestore")
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter
        docs = list(
            db.collection("item_master")
            .where(filter=FieldFilter("type", "==", "Service"))
            .stream()
        )
        items = []
        for doc in docs:
            d = doc.to_dict()
            items.append({
                "num":   d.get("num", ""),
                "name":  d.get("name", ""),
                "type":  d.get("type", ""),
                "group": d.get("group", ""),
                "uom":   d.get("uom", ""),
                "cost":  d.get("cost", 0),
            })
        items.sort(key=lambda s: s["name"])
        _set(_KEY_SERVICE_CATALOG, items, TTL_SERVICE_CATALOG)
        logger.info("cache_manager: service_catalog cached (%d items, TTL=%ds)",
                    len(items), TTL_SERVICE_CATALOG)
        return items
    except Exception as exc:
        logger.error("cache_manager: failed to fetch service_catalog: %s", exc)
        return None


def warm_service_catalog(db) -> list[dict]:
    """Force-refresh the service catalog cache. Returns the fresh list."""
    invalidate(_KEY_SERVICE_CATALOG)
    result = get_service_catalog(db)
    return result or []


# ── Full item catalog (item_master, all types) ────────────────────────────────

_KEY_ITEM_CATALOG_ALL      = "item_catalog_all"
_KEY_ITEM_CATALOG_MATERIAL = "item_catalog_material"


def get_item_catalog_cached(db=None, item_type: str | None = None) -> list[dict] | None:
    """
    Return the cached item catalog (all types or filtered by item_type).
    item_type: None → all  |  "Service" → services  |  "Material" → materials
    """
    key = (
        _KEY_SERVICE_CATALOG     if item_type == "Service"  else
        _KEY_ITEM_CATALOG_MATERIAL if item_type == "Material" else
        _KEY_ITEM_CATALOG_ALL
    )
    cached = _get(key)
    if cached is not None:
        return cached

    if db is None:
        return None

    logger.info("cache_manager: item_catalog MISS (type=%r) — fetching", item_type)
    try:
        from google.cloud.firestore_v1.base_query import FieldFilter
        query = db.collection("item_master")
        if item_type:
            query = query.where(filter=FieldFilter("type", "==", item_type))
        docs = list(query.stream())
        items = []
        for doc in docs:
            d = doc.to_dict()
            items.append({
                "num":   d.get("num", ""),
                "name":  d.get("name", ""),
                "type":  d.get("type", ""),
                "group": d.get("group", ""),
                "uom":   d.get("uom", ""),
                "cost":  d.get("cost", 0),
            })
        items.sort(key=lambda s: (s["type"], s["name"]))
        _set(key, items, TTL_SERVICE_CATALOG)
        return items
    except Exception as exc:
        logger.error("cache_manager: failed to fetch item_catalog: %s", exc)
        return None


# ── Admin lookup tables (users, vehicles) ─────────────────────────────────────
# These are built once per call in firestore_tools.py (full collection scan).
# We cache the lookup dicts here to avoid re-scanning on every admin question.

_KEY_USER_LOOKUP       = "admin_user_lookup"
_KEY_VEHICLE_LOOKUP_ID = "admin_vehicle_lookup_by_id"
_KEY_VEHICLE_LOOKUP_PL = "admin_vehicle_lookup_by_plate"


def get_user_lookup(db=None) -> dict | None:
    cached = _get(_KEY_USER_LOOKUP)
    if cached is not None:
        return cached
    if db is None:
        return None
    logger.info("cache_manager: user_lookup MISS — fetching")
    try:
        lookup = {}
        for doc in db.collection("users").stream():
            d = doc.to_dict()
            lookup[doc.id] = {
                "name":  (d.get("name") or
                          (d.get("firstName", "") + " " + d.get("lastName", "")).strip()),
                "email": d.get("email", ""),
                "role":  d.get("role", ""),
            }
        _set(_KEY_USER_LOOKUP, lookup, TTL_USER_LOOKUP)
        logger.info("cache_manager: user_lookup cached (%d users)", len(lookup))
        return lookup
    except Exception as exc:
        logger.error("cache_manager: failed to fetch user_lookup: %s", exc)
        return None


def get_vehicle_lookup_by_id(db=None) -> dict | None:
    cached = _get(_KEY_VEHICLE_LOOKUP_ID)
    if cached is not None:
        return cached
    if db is None:
        return None
    logger.info("cache_manager: vehicle_lookup_by_id MISS — fetching")
    try:
        lookup = {}
        for doc in db.collection("vehicles").stream():
            d = doc.to_dict()
            lookup[doc.id] = {
                "plate":   d.get("plateNumber") or d.get("plate") or "",
                "desc":    d.get("description") or d.get("desc") or d.get("assetDescription") or "",
                "owner":   d.get("owner", ""),
                "ownerId": d.get("ownerId", ""),
                "type":    d.get("type", ""),
                "status":  d.get("status", ""),
            }
        _set(_KEY_VEHICLE_LOOKUP_ID, lookup, TTL_VEHICLE_LOOKUP)
        logger.info("cache_manager: vehicle_lookup_by_id cached (%d vehicles)", len(lookup))
        return lookup
    except Exception as exc:
        logger.error("cache_manager: failed to fetch vehicle_lookup_by_id: %s", exc)
        return None


def get_vehicle_lookup_by_plate(db=None) -> dict | None:
    cached = _get(_KEY_VEHICLE_LOOKUP_PL)
    if cached is not None:
        return cached
    if db is None:
        return None
    logger.info("cache_manager: vehicle_lookup_by_plate MISS — fetching")
    try:
        lookup = {}
        for doc in db.collection("vehicles").stream():
            d = doc.to_dict()
            plate = (d.get("plateNumber") or d.get("plate") or "").strip()
            if plate:
                lookup[plate] = {
                    "docId":   doc.id,
                    "desc":    d.get("description") or d.get("desc") or d.get("assetDescription") or "",
                    "owner":   d.get("owner", ""),
                    "ownerId": d.get("ownerId", ""),
                    "type":    d.get("type", ""),
                    "status":  d.get("status", ""),
                }
        _set(_KEY_VEHICLE_LOOKUP_PL, lookup, TTL_VEHICLE_LOOKUP)
        logger.info("cache_manager: vehicle_lookup_by_plate cached (%d plates)", len(lookup))
        return lookup
    except Exception as exc:
        logger.error("cache_manager: failed to fetch vehicle_lookup_by_plate: %s", exc)
        return None


# ── Customer company name (per-user, short TTL) ───────────────────────────────

def get_company_name(db, customer_uid: str) -> str:
    """Cache the customer's companyName field to avoid repeated single-doc reads."""
    key = f"company_name:{customer_uid}"
    cached = _get(key)
    if cached is not None:
        return cached
    try:
        doc = db.collection("users").document(customer_uid).get()
        company = ""
        if doc.exists:
            company = (doc.to_dict().get("companyName") or "").strip()
        # Cache even empty strings to avoid repeated reads for customers without a company
        _set(key, company, 300)   # 5-minute TTL per user
        return company
    except Exception as exc:
        logger.warning("cache_manager: could not fetch companyName for uid=%s: %s",
                       customer_uid, exc)
        return ""


# ── Cache stats (for debugging/admin) ────────────────────────────────────────

def get_stats() -> dict:
    """Return current cache contents summary (keys + expiry, no data values)."""
    with _lock:
        now = time.monotonic()
        return {
            key: {
                "expires_in_s": max(0, round(expires_at - now)),
                "expired": now > expires_at,
            }
            for key, (expires_at, _) in _store.items()
        }
