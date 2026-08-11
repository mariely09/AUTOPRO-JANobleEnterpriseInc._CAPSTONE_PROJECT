import os
from dotenv import load_dotenv

load_dotenv()


class Settings:
    # ── Groq / LLM ────────────────────────────────────────────────────────────
    # ONLY provider: Groq (free tier).
    # GROQ_API_KEY is the single key used for all LLM calls.
    GROQ_API_KEY: str = os.getenv("GROQ_API_KEY", "")

    # ── Model routing ─────────────────────────────────────────────────────────
    # PRIMARY (default): Llama 3.1 8B Instant — fast, cheap, handles the
    # vast majority of requests (DB phrasing, simple Q&A, general knowledge).
    GROQ_MODEL_PRIMARY: str = os.getenv("GROQ_MODEL_PRIMARY", "llama-3.1-8b-instant")

    # SECONDARY: Llama 3.3 70B Versatile — reserved for genuinely complex
    # reasoning (multi-source analysis, prioritisation, complex recommendations).
    GROQ_MODEL_SECONDARY: str = os.getenv("GROQ_MODEL_SECONDARY", "llama-3.3-70b-versatile")

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