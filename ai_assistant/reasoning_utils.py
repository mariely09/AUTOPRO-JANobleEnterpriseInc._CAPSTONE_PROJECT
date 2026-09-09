"""
reasoning_utils.py — strips Qwen's internal reasoning from model output.

Qwen3-family models (qwen/qwen3.6-27b, qwen/qwen3-32b) may emit their
planning/reasoning as a <think>...</think> block inside the message
content. That text must NEVER reach the customer: not in the chat UI,
not in session history (where it would be re-sent as context on every
future turn and bloat tokens), and not in answer caches.

Every assistant reply passes through strip_reasoning() exactly once,
at the boundary where the raw Groq message is converted into the
user-facing reply.

Performance: two compiled regexes, no I/O — negligible cost.
"""

import re

# Paired block(s): <think> ... </think>  (multiline, case-insensitive)
_THINK_PAIRED_RE = re.compile(
    r"<think\b[^>]*>.*?</think\s*>",
    re.DOTALL | re.IGNORECASE,
)

# Unclosed block: model started reasoning but got cut off by the
# max-token limit before emitting </think>.  Drop everything from the
# opening tag to the end of the string.
_THINK_UNCLOSED_RE = re.compile(
    r"<think\b[^>]*>.*\Z",
    re.DOTALL | re.IGNORECASE,
)

# Some models emit a bare opening tag with no content at all.
_THINK_ORPHAN_RE = re.compile(r"</?think\b[^>]*>", re.IGNORECASE)


def strip_reasoning(text: str) -> str:
    """
    Remove <think>...</think> reasoning blocks from a model reply and
    return the clean, user-facing answer.

    Handles:
      - complete paired blocks (anywhere in the text)
      - unclosed blocks truncated by the output-token cap
      - stray opening/closing tags
      - leading/trailing whitespace left behind after removal

    Safe to call on any string (including None -> empty string).
    """
    if not text:
        return ""
    s = _THINK_PAIRED_RE.sub("", text)
    s = _THINK_UNCLOSED_RE.sub("", s)
    s = _THINK_ORPHAN_RE.sub("", s)
    return s.strip()


def has_reasoning(text: str) -> bool:
    """True when the text still contains a <think> block (diagnostics)."""
    if not text:
        return False
    return bool(_THINK_PAIRED_RE.search(text) or _THINK_UNCLOSED_RE.search(text))


def split_reasoning(text: str) -> tuple[str, str]:
    """
    Return (clean_answer, reasoning_text).  Reasoning is kept separate
    (never returned to the client) so it can be logged for debugging
    without leaking it to the customer.
    """
    if not text:
        return "", ""
    reasoning = "".join(m.group(0) for m in _THINK_PAIRED_RE.finditer(text))
    if _THINK_UNCLOSED_RE.search(text):
        reasoning += _THINK_UNCLOSED_RE.search(text).group(0)
    return strip_reasoning(text), reasoning
