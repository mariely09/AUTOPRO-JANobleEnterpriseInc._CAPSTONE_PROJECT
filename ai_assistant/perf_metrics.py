"""
perf_metrics.py — per-request performance instrumentation.

Gives every AI request:
  - stage timers (intent / Firestore / Groq / tools / total)
  - counters (Firestore reads, LLM calls)
  - one final [AI PERFORMANCE] log line (spec #22)

Groq calls register themselves via .groq_timer(); every tool function that
touches Firestore should wrap its DB work in .read_timer() so read counts and
Firestore latency are captured without touching each tool individually.

Thread-local: FastAPI serves sync endpoints on a threadpool, so per-request
state must follow the thread.
"""

import logging
import os
import threading
import time
import uuid
from contextlib import contextmanager

logger = logging.getLogger("ai_perf")

STAGES = ("auth", "intent", "firestore", "groq", "tools", "context", "report")

_local = threading.local()


def _stack() -> list[dict]:
    if not hasattr(_local, "stack"):
        _local.stack = []
    return _local.stack


def push(user_id: str, role: str, intent: str) -> dict:
    """Start a request context (endpoints call this at entry)."""
    ctx = {
        "request_id": uuid.uuid4().hex[:8],
        "user_id": user_id,
        "role": role,
        "intent": intent,
        "started": time.perf_counter(),
        "stages": {s: 0.0 for s in STAGES},
        "firestore_reads": 0,
        "llm_calls": 0,
        "input_tokens": 0,
        "output_tokens": 0,
    }
    _stack().append(ctx)
    return ctx


def pop() -> dict | None:
    """End the current request context."""
    stack = _stack()
    return stack.pop() if stack else None


def current() -> dict | None:
    stack = _stack()
    return stack[-1] if stack else None


@contextmanager
def stage(name: str):
    """Time one stage of the current request (no-op outside a request)."""
    ctx = current()
    t0 = time.perf_counter()
    try:
        yield
    finally:
        if ctx is not None and name in ctx["stages"]:
            ctx["stages"][name] += time.perf_counter() - t0


@contextmanager
def read_timer(count: int = 1):
    """
    Time Firestore work inside the current request AND count document reads.
    Usage inside a tool:
        with perf_metrics.read_timer(docs_fetched):
            docs = db.collection(...).get()
    """
    ctx = current()
    t0 = time.perf_counter()
    try:
        yield
    finally:
        if ctx is not None:
            ctx["stages"]["firestore"] += time.perf_counter() - t0
            ctx["firestore_reads"] += max(0, int(count))


@contextmanager
def groq_timer():
    """Time one Groq API call and increment the LLM-call counter."""
    ctx = current()
    t0 = time.perf_counter()
    try:
        yield
    finally:
        if ctx is not None:
            ctx["stages"]["groq"] += time.perf_counter() - t0
            ctx["llm_calls"] += 1


def record_usage(input_tokens: int, output_tokens: int) -> None:
    ctx = current()
    if ctx is not None:
        ctx["input_tokens"] += int(input_tokens or 0)
        ctx["output_tokens"] += int(output_tokens or 0)


def log_summary(ctx: dict) -> None:
    """Emit the [AI PERFORMANCE] line (spec #22)."""
    if not ctx:
        return
    if os.environ.get("PERF_LOG_ENABLED", "1").lower() in ("0", "false", "no"):
        return
    total = time.perf_counter() - ctx["started"]
    stages = ctx["stages"]
    logger.info(
        "[AI PERFORMANCE]\n"
        "  request_id: %s\n"
        "  user_id: %s | role: %s | intent: %s\n"
        "  firestore_reads: %d | firestore_ms: %.0f\n"
        "  llm_calls: %d | groq_ms: %.0f\n"
        "  input_tokens: %d | output_tokens: %d | total_tokens: %d\n"
        "  intent_ms: %.0f | tools_ms: %.0f | context_ms: %.0f | report_ms: %.0f\n"
        "  total_latency: %.2fs",
        ctx["request_id"], ctx["user_id"], ctx["role"], ctx["intent"],
        ctx["firestore_reads"], stages.get("firestore", 0.0) * 1000,
        ctx["llm_calls"], stages.get("groq", 0.0) * 1000,
        ctx["input_tokens"], ctx["output_tokens"],
        ctx["input_tokens"] + ctx["output_tokens"],
        stages.get("intent", 0.0) * 1000, stages.get("tools", 0.0) * 1000,
        stages.get("context", 0.0) * 1000, stages.get("report", 0.0) * 1000,
        total,
    )
