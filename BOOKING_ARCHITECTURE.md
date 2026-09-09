# 📐 Booking System Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CUSTOMER INTERFACE                          │
│  (Mobile App / Web App / Voice Assistant)                          │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      FASTAPI SERVER (main.py)                       │
│                                                                     │
│  POST /customer/chat                                                │
│  ├─ Parse request (message, customer_uid, customer_name)           │
│  ├─ Check daily usage limits                                       │
│  ├─ Load conversation history                                      │
│  └─ Route to customer chat handler                                 │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   INTENT CLASSIFIER (model_router.py)               │
│                                                                     │
│  Deterministic Rule-Based Classification:                           │
│  ├─ MY_VEHICLES                                                     │
│  ├─ MY_SERVICE_HISTORY                                              │
│  ├─ BOOK_SERVICE ← Booking intent                                   │
│  ├─ SERVICE_RECOMMENDATION                                          │
│  └─ Other intents...                                                │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    GROQ LLM (client.py)                             │
│                    with Tool Calling                                │
│                                                                     │
│  System Prompt:                                                     │
│  ├─ Booking workflow rules                                          │
│  ├─ Conversation memory guidelines                                  │
│  ├─ Tool usage instructions                                         │
│  └─ Confirmation standards                                          │
│                                                                     │
│  Available Tools: (CUSTOMER_TOOL_SCHEMAS)                           │
│  ├─ suggest_booking_date ← NEW!                                     │
│  ├─ check_booking_availability                                      │
│  ├─ create_customer_booking                                         │
│  ├─ get_my_vehicles                                                 │
│  ├─ get_my_service_history                                          │
│  └─ Other tools...                                                  │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │                                     │
        ▼                                     ▼
┌─────────────────────┐          ┌─────────────────────┐
│  BOOKING WORKFLOW   │          │  OTHER TOOLS        │
│  (customer_tools)   │          │  (customer_tools)   │
└─────────────────────┘          └─────────────────────┘
        │
        │
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│              INTELLIGENT BOOKING FLOW                               │
└─────────────────────────────────────────────────────────────────────┘

Step 1: suggest_booking_date()
┌─────────────────────────────────────────────────────────────────────┐
│  Input: plate, service_type                                         │
│  ├─ Verify vehicle ownership                                        │
│  ├─ Get vehicle details & service frequency                         │
│  ├─ Query service history for this vehicle + service type           │
│  ├─ Calculate interval (oil=3mo, tire=6mo, brake=6mo, coolant=12mo)│
│  ├─ Calculate recommended date = last_service + interval            │
│  ├─ Determine urgency (overdue / due this week / due soon / on track)│
│  ├─ Find available slots around recommended date                    │
│  └─ Return top 4 suggested dates with reasoning                     │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
Step 2: check_booking_availability()
┌─────────────────────────────────────────────────────────────────────┐
│  Input: preferred_date, preferred_time                              │
│  ├─ Parse & validate date (must be future)                          │
│  ├─ Query existing bookings for that date                           │
│  ├─ Build list of booked time slots                                 │
│  ├─ Generate available slots (8AM-11AM, 1PM-4PM)                    │
│  └─ Return available_slots, is_available                            │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
Step 3: create_customer_booking()
┌─────────────────────────────────────────────────────────────────────┐
│  Input: plate, services, preferred_date, preferred_time, notes      │
│  ├─ Validate all required fields present                            │
│  ├─ Verify vehicle ownership (security check)                       │
│  ├─ Verify services exist in catalog                                │
│  ├─ Validate & parse date                                           │
│  ├─ Check availability again (last minute verification)             │
│  ├─ Get vehicle description                                         │
│  ├─ Create booking document in Firestore                            │
│  ├─ Verify write succeeded (read back)                              │
│  └─ Return success with booking_id & all details                    │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      FIRESTORE DATABASE                             │
│                                                                     │
│  Collections:                                                       │
│  ├─ service_bookings (booking records)                              │
│  ├─ vehicles (vehicle details & service frequency)                  │
│  ├─ maintenance (service history)                                   │
│  ├─ item_master (service catalog)                                   │
│  └─ users (customer profiles)                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow - Complete Booking Example

```
1. Customer Message
   ↓
   "I want to book an oil change"
   ↓

2. LLM Receives Context
   ↓
   System Prompt: "When customer wants to book, ALWAYS call 
                   suggest_booking_date first..."
   Message: "I want to book an oil change"
   History: [previous conversation turns]
   Tools: [suggest_booking_date, check_booking_availability, ...]
   ↓

3. LLM Decides to Call Tool
   ↓
   Tool: suggest_booking_date
   Args: {
     plate: "ABC123",  (from conversation history or will ask)
     service_type: "oil change"
   }
   ↓

4. Tool Execution: suggest_booking_date()
   ↓
   Query vehicle: "ABC123"
   ├─ last_service_date: "2026-01-15"
   ├─ service_frequency: 3 months
   └─ Query maintenance history for oil changes
   ↓
   Calculate: 2026-01-15 + 3 months = 2026-04-15
   ↓
   Check availability around 2026-04-15
   ├─ 2026-04-15: [8AM, 9AM, 10AM, 11AM] available
   ├─ 2026-04-16: [9AM, 1PM, 2PM] available
   └─ 2026-04-17: [8AM, 9AM] available
   ↓
   Return: {
     "suggested_dates": [
       {
         "date": "2026-04-15",
         "available_slots": ["8:00 AM", "9:00 AM", ...],
         "is_recommended": true
       }
     ],
     "reasoning": [
       "Oil change services are typically every 3 months",
       "Your last oil change was on January 15, 2026",
       "✅ Your next service is recommended in 30 days"
     ]
   }
   ↓

5. LLM Formats Response
   ↓
   "Based on your last oil change on January 15, your next 
    service is recommended around April 15, 2026.
    
    ⭐ April 15, 2026 (Tuesday) - RECOMMENDED
       Available: 8:00 AM, 9:00 AM, 10:00 AM, 11:00 AM
    
    April 16, 2026 (Wednesday)
       Available: 9:00 AM, 1:00 PM, 2:00 PM
    
    Would any of these work for you?"
   ↓

6. Customer Responds
   ↓
   "April 15 at 9 AM works"
   ↓

7. LLM Decides to Call Tools
   ↓
   Tool 1: check_booking_availability
   Args: {
     preferred_date: "2026-04-15",
     preferred_time: "9:00 AM"
   }
   ↓
   Result: { "is_available": true }
   ↓
   Tool 2: create_customer_booking
   Args: {
     plate: "ABC123",
     services: ["Change Oil"],
     preferred_date: "2026-04-15",
     preferred_time: "9:00 AM"
   }
   ↓

8. Tool Execution: create_customer_booking()
   ↓
   Validate: ✓ plate owned by customer
   Validate: ✓ service in catalog
   Validate: ✓ date is future
   Validate: ✓ slot available
   ↓
   Firestore: Create document in service_bookings
   {
     "customerId": "customer_uid_123",
     "plate": "ABC123",
     "services": ["Change Oil"],
     "preferredDate": "2026-04-15",
     "preferredTime": "9:00 AM",
     "status": "Pending",
     "createdAt": "2026-03-10T14:30:00Z"
   }
   ↓
   Read back to verify
   ↓
   Return: {
     "success": true,
     "booking_id": "BK20260315001",
     "plate": "ABC123",
     "vehicle": "2020 Toyota Fortuner",
     "services": ["Change Oil"],
     "date": "April 15, 2026",
     "time": "9:00 AM",
     "status": "Pending",
     "message": "Your booking has been successfully created..."
   }
   ↓

9. LLM Formats Final Response
   ↓
   "✅ Perfect! Your booking is confirmed.
   
   Booking Details:
   • Booking ID: BK20260315001
   • Vehicle: ABC123 - 2020 Toyota Fortuner
   • Service: Change Oil
   • Date: April 15, 2026
   • Time: 9:00 AM
   • Status: Pending
   
   Your booking is now pending confirmation. Our team will 
   review and confirm your appointment shortly. You can check 
   your booking status anytime by asking 'show my bookings'."
   ↓

10. Response Sent to Customer
    ↓
    Display in mobile app / web interface
```

---

## Security Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLIENT REQUEST                              │
│  { message, customer_uid, customer_name }                           │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    FIREBASE AUTHENTICATION                          │
│  ├─ Verify Firebase Auth token                                     │
│  ├─ Extract customer_uid from token (server-side)                   │
│  └─ NEVER trust client-provided UID                                 │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     TOOL PARAMETER INJECTION                        │
│  All customer tools receive:                                        │
│  ├─ customer_uid (injected server-side, cannot be spoofed)         │
│  ├─ customer_name (from authenticated session)                      │
│  └─ LLM CANNOT override these parameters                            │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    OWNERSHIP VERIFICATION                           │
│  Every tool verifies:                                               │
│  ├─ Vehicle ownership (4-pass lookup)                               │
│  ├─ Booking ownership (customerId == customer_uid)                  │
│  └─ Service catalog validation                                      │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        DATA ISOLATION                               │
│  Customers can ONLY access:                                         │
│  ├─ Their own vehicles                                              │
│  ├─ Their own service history                                       │
│  ├─ Their own bookings                                              │
│  └─ Public service catalog (prices only, no stock info)             │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Relationships

```
┌──────────────────┐
│   FastAPI        │
│   main.py        │
└────────┬─────────┘
         │
         ├─────────────┐
         │             │
         ▼             ▼
┌──────────────┐  ┌──────────────┐
│ Admin Chat   │  │Customer Chat │
│  Handler     │  │  Handler     │
└──────┬───────┘  └──────┬───────┘
       │                 │
       ▼                 ▼
┌──────────────┐  ┌──────────────┐
│Model Router  │  │Model Router  │
│(classify)    │  │(classify)    │
└──────┬───────┘  └──────┬───────┘
       │                 │
       ▼                 ▼
┌──────────────┐  ┌──────────────┐
│  Groq LLM    │  │  Groq LLM    │
│  + Tools     │  │  + Tools     │
└──────┬───────┘  └──────┬───────┘
       │                 │
       ▼                 ▼
┌──────────────┐  ┌──────────────────────┐
│firestore_    │  │customer_tools.py     │
│tools.py      │  │                      │
│              │  │ • suggest_booking_   │
│• get_vehicles│  │   date()             │
│• get_stock   │  │ • check_booking_     │
│• get_bookings│  │   availability()     │
│  (all)       │  │ • create_customer_   │
│              │  │   booking()          │
│              │  │ • get_my_vehicles()  │
│              │  │ • get_my_service_    │
│              │  │   history()          │
└──────┬───────┘  └──────┬───────────────┘
       │                 │
       └────────┬────────┘
                │
                ▼
       ┌────────────────┐
       │   Firestore    │
       │   Database     │
       │                │
       │ • vehicles     │
       │ • maintenance  │
       │ • service_     │
       │   bookings     │
       │ • item_master  │
       │ • users        │
       └────────────────┘
```

---

## Cache & Performance

```
┌─────────────────────────────────────────────────────────────────────┐
│                      CACHE LAYER (cache_manager.py)                 │
│                                                                     │
│  Service Catalog Cache:                                             │
│  ├─ TTL: 300 seconds (5 minutes)                                    │
│  ├─ Key: "service_catalog"                                          │
│  ├─ Invalidate: Manual via /cache/invalidate                        │
│  └─ Reduces Firestore reads by ~90%                                 │
│                                                                     │
│  Company Name Cache:                                                │
│  ├─ TTL: 600 seconds (10 minutes)                                   │
│  ├─ Key: "company_name_{customer_uid}"                              │
│  └─ Reduces user lookups                                            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Session Management

```
┌─────────────────────────────────────────────────────────────────────┐
│                  SESSION STORE (session_store.py)                   │
│                                                                     │
│  In-Memory Conversation History:                                    │
│  ├─ Key: session_id                                                 │
│  ├─ Value: [ {role, content}, {role, content}, ... ]              │
│  ├─ Max history: Last 6 messages (GROQ_MAX_HISTORY_MSGS)           │
│  └─ Enables conversation memory for booking flow                    │
│                                                                     │
│  Conversation Context Example:                                      │
│  Turn 1: "I want to book" (customer initiates)                     │
│  Turn 2: "Which vehicle?" (AI asks)                                │
│  Turn 3: "My Toyota" (customer responds)                           │
│  Turn 4: "What service?" (AI asks)                                 │
│  Turn 5: "Oil change" (customer responds)                          │
│  → AI remembers "Toyota" and "oil change" for turn 6               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Error Handling Flow

```
create_customer_booking()
    │
    ├─ Validate fields
    │  └─ Missing? → Return MISSING_FIELDS error
    │
    ├─ Verify vehicle ownership
    │  └─ Not owned? → Return VEHICLE_NOT_OWNED error
    │
    ├─ Verify services in catalog
    │  └─ Not found? → Return SERVICE_NOT_FOUND error
    │
    ├─ Parse date
    │  └─ Invalid? → Return INVALID_DATE error
    │  └─ Past? → Return PAST_DATE error
    │
    ├─ Check availability
    │  └─ Not available? → Return TIME_NOT_AVAILABLE error
    │  └─ Fully booked? → Return DATE_FULLY_BOOKED error
    │
    ├─ Create booking in Firestore
    │  └─ Write failed? → Return DB_WRITE_FAILED error
    │
    └─ Success → Return booking details with booking_id
```

---

This architecture ensures:
- ✅ Security through server-side UID injection
- ✅ Performance through caching
- ✅ Intelligence through service history analysis
- ✅ Reliability through comprehensive validation
- ✅ User experience through conversation memory
