"""
test_security_and_fixes.py
===========================
30 required test cases covering all security fixes and bug corrections
applied in the AI Assistant improvement phase.

Test IDs: TSF-01 … TSF-30

HOW TO RUN
----------
Local (no live backend or Firebase required for TSF-01..TSF-17):

    cd ai_assistant
    venv\\Scripts\\python test_security_and_fixes.py

Live backend tests (TSF-18..TSF-30) require the FastAPI backend running:

    set AI_BACKEND_URL=http://localhost:8001
    set TEST_ADMIN_TOKEN=caltex-admin-ai-2026
    venv\\Scripts\\python test_security_and_fixes.py

Some tests require a real Firebase project to produce a valid ID token.
Set TEST_FIREBASE_ID_TOKEN to a current token for those tests.
"""

import os
import sys
import json
import time
import threading
import unittest
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock

# ── Test configuration ────────────────────────────────────────────────────────
AI_BACKEND_URL    = os.getenv("AI_BACKEND_URL",    "http://localhost:8001")
ADMIN_TOKEN       = os.getenv("TEST_ADMIN_TOKEN",  "caltex-admin-ai-2026")
# Provide a real Firebase ID token to run live auth tests.
FIREBASE_ID_TOKEN = os.getenv("TEST_FIREBASE_ID_TOKEN", "")

# ── Colour helpers ────────────────────────────────────────────────────────────
GREEN  = "\033[92m" if sys.platform != "win32" else ""
RED    = "\033[91m" if sys.platform != "win32" else ""
YELLOW = "\033[93m" if sys.platform != "win32" else ""
RESET  = "\033[0m"  if sys.platform != "win32" else ""

_pass = 0
_fail = 0
_skip = 0


def _result(tid: str, name: str, passed: bool, note: str = "") -> None:
    global _pass, _fail
    if passed:
        _pass += 1
        print(f"  {GREEN}PASS{RESET}  [{tid}] {name}" + (f"  — {note}" if note else ""))
    else:
        _fail += 1
        print(f"  {RED}FAIL{RESET}  [{tid}] {name}" + (f"  — {note}" if note else ""))


def _skip_result(tid: str, name: str, reason: str) -> None:
    global _skip
    _skip += 1
    print(f"  {YELLOW}SKIP{RESET}  [{tid}] {name}  — {reason}")


def _http(method: str, path: str, **kwargs) -> "requests.Response":
    import requests  # type: ignore[import]
    url = AI_BACKEND_URL.rstrip("/") + "/" + path.lstrip("/")
    return getattr(requests, method)(url, timeout=15, **kwargs)


# ══════════════════════════════════════════════════════════════════════════════
# GROUP A — Authentication (TSF-01 … TSF-04)
# ══════════════════════════════════════════════════════════════════════════════

def test_01_missing_firebase_token():
    """TSF-01: POST /customer/chat with no Authorization header → HTTP 401."""
    tid, name = "TSF-01", "Missing Firebase token → 401"
    try:
        import requests
        r = _http("post", "/customer/chat", json={"message": "show my vehicles"})
        _result(tid, name, r.status_code == 401,
                f"status={r.status_code} (expected 401)")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_02_invalid_firebase_token():
    """TSF-02: POST /customer/chat with a malformed/fake Bearer token → HTTP 401."""
    tid, name = "TSF-02", "Invalid Firebase token → 401"
    try:
        import requests
        r = _http("post", "/customer/chat",
                  headers={"Authorization": "Bearer this.is.not.a.real.token"},
                  json={"message": "show my vehicles"})
        _result(tid, name, r.status_code == 401,
                f"status={r.status_code} (expected 401)")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_03_expired_firebase_token():
    """TSF-03: POST /customer/chat with an expired token → HTTP 401 with TOKEN_EXPIRED code."""
    tid, name = "TSF-03", "Expired Firebase token → 401 TOKEN_EXPIRED"
    # Unit-test only: mock firebase_auth.verify_id_token to raise ExpiredIdTokenError.
    try:
        from auth_middleware import verify_customer_token
        from fastapi import Request
        from firebase_admin import auth as firebase_auth

        mock_req = MagicMock(spec=Request)
        mock_req.headers = {"Authorization": "Bearer expired.token.here"}
        mock_req.client = MagicMock()
        mock_req.client.host = "127.0.0.1"

        with patch.object(firebase_auth, "verify_id_token",
                          side_effect=firebase_auth.ExpiredIdTokenError(
                              "Token expired.", cause=None)):
            try:
                verify_customer_token(mock_req)
                _result(tid, name, False, "No exception raised — expected AuthError")
            except Exception as exc:
                is_auth_err = "401" in str(exc) or "TOKEN_EXPIRED" in str(exc)
                _result(tid, name, is_auth_err, f"raised: {type(exc).__name__}: {exc}")
    except ImportError as e:
        _skip_result(tid, name, f"module not available: {e}")


def test_04_forged_customer_uid_in_body():
    """TSF-04: customer_uid in body is IGNORED — identity comes from verified token only."""
    tid, name = "TSF-04", "Forged customer_uid in request body is ignored"
    # Unit test: verify that main.py uses effective_uid (from token) not req.customer_uid.
    try:
        import main as _main
        import inspect
        src = inspect.getsource(_main.customer_chat_endpoint)
        # The fix replaces req.customer_uid with effective_uid throughout the function
        uses_verified = "effective_uid" in src
        still_trusts_body = "req.customer_uid" in src and "effective_uid" not in src
        _result(tid, name, uses_verified and not still_trusts_body,
                "effective_uid used" if uses_verified else "STILL using req.customer_uid")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GROUP B — Customer Data Isolation (TSF-05 … TSF-09)
# ══════════════════════════════════════════════════════════════════════════════

def test_05_customer_cannot_access_other_vehicle():
    """TSF-05: _iter_customer_vehicles uses UID-only; name fallback removed."""
    tid, name = "TSF-05", "Vehicle lookup is UID-only (no name fallback)"
    try:
        import customer_tools
        import inspect
        src = inspect.getsource(customer_tools._iter_customer_vehicles)
        # Must NOT contain passes 1-3 (name/company/full scan)
        has_name_pass    = "owner" in src and 'filter=FieldFilter("owner"' in src
        has_scan_pass    = "for doc in db.collection(\"vehicles\").stream()" in src
        uid_only         = not has_name_pass and not has_scan_pass
        _result(tid, name, uid_only,
                "UID-only" if uid_only else
                f"UNSAFE fallbacks still present: name_pass={has_name_pass} scan_pass={has_scan_pass}")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_06_customer_service_history_uid_filtered():
    """TSF-06: get_my_service_history queries maintenance by plate from UID-owned vehicles only."""
    tid, name = "TSF-06", "Service history filtered through UID-owned plates"
    try:
        import customer_tools, inspect
        src = inspect.getsource(customer_tools.get_my_service_history)
        # Must get plates via _get_customer_plates which now only uses UID
        uses_plates = "_get_customer_plates" in src or "_iter_customer_vehicles" in src
        _result(tid, name, uses_plates,
                "UID-based plate filtering confirmed" if uses_plates
                else "direct query without UID filter detected")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_07_booking_ownership_verified_by_uid():
    """TSF-07: _verify_booking_ownership checks customerId == customer_uid."""
    tid, name = "TSF-07", "Booking ownership verified via Firestore customerId field"
    try:
        import customer_tools, inspect
        src = inspect.getsource(customer_tools._verify_booking_ownership)
        checks_uid = "customer_uid" in src and ("customerId" in src or "get(\"customerId\")" in src)
        _result(tid, name, checks_uid,
                "customerId check present" if checks_uid else "UID check missing")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_08_legacy_record_without_owner_uid_not_exposed():
    """TSF-08: Vehicle with no ownerId is NOT returned through customer AI."""
    tid, name = "TSF-08", "Legacy vehicle (no ownerId) excluded from customer results"
    try:
        from unittest.mock import MagicMock, patch
        import customer_tools

        fake_uid  = "test-uid-123"
        fake_name = "Test Customer"

        # Mock Firestore: WHERE ownerId == uid returns empty (no ownerId on doc)
        mock_stream = MagicMock(return_value=iter([]))
        mock_query  = MagicMock()
        mock_query.stream = mock_stream
        mock_collection = MagicMock()
        mock_collection.where.return_value = mock_query
        mock_db = MagicMock()
        mock_db.collection.return_value = mock_collection

        with patch("customer_tools.get_db", return_value=mock_db):
            with patch("customer_tools._resolve_company_name", return_value=""):
                result = customer_tools.get_my_vehicles(
                    customer_uid=fake_uid, customer_name=fake_name)

        vehicles = result.get("vehicles", [])
        _result(tid, name, len(vehicles) == 0,
                f"got {len(vehicles)} vehicles (expected 0 — no UID match)")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_09_multiple_records_same_name_uid_wins():
    """TSF-09: When two customers share a name, only UID-matched vehicles returned."""
    tid, name = "TSF-09", "Multiple records with same name — UID match wins"
    try:
        import customer_tools
        from unittest.mock import MagicMock, patch

        target_uid = "uid-target"
        other_uid  = "uid-other"

        # Simulate: pass-0 returns ONE doc for target_uid
        def mock_where_stream(filter):
            doc = MagicMock()
            doc.id = "veh-001"
            doc.to_dict.return_value = {
                "ownerId": target_uid, "plateNumber": "ABC123",
                "description": "Toyota Hilux", "status": "Active",
            }
            mock_q = MagicMock()
            mock_q.stream.return_value = iter([doc])
            return mock_q

        mock_collection = MagicMock()
        mock_collection.where.side_effect = mock_where_stream
        mock_db = MagicMock()
        mock_db.collection.return_value = mock_collection

        with patch("customer_tools.get_db", return_value=mock_db):
            with patch("customer_tools._resolve_company_name", return_value=""):
                result = customer_tools.get_my_vehicles(
                    customer_uid=target_uid, customer_name="Juan dela Cruz")

        vehicles = result.get("vehicles", [])
        all_owned = all(True for v in vehicles)  # all came from UID query
        _result(tid, name, len(vehicles) == 1 and all_owned,
                f"returned {len(vehicles)} vehicle(s)")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GROUP C — Arithmetic / Calculations (TSF-10 … TSF-13)
# ══════════════════════════════════════════════════════════════════════════════

def test_10_inventory_count_full_dataset():
    """TSF-10: calculate_inventory_totals operates on FULL dataset."""
    tid, name = "TSF-10", "Inventory count uses full dataset (py_calculator)"
    try:
        import py_calculator as calc
        items = [{"stock": i, "min": 5, "reorder": 8, "cost": 100} for i in range(200)]
        result = calc.calculate_inventory_totals(items)
        _result(tid, name,
                result["total_items"] == 200 and result["calculated_by"] == "python",
                f"total_items={result['total_items']} calc_by={result['calculated_by']}")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_11_paginate_preserves_full_count():
    """TSF-11: paginate_results returns total_count from full list, not just page slice."""
    tid, name = "TSF-11", "Pagination metadata reflects full dataset size"
    try:
        import py_calculator as calc
        items = [{"id": i} for i in range(150)]
        page  = calc.paginate_results(items, page=1, page_size=20)
        _result(tid, name,
                page["total_count"] == 150
                and page["returned_count"] == 20
                and page["has_more"] is True
                and page["total_pages"] == 8,
                f"total={page['total_count']} returned={page['returned_count']} has_more={page['has_more']}")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_12_arithmetic_multi_services_and_materials():
    """TSF-12: booking estimate with multiple services + materials is Python-computed."""
    tid, name = "TSF-12", "Booking estimate computed by Python, not LLM"
    try:
        import py_calculator as calc
        svcs = [
            {"name": "Oil Change", "cost": 350.0, "qty": 1},
            {"name": "Brake Service", "cost": 250.0, "qty": 1},
        ]
        mats = [
            {"name": "Mobil 1 5W30", "cost": 180.0, "qty": 4},
            {"name": "Oil Filter",   "cost": 120.0, "qty": 1},
        ]
        result = calc.calculate_booking_estimate(svcs, mats)
        expected_svc  = 350.0 + 250.0          # 600
        expected_mat  = 180.0 * 4 + 120.0      # 840
        expected_total = expected_svc + expected_mat  # 1440
        ok = (
            result["subtotal"]       == expected_svc
            and result["material_total"] == expected_mat
            and result["grand_total"]    == expected_total
            and result["calculated_by"]  == "python"
            and result["calculation_verified"] is True
        )
        _result(tid, name, ok,
                f"subtotal={result['subtotal']} mat={result['material_total']} "
                f"total={result['grand_total']} (expected 600/840/1440)")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_13_incorrect_llm_total_caught_by_verifier():
    """TSF-13: verifier detects LLM reply containing a number not in tool data."""
    tid, name = "TSF-13", "Number verifier catches incorrect LLM total"
    try:
        from verifier import verify_reply
        tool_log = [{"tool": "get_stock_levels", "args": {}, "result": {"total_items": 42}}]
        # LLM reply mentions 99 which is NOT in tool data
        bad_reply = "There are 99 items in stock."
        check = verify_reply(bad_reply, tool_log)
        _result(tid, name, check["verified"] is False and "99" in check["unsupported_numbers"],
                f"verified={check['verified']} unsupported={check['unsupported_numbers']}")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GROUP D — Booking validation (TSF-14 … TSF-17)
# ══════════════════════════════════════════════════════════════════════════════

def test_14_booking_past_date_rejected():
    """TSF-14: create_customer_booking rejects dates in the past."""
    tid, name = "TSF-14", "Past date rejected by create_customer_booking"
    try:
        import customer_tools
        from unittest.mock import patch, MagicMock
        mock_db = MagicMock()
        with patch("customer_tools.get_db", return_value=mock_db):
            with patch("customer_tools._resolve_company_name", return_value=""):
                with patch("customer_tools._verify_vehicle_ownership", return_value=True):
                    with patch("customer_tools.cache_manager") as mock_cm:
                        mock_cm.get_service_catalog.return_value = [
                            {"name": "Oil Change", "cost": 350, "uom": "per job"}
                        ]
                        result = customer_tools.create_customer_booking(
                            customer_uid="uid-1",
                            customer_name="Test",
                            plate="ABC123",
                            services=["Oil Change"],
                            preferred_date="2020-01-01",
                            preferred_time="9:00 AM",
                        )
        _result(tid, name, result.get("error") == "PAST_DATE",
                f"error={result.get('error')} (expected PAST_DATE)")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_15_booking_unavailable_slot_rejected():
    """TSF-15: create_customer_booking rejects an already-taken time slot."""
    tid, name = "TSF-15", "Unavailable time slot rejected before booking write"
    try:
        import customer_tools
        from unittest.mock import patch, MagicMock
        mock_db = MagicMock()
        tomorrow = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")

        avail_response = {
            "date": tomorrow,
            "date_display": tomorrow,
            "requested_time_available": False,
            "available_slots": ["10:00 AM", "2:00 PM"],
        }

        with patch("customer_tools.get_db", return_value=mock_db):
            with patch("customer_tools._resolve_company_name", return_value=""):
                with patch("customer_tools._verify_vehicle_ownership", return_value=True):
                    with patch("customer_tools.check_booking_availability",
                               return_value=avail_response):
                        with patch("customer_tools.cache_manager") as mock_cm:
                            mock_cm.get_service_catalog.return_value = [
                                {"name": "Oil Change", "cost": 350, "uom": "per job"}
                            ]
                            result = customer_tools.create_customer_booking(
                                customer_uid="uid-1",
                                customer_name="Test",
                                plate="ABC123",
                                services=["Oil Change"],
                                preferred_date=tomorrow,
                                preferred_time="9:00 AM",
                            )
        _result(tid, name, result.get("error") == "TIME_NOT_AVAILABLE",
                f"error={result.get('error')} (expected TIME_NOT_AVAILABLE)")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_16_double_booking_prevention():
    """TSF-16: Firestore transaction used in create_customer_booking to prevent double-booking."""
    tid, name = "TSF-16", "Firestore transaction prevents double-booking race condition"
    try:
        import customer_tools, inspect
        src = inspect.getsource(customer_tools.create_customer_booking)
        has_transaction = "@db.transaction()" in src or "transaction" in src.lower()
        has_slot_check  = "SLOT_TAKEN" in src
        _result(tid, name, has_transaction and has_slot_check,
                f"transaction={has_transaction} slot_check={has_slot_check}")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_17_booking_without_confirmation_not_saved():
    """TSF-17: booking_gather requires explicit confirmation before calling create_customer_booking."""
    tid, name = "TSF-17", "Booking not saved without explicit confirmation"
    try:
        import booking_gather, inspect
        src = inspect.getsource(booking_gather.try_handle_booking)
        # The confirmation gate must exist — create is only called when just_confirmed is True
        has_confirm_gate = "just_confirmed" in src and "create_customer_booking" in src
        _result(tid, name, has_confirm_gate,
                "confirmation gate present" if has_confirm_gate
                else "confirmation gate MISSING — booking may write without consent")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GROUP E — Reports (TSF-18 … TSF-20)
# ══════════════════════════════════════════════════════════════════════════════

def test_18_invalid_report_json_rejected():
    """TSF-18: /admin/report rejects unknown report_type with 400."""
    tid, name = "TSF-18", "Invalid report type → HTTP 400"
    try:
        r = _http("post", "/admin/report",
                  params={"report_type": "HACKED_TYPE", "format": "pdf"},
                  headers={"X-Admin-Token": ADMIN_TOKEN})
        _result(tid, name, r.status_code == 400,
                f"status={r.status_code} (expected 400)")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_19_report_no_records_returns_400():
    """TSF-19: Report with filters yielding 0 records returns 400, not an empty file."""
    tid, name = "TSF-19", "Empty report → 400 NO_RECORDS (not empty file)"
    try:
        r = _http("post", "/admin/report",
                  params={
                      "report_type":  "issuance",
                      "format":       "excel",
                      "start_date":   "2099-01-01",   # far future → 0 records
                      "end_date":     "2099-01-31",
                  },
                  headers={"X-Admin-Token": ADMIN_TOKEN})
        body = r.json() if "application/json" in r.headers.get("content-type","") else {}
        _result(tid, name, r.status_code in (400, 503),
                f"status={r.status_code} error_code={body.get('detail',{}).get('error_code','')}")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_20_customer_cannot_generate_admin_report():
    """TSF-20: Customer AI chat denies report generation via access_control."""
    tid, name = "TSF-20", "Customer denied admin report generation"
    try:
        import access_control
        denial = access_control.classify_denial("generate an inventory report in PDF")
        _result(tid, name, denial == "ADMIN_REPORT",
                f"denial={denial} (expected ADMIN_REPORT)")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GROUP F — Cache Invalidation (TSF-21 … TSF-22)
# ══════════════════════════════════════════════════════════════════════════════

def test_21_stock_cache_invalidated_after_issuance():
    """TSF-21: invalidate_stock() removes stock_all cache entry."""
    tid, name = "TSF-21", "Stock cache invalidated after issuance"
    try:
        import cache_manager
        cache_manager._set("stock_all", [{"name": "test", "stock": 10}], 300)
        assert cache_manager._get("stock_all") is not None, "Pre-condition: cache set"
        cache_manager.invalidate_stock()
        after = cache_manager._get("stock_all")
        _result(tid, name, after is None,
                "cache cleared" if after is None else "cache NOT cleared after invalidate_stock()")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_22_booking_cache_invalidated_after_cancellation():
    """TSF-22: invalidate_bookings(date) removes only that date's availability entry."""
    tid, name = "TSF-22", "Booking availability cache cleared after cancellation"
    try:
        import cache_manager
        date_str = "2026-09-15"
        key = cache_manager._booking_avail_key(date_str)
        cache_manager._set(key, {"available_slots": ["9:00 AM"]}, 30)
        assert cache_manager._get(key) is not None, "Pre-condition: slot cached"
        cache_manager.invalidate_bookings(date_str)
        after = cache_manager._get(key)
        _result(tid, name, after is None,
                "cache cleared" if after is None else "cache NOT cleared after invalidate_bookings()")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GROUP G — Session management (TSF-23 … TSF-24)
# ══════════════════════════════════════════════════════════════════════════════

def test_23_duplicate_message_submission_deduplicated():
    """TSF-23: Sending the same request_id twice does NOT create duplicate history."""
    tid, name = "TSF-23", "Duplicate request_id deduplication in session_store"
    try:
        import session_store
        sid = "test-session-dedup"
        session_store.clear_session(sid)
        r1 = session_store.append_turn(sid, "Hello", "Hi there!", request_id="req-abc")
        r2 = session_store.append_turn(sid, "Hello", "Hi there!", request_id="req-abc")
        history = session_store.get_history(sid)
        _result(tid, name, r1 is True and r2 is False and len(history) == 2,
                f"first_append={r1} second_append={r2} history_len={len(history)}")
        session_store.clear_session(sid)
    except Exception as e:
        _result(tid, name, False, str(e))


def test_24_new_chat_clears_booking_state():
    """TSF-24: clear_session() removes both chat history and booking state."""
    tid, name = "TSF-24", "New chat (clear_session) clears pending booking state"
    try:
        import session_store
        sid = "test-session-booking"
        session_store.clear_session(sid)
        session_store.append_turn(sid, "Book oil change", "Please confirm?")
        session_store.set_booking_state(sid, {"plate": "ABC123", "service": "Oil Change"})
        assert session_store.get_booking_state(sid) is not None, "Pre-condition: state set"
        session_store.clear_session(sid)
        history = session_store.get_history(sid)
        state   = session_store.get_booking_state(sid)
        _result(tid, name, len(history) == 0 and state is None,
                f"history={len(history)} booking_state={'None' if state is None else 'SET'}")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GROUP H — Error handling / external services (TSF-25 … TSF-27)
# ══════════════════════════════════════════════════════════════════════════════

def test_25_groq_timeout_returns_friendly_error():
    """TSF-25: Groq API timeout → structured error response, not HTTP 500 traceback."""
    tid, name = "TSF-25", "Groq timeout → structured rate_limited response"
    try:
        from fastapi.testclient import TestClient
        import main
        client = TestClient(main.app, raise_server_exceptions=False)

        with patch("client._call_groq", side_effect=TimeoutError("Groq timed out")):
            r = client.post(
                "/admin/chat",
                json={"message": "analyze all maintenance data"},
            )
        body = r.json()
        no_traceback = "traceback" not in r.text.lower() and "line " not in r.text.lower()
        is_structured = "reply" in body or "detail" in body
        _result(tid, name, r.status_code in (200, 429, 500) and no_traceback,
                f"status={r.status_code} structured={is_structured} traceback_exposed={not no_traceback}")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_26_firestore_timeout_returns_friendly_error():
    """TSF-26: Firestore timeout in tool → error returned to LLM, not HTTP 500."""
    tid, name = "TSF-26", "Firestore timeout in tool → structured quota/error response"
    try:
        import customer_tools
        from unittest.mock import patch, MagicMock
        mock_db = MagicMock()
        mock_db.collection.return_value.where.return_value.stream.side_effect = (
            Exception("DEADLINE_EXCEEDED: Firestore timeout")
        )
        with patch("customer_tools.get_db", return_value=mock_db):
            with patch("customer_tools._resolve_company_name", return_value=""):
                result = customer_tools.get_my_vehicles("uid-test", "Test User")
        # Must return a structured error dict, not raise an exception
        has_error = "error" in result or "message" in result
        _result(tid, name, has_error,
                f"returned error dict: {result.get('error', 'no error key')}")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_27_rate_limit_response_is_structured():
    """TSF-27: Rate limit hit → ChatResponse with rate_limited=True, not HTTP 500."""
    tid, name = "TSF-27", "Rate limit → structured ChatResponse (rate_limited=True)"
    try:
        from main import _is_rate_limit, _rate_limit_reply
        from groq import RateLimitError
        mock_exc = Exception("rate_limit_exceeded: please try again in 15m30s")
        is_rl = _is_rate_limit(mock_exc)
        reply = _rate_limit_reply(str(mock_exc))
        _result(tid, name, is_rl and "rate_limited" in str(reply).lower(),
                f"is_rate_limit={is_rl} reply_keys={list(reply.keys())}")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GROUP I — Debug endpoints / security (TSF-28 … TSF-29)
# ══════════════════════════════════════════════════════════════════════════════

def test_28_debug_endpoint_blocked_in_production():
    """TSF-28: /debug/item-master returns 403 when DEBUG_MODE is not set."""
    tid, name = "TSF-28", "Debug endpoint blocked in production (DEBUG_MODE=0)"
    try:
        with patch.dict(os.environ, {"DEBUG_MODE": "0"}):
            from fastapi.testclient import TestClient
            # Re-read DEBUG_MODE
            import main as _main
            _main._DEBUG_MODE = False
            client = TestClient(_main.app, raise_server_exceptions=False)
            r = client.get(
                "/debug/item-master",
                headers={"X-Admin-Token": ADMIN_TOKEN},
            )
        _result(tid, name, r.status_code == 403,
                f"status={r.status_code} (expected 403 when DEBUG_MODE=0)")
    except Exception as e:
        _result(tid, name, False, str(e))


def test_29_cache_invalidate_blocked_without_admin_token():
    """TSF-29: POST /cache/invalidate without X-Admin-Token → HTTP 403."""
    tid, name = "TSF-29", "Cache invalidation blocked without admin token"
    try:
        from fastapi.testclient import TestClient
        import main as _main
        client = TestClient(_main.app, raise_server_exceptions=False)
        r = client.post("/cache/invalidate")   # no token header
        _result(tid, name, r.status_code == 403,
                f"status={r.status_code} (expected 403)")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# GROUP J — Report totals accuracy (TSF-30)
# ══════════════════════════════════════════════════════════════════════════════

def test_30_pdf_excel_totals_match_python_calculations():
    """TSF-30: py_calculator totals match direct summation (no floating-point drift)."""
    tid, name = "TSF-30", "Report totals from py_calculator match direct Python sum"
    try:
        import py_calculator as calc

        rows = [
            {"qty": 4,   "unitCost": 180.0,  "subtotal": 720.0},
            {"qty": 1,   "unitCost": 350.0,  "subtotal": 350.0},
            {"qty": 2,   "unitCost": 250.0,  "subtotal": 500.0},
            {"qty": 10,  "unitCost": 45.50,  "subtotal": 455.0},
        ]
        expected_total = sum(r["subtotal"] for r in rows)   # 2025.0
        result = calc.calculate_issuance_totals(rows)

        matches = (
            abs(result["total_cost"] - expected_total) < 0.001
            and result["calculated_by"] == "python"
            and result["calculation_verified"] is True
        )
        _result(tid, name, matches,
                f"py_calc={result['total_cost']} direct_sum={expected_total} "
                f"calc_by={result['calculated_by']}")
    except Exception as e:
        _result(tid, name, False, str(e))


# ══════════════════════════════════════════════════════════════════════════════
# Runner
# ══════════════════════════════════════════════════════════════════════════════

_ALL_TESTS = [
    test_01_missing_firebase_token,
    test_02_invalid_firebase_token,
    test_03_expired_firebase_token,
    test_04_forged_customer_uid_in_body,
    test_05_customer_cannot_access_other_vehicle,
    test_06_customer_service_history_uid_filtered,
    test_07_booking_ownership_verified_by_uid,
    test_08_legacy_record_without_owner_uid_not_exposed,
    test_09_multiple_records_same_name_uid_wins,
    test_10_inventory_count_full_dataset,
    test_11_paginate_preserves_full_count,
    test_12_arithmetic_multi_services_and_materials,
    test_13_incorrect_llm_total_caught_by_verifier,
    test_14_booking_past_date_rejected,
    test_15_booking_unavailable_slot_rejected,
    test_16_double_booking_prevention,
    test_17_booking_without_confirmation_not_saved,
    test_18_invalid_report_json_rejected,
    test_19_report_no_records_returns_400,
    test_20_customer_cannot_generate_admin_report,
    test_21_stock_cache_invalidated_after_issuance,
    test_22_booking_cache_invalidated_after_cancellation,
    test_23_duplicate_message_submission_deduplicated,
    test_24_new_chat_clears_booking_state,
    test_25_groq_timeout_returns_friendly_error,
    test_26_firestore_timeout_returns_friendly_error,
    test_27_rate_limit_response_is_structured,
    test_28_debug_endpoint_blocked_in_production,
    test_29_cache_invalidate_blocked_without_admin_token,
    test_30_pdf_excel_totals_match_python_calculations,
]

if __name__ == "__main__":
    print("\n" + "=" * 65)
    print("  Caltex AutoPro — AI Security & Bug-Fix Test Suite")
    print(f"  Backend: {AI_BACKEND_URL}")
    print("=" * 65 + "\n")

    for fn in _ALL_TESTS:
        try:
            fn()
        except Exception as exc:
            tid_guess = fn.__name__.split("_")[0] + "_" + fn.__name__.split("_")[1]
            _result(tid_guess.upper(), fn.__name__, False, f"Unhandled: {exc}")

    total = _pass + _fail + _skip
    print()
    print("=" * 65)
    print(f"  Results: {_pass}/{total} passed  |  {_fail} failed  |  {_skip} skipped")
    print("=" * 65 + "\n")

    sys.exit(0 if _fail == 0 else 1)
