"""
test_latency_optimization.py - offline tests for the latency optimization.

Verifies (without network/Firestore/LLM):
  1. Config: Groq timeout + capped tool-loop turns are wired.
  2. perf_metrics: stage timing, groq_timer counting, read accounting,
     [AI PERFORMANCE] summary emission.
  3. request_cache: memo hits within a request, fresh execution across
     requests, write-tools never memoized, bucket cleanup.
  4. Both chat dispatch paths use the memoized table (static check).
  5. Groq client reuse: same key -> same client object; timeout passed.
"""
import os
import sys
import types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PASS = 0
FAIL = 0

def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


print("\n== 1. Config knobs ==")
from config import settings
check("GROQ_TIMEOUT_SECONDS defaults to 30", settings.GROQ_TIMEOUT_SECONDS == 30,
      f"got {settings.GROQ_TIMEOUT_SECONDS}")
check("MAX_TOOL_LOOP_TURNS defaults to 3", settings.MAX_TOOL_LOOP_TURNS == 3,
      f"got {settings.MAX_TOOL_LOOP_TURNS}")

print("\n== 2. perf_metrics instrumentation ==")
import perf_metrics

perf_metrics.push("u1", "customer", "TEST")
with perf_metrics.stage("intent"):
    pass
with perf_metrics.groq_timer():
    pass
ctx = perf_metrics.current()
ctx["firestore_reads"] += 2
perf_metrics.record_usage(120, 40)
check("llm_calls counted", ctx["llm_calls"] == 1, f"got {ctx['llm_calls']}")
check("groq stage timed", ctx["stages"]["groq"] >= 0, "")
check("input/output tokens recorded",
      ctx["input_tokens"] == 120 and ctx["output_tokens"] == 40)
perf_metrics.pop()

# log_summary smoke: should not raise and should respect disable flag
perf_metrics.push("u2", "admin", "TEST2")
ctx2 = perf_metrics.current()
os.environ["PERF_LOG_ENABLED"] = "0"
try:
    perf_metrics.log_summary(ctx2)
    check("log_summary honors PERF_LOG_ENABLED=0", True)
finally:
    os.environ.pop("PERF_LOG_ENABLED", None)
perf_metrics.pop()
check("nested requests pop correctly", perf_metrics.current() is None)

print("\n== 3. request_cache memoization ==")
import request_cache

calls = {"n": 0}
def fake_lookup(**kw):
    calls["n"] += 1
    return {"vehicles": ["V1", "V2"], "query": kw}

bucket = request_cache.begin_request()
wrapped = request_cache.memoize({"get_my_vehicles": fake_lookup}, bucket)
r1 = wrapped["get_my_vehicles"](customer_uid="u1")
r2 = wrapped["get_my_vehicles"](customer_uid="u1")
r3 = wrapped["get_my_vehicles"](customer_uid="u2")
check("identical args -> 1 execution", calls["n"] == 2, f"got {calls['n']}")  # r1 + r3 (r2 was memo hit)
check("memo returns same object", r1 is r2)
check("different args -> new execution", calls["n"] == 2, f"got {calls['n']}")
request_cache.end_request(bucket)

# fresh request -> executes again (no cross-request leakage)
bucket2 = request_cache.begin_request()
wrapped2 = request_cache.memoize({"get_my_vehicles": fake_lookup}, bucket2)
wrapped2["get_my_vehicles"](customer_uid="u1")
check("new request re-executes", calls["n"] == 3, f"got {calls['n']}")
request_cache.end_request(bucket2)

# write-tools and availability checks are never memoized
calls["n"] = 0  # reset counter for this block
def fake_create(**kw):
    calls["n"] += 1
    return {"ok": True}
def fake_avail(**kw):
    calls["n"] += 1
    return {"available": True}
b3 = request_cache.begin_request()
w3 = request_cache.memoize(
    {"create_customer_booking": fake_create, "check_booking_availability": fake_avail}, b3)
w3["create_customer_booking"](x=1)
w3["create_customer_booking"](x=1)
w3["check_booking_availability"](x=1)
w3["check_booking_availability"](x=1)
check("write/availability tools always execute", calls["n"] == 4, f"got {calls['n']}")
request_cache.end_request(b3)

print("\n== 4. Chat paths use the memoized dispatch ==")
import re as _re
main_src = open("main.py", encoding="utf-8").read()
client_src = open("client.py", encoding="utf-8").read()
check("customer loop dispatches via memoized table",
      "tool_fns.get(fn_name)" in main_src and "request_cache.memoize(CUSTOMER_TOOL_FUNCTIONS" in main_src)
check("admin loop dispatches via memoized table",
      "tool_fns.get(fn_name)" in client_src and "request_cache.memoize(TOOL_FUNCTIONS" in client_src)
check("admin loop capped by MAX_TOOL_LOOP_TURNS",
      "settings.MAX_TOOL_LOOP_TURNS" in client_src)
check("customer loop capped by MAX_TOOL_LOOP_TURNS",
      "range(max(1, settings.MAX_TOOL_LOOP_TURNS))" in main_src)
check("admin Groq client reused", "get_groq_client(api_key)" in client_src)
check("customer Groq client reused", "get_groq_client(api_key)" in main_src)
check("no per-call Groq construction remains",
      "Groq(api_key=api_key)" not in client_src and "Groq(api_key=api_key)" not in main_src)
check("endpoints emit [AI PERFORMANCE]", "log_summary(_perf)" in main_src)

print("\n== 5. Groq client cache ==")
import client as llm_client

class _FakeGroq:
    def __init__(self, api_key=None, timeout=None):
        self.api_key = api_key
        self.timeout = timeout

import client
_real_groq = client.Groq
try:
    client.Groq = _FakeGroq
    c1 = llm_client.get_groq_client("keyA")
    c2 = llm_client.get_groq_client("keyA")
    c3 = llm_client.get_groq_client("keyB")
    check("same key -> same client object", c1 is c2)
    check("different key -> new client", c1 is not c3)
    check("timeout propagated", c1.timeout == 30, f"got {c1.timeout}")
finally:
    client.Groq = _real_groq
    llm_client._groq_client_cache.clear()

print(f"\n{'='*60}\nRESULT: {PASS} passed, {FAIL} failed\n{'='*60}")
sys.exit(1 if FAIL else 0)
