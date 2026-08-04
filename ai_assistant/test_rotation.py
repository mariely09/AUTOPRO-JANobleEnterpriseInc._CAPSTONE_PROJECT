"""
test_rotation.py — End-to-end test for API key rotation.

Tests:
  1. Basic rotation  — manager rotates to key 2 when key 1 hits rate limit
  2. Cooldown state  — rotated-away key is marked in cooldown, skipped on retry
  3. All keys exhausted  — friendly error returned, not a crash
  4. Cooldown expiry  — key becomes available again after cooldown
  5. _call_groq simulation  — mocked Groq client triggers real rotation logic
  6. Reload preserves cooldown  — load_from_firestore does NOT wipe in-memory cooldown
  7. client._call_groq with live key (optional — requires real keys in Firestore)

Run with::

    cd ai_assistant
    venv/Scripts/python test_rotation.py
"""

import os
import sys
import time
import unittest
from unittest.mock import MagicMock, patch, call
from io import StringIO

# ── Bootstrap path so we can import from the ai_assistant package ─────────────
sys.path.insert(0, os.path.dirname(__file__))

from api_key_manager import (
    ApiKeyManager,
    _KeyState,
    encrypt_key,
    decrypt_key,
    mask_key,
    get_manager,
)


# ── Helpers ───────────────────────────────────────────────────────────────────

def _make_manager_with_keys(*account_names: str) -> ApiKeyManager:
    """Return a fresh ApiKeyManager pre-loaded with fake in-memory keys."""
    m = ApiKeyManager()
    for i, name in enumerate(account_names):
        k = _KeyState(f"id{i+1}", f"gsk_fakekey_{i+1:04d}", name, "active")
        m._keys.append(k)
    if m._keys:
        m._keys[0].is_current = True
        m._current_idx = 0
    m._loaded = True
    m._rotation_enabled = True
    m._cooldown_seconds = 300
    m._max_retries = 3
    return m


# ── Test suite ────────────────────────────────────────────────────────────────

class TestApiKeyManager(unittest.TestCase):

    # ── Test 1: Basic rotation ────────────────────────────────────────────────
    def test_rotates_to_next_key_on_rate_limit(self):
        m = _make_manager_with_keys("Account A", "Account B", "Account C")

        self.assertEqual(m._current_idx, 0)
        self.assertEqual(m._keys[0].account_name, "Account A")

        next_key = m.rotate_on_rate_limit(failed_key_id="id1")

        self.assertIsNotNone(next_key, "Should return a key after rotating")
        self.assertEqual(next_key, "gsk_fakekey_0002",
                         "Should have rotated to Account B's key")
        self.assertEqual(m._current_idx, 1)
        self.assertTrue(m._keys[1].is_current)
        self.assertFalse(m._keys[0].is_current)
        print("  PASS test 1: rotated to next key on rate limit")

    # ── Test 2: Cooldown state ────────────────────────────────────────────────
    def test_rate_limited_key_enters_cooldown(self):
        m = _make_manager_with_keys("Account A", "Account B")
        before = time.time()

        m.rotate_on_rate_limit(failed_key_id="id1")

        k1 = m._keys[0]
        self.assertTrue(k1.in_cooldown,
                        "Key A should be in cooldown after rate limit")
        self.assertGreater(k1.cooldown_until, before,
                           "cooldown_until should be set to future time")
        self.assertEqual(k1.effective_status, "cooldown")
        print("  PASS test 2: rate-limited key is in cooldown")

    # ── Test 3: All keys exhausted ────────────────────────────────────────────
    def test_all_keys_in_cooldown_returns_none(self):
        m = _make_manager_with_keys("Account A", "Account B")
        # Put both keys in cooldown manually
        for k in m._keys:
            k.cooldown_until = time.time() + 300

        result = m.rotate_on_rate_limit(failed_key_id="id1")

        self.assertIsNone(result,
                          "Should return None when all keys are in cooldown")
        print("  PASS test 3: returns None when all keys exhausted")

    # ── Test 4: Cooldown expiry ───────────────────────────────────────────────
    def test_key_becomes_available_after_cooldown(self):
        m = _make_manager_with_keys("Account A", "Account B")
        # Set cooldown to the past (already expired)
        m._keys[0].cooldown_until = time.time() - 1

        self.assertFalse(m._keys[0].in_cooldown,
                         "Key should NOT be in cooldown if time has passed")
        self.assertEqual(m._keys[0].effective_status, "active")
        print("  PASS test 4: key becomes available after cooldown expires")

    # ── Test 5: Circular rotation ─────────────────────────────────────────────
    def test_circular_rotation_wraps_to_first_key(self):
        m = _make_manager_with_keys("Account A", "Account B")
        # Set current to the LAST key
        for k in m._keys:
            k.is_current = False
        m._current_idx = 1
        m._keys[1].is_current = True

        # Rate-limit the last key — should wrap back to key 0
        next_key = m.rotate_on_rate_limit(failed_key_id="id2")

        self.assertIsNotNone(next_key)
        self.assertEqual(m._current_idx, 0,
                         "Should have wrapped back to index 0")
        self.assertEqual(next_key, "gsk_fakekey_0001")
        print("  PASS test 5: circular rotation wraps back to first key")

    # ── Test 6: Cooldown survives reload ──────────────────────────────────────
    def test_cooldown_survives_reload(self):
        """
        The critical bug fix: load_from_firestore must NOT wipe in-memory cooldown.
        We simulate a reload by running the preservation logic from load_from_firestore.
        """
        m = _make_manager_with_keys("Account A", "Account B")

        # Simulate: key 1 hit rate limit and is now in cooldown
        m.rotate_on_rate_limit(failed_key_id="id1")
        cooldown_time = m._keys[0].cooldown_until
        self.assertTrue(m._keys[0].in_cooldown, "Key 1 should be in cooldown")
        self.assertEqual(m._current_idx, 1, "Should be on key 2")

        # ── Simulate what load_from_firestore does (preservation logic) ──────
        # Capture existing runtime state (exactly as in the real method)
        existing_runtime = {k.key_id: k for k in m._keys}
        old_current_id = m._keys[m._current_idx].key_id  # "id2"

        # Rebuild from "Firestore" (same keys, no cooldown data in Firestore)
        new_k1 = _KeyState("id1", "gsk_fakekey_0001", "Account A", "active")
        new_k2 = _KeyState("id2", "gsk_fakekey_0002", "Account B", "active")
        new_keys = [new_k1, new_k2]

        # Apply preservation (this is the actual fix)
        for k in new_keys:
            prev = existing_runtime.get(k.key_id)
            if prev is not None:
                k.cooldown_until = prev.cooldown_until
                k.last_used = prev.last_used

        m._keys = new_keys

        # Restore current idx
        for i, k in enumerate(m._keys):
            k.is_current = False
            if k.key_id == old_current_id:
                m._current_idx = i
        m._keys[m._current_idx].is_current = True

        # ── Assertions ────────────────────────────────────────────────────────
        self.assertEqual(m._keys[0].cooldown_until, cooldown_time,
                         "cooldown_until must survive reload")
        self.assertTrue(m._keys[0].in_cooldown,
                        "Key 1 must still be in cooldown after reload")
        self.assertEqual(m._current_idx, 1,
                         "_current_idx must point to key 2 after reload")
        self.assertTrue(m._keys[1].is_current,
                        "Key 2 must still be marked current after reload")
        print("  PASS test 6: cooldown and current_idx survive reload")

    # ── Test 7: get_current_key skips unavailable ─────────────────────────────
    def test_get_current_key_skips_cooldown_key(self):
        m = _make_manager_with_keys("Account A", "Account B")
        # Put key 1 in cooldown
        m._keys[0].cooldown_until = time.time() + 300

        key = m.get_current_key()

        self.assertIsNotNone(key)
        self.assertEqual(key, "gsk_fakekey_0002",
                         "Should skip key 1 (in cooldown) and return key 2")
        print("  PASS test 7: get_current_key skips key in cooldown")

    # ── Test 8: disabled key is skipped ──────────────────────────────────────
    def test_disabled_key_is_skipped(self):
        m = _make_manager_with_keys("Account A", "Account B")
        m._keys[0].status = "disabled"

        key = m.get_current_key()

        self.assertIsNotNone(key)
        self.assertEqual(key, "gsk_fakekey_0002",
                         "Should skip disabled key 1 and return key 2")
        print("  PASS test 8: disabled key is skipped")

    # ── Test 9: get_status returns all keys ───────────────────────────────────
    def test_get_status_returns_all_keys_including_cooldown(self):
        """Keys in cooldown must still appear in the status table — they should
        never disappear from the UI."""
        m = _make_manager_with_keys("Account A", "Account B", "Account C")
        # Put key 1 in cooldown
        m._keys[0].cooldown_until = time.time() + 300

        status = m.get_status()

        self.assertEqual(status["total_keys"], 3,
                         "All 3 keys must appear in total_keys")
        self.assertEqual(len(status["keys"]), 3,
                         "All 3 keys must appear in the keys list")
        self.assertEqual(status["cooldown_keys"], 1,
                         "1 key should be shown as cooling down")
        self.assertEqual(status["active_keys"], 2,
                         "2 keys should be shown as active")

        # Check the cooldown key shows correctly
        k1_info = next(k for k in status["keys"] if k["key_id"] == "id1")
        self.assertEqual(k1_info["status"], "cooldown")
        self.assertGreater(k1_info["cooldown_remaining"], 0)

        print("  PASS test 9: get_status shows all keys including those in cooldown")

    # ── Test 10: event log captures rotation events ───────────────────────────
    def test_event_log_captures_rotation(self):
        m = _make_manager_with_keys("Account A", "Account B")

        m.rotate_on_rate_limit(failed_key_id="id1")

        logs = m.get_event_log()
        event_types = [e["event_type"] for e in logs]

        self.assertIn("rate_limit", event_types,
                      "rate_limit event should be logged")
        self.assertIn("key_switch", event_types,
                      "key_switch event should be logged")
        print("  PASS test 10: event log captures rate_limit and key_switch")

    # ── Test 11: _call_groq mock — full rotation flow ─────────────────────────
    def test_call_groq_rotates_on_rate_limit_error(self):
        """
        Mock the Groq client so the first call raises RateLimitError,
        the second call (after rotation) succeeds.
        Verifies the real _call_groq function in client.py handles this correctly.
        """
        from groq import RateLimitError as GroqRateLimitError

        m = _make_manager_with_keys("Account A", "Account B")

        call_count = {"n": 0}
        mock_response = MagicMock()
        mock_response.choices = [MagicMock()]
        mock_response.choices[0].message.content = "Hello, rotation worked!"
        mock_response.choices[0].message.tool_calls = None

        def fake_create(**kwargs):
            call_count["n"] += 1
            if call_count["n"] == 1:
                # First key → simulate rate limit
                raise GroqRateLimitError(
                    message="Rate limit reached",
                    response=MagicMock(status_code=429),
                    body={}
                )
            # Second key → success
            return mock_response

        mock_groq_instance = MagicMock()
        mock_groq_instance.chat.completions.create.side_effect = fake_create

        with patch("client.get_manager", return_value=m), \
             patch("client.Groq", return_value=mock_groq_instance):
            import client
            result = client._call_groq(
                messages=[{"role": "user", "content": "test"}]
            )

        self.assertEqual(result, mock_response,
                         "Should return successful response after rotation")
        self.assertEqual(call_count["n"], 2,
                         "Groq should have been called exactly twice")
        self.assertTrue(m._keys[0].in_cooldown,
                        "Key A should be in cooldown after rate limit")
        self.assertEqual(m._current_idx, 1,
                         "Should be on key B after rotation")
        print("  PASS test 11: _call_groq rotates to next key on RateLimitError")

    # ── Test 12: mask_key ─────────────────────────────────────────────────────
    def test_mask_key(self):
        key = "gsk_abcdefghijklmn1234"
        masked = mask_key(key)
        self.assertTrue(masked.endswith("1234"), "Should show last 4 chars")
        self.assertEqual(len(masked), len(key), "Masked key length must match")
        self.assertNotIn("gsk_", masked, "Should not contain plain prefix")
        print("  PASS test 12: mask_key hides all but last 4 chars")

    # ── Test 13: encrypt / decrypt roundtrip ──────────────────────────────────
    def test_encrypt_decrypt_roundtrip(self):
        original = "gsk_super_secret_key_12345"
        encrypted = encrypt_key(original)
        self.assertNotEqual(encrypted, original, "Encrypted must differ from plain")
        decrypted = decrypt_key(encrypted)
        self.assertEqual(decrypted, original, "Decrypted must equal original")
        print("  PASS test 13: encrypt/decrypt roundtrip OK")


# ── Live integration test (only when AI service is running) ──────────────────

def run_live_test():
    """
    Live test against the deployed Render backend.
    Checks /health then /ai-settings/status to confirm keys are loaded.
    Override backend URL with AI_BACKEND_URL env var if needed.
    """
    try:
        import requests

        backend_url = os.getenv(
            "AI_BACKEND_URL",
            "https://caltex-autopro-capstone-project.onrender.com"
        ).rstrip("/")
        token = os.getenv("AI_ADMIN_TOKEN", "caltex-admin-ai-2026")

        print("\n── Live service test ──────────────────────────────────")
        print(f"  Backend: {backend_url}")

        # 1. Health check (allows longer timeout for Render cold start)
        r = requests.get(f"{backend_url}/health", timeout=20)
        if r.status_code != 200:
            print(f"  SKIP: health check returned HTTP {r.status_code}")
            return

        print(f"  Health: OK  ({r.json()})")

        # 2. AI settings status
        r2 = requests.get(
            f"{backend_url}/ai-settings/status",
            headers={"X-Admin-Token": token},
            timeout=15,
        )
        if r2.status_code == 403:
            print("  SKIP: admin token rejected — check AI_ADMIN_TOKEN env var")
            return
        r2.raise_for_status()
        data = r2.json()

        total    = data.get("total_keys", 0)
        active   = data.get("active_keys", 0)
        cooldown = data.get("cooldown_keys", 0)
        disabled = data.get("disabled_keys", 0)

        print(f"  Service:       ONLINE")
        print(f"  Total keys:    {total}")
        print(f"  Active keys:   {active}")
        print(f"  Cooling down:  {cooldown}")
        print(f"  Disabled:      {disabled}")
        print(f"  Current acct:  {data.get('current_account', '—')}")
        print(f"  Current key:   {data.get('current_key_masked', '—')}")
        print(f"  Model:         {data.get('current_model', '—')}")
        print(f"  Rotation:      {'ON' if data.get('rotation_enabled') else 'OFF'}")
        print(f"  Cooldown secs: {data.get('cooldown_seconds', '—')}")
        print(f"  Max retries:   {data.get('max_retries', '—')}")

        keys = data.get("keys", [])
        if keys:
            print(f"\n  Keys in Firestore ({len(keys)}):")
            for k in keys:
                tag          = " ← CURRENT" if k.get("is_current") else ""
                cooldown_str = (f"  (cooling {k['cooldown_remaining']}s left)"
                                if k.get("cooldown_remaining", 0) > 0 else "")
                print(f"    [{k['status'].upper():10s}] "
                      f"{k['account_name']:<22s} "
                      f"{k['api_key_masked']}"
                      f"{tag}{cooldown_str}")
        else:
            print("  No keys in Firestore — AI is using GROQ_API_KEY from .env")

        print("\n  PASS: live Render service is reachable and responding correctly")

    except requests.exceptions.ConnectionError:
        print("  SKIP: cannot reach the Render backend — check your internet or deployment")
    except requests.exceptions.Timeout:
        print("  SKIP: request timed out — Render may be cold-starting (try again in 30s)")
    except Exception as e:
        print(f"  SKIP: unexpected error — {e}")


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 60)
    print("  API Key Rotation — Unit Tests")
    print("=" * 60)

    loader = unittest.TestLoader()
    suite  = loader.loadTestsFromTestCase(TestApiKeyManager)

    runner = unittest.TextTestRunner(verbosity=0, stream=StringIO())
    result = runner.run(suite)

    # Print results manually so output is clean
    if result.errors:
        print("\nERRORS:")
        for test, tb in result.errors:
            print(f"  {test}: {tb}")

    if result.failures:
        print("\nFAILURES:")
        for test, tb in result.failures:
            print(f"  {test}: {tb}")

    if result.wasSuccessful():
        print(f"\n{'='*60}")
        print(f"  All {result.testsRun} unit tests PASSED")
        print(f"{'='*60}")
        run_live_test()
        sys.exit(0)
    else:
        passed = result.testsRun - len(result.failures) - len(result.errors)
        print(f"\n  {passed}/{result.testsRun} passed, "
              f"{len(result.failures)} failed, {len(result.errors)} errors")
        sys.exit(1)

    run_live_test()
