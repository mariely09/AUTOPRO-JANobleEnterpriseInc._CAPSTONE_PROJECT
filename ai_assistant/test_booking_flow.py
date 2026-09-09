"""
test_booking_flow.py — Comprehensive booking workflow test suite

Tests the complete customer booking experience with intelligent date suggestions
based on service history and PMS intervals.

Run: python test_booking_flow.py
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from customer_tools import (
    get_my_vehicles,
    get_my_service_history,
    suggest_booking_date,
    check_booking_availability,
    create_customer_booking,
    get_my_bookings,
    update_my_booking,
    cancel_my_booking,
)
from datetime import datetime, timedelta

# ANSI color codes
BOLD = "\033[1m"
GREEN = "\033[92m"
RED = "\033[91m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
RESET = "\033[0m"

# Test customer (replace with actual test customer UID from your Firestore)
TEST_CUSTOMER_UID = "test_customer_123"
TEST_CUSTOMER_NAME = "Test Customer"

passed = 0
failed = 0


def print_test(name: str, result: bool, details: str = ""):
    global passed, failed
    if result:
        print(f"{GREEN}✓{RESET} {name}")
        if details:
            print(f"  {details}")
        passed += 1
    else:
        print(f"{RED}✗{RESET} {name}")
        if details:
            print(f"  {RED}{details}{RESET}")
        failed += 1


# =============================================================================
# TEST 1: Suggest booking date based on service history (oil change)
# =============================================================================
print(f"\n{CYAN}{'='*80}{RESET}")
print(f"{BOLD}TEST 1: Intelligent Date Suggestion - Oil Change{RESET}")
print(f"{CYAN}{'='*80}{RESET}\n")

print("Step 1: Get customer vehicles...")
vehicles_result = get_my_vehicles(
    customer_uid=TEST_CUSTOMER_UID,
    customer_name=TEST_CUSTOMER_NAME
)

if vehicles_result.get("total_vehicles", 0) > 0:
    test_plate = vehicles_result["vehicles"][0]["plate"]
    print(f"  Found vehicle: {test_plate}")
    
    print(f"\nStep 2: Get service history for {test_plate}...")
    history_result = get_my_service_history(
        customer_uid=TEST_CUSTOMER_UID,
        customer_name=TEST_CUSTOMER_NAME,
        plate=test_plate,
        recent=3
    )
    print(f"  Total services: {history_result.get('total_jobs', 0)}")
    if history_result.get("jobs"):
        print(f"  Last service: {history_result['jobs'][0].get('date', 'N/A')}")
    
    print(f"\nStep 3: Suggest booking date for oil change...")
    suggestion_result = suggest_booking_date(
        customer_uid=TEST_CUSTOMER_UID,
        customer_name=TEST_CUSTOMER_NAME,
        plate=test_plate,
        service_type="oil change"
    )
    
    has_suggestions = len(suggestion_result.get("suggested_dates", [])) > 0
    print_test(
        "Date suggestion returns available dates",
        has_suggestions,
        f"Suggested {len(suggestion_result.get('suggested_dates', []))} dates"
    )
    
    if has_suggestions:
        print(f"\n  {BOLD}Suggested Dates:{RESET}")
        for i, date_info in enumerate(suggestion_result["suggested_dates"][:3], 1):
            indicator = "⭐ RECOMMENDED" if date_info.get("is_recommended") else ""
            print(f"    {i}. {date_info['date_display']} {indicator}")
            print(f"       Available slots: {', '.join(date_info['available_slots'][:4])}")
        
        if suggestion_result.get("reasoning"):
            print(f"\n  {BOLD}Reasoning:{RESET}")
            for reason in suggestion_result["reasoning"]:
                print(f"    • {reason}")
    
    print_test(
        "Suggestion includes service context",
        bool(suggestion_result.get("service_context")),
        suggestion_result.get("service_context", "")[:100]
    )
    
    print_test(
        "Interval calculation is correct",
        suggestion_result.get("interval_months") == 3,  # Oil change = 3 months
        f"Interval: {suggestion_result.get('interval_months')} months"
    )
else:
    print(f"{YELLOW}⚠ No vehicles found for test customer. Skipping date suggestion tests.{RESET}")


# =============================================================================
# TEST 2: Complete booking workflow with conversation memory simulation
# =============================================================================
print(f"\n{CYAN}{'='*80}{RESET}")
print(f"{BOLD}TEST 2: Complete Booking Workflow (Simulating Conversation Memory){RESET}")
print(f"{CYAN}{'='*80}{RESET}\n")

# Simulate a conversation where customer provides details progressively
print(f"{BOLD}Conversation Simulation:{RESET}")
print(f"Customer: \"I want to book an oil change\"")
print(f"AI: (calls suggest_booking_date for oil change)")

if vehicles_result.get("total_vehicles", 0) > 0:
    test_plate = vehicles_result["vehicles"][0]["plate"]
    
    suggestion = suggest_booking_date(
        customer_uid=TEST_CUSTOMER_UID,
        customer_name=TEST_CUSTOMER_NAME,
        plate=test_plate,
        service_type="oil change"
    )
    
    print(f"AI: \"Based on your service history, I recommend {suggestion['suggested_dates'][0]['date_display']}\"")
    print(f"    \"Available slots: {', '.join(suggestion['suggested_dates'][0]['available_slots'][:3])}\"")
    print(f"\nCustomer: \"Book me for {suggestion['suggested_dates'][0]['available_slots'][0]}\"")
    
    # Now create the booking
    booking_date = suggestion['suggested_dates'][0]['date']
    booking_time = suggestion['suggested_dates'][0]['available_slots'][0]
    
    print(f"\nAI: (creating booking with remembered details)")
    booking_result = create_customer_booking(
        customer_uid=TEST_CUSTOMER_UID,
        customer_name=TEST_CUSTOMER_NAME,
        plate=test_plate,
        services=["Change Oil"],
        preferred_date=booking_date,
        preferred_time=booking_time,
        notes="Booking created via AI assistant test"
    )
    
    booking_success = booking_result.get("success", False)
    print_test(
        "Booking created successfully",
        booking_success,
        f"Booking ID: {booking_result.get('booking_id', 'N/A')}"
    )
    
    if booking_success:
        booking_id = booking_result["booking_id"]
        
        print(f"\n  {BOLD}Booking Confirmation:{RESET}")
        print(f"    Booking ID: {booking_id}")
        print(f"    Vehicle: {booking_result['plate']} - {booking_result['vehicle']}")
        print(f"    Service: {', '.join(booking_result['services'])}")
        print(f"    Date: {booking_result['date']}")
        print(f"    Time: {booking_result['time']}")
        print(f"    Status: {booking_result['status']}")
        
        print_test(
            "Confirmation includes all required details",
            all(k in booking_result for k in ['booking_id', 'plate', 'services', 'date', 'time', 'status']),
            "All fields present"
        )
        
        print_test(
            "Confirmation message is informative",
            len(booking_result.get('message', '')) > 50,
            booking_result.get('message', '')[:100] + "..."
        )
        
        # Verify the booking appears in customer's booking list
        print(f"\nCustomer: \"Show my bookings\"")
        my_bookings = get_my_bookings(
            customer_uid=TEST_CUSTOMER_UID,
            customer_name=TEST_CUSTOMER_NAME,
            filter_status="Pending"
        )
        
        booking_found = any(b["booking_id"] == booking_id for b in my_bookings.get("bookings", []))
        print_test(
            "Booking appears in customer's booking list",
            booking_found,
            f"Found {my_bookings.get('total', 0)} total bookings"
        )
        
        # Clean up - cancel the test booking
        print(f"\nCleaning up test booking...")
        cancel_result = cancel_my_booking(
            customer_uid=TEST_CUSTOMER_UID,
            customer_name=TEST_CUSTOMER_NAME,
            booking_id=booking_id,
            reason="Test booking cleanup"
        )
        print_test(
            "Test booking cancelled successfully",
            cancel_result.get("success", False),
            "Cleanup complete"
        )


# =============================================================================
# TEST 3: Date suggestion for different service types
# =============================================================================
print(f"\n{CYAN}{'='*80}{RESET}")
print(f"{BOLD}TEST 3: Service Type Interval Detection{RESET}")
print(f"{CYAN}{'='*80}{RESET}\n")

if vehicles_result.get("total_vehicles", 0) > 0:
    test_plate = vehicles_result["vehicles"][0]["plate"]
    
    service_types = [
        ("oil change", 3),      # 3 months
        ("tire rotation", 6),   # 6 months
        ("brake service", 6),   # 6 months
        ("coolant flush", 12),  # 12 months
    ]
    
    for service_name, expected_interval in service_types:
        result = suggest_booking_date(
            customer_uid=TEST_CUSTOMER_UID,
            customer_name=TEST_CUSTOMER_NAME,
            plate=test_plate,
            service_type=service_name
        )
        
        actual_interval = result.get("interval_months")
        print_test(
            f"{service_name.title()} interval detection",
            actual_interval == expected_interval,
            f"Expected {expected_interval} months, got {actual_interval} months"
        )


# =============================================================================
# TEST 4: Missing information handling (conversational collection)
# =============================================================================
print(f"\n{CYAN}{'='*80}{RESET}")
print(f"{BOLD}TEST 4: Missing Information Handling{RESET}")
print(f"{CYAN}{'='*80}{RESET}\n")

# Try to create booking without plate
print("Test: Create booking without vehicle plate")
result = create_customer_booking(
    customer_uid=TEST_CUSTOMER_UID,
    customer_name=TEST_CUSTOMER_NAME,
    plate="",  # Missing
    services=["Change Oil"],
    preferred_date=(datetime.now() + timedelta(days=7)).strftime("%Y-%m-%d"),
    preferred_time="9:00 AM"
)
print_test(
    "Returns error for missing plate",
    result.get("error") == "MISSING_FIELDS",
    result.get("message", "")
)

# Try to create booking without services
print("\nTest: Create booking without services")
result = create_customer_booking(
    customer_uid=TEST_CUSTOMER_UID,
    customer_name=TEST_CUSTOMER_NAME,
    plate=test_plate if vehicles_result.get("total_vehicles", 0) > 0 else "ABC123",
    services=[],  # Missing
    preferred_date=(datetime.now() + timedelta(days=7)).strftime("%Y-%m-%d"),
    preferred_time="9:00 AM"
)
print_test(
    "Returns error for missing services",
    result.get("error") == "MISSING_FIELDS",
    result.get("message", "")
)

# Try to create booking without date
print("\nTest: Create booking without date")
result = create_customer_booking(
    customer_uid=TEST_CUSTOMER_UID,
    customer_name=TEST_CUSTOMER_NAME,
    plate=test_plate if vehicles_result.get("total_vehicles", 0) > 0 else "ABC123",
    services=["Change Oil"],
    preferred_date="",  # Missing
    preferred_time="9:00 AM"
)
print_test(
    "Returns error for missing date",
    result.get("error") == "MISSING_FIELDS",
    result.get("message", "")
)


# =============================================================================
# TEST 5: Availability checking
# =============================================================================
print(f"\n{CYAN}{'='*80}{RESET}")
print(f"{BOLD}TEST 5: Availability Checking{RESET}")
print(f"{CYAN}{'='*80}{RESET}\n")

next_week = (datetime.now() + timedelta(days=7)).strftime("%Y-%m-%d")
print(f"Checking availability for {next_week}...")

avail_result = check_booking_availability(
    customer_uid=TEST_CUSTOMER_UID,
    customer_name=TEST_CUSTOMER_NAME,
    preferred_date=next_week
)

print_test(
    "Availability check returns valid response",
    "available_slots" in avail_result,
    f"Available slots: {len(avail_result.get('available_slots', []))}"
)

print_test(
    "Returns standard time slots",
    len(avail_result.get("available_slots", [])) > 0,
    f"Slots: {', '.join(avail_result.get('available_slots', [])[:4])}"
)

# Check past date validation
past_date = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
past_result = check_booking_availability(
    customer_uid=TEST_CUSTOMER_UID,
    customer_name=TEST_CUSTOMER_NAME,
    preferred_date=past_date
)

print_test(
    "Rejects past dates",
    past_result.get("error") == "PAST_DATE",
    past_result.get("message", "")
)


# =============================================================================
# SUMMARY
# =============================================================================
print(f"\n{CYAN}{'='*80}{RESET}")
print(f"{BOLD}TEST SUMMARY{RESET}")
print(f"{CYAN}{'='*80}{RESET}\n")

total = passed + failed
pass_rate = (passed / total * 100) if total > 0 else 0

print(f"  Total Tests: {total}")
print(f"  {GREEN}Passed: {passed}{RESET}")
print(f"  {RED}Failed: {failed}{RESET}")
print(f"  Pass Rate: {pass_rate:.1f}%\n")

if failed == 0:
    print(f"{GREEN}{BOLD}✓ All tests passed!{RESET}\n")
    sys.exit(0)
else:
    print(f"{RED}{BOLD}✗ Some tests failed.{RESET}\n")
    sys.exit(1)
