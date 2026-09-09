# AI Assistant Booking System Guide

## Overview

The AI assistant booking system enables customers to book automotive services through natural conversation. The system intelligently suggests booking dates based on vehicle service history, maintenance intervals, and current availability.

## Key Features

### 1. **Intelligent Date Suggestions** 🎯
The AI analyzes:
- Vehicle's last service date
- Service type (oil change, tire rotation, brake service, etc.)
- Recommended maintenance intervals
- Current slot availability

**Example intervals:**
- Oil Change / PMS: Every 3 months
- Tire Services: Every 6 months  
- Brake Services: Every 6 months
- Coolant Flush: Every 12 months

### 2. **Conversational Booking Flow** 💬
The AI remembers conversation context and guides customers through booking:

```
Customer: "I want to book an oil change"
AI: (Checks service history) "Based on your last oil change on Jan 15, 2026, 
     I recommend booking around April 15. I have these slots available:
     - April 15 at 9:00 AM ⭐ RECOMMENDED
     - April 16 at 10:00 AM
     - April 17 at 9:00 AM
     Would any of these work for you?"

Customer: "9 AM on April 15 works"
AI: (Creates booking) "✅ Perfect! Your oil change is booked for April 15 
     at 9:00 AM. Booking ID: ABC123. Status: Pending confirmation."
```

### 3. **Progressive Information Collection** 📝
The AI only asks for missing information:
- ✅ Vehicle plate (from customer's registered vehicles)
- ✅ Service type(s)
- ✅ Preferred date (suggests if not provided)
- ✅ Preferred time

### 4. **Comprehensive Validation** ✓
Before creating a booking, the system verifies:
1. Vehicle ownership (plate must belong to customer)
2. Service exists in catalog
3. Date is valid and in the future
4. Time slot is available
5. All required fields are provided

### 5. **Booking Management** 📅
Customers can:
- View all bookings: "Show my bookings"
- Reschedule: "Move my appointment to next week"
- Cancel: "Cancel my booking ABC123"
- Check status: "What's the status of my booking?"

## Technical Implementation

### New Tool: `suggest_booking_date`

**Purpose:** Provides intelligent date suggestions based on service history and maintenance intervals.

**Parameters:**
- `plate`: Vehicle plate number (required)
- `service_type`: Type of service, e.g., "oil change" (optional)

**Returns:**
```json
{
  "vehicle_plate": "ABC123",
  "vehicle_desc": "2020 Toyota Fortuner",
  "service_type": "oil change",
  "last_service_date": "2026-01-15",
  "interval_months": 3,
  "suggested_dates": [
    {
      "date": "2026-04-15",
      "date_display": "April 15, 2026 (Tuesday)",
      "available_slots": ["8:00 AM", "9:00 AM", "10:00 AM"],
      "is_recommended": true
    }
  ],
  "reasoning": [
    "Oil change services are typically recommended every 3 months or 5,000 km.",
    "Your last oil change was on January 15, 2026.",
    "✅ Your next service is recommended in 30 days."
  ]
}
```

### Enhanced Tool: `create_customer_booking`

**Workflow:**
1. Validate all required fields
2. Verify vehicle ownership
3. Verify services exist in catalog
4. Parse and validate date
5. Check slot availability
6. Create booking in Firestore
7. Verify write succeeded
8. Return detailed confirmation

**Enhanced Confirmation Message:**
```
✅ Your booking has been successfully created.

Booking Details:
• Booking ID: BK20260315001
• Vehicle: ABC123 - 2020 Toyota Fortuner
• Service: Change Oil, Oil Filter Replacement
• Date: March 15, 2026
• Time: 9:00 AM
• Status: Pending

Your booking is now pending confirmation. Our team will review and confirm 
your appointment shortly. You can check your booking status anytime by 
asking "show my bookings".
```

## AI Assistant System Prompt Updates

### Enhanced Booking Workflow Rules

1. **Intelligent Date Suggestion**
   - ALWAYS call `suggest_booking_date` when customer initiates booking
   - Present suggestions conversationally with reasoning
   - Explain why specific dates are recommended

2. **Conversation Memory**
   - Remember vehicle plate from earlier in conversation
   - Remember service type mentioned
   - Only ask for truly missing information
   - Don't re-ask for provided details

3. **Confirmation Standards**
   - Only claim success when tool returns `success=True`
   - Include all booking details in confirmation
   - Explain next steps (pending confirmation, how to check status)
   - Provide booking ID for reference

4. **Error Handling**
   - Specific error messages for each failure type
   - Offer alternatives when slot unavailable
   - Guide customer through fixing issues

## Service Type Interval Detection

The system automatically detects service intervals:

| Service Keywords | Interval | Examples |
|-----------------|----------|----------|
| oil, pms, preventive | 3 months | "oil change", "PMS", "change oil" |
| tire, alignment, balance | 6 months | "tire rotation", "wheel alignment" |
| brake, brakes | 6 months | "brake service", "brake fluid" |
| coolant, radiator, flush | 12 months | "coolant flush", "radiator service" |
| *custom* | Vehicle frequency | Falls back to vehicle's `serviceFrequency` field |

## Example Conversations

### Scenario 1: Customer with Service History

```
Customer: "I need to book a service"

AI: "I'd be happy to help! Which vehicle would you like to book for?"

Customer: "My Toyota"

AI: (calls get_my_vehicles) "I see you have a 2020 Toyota Fortuner (ABC123). 
     What type of service do you need?"

Customer: "Oil change"

AI: (calls suggest_booking_date)
     "Based on your last oil change on January 15, your next service is 
     recommended around April 15. Here are my available dates:
     
     ⭐ April 15, 2026 (Tuesday) - RECOMMENDED
        Available: 8:00 AM, 9:00 AM, 10:00 AM, 11:00 AM
     
     April 16, 2026 (Wednesday)
        Available: 9:00 AM, 1:00 PM, 2:00 PM
     
     Would any of these work for you?"

Customer: "April 15 at 9 AM"

AI: (calls check_booking_availability, then create_customer_booking)
     "✅ Perfect! I've booked your oil change for April 15 at 9:00 AM.
     
     Booking ID: BK20260315001
     Vehicle: ABC123 - 2020 Toyota Fortuner
     Service: Change Oil
     Status: Pending confirmation
     
     Our team will confirm your appointment shortly. You can check the 
     status anytime by saying 'show my bookings'."
```

### Scenario 2: Customer Lacks Some Details

```
Customer: "Book me for next Tuesday at 9 AM"

AI: "I'd be happy to book that for you! Which vehicle should I book this for?"

Customer: "ABC123"

AI: (calls get_my_vehicles to verify ownership)
     "Great! What service would you like to book for your 2020 Toyota Fortuner?"

Customer: "Oil change"

AI: (calls check_booking_availability for next Tuesday 9 AM)
     "Perfect! I can confirm that Tuesday, March 18 at 9:00 AM is available. 
     Shall I book your oil change for that time?"

Customer: "Yes"

AI: (calls create_customer_booking)
     "✅ All set! Your oil change is booked for March 18, 2026 at 9:00 AM..."
```

### Scenario 3: Overdue Service

```
Customer: "When should I get my next service?"

AI: (calls get_service_recommendations)
     "⚠️ Your 2020 Toyota Fortuner (ABC123) is overdue for service! 
     Your last PMS was on November 15, 2025, and with a 3-month interval, 
     you were due on February 15.
     
     Would you like me to help you book a service?"

Customer: "Yes please"

AI: (calls suggest_booking_date for oil change)
     "I have availability as soon as tomorrow! Here are some options:
     
     March 11, 2026 (Tomorrow)
        Available: 9:00 AM, 10:00 AM, 1:00 PM
     
     March 12, 2026 (Thursday)
        Available: 8:00 AM, 9:00 AM, 11:00 AM
     
     Which would work best for you?"
```

## Testing

Run the comprehensive test suite:

```powershell
cd ai_assistant
python test_booking_flow.py
```

**Test Coverage:**
1. ✅ Intelligent date suggestion based on service history
2. ✅ Service type interval detection
3. ✅ Complete booking workflow with conversation memory
4. ✅ Missing information handling
5. ✅ Availability checking
6. ✅ Past date validation
7. ✅ Booking confirmation details
8. ✅ Booking list verification

## Database Schema

### service_bookings Collection

```javascript
{
  "customerId": "firebase_auth_uid",      // Customer's Firebase Auth UID
  "customerName": "John Doe",             // Display name
  "plate": "ABC123",                      // Vehicle plate (uppercase)
  "vehicleDesc": "2020 Toyota Fortuner",  // Human-readable vehicle description
  "services": ["Change Oil", "Oil Filter"], // Array of service names
  "preferredDate": "2026-04-15",         // YYYY-MM-DD format
  "preferredTime": "9:00 AM",            // Time slot
  "status": "Pending",                    // Pending|Confirmed|Completed|Cancelled
  "notes": "Customer notes",              // Optional notes
  "createdAt": "2026-03-10T14:30:00Z",   // ISO timestamp
  "createdBy": "customer_ai",             // Source indicator
  "updatedAt": "2026-03-10T14:35:00Z",   // Last update timestamp
  "cancelledAt": "",                      // Set when cancelled
  "cancelledBy": "",                      // "customer" or "admin"
  "cancelReason": ""                      // Optional cancellation reason
}
```

## Security & Privacy

1. **Identity Verification**: `customer_uid` is ALWAYS injected server-side from authenticated Firebase session
2. **Ownership Checks**: All booking operations verify vehicle ownership through 4-pass lookup
3. **Data Isolation**: Customers can only view/modify their own bookings
4. **Access Denial**: Any attempt to access another customer's data returns `ACCESS_DENIED` error

## Future Enhancements

Potential improvements:
- [ ] SMS/Email booking confirmations
- [ ] Booking reminders (24 hours before)
- [ ] Multi-vehicle batch booking
- [ ] Recurring maintenance schedules
- [ ] Service package recommendations
- [ ] Real-time mechanic availability
- [ ] Integration with calendar apps
- [ ] Booking wait-list for full dates

## Support

For issues or questions:
- **Email**: caltexautopro2026@gmail.com
- **Test File**: `test_booking_flow.py`
- **Documentation**: This file
