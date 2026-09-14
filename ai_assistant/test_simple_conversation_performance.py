"""
test_simple_conversation_performance.py

Measures actual response times for simple conversational queries to verify
the ultra-fast response requirement (<1 second for greetings, thanks, help).

This test verifies that:
  1. Simple conversation handler returns instant responses (<100ms target)
  2. Greetings, thanks, and help queries work for both admin and customer roles
  3. Non-simple queries correctly fall through (return None)
  4. Performance is consistent across multiple calls

Run: python test_simple_conversation_performance.py
"""
import sys
import os
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from simple_conversation import get_simple_response, is_simple_conversation

PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ✓ PASS  {name}")
    else:
        FAIL += 1
        print(f"  ✗ FAIL  {name}  {detail}")


def measure_time(func, *args, **kwargs):
    """Measure execution time in milliseconds"""
    start = time.perf_counter()
    result = func(*args, **kwargs)
    elapsed_ms = (time.perf_counter() - start) * 1000
    return result, elapsed_ms


print("\n" + "=" * 70)
print("SIMPLE CONVERSATION PERFORMANCE TEST")
print("=" * 70)

# ══════════════════════════════════════════════════════════════════════════════
# 1. Admin Greetings - Must return instant responses
# ══════════════════════════════════════════════════════════════════════════════
print("\n== 1. ADMIN GREETINGS (Target: <100ms) ==")

admin_greetings = [
    "hello",
    "Hello",
    "HELLO",
    "  hello  ",  # with whitespace
    "hi",
    "hey",
    "good morning",
    "good afternoon",
    "good evening",
    "how are you?",
    "how are you",
    "thanks",
    "thank you",
    "ty",
]

for msg in admin_greetings:
    result, elapsed = measure_time(get_simple_response, msg, "admin")
    check(f"Admin '{msg[:20]}...' -> response exists", result is not None,
          f"returned None")
    check(f"Admin '{msg[:20]}...' -> fast (<100ms)", elapsed < 100,
          f"took {elapsed:.2f}ms")
    check(f"Admin '{msg[:20]}...' -> has content", result and len(result) > 10,
          f"len={len(result) if result else 0}")

# ══════════════════════════════════════════════════════════════════════════════
# 2. Admin Capability Questions - Must return instant responses
# ══════════════════════════════════════════════════════════════════════════════
print("\n== 2. ADMIN CAPABILITY QUESTIONS (Target: <100ms) ==")

admin_capability = [
    "what can you do",
    "what can you help me with",
    "who are you",
    "what are you",
    "help",
    "help me",
    "what is this system",
]

for msg in admin_capability:
    result, elapsed = measure_time(get_simple_response, msg, "admin")
    check(f"Admin capability '{msg[:30]}...' -> response exists", result is not None)
    check(f"Admin capability '{msg[:30]}...' -> fast (<100ms)", elapsed < 100,
          f"took {elapsed:.2f}ms")
    check(f"Admin capability '{msg[:30]}...' -> detailed", result and len(result) > 50,
          f"len={len(result) if result else 0}")

# ══════════════════════════════════════════════════════════════════════════════
# 3. Customer Greetings - Must return instant responses
# ══════════════════════════════════════════════════════════════════════════════
print("\n== 3. CUSTOMER GREETINGS (Target: <100ms) ==")

customer_greetings = [
    "hello",
    "hi",
    "hey",
    "kumusta",
    "magandang umaga",
    "good morning",
    "salamat",
    "thank you",
    "how are you",
]

for msg in customer_greetings:
    result, elapsed = measure_time(get_simple_response, msg, "customer")
    check(f"Customer '{msg[:20]}...' -> response exists", result is not None)
    check(f"Customer '{msg[:20]}...' -> fast (<100ms)", elapsed < 100,
          f"took {elapsed:.2f}ms")
    check(f"Customer '{msg[:20]}...' -> has content", result and len(result) > 10)

# ══════════════════════════════════════════════════════════════════════════════
# 4. Customer Capability Questions - Must return instant responses
# ══════════════════════════════════════════════════════════════════════════════
print("\n== 4. CUSTOMER CAPABILITY QUESTIONS (Target: <100ms) ==")

customer_capability = [
    "what can you do",
    "what can you help me with",
    "who are you",
    "help",
]

for msg in customer_capability:
    result, elapsed = measure_time(get_simple_response, msg, "customer")
    check(f"Customer capability '{msg[:30]}...' -> response exists", result is not None)
    check(f"Customer capability '{msg[:30]}...' -> fast (<100ms)", elapsed < 100,
          f"took {elapsed:.2f}ms")

# ══════════════════════════════════════════════════════════════════════════════
# 5. Non-Simple Queries - Must return None (fall through to AI)
# ══════════════════════════════════════════════════════════════════════════════
print("\n== 5. NON-SIMPLE QUERIES (Must return None) ==")

non_simple_queries = [
    "show my vehicles",
    "what items are low in stock",
    "how many bookings",
    "generate a report",
    "calculate the reorder point",
    "when is my next service",
    "how much is an oil change",
]

for msg in non_simple_queries:
    result, elapsed = measure_time(get_simple_response, msg, "admin")
    check(f"Non-simple '{msg[:30]}...' -> correctly returns None", result is None,
          f"incorrectly matched with: {result[:50] if result else 'N/A'}")
    check(f"Non-simple '{msg[:30]}...' -> still fast check (<10ms)", elapsed < 10,
          f"took {elapsed:.2f}ms")

# ══════════════════════════════════════════════════════════════════════════════
# 6. is_simple_conversation() Helper Function
# ══════════════════════════════════════════════════════════════════════════════
print("\n== 6. is_simple_conversation() HELPER ==")

check("is_simple_conversation('hello') == True", is_simple_conversation("hello"))
check("is_simple_conversation('thanks') == True", is_simple_conversation("thanks"))
check("is_simple_conversation('what can you do') == True", is_simple_conversation("what can you do"))
check("is_simple_conversation('show inventory') == False", not is_simple_conversation("show inventory"))
check("is_simple_conversation('') == False", not is_simple_conversation(""))

# ══════════════════════════════════════════════════════════════════════════════
# 7. Performance Consistency - Multiple calls should be consistently fast
# ══════════════════════════════════════════════════════════════════════════════
print("\n== 7. PERFORMANCE CONSISTENCY (100 iterations) ==")

test_msg = "hello"
times = []
for _ in range(100):
    _, elapsed = measure_time(get_simple_response, test_msg, "admin")
    times.append(elapsed)

avg_time = sum(times) / len(times)
max_time = max(times)
min_time = min(times)

check(f"Average time < 10ms", avg_time < 10, f"avg={avg_time:.3f}ms")
check(f"Max time < 50ms", max_time < 50, f"max={max_time:.3f}ms")
check(f"Min time < 5ms", min_time < 5, f"min={min_time:.3f}ms")

print(f"\n  Performance stats over 100 calls:")
print(f"    Average: {avg_time:.3f}ms")
print(f"    Min:     {min_time:.3f}ms")
print(f"    Max:     {max_time:.3f}ms")

# ══════════════════════════════════════════════════════════════════════════════
# 8. Pattern Coverage - Verify all expected patterns are covered
# ══════════════════════════════════════════════════════════════════════════════
print("\n== 8. PATTERN COVERAGE ==")

# Test edge cases
edge_cases = [
    ("ok", "admin", True),  # acknowledgment
    ("okay", "admin", True),
    ("got it", "admin", True),
    ("sige", "customer", True),  # Filipino acknowledgment
    ("", "admin", False),  # empty
    ("   ", "admin", False),  # whitespace only
]

for msg, role, should_match in edge_cases:
    result = get_simple_response(msg, role)
    matched = result is not None
    check(f"Edge case '{msg}' ({role}) -> {'matches' if should_match else 'no match'}",
          matched == should_match,
          f"expected {should_match}, got {matched}")

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
print("\n" + "=" * 70)
print(f"RESULT: {PASS} passed, {FAIL} failed")
print("=" * 70)

if FAIL == 0:
    print("\n✓ All tests passed! Simple conversation responses are ultra-fast.")
    print("  Target achieved: <100ms for simple queries (most <10ms)")
else:
    print(f"\n✗ {FAIL} test(s) failed. Review output above for details.")

sys.exit(0 if FAIL == 0 else 1)
