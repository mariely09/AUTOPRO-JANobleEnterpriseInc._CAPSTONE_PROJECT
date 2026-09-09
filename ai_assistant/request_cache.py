"""
request_cache.py — request-level memoization + read accounting for AI tools.

Purpose (latency spec #6, #13):
  The LLM tool loop can request the SAME data multiple times within one chat
  turn (e.g. get_my_vehicles twice). Without memoization each call repeats the
  identical Firestore queries — pure duplicated latency and reads.

  Wrapping the dispatch tables memoizes per (tool, args) inside a single
  request only. The memo bucket is created per request and dropped at the end
  of it — NOTHING is shared across requests or users, so there is no
  cross-user leakage and no stale-data risk.

  Read accounting (spec #22): wrapped tools report the number of records they
  returned to perf_metrics so the [AI PERFORMANCE] log shows read counts.
"""

import logging
import threading

logger = logging.getLogger(__name__)

_memo: dict[int, dict] = {}
_memo_lock = threading.Lock()
_seq = [0]

# Tools whose result must NEVER be memoized: they write data, or they verify
# freshest state against Firestore (e.g. slot availability right before a
# booking is created).
_UNSAFE_PREFIXES = ("create_", "update_", "cancel_", "delete_", "add_")
_ALWAYS_FRESH = {"check_booking_availability"}


def begin_request() -> int:
    """Allocate a memo bucket for the current request (main.py calls this)."""
    with _memo_lock:
        _seq[0] += 1
        _memo[_seq[0]] = {}
        return _seq[0]


def end_request(bucket_id: int) -> None:
    """Drop the request's memo bucket — nothing survives the request."""
    with _memo_lock:
        _memo.pop(bucket_id, None)


def _make_memoized(fn, name: str, bucket_id: int):
    """Build one memoizing wrapper (factory avoids late-binding closures)."""

    def _memoized(**kwargs):
        bucket = _memo.get(bucket_id)
        key = (name, tuple(sorted((k, str(v)) for k, v in kwargs.items())))
        if bucket is not None and key in bucket:
            logger.debug("request_cache: memo hit for %s", name)
            return bucket[key]
        result = fn(**kwargs)
        if bucket is not None:
            bucket[key] = result
        # Read accounting: estimate one Firestore read per record returned.
        try:
            import perf_metrics
            ctx = perf_metrics.current()
            if ctx is not None:
                n = _estimate_records(result)
                if n:
                    ctx["firestore_reads"] += n
        except Exception:
            pass
        return result

    return _memoized


def memoize(dispatch: dict, bucket_id: int) -> dict:
    """
    Return a wrapped copy of a tool dispatch table that memoizes results
    within the request identified by bucket_id.
    """
    wrapped: dict = {}
    for name, fn in dispatch.items():
        if name.startswith(_UNSAFE_PREFIXES) or name in _ALWAYS_FRESH:
            wrapped[name] = fn
        else:
            wrapped[name] = _make_memoized(fn, name, bucket_id)
    return wrapped


def _estimate_records(result) -> int:
    """Best-effort count of records in a tool result for read accounting."""
    if isinstance(result, dict):
        for k in ("vehicles", "bookings", "jobs", "records", "history",
                  "items", "materials", "results"):
            v = result.get(k)
            if isinstance(v, list):
                return len(v)
        for k in ("total_vehicles", "total_bookings", "count", "total"):
            v = result.get(k)
            if isinstance(v, int):
                return v
        return 1
    if isinstance(result, list):
        return len(result)
    return 1
