from pydantic import BaseModel


class ChatRequest(BaseModel):
    message: str
    session_id: str | None = None      # server-side memory key; auto-generated if omitted
    history: list[dict] | None = None  # optional client-side history (merged with server memory)


class ChatResponse(BaseModel):
    reply: str
    session_id: str                    # always returned so the client can send it back
    tool_calls: list[dict] = []
    rate_limited: bool = False         # True when Groq daily token limit OR user daily limit is reached
    reset_in: str = ""                 # human-readable reset time e.g. "about 15 minutes" or "midnight"


class CustomerChatRequest(BaseModel):
    message: str
    customer_uid: str                  # Firebase Auth UID (used for booking queries + usage tracking)
    customer_name: str                 # Display name (used for Firestore owner field matching)
    session_id: str | None = None
    history: list[dict] | None = None


class SessionInfoResponse(BaseModel):
    session_id: str
    turns: int
    exists: bool


class UsageResponse(BaseModel):
    user_id: str
    role: str
    date: str
    tokens_used: int
    requests_used: int
    token_limit: int
    request_limit: int
    tokens_remaining: int | None = None
    requests_remaining: int | None = None
    resets_at: str
