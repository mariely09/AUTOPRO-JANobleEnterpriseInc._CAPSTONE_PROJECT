"""
API Key Manager for Groq — circular rotation with per-key cooldown.

Features:
  - Up to 10 API keys stored in Firestore (encrypted at rest via Fernet).
  - Thread-safe via threading.Lock — safe for concurrent FastAPI workers.
  - Automatic key rotation on HTTP 429 (rate-limit) or quota errors.
  - Per-key cooldown: keys that hit a rate limit are marked unavailable and
    automatically re-enabled after COOLDOWN_SECONDS.
  - Circular rotation: wraps back to key 0 after the last key.
  - Friendly error when ALL keys are in cooldown.
  - Global statistics: total_requests, total_switches.
  - Event log: last 100 events (key switch, rate-limit, cooldown, etc.).

Security:
  - Keys are encrypted with Fernet (symmetric encryption) before writing to
    Firestore and decrypted only in-process for use.
  - The Fernet secret is stored in the .env file as GROQ_KEY_ENCRYPTION_SECRET.
    If absent a deterministic key derived from the Firebase project ID is used
    (still better than plain-text, but set a real secret in production).
  - API keys are masked in logs and UI (shows last 4 chars only).
"""

import logging
import os
import threading
import time
from collections import deque
from datetime import datetime
from typing import Optional

logger = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────
MAX_KEYS = 10
COOLDOWN_SECONDS = int(os.getenv("GROQ_COOLDOWN_SECONDS", "300"))   # 5 min default
MAX_RETRY_ATTEMPTS = int(os.getenv("GROQ_MAX_RETRY_ATTEMPTS", "3"))
ROTATION_ENABLED_DEFAULT = True
LOG_MAX = 100   # keep last N events in the in-memory event log

# ── Encryption helpers ────────────────────────────────────────────────────────

def _get_fernet():
    """Return a Fernet instance. Creates one lazily and caches it."""
    global _fernet_instance
    try:
        return _fernet_instance
    except NameError:
        pass

    from cryptography.fernet import Fernet
    import base64
    import hashlib

    secret = os.getenv("GROQ_KEY_ENCRYPTION_SECRET", "")
    if secret:
        raw = hashlib.sha256(secret.encode()).digest()
    else:
        project_id = os.getenv("FIREBASE_PROJECT_ID", "caltex-autopro")
        raw = hashlib.sha256(f"caltex-groq-keys-{project_id}".encode()).digest()

    fernet_key = base64.urlsafe_b64encode(raw)
    _fernet_instance = Fernet(fernet_key)
    return _fernet_instance


def encrypt_key(plain_key: str) -> str:
    """Encrypt an API key for storage."""
    return _get_fernet().encrypt(plain_key.encode()).decode()


def decrypt_key(encrypted_key: str) -> str:
    """Decrypt an API key retrieved from storage."""
    return _get_fernet().decrypt(encrypted_key.encode()).decode()


def mask_key(key: str) -> str:
    """Return a masked version showing only the last 4 characters."""
    if not key or len(key) < 8:
        return "****"
    return "•" * (len(key) - 4) + key[-4:]


# ── In-memory state ───────────────────────────────────────────────────────────

class _KeyState:
    """Runtime state for a single API key (not persisted)."""

    __slots__ = ("key_id", "plain_key", "account_name", "status",
                 "is_current", "cooldown_until", "last_used")

    def __init__(self, key_id: str, plain_key: str, account_name: str,
                 status: str = "active"):
        self.key_id: str = key_id
        self.plain_key: str = plain_key
        self.account_name: str = account_name
        self.status: str = status          # "active" | "disabled"
        self.is_current: bool = False
        self.cooldown_until: float = 0.0   # epoch seconds; 0 = not in cooldown
        self.last_used: float = 0.0        # epoch seconds

    @property
    def in_cooldown(self) -> bool:
        return self.cooldown_until > time.time()

    @property
    def cooldown_remaining(self) -> int:
        remaining = self.cooldown_until - time.time()
        return max(0, int(remaining))

    @property
    def effective_status(self) -> str:
        if self.status == "disabled":
            return "disabled"
        if self.in_cooldown:
            return "cooldown"
        return "active"

    def to_dict(self, masked: bool = True) -> dict:
        display_key = mask_key(self.plain_key) if masked else self.plain_key
        return {
            "key_id":             self.key_id,
            "account_name":       self.account_name,
            "api_key_masked":     display_key,
            "status":             self.effective_status,
            "is_current":         self.is_current,
            "last_used":          datetime.fromtimestamp(self.last_used).strftime(
                                      "%Y-%m-%d %H:%M:%S") if self.last_used else "Never",
            "cooldown_remaining": self.cooldown_remaining,
        }


# ── Main manager ──────────────────────────────────────────────────────────────

class ApiKeyManager:
    """Thread-safe circular API key rotation manager."""

    def __init__(self):
        self._lock = threading.Lock()
        self._keys: list[_KeyState] = []
        self._current_idx: int = 0
        self._total_requests: int = 0
        self._total_switches: int = 0
        self._rotation_enabled: bool = ROTATION_ENABLED_DEFAULT
        self._cooldown_seconds: int = COOLDOWN_SECONDS
        self._max_retries: int = MAX_RETRY_ATTEMPTS
        self._event_log: deque = deque(maxlen=LOG_MAX)
        self._loaded: bool = False
        self._load_lock = threading.Lock()   # separate lock just for load serialisation
        self._settings_id: str = "rotation_settings"

    # ── Loading ───────────────────────────────────────────────────────────────

    def load_from_firestore(self):
        """
        Load / reload API keys from Firestore into memory.

        KEY DESIGN DECISIONS:
        1. Uses a separate _load_lock so that concurrent callers cannot trigger
           two simultaneous reloads.
        2. Preserves existing per-key runtime state (cooldown_until, last_used)
           across reloads — Firestore does NOT store cooldown, so a reload must
           NOT wipe it.  This is the root cause of "keys disappear on rate-limit".
        3. Does NOT reset _current_idx to 0 unless the previously-current key
           was actually removed from Firestore — keeps rotation position stable.
        4. Sets _loaded = True OUTSIDE the _lock so _ensure_loaded() is safe to
           call from any thread without holding the main lock.
        """
        with self._load_lock:
            try:
                from firestore_client import get_db
                db = get_db()

                # ── Load rotation settings (no lock needed — scalar writes are atomic in CPython) ──
                settings_doc = db.collection("ai_settings").document(self._settings_id).get()
                if settings_doc.exists:
                    s = settings_doc.to_dict()
                    self._rotation_enabled = s.get("rotation_enabled", True)
                    self._cooldown_seconds = int(s.get("cooldown_seconds", COOLDOWN_SECONDS))
                    self._max_retries      = int(s.get("max_retries", MAX_RETRY_ATTEMPTS))

                # ── Fetch Firestore key documents ─────────────────────────────
                # Sort in Python to avoid requiring a Firestore single-field index
                # on sort_order (which may not exist and causes a silent failure).
                docs = list(db.collection("ai_api_keys").stream())
                docs.sort(key=lambda d: d.to_dict().get("sort_order", 0))

                with self._lock:
                    # Build a map of existing runtime state keyed by key_id so we
                    # can re-apply cooldown_until and last_used after the reload.
                    existing_runtime: dict[str, _KeyState] = {
                        k.key_id: k for k in self._keys
                    }

                    # Remember which key_id was "current" before reload
                    old_current_id: Optional[str] = (
                        self._keys[self._current_idx].key_id
                        if self._keys else None
                    )

                    # Rebuild the key list from Firestore
                    new_keys: list[_KeyState] = []
                    for doc in docs:
                        d = doc.to_dict()
                        if not d.get("encrypted_key"):
                            continue
                        try:
                            plain_key = decrypt_key(d["encrypted_key"])
                        except Exception as exc:
                            logger.error("Failed to decrypt key %s: %s", doc.id, exc)
                            continue

                        state = _KeyState(
                            key_id=doc.id,
                            plain_key=plain_key,
                            account_name=d.get("account_name", "Unnamed"),
                            status=d.get("status", "active"),
                        )

                        # ── CRITICAL: restore runtime state from before the reload ──
                        # cooldown_until and last_used are in-memory only.
                        # Without this, a reload after a rate-limit would reset
                        # cooldown_until to 0 and make all keys look available again
                        # before the cooldown period has actually passed.
                        prev = existing_runtime.get(doc.id)
                        if prev is not None:
                            state.cooldown_until = prev.cooldown_until
                            state.last_used      = prev.last_used

                        new_keys.append(state)

                    self._keys = new_keys

                    # ── Restore or choose the current index ───────────────────
                    # Try to keep pointing at the same key that was active before.
                    new_current_idx = 0
                    if old_current_id:
                        for i, k in enumerate(self._keys):
                            if k.key_id == old_current_id:
                                new_current_idx = i
                                break
                        # If the old key was deleted, new_current_idx stays 0

                    # Clear all is_current flags, then set the right one
                    for k in self._keys:
                        k.is_current = False
                    self._current_idx = new_current_idx
                    if self._keys:
                        self._keys[self._current_idx].is_current = True

                # Set _loaded AFTER releasing the lock — safe for other threads to read
                self._loaded = True

                logger.info(
                    "ApiKeyManager: loaded %d key(s). Rotation=%s, cooldown=%ds",
                    len(self._keys), self._rotation_enabled, self._cooldown_seconds,
                )

            except Exception as exc:
                logger.error("ApiKeyManager: failed to load from Firestore: %s", exc)
                # Mark as loaded anyway so we don't infinitely retry on every request.
                # Keys list will just be empty and we fall back to GROQ_API_KEY env var.
                self._loaded = True

    def _ensure_loaded(self):
        """Load keys on first use. Thread-safe via _load_lock inside load_from_firestore."""
        if not self._loaded:
            self.load_from_firestore()

    # ── Key access ────────────────────────────────────────────────────────────

    def get_current_key(self) -> Optional[str]:
        """Return the current active API key value, or None if none available."""
        self._ensure_loaded()
        with self._lock:
            if not self._keys:
                return os.getenv("GROQ_API_KEY", "") or None

            key = self._keys[self._current_idx]
            if key.status != "disabled" and not key.in_cooldown:
                key.last_used = time.time()
                self._total_requests += 1
                return key.plain_key

            # Current key unavailable — find the next available one
            return self._next_available_key_locked()

    def get_current_key_id(self) -> Optional[str]:
        """Return the key_id of the currently active key."""
        self._ensure_loaded()
        with self._lock:
            if not self._keys:
                return None
            return self._keys[self._current_idx].key_id

    def _next_available_key_locked(self) -> Optional[str]:
        """
        Find the next available key (not disabled, not in cooldown).
        Must be called while holding self._lock.
        Searches starting from the slot AFTER _current_idx (circular).
        """
        n = len(self._keys)
        if n == 0:
            return os.getenv("GROQ_API_KEY", "") or None

        for offset in range(1, n + 1):
            idx = (self._current_idx + offset) % n
            candidate = self._keys[idx]
            if candidate.status != "disabled" and not candidate.in_cooldown:
                self._keys[self._current_idx].is_current = False
                self._current_idx = idx
                candidate.is_current = True
                candidate.last_used = time.time()
                self._total_requests += 1
                return candidate.plain_key

        return None  # all keys unavailable

    # ── Rotation ──────────────────────────────────────────────────────────────

    def rotate_on_rate_limit(self, failed_key_id: Optional[str] = None) -> Optional[str]:
        """
        Called when a rate-limit (429) or quota error occurs.
        1. Puts the failed key into cooldown (in-memory only — not persisted).
        2. Advances to the next available key.
        3. Returns the new key's value, or None if all are unavailable.
        """
        self._ensure_loaded()
        if not self._rotation_enabled:
            return None

        with self._lock:
            # 1. Mark the failed key as cooling down
            if failed_key_id:
                for k in self._keys:
                    if k.key_id == failed_key_id and k.status != "disabled":
                        k.cooldown_until = time.time() + self._cooldown_seconds
                        self._log_event(
                            "rate_limit", k.account_name,
                            f"Rate limit hit. Cooldown for {self._cooldown_seconds}s "
                            f"(until {datetime.fromtimestamp(k.cooldown_until).strftime('%H:%M:%S')})"
                        )
                        logger.warning(
                            "ApiKeyManager: key [%s / %s] hit rate limit — cooling down until %s",
                            k.account_name, mask_key(k.plain_key),
                            datetime.fromtimestamp(k.cooldown_until).strftime("%H:%M:%S"),
                        )
                        break

            # 2. Advance to the next available key
            prev_idx = self._current_idx
            new_key_value = self._next_available_key_locked()

            if new_key_value is not None and self._current_idx != prev_idx:
                new_key = self._keys[self._current_idx]
                self._total_switches += 1
                self._log_event(
                    "key_switch", new_key.account_name,
                    f"Switched to key {mask_key(new_key.plain_key)}"
                )
                logger.info(
                    "ApiKeyManager: switched to key [%s / %s]",
                    new_key.account_name, mask_key(new_key.plain_key),
                )
            elif new_key_value is None:
                self._log_event(
                    "all_unavailable", "—",
                    "All API keys are rate-limited or disabled"
                )
                logger.error("ApiKeyManager: ALL keys are unavailable.")

            return new_key_value

    # ── CRUD ─────────────────────────────────────────────────────────────────

    def add_key(self, plain_key: str, account_name: str,
                status: str = "active") -> dict:
        """Encrypt and persist a new API key to Firestore, then reload in-memory."""
        from firestore_client import get_db
        db = get_db()

        # Check limit before acquiring the main lock
        with self._lock:
            current_count = len(self._keys)
        if current_count >= MAX_KEYS:
            raise ValueError(f"Maximum of {MAX_KEYS} API keys allowed.")

        encrypted = encrypt_key(plain_key)

        # sort_order = current count so new key lands at the end
        doc_ref = db.collection("ai_api_keys").document()
        doc_ref.set({
            "account_name":  account_name,
            "encrypted_key": encrypted,
            "status":        status,
            "sort_order":    current_count,
            "created_at":    datetime.utcnow().isoformat(),
        })

        self._log_event("key_added", account_name,
                        f"New key added ({mask_key(plain_key)})")
        # Reload preserves existing cooldown state for other keys
        self.load_from_firestore()
        return {"key_id": doc_ref.id, "account_name": account_name, "status": status}

    def update_key(self, key_id: str,
                   account_name: Optional[str] = None,
                   plain_key: Optional[str] = None,
                   status: Optional[str] = None) -> dict:
        """Update an existing key's fields in Firestore."""
        from firestore_client import get_db
        db = get_db()

        updates: dict = {"updated_at": datetime.utcnow().isoformat()}
        if account_name is not None:
            updates["account_name"] = account_name
        if plain_key is not None:
            updates["encrypted_key"] = encrypt_key(plain_key)
        if status is not None:
            updates["status"] = status

        db.collection("ai_api_keys").document(key_id).update(updates)
        self._log_event("key_updated", key_id,
                        f"Key updated: {[k for k in updates if k != 'updated_at']}")
        self.load_from_firestore()
        return {"key_id": key_id, "updated": list(updates.keys())}

    def delete_key(self, key_id: str) -> dict:
        """Remove an API key from Firestore and reload."""
        from firestore_client import get_db
        db = get_db()

        db.collection("ai_api_keys").document(key_id).delete()
        self._log_event("key_deleted", key_id, "Key deleted")
        self.load_from_firestore()
        return {"key_id": key_id, "deleted": True}

    def test_key(self, plain_key: str) -> dict:
        """Test whether a Groq API key is valid by making a minimal API call."""
        try:
            from groq import Groq
            client = Groq(api_key=plain_key)
            model = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
            resp = client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": "ping"}],
                max_tokens=5,
            )
            return {"valid": True, "model": model,
                    "message": f"Connection successful. Model: {model}"}
        except Exception as exc:
            err = str(exc)
            if "401" in err or "invalid" in err.lower() or "unauthorized" in err.lower():
                return {"valid": False,
                        "message": "Invalid API key — authentication failed."}
            if "429" in err or "rate" in err.lower():
                return {"valid": True,
                        "message": "Key is valid but currently rate-limited."}
            return {"valid": False, "message": f"Connection failed: {err[:200]}"}

    def save_rotation_settings(self,
                               rotation_enabled: Optional[bool] = None,
                               cooldown_seconds: Optional[int] = None,
                               max_retries: Optional[int] = None) -> dict:
        """Persist rotation settings to Firestore and apply immediately in-memory."""
        from firestore_client import get_db
        db = get_db()

        updates: dict = {"updated_at": datetime.utcnow().isoformat()}
        if rotation_enabled is not None:
            updates["rotation_enabled"] = rotation_enabled
            self._rotation_enabled = rotation_enabled
        if cooldown_seconds is not None:
            updates["cooldown_seconds"] = cooldown_seconds
            self._cooldown_seconds = cooldown_seconds
        if max_retries is not None:
            updates["max_retries"] = max_retries
            self._max_retries = max_retries

        db.collection("ai_settings").document(self._settings_id).set(
            updates, merge=True
        )
        self._log_event("settings_updated", "system",
                        f"Rotation settings updated: {[k for k in updates if k != 'updated_at']}")
        return {"updated": list(updates.keys())}

    # ── Status / info ─────────────────────────────────────────────────────────

    def get_status(self) -> dict:
        """Return current AI service status (safe for the admin UI — all keys masked)."""
        self._ensure_loaded()
        with self._lock:
            keys_info = [k.to_dict(masked=True) for k in self._keys]

            current_key = (
                self._keys[self._current_idx] if self._keys else None
            )

            active_count   = sum(1 for k in self._keys
                                 if k.status != "disabled" and not k.in_cooldown)
            cooldown_count = sum(1 for k in self._keys
                                 if k.status != "disabled" and k.in_cooldown)
            disabled_count = sum(1 for k in self._keys if k.status == "disabled")

            from config import settings
            return {
                "current_account":    current_key.account_name if current_key else "—",
                "current_key_masked": (mask_key(current_key.plain_key)
                                       if current_key else "—"),
                "current_model":      settings.GROQ_MODEL,
                "total_keys":         len(self._keys),
                "active_keys":        active_count,
                "cooldown_keys":      cooldown_count,
                "disabled_keys":      disabled_count,
                "total_requests":     self._total_requests,
                "total_switches":     self._total_switches,
                "rotation_enabled":   self._rotation_enabled,
                "cooldown_seconds":   self._cooldown_seconds,
                "max_retries":        self._max_retries,
                "rotation_strategy":  "Round Robin",
                "keys":               keys_info,
            }

    def get_event_log(self) -> list[dict]:
        """Return the most recent events — reads from Firestore so all workers agree."""
        try:
            from firestore_client import get_db
            db = get_db()
            # Fetch all and sort in Python to avoid needing a Firestore index
            docs = list(db.collection("ai_event_log").stream())
            entries = [d.to_dict() for d in docs]
            entries.sort(key=lambda e: e.get("timestamp_epoch", 0), reverse=True)
            return entries[:LOG_MAX]
        except Exception as exc:
            logger.warning("get_event_log: Firestore unavailable, falling back to memory: %s", exc)
            with self._lock:
                return list(reversed(self._event_log))

    # ── Internal ──────────────────────────────────────────────────────────────

    def _log_event(self, event_type: str, account: str, message: str):
        """Append an event to the in-memory log AND persist to Firestore.
        Must be called while self._lock is held.
        Firestore write is fire-and-forget (errors are logged, not raised).
        """
        entry = {
            "timestamp":       datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "timestamp_epoch": time.time(),   # used for server-side ordering
            "event_type":      event_type,
            "account":         account,
            "message":         message,
        }
        self._event_log.append(entry)

        # Persist to Firestore so all Render workers share the same log
        def _write():
            try:
                from firestore_client import get_db
                db = get_db()
                db.collection("ai_event_log").document().set(entry)
                # Keep only the last LOG_MAX documents — prune oldest in background
                _prune_event_log(db)
            except Exception as exc:
                logger.warning("_log_event: could not persist to Firestore: %s", exc)

        import threading as _threading
        _threading.Thread(target=_write, daemon=True).start()


def _prune_event_log(db):
    """Delete event log documents beyond LOG_MAX (keep newest LOG_MAX).
    Called in a background thread — errors are silently swallowed.
    """
    try:
        docs = list(db.collection("ai_event_log").stream())
        if len(docs) <= LOG_MAX:
            return
        # Sort newest-first and delete anything beyond the limit
        docs.sort(key=lambda d: d.to_dict().get("timestamp_epoch", 0), reverse=True)
        for doc in docs[LOG_MAX:]:
            doc.reference.delete()
    except Exception:
        pass


# ── Singleton ─────────────────────────────────────────────────────────────────

_manager_instance: Optional[ApiKeyManager] = None
_manager_init_lock = threading.Lock()


def get_manager() -> ApiKeyManager:
    """Return the application-wide singleton ApiKeyManager (lazy init)."""
    global _manager_instance
    if _manager_instance is None:
        with _manager_init_lock:
            if _manager_instance is None:
                _manager_instance = ApiKeyManager()
    return _manager_instance
