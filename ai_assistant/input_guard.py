"""
input_guard.py — deterministic input-size guards for LLM requests.

Provides:
  - estimate_tokens(text)      — conservative char/4 estimate
  - truncate_message(text)     — cap oversized user messages gracefully
  - build_request_context()    — assemble messages under a per-request budget,
                                 trimming history before any LLM call is made.

Pure Python, no network.  Used by both the admin and customer chat paths so
an oversized prompt NEVER reaches Groq.
"""
import re

# ── Token estimation ──────────────────────────────────────────────────────────
# Groq/Qwen tokenizers average ~4 characters per token for English prose.
# We use 3 chars/token (conservative) so the estimate over-counts slightly —
# better to trim a little early than to blow the budget.

_CHARS_PER_TOKEN = 3


def estimate_tokens(text: str) -> int:
    """Conservative token estimate for *text* (~3 chars/token, rounded up)."""
    if not text:
        return 0
    return max(1, -(-len(text) // _CHARS_PER_TOKEN))


# ── Oversized user input ──────────────────────────────────────────────────────
_TRUNCATION_NOTE = (
    "\n\n[Your message was shortened because it exceeded the maximum length. "
    "The answer is based on the first part of your message.]"
)


def truncate_message(text: str, max_chars: int) -> str:
    """
    Gracefully cap an oversized user message at *max_chars* characters,
    on a whitespace boundary, with a short notice appended.
    """
    if not text or len(text) <= max_chars:
        return text
    cut = text[:max_chars]
    # Prefer cutting at whitespace/newline so words are not split
    for sep in ("\n", ". ", " ", ""):
        idx = cut.rfind(sep)
        if idx > max_chars // 2:
            cut = cut[:idx]
            break
    return cut.rstrip() + _TRUNCATION_NOTE


# ── History sanitisation ──────────────────────────────────────────────────────
def sanitize_history(history: list[dict], max_msgs: int, max_msg_chars: int) -> list[dict]:
    """
    Prepare conversation history for the LLM:

    - keeps only valid {role, content} messages
    - drops legacy tool-call / tool-result messages entirely (their data is
      stale; re-sending Firestore payloads burns tokens for no benefit)
    - compacts each retained message to *max_msg_chars* (tool-heavy turns are
      the main source of history bloat)
    - keeps only the most recent *max_msgs* messages
    """
    out: list[dict] = []
    for m in (history or []):
        if not isinstance(m, dict):
            continue
        role = m.get("role")
        if role not in ("user", "assistant"):
            continue  # drops 'tool' / 'tool_calls' payloads
        content = m.get("content") or ""
        if not isinstance(content, str) or not content.strip():
            continue
        if len(content) > max_msg_chars:
            content = content[:max_msg_chars].rstrip() + "…"
        out.append({"role": role, "content": content})
    return out[-max_msgs:] if len(out) > max_msgs else out


# ── Per-request budget enforcement ────────────────────────────────────────────
def build_request_context(
    system_prompt: str,
    history: list[dict],
    user_message: str,
    *,
    history_max_msgs: int,
    history_msg_max_chars: int,
    budget_tokens: int,
) -> tuple[list[dict], dict]:
    """
    Assemble the final messages array for one LLM call, enforcing a
    per-request token budget WITHOUT calling the LLM.

    Order of reduction (least valuable first):
      1. drop older history messages (keep the most recent)
      2. compact history messages further (half size)
      3. as a last resort, hard-truncate the oldest message

    Returns (messages, stats) where stats documents what was done
    (for logging/tests): budget, estimated tokens, actions taken.
    """
    stats = {"budget_tokens": budget_tokens, "actions": []}

    fixed_tokens = estimate_tokens(system_prompt) + estimate_tokens(user_message) + 24
    remaining = budget_tokens - fixed_tokens
    if remaining < 200:
        remaining = 200   # always allow a minimal window

    hist = sanitize_history(history, history_max_msgs, history_msg_max_chars)

    def hist_cost(msgs: list[dict]) -> int:
        return sum(estimate_tokens(m["content"]) for m in msgs) + 4 * max(0, len(msgs))

    # 1. trim from the oldest end until we fit
    while hist and hist_cost(hist) > remaining:
        hist = hist[1:]
        if not stats["actions"] or stats["actions"][-1] != "trimmed_old_history":
            stats["actions"].append("trimmed_old_history")

    # 2. still over → compact each message to half size
    if hist and hist_cost(hist) > remaining:
        half = max(120, history_msg_max_chars // 2)
        hist = [
            {**m, "content": (m["content"][:half].rstrip() + "…") if len(m["content"]) > half else m["content"]}
            for m in hist
        ]
        stats["actions"].append("compacted_history")

    # 3. still over (tiny budget) → keep only the newest message, hard-capped
    while len(hist) > 1 and hist_cost(hist) > remaining:
        hist = hist[1:]
        if stats["actions"][-1] != "dropped_history_for_budget":
            stats["actions"].append("dropped_history_for_budget")

    stats["estimated_tokens"] = fixed_tokens + hist_cost(hist)
    stats["history_msgs"] = len(hist)

    messages = [{"role": "system", "content": system_prompt}]
    messages.extend(hist)
    messages.append({"role": "user", "content": user_message})
    return messages, stats
