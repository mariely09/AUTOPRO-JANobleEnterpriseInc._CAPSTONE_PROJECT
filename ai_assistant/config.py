import os
from dotenv import load_dotenv

load_dotenv()


class Settings:
    # ── Groq / LLM ────────────────────────────────────────────────────────────
    # Primary provider: Groq free tier with llama-3.3-70b-versatile.
    # GROQ_API_KEY is the fallback used when no keys are stored in Firestore.
    GROQ_API_KEY: str = os.getenv("GROQ_API_KEY", "")
    GROQ_MODEL:   str = os.getenv("GROQ_MODEL",   "llama-3.3-70b-versatile")

    # ── Token optimisation ────────────────────────────────────────────────────
    # Hard cap on output tokens for every LLM call.
    # Groq free tier: 6,000 tokens/min, 500,000 tokens/day on llama-3.3-70b.
    # A customer answer rarely needs more than 600 tokens; admin answers rarely
    # more than 800.  Capping at 800 saves 1,000–3,000 tokens per call vs
    # the model's 8,192-token default output.
    GROQ_MAX_OUTPUT_TOKENS: int = int(os.getenv("GROQ_MAX_OUTPUT_TOKENS", "800"))

    # Maximum characters of tool-result JSON to send back to the LLM.
    # Prevents a large Firestore result (e.g. all stock items) from blowing up
    # the context window. ~6,000 chars ≈ 1,500 tokens — enough for 20 records.
    GROQ_MAX_TOOL_RESULT_CHARS: int = int(os.getenv("GROQ_MAX_TOOL_RESULT_CHARS", "6000"))

    # Maximum number of history messages to include in each LLM request.
    # Each user+assistant exchange = 2 messages; 10 messages = 5 turns.
    # Groq free tier runs out faster with long histories — 10 messages keeps
    # context useful while saving ~1,500–4,000 tokens vs the old 30-message cap.
    GROQ_MAX_HISTORY_MSGS: int = int(os.getenv("GROQ_MAX_HISTORY_MSGS", "10"))

    # ── Firebase / Firestore ──────────────────────────────────────────────────
    FIREBASE_CREDENTIALS_PATH: str = os.getenv(
        "FIREBASE_CREDENTIALS_PATH", "./serviceAccountKey.json"
    )

    # ── App ───────────────────────────────────────────────────────────────────
    APP_ROLE: str = "admin"

    # ── API key rotation settings ─────────────────────────────────────────────
    GROQ_KEY_ENCRYPTION_SECRET: str = os.getenv("GROQ_KEY_ENCRYPTION_SECRET", "")
    AI_ADMIN_TOKEN:             str = os.getenv("AI_ADMIN_TOKEN", "caltex-admin-ai-2026")
    GROQ_COOLDOWN_SECONDS:      int = int(os.getenv("GROQ_COOLDOWN_SECONDS", "300"))
    GROQ_MAX_RETRY_ATTEMPTS:    int = int(os.getenv("GROQ_MAX_RETRY_ATTEMPTS", "3"))


settings = Settings()