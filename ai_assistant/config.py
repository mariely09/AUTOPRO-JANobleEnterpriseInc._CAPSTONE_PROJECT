import os
from dotenv import load_dotenv, dotenv_values

# Load .env into the process environment on startup.
load_dotenv(override=True)

# Path to .env — resolved relative to this file so it works regardless of cwd.
_ENV_PATH = os.path.join(os.path.dirname(__file__), ".env")


def _reload_env_key(key: str, default: str = "") -> str:
    """
    Read a single key directly from the .env file on disk.
    This bypasses the in-memory os.environ cache so a key updated in .env
    is picked up without restarting the server.
    Falls back to os.environ (the value set at startup) if the file is missing.
    """
    try:
        values = dotenv_values(_ENV_PATH)
        return values.get(key, os.getenv(key, default)) or default
    except Exception:
        return os.getenv(key, default)


class Settings:
    # ── Groq / LLM ────────────────────────────────────────────────────────────
    # ONLY provider: Groq (free tier).
    # GROQ_API_KEY is read fresh from .env on every access so that updating
    # the key in .env takes effect immediately without restarting the server.
    @property
    def GROQ_API_KEY(self) -> str:  # type: ignore[override]
        return _reload_env_key("GROQ_API_KEY")

    # ── Model routing ─────────────────────────────────────────────────────────
    # PRIMARY (default): Qwen3.6 27B — fast, replaces deprecated llama-3.1-8b-instant.
    # GROQ_MODEL is the canonical env alias; GROQ_MODEL_PRIMARY kept for back-compat.
    GROQ_MODEL_PRIMARY: str = os.getenv("GROQ_MODEL", None) or os.getenv("GROQ_MODEL_PRIMARY", "qwen/qwen3.6-27b")

    # SECONDARY: Qwen3 32B — reserved for complex reasoning tasks.
    # Replaces deprecated llama-3.3-70b-versatile.
    GROQ_MODEL_SECONDARY: str = os.getenv("GROQ_MODEL_SECONDARY", "qwen/qwen3-32b")

    # Legacy alias — kept so any code that still reads GROQ_MODEL still works.
    # Points to PRIMARY so unrouted calls default to the cheaper model.
    @property
    def GROQ_MODEL(self) -> str:
        return self.GROQ_MODEL_PRIMARY

    # ── Token optimisation ────────────────────────────────────────────────────
    # Hard cap on output tokens.
    # 8B model: simpler answers, 512 tokens is plenty for most replies.
    # 70B model: complex answers may need up to 800.
    # We use a single cap here; callers override per model if needed.
    GROQ_MAX_OUTPUT_TOKENS: int = int(os.getenv("GROQ_MAX_OUTPUT_TOKENS", "512"))

    # Maximum characters of tool-result JSON sent back to the LLM.
    # ~4,000 chars ≈ 1,000 tokens — sufficient for most results, saves tokens
    # vs the old 6,000-char default.
    GROQ_MAX_TOOL_RESULT_CHARS: int = int(os.getenv("GROQ_MAX_TOOL_RESULT_CHARS", "4000"))

    # Maximum number of history messages to include in each LLM request.
    # 6 messages = 3 turns — sufficient for follow-ups while saving tokens.
    GROQ_MAX_HISTORY_MSGS: int = int(os.getenv("GROQ_MAX_HISTORY_MSGS", "6"))

    # ── Latency optimisation ─────────────────────────────────────────────────
    # Explicit timeout for every Groq API call (seconds). Without this the SDK
    # default is 600 s — a stalled request silently hangs for minutes and, in a
    # 5–6 iteration tool loop, can stall a whole chat for several minutes.
    GROQ_TIMEOUT_SECONDS: int = int(os.getenv("GROQ_TIMEOUT_SECONDS", "30"))

    # Max iterations of the LLM tool loop. Each iteration is a full Groq
    # round-trip (system prompt + schemas + history re-sent every time), so
    # latency and tokens grow linearly with the loop length. 3 iterations is
    # enough for every flow the assistant actually performs (lookup → answer,
    # availability → create booking → confirm).
    MAX_TOOL_LOOP_TURNS: int = int(os.getenv("MAX_TOOL_LOOP_TURNS", "3"))

    # ── Token-budget optimisation ─────────────────────────────────────────────
    # Max characters accepted for a single user message. Larger inputs are
    # truncated gracefully (guard against pasted documents flooding the LLM).
    MAX_INPUT_CHARS: int = int(os.getenv("MAX_INPUT_CHARS", "2000"))

    # Per-REQUEST token budgets (system prompt + tool schemas + history +
    # message estimate). When a request would exceed the budget, history is
    # trimmed first, then older tool-result content, before the call is made.
    CUSTOMER_MAX_REQUEST_TOKENS: int = int(os.getenv("CUSTOMER_MAX_REQUEST_TOKENS", "6000"))
    ADMIN_MAX_REQUEST_TOKENS:    int = int(os.getenv("ADMIN_MAX_REQUEST_TOKENS",    "8000"))

    # Per-message content cap inside history (chars). Old turns are compacted
    # to this size before being re-sent to the model.
    HISTORY_MSG_MAX_CHARS: int = int(os.getenv("HISTORY_MSG_MAX_CHARS", "600"))

    # ── Firebase / Firestore ──────────────────────────────────────────────────
    FIREBASE_CREDENTIALS_PATH: str = os.getenv(
        "FIREBASE_CREDENTIALS_PATH", "./serviceAccountKey.json"
    )

    # ── App ───────────────────────────────────────────────────────────────────
    APP_ROLE: str = "admin"

    # ── API key management settings ───────────────────────────────────────────
    GROQ_KEY_ENCRYPTION_SECRET: str = os.getenv("GROQ_KEY_ENCRYPTION_SECRET", "")
    AI_ADMIN_TOKEN:             str = os.getenv("AI_ADMIN_TOKEN", "caltex-admin-ai-2026")
    GROQ_COOLDOWN_SECONDS:      int = int(os.getenv("GROQ_COOLDOWN_SECONDS", "300"))
    GROQ_MAX_RETRY_ATTEMPTS:    int = int(os.getenv("GROQ_MAX_RETRY_ATTEMPTS", "3"))


settings = Settings()