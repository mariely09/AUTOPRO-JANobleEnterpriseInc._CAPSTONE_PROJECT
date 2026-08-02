import os
from dotenv import load_dotenv

load_dotenv()


class Settings:
    # Groq — fast cloud inference (OpenAI-compatible API). Chosen because local
    # hardware (laptop, no dedicated GPU) can't run a 14B+ model fast enough for
    # the multi-step tool-calling loop this app uses.
    # NOTE: this sends data (inventory/sales/PMS queries) to Groq's servers.
    # Keep customer PII out of prompts where possible if that's a concern.
    #
    # GROQ_API_KEY is the fallback key used when no keys are stored in Firestore.
    # Once keys are added via the AI Settings admin page, ApiKeyManager takes over
    # and rotates among all configured keys automatically.
    GROQ_API_KEY: str = os.getenv("GROQ_API_KEY", "")
    GROQ_MODEL: str = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
    # Alt: "llama-3.1-8b-instant" — much faster, less reliable at instruction-following.

    # Firebase / Firestore
    FIREBASE_CREDENTIALS_PATH: str = os.getenv(
        "FIREBASE_CREDENTIALS_PATH", "./serviceAccountKey.json"
    )

    # App
    APP_ROLE: str = "admin"  # this service instance is the Admin AI

    # ── API key rotation settings ─────────────────────────────────────────────
    # These can be overridden in .env or set via the AI Settings admin page.
    # GROQ_KEY_ENCRYPTION_SECRET: secret used to encrypt stored API keys in
    #   Firestore. Set to a random 32-char string in production.
    # AI_ADMIN_TOKEN: bearer token required by the /ai-settings/* endpoints.
    #   The Flask website sends this when proxying admin requests.
    GROQ_KEY_ENCRYPTION_SECRET: str = os.getenv("GROQ_KEY_ENCRYPTION_SECRET", "")
    AI_ADMIN_TOKEN: str = os.getenv("AI_ADMIN_TOKEN", "caltex-admin-ai-2026")
    GROQ_COOLDOWN_SECONDS: int = int(os.getenv("GROQ_COOLDOWN_SECONDS", "300"))
    GROQ_MAX_RETRY_ATTEMPTS: int = int(os.getenv("GROQ_MAX_RETRY_ATTEMPTS", "3"))


settings = Settings()