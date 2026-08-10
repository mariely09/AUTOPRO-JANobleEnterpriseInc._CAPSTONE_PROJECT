"""
Server-side conversational memory store.

Stores chat history per session_id in memory (dict).
Each session keeps the last MAX_TURNS user/assistant pairs so the
context window stays manageable.

Thread-safe via a threading.Lock — uvicorn runs in a single process
with async workers, but the lock is cheap and safe.

Sessions expire after SESSION_TTL_MINUTES of inactivity and are
pruned lazily on every write (no background thread needed).
"""

import threading
import time
from collections import OrderedDict

MAX_TURNS          = 8     # user+assistant pairs kept per session (was 15)
                           # 8 turns = 5 turns of context — sufficient for follow-ups
                           # while saving ~2,000–4,000 input tokens per request vs 15 turns
SESSION_TTL_MINUTES = 60   # idle sessions expire after this many minutes

_lock = threading.Lock()

# session_id → {"turns": [...], "last_active": float}
# Each turn = {"role": "user"|"assistant", "content": "..."}
_store: dict[str, dict] = {}


# ── Public API ────────────────────────────────────────────────────────────────

def get_history(session_id: str) -> list[dict]:
    """Return the current conversation history for a session (may be empty)."""
    with _lock:
        _prune()
        entry = _store.get(session_id)
        if entry is None:
            return []
        entry["last_active"] = time.time()
        return list(entry["turns"])


def append_turn(session_id: str, user_message: str, assistant_reply: str) -> None:
    """
    Append one user/assistant exchange to the session history.
    Trims to MAX_TURNS pairs automatically.
    """
    with _lock:
        _prune()
        if session_id not in _store:
            _store[session_id] = {"turns": [], "last_active": time.time()}

        entry = _store[session_id]
        entry["turns"].append({"role": "user",      "content": user_message})
        entry["turns"].append({"role": "assistant",  "content": assistant_reply})

        # Keep only the last MAX_TURNS pairs (2 messages each)
        max_messages = MAX_TURNS * 2
        if len(entry["turns"]) > max_messages:
            entry["turns"] = entry["turns"][-max_messages:]

        entry["last_active"] = time.time()


def clear_session(session_id: str) -> None:
    """Delete all history for a session."""
    with _lock:
        _store.pop(session_id, None)


def session_info(session_id: str) -> dict:
    """Return metadata about a session (for debugging / health checks)."""
    with _lock:
        entry = _store.get(session_id)
        if entry is None:
            return {"session_id": session_id, "turns": 0, "exists": False}
        return {
            "session_id":  session_id,
            "turns":       len(entry["turns"]) // 2,
            "exists":      True,
            "last_active": entry["last_active"],
        }


def active_session_count() -> int:
    with _lock:
        _prune()
        return len(_store)


# ── Internal ──────────────────────────────────────────────────────────────────

def _prune() -> None:
    """Remove sessions that have been idle longer than SESSION_TTL_MINUTES."""
    cutoff = time.time() - SESSION_TTL_MINUTES * 60
    expired = [sid for sid, e in _store.items() if e["last_active"] < cutoff]
    for sid in expired:
        del _store[sid]
