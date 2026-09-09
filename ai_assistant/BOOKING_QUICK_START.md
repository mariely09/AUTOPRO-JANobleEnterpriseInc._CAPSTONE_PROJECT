# Booking System - Quick Start Guide

## For Customers 👤

### How to Book a Service

Just talk naturally to the AI! Here are some ways to start:

**Simple requests:**
- "I want to book a service"
- "Book an oil change"
- "Schedule my car for maintenance"
- "I need a PMS"

**The AI will guide you through:**
1. Which vehicle (if you have multiple)
2. What service you need
3. When you'd like to come in (with smart suggestions!)

**Example conversation:**
```
You: "I want to book an oil change"

AI: "Based on your last oil change on January 15, I recommend 
     booking around April 15. I have these slots available:
     - April 15 at 9:00 AM ⭐ RECOMMENDED
     - April 16 at 10:00 AM
     Would any of these work for you?"

You: "9 AM on April 15 works"

AI: "✅ Perfect! Your oil change is booked for April 15, 2026 
     at 9:00 AM. Booking ID: BK123. Status: Pending."
```

### Check Your Bookings

- "Show my bookings"
- "What appointments do I have?"
- "My upcoming services"

### Reschedule

- "Reschedule my appointment"
- "Move my booking to next week"
- "Change my appointment date"

### Cancel

- "Cancel my booking"
- "Cancel appointment BK123"

### Get Recommendations

- "When should I get my next service?"
- "Is my car due for maintenance?"
- "What services do I need?"

## For Developers 💻

### Quick Implementation Check

1. **Verify the new tool exists:**
   ```python
   from customer_tools import suggest_booking_date
   
   # Test with a customer vehicle
   result = suggest_booking_date(
       customer_uid="test_uid",
       customer_name="Test Customer",
       plate="ABC123",
       service_type="oil change"
   )
   print(result)
   ```

2. **Run the test suite:**
   ```powershell
   cd ai_assistant
   python test_booking_flow.py
   ```

3. **Check tool registration:**
   ```python
   from customer_tools import CUSTOMER_TOOL_SCHEMAS, CUSTOMER_TOOL_FUNCTIONS
   
   # Verify suggest_booking_date is registered
   tool_names = [s['function']['name'] for s in CUSTOMER_TOOL_SCHEMAS]
   assert 'suggest_booking_date' in tool_names
   assert 'suggest_booking_date' in CUSTOMER_TOOL_FUNCTIONS
   ```

### API Endpoints

The customer chat endpoint automatically has access to the new booking features:

**Endpoint:** `POST /customer/chat`

**Request:**
```json
{
  "message": "I want to book an oil change",
  "customer_uid": "firebase_auth_uid",
  "customer_name": "John Doe",
  "session_id": "optional_session_id"
}
```

**Response:**
```json
{
  "reply": "Based on your last oil change on...",
  "session_id": "session_id",
  "tool_calls": [
    {
      "tool": "suggest_booking_date",
      "result": {...}
    }
  ]
}
```

### Integration with Frontend

**Mobile App (Flutter):**
```dart
// Customer initiates booking
final response = await apiService.sendMessage(
  message: "I want to book an oil change",
  customerUid: firebaseUser.uid,
  customerName: firebaseUser.displayName,
);

// Display AI response with suggestions
showDialog(
  context: context,
  child: BookingSuggestionDialog(
    suggestions: response.toolCalls
        .where((t) => t.tool == 'suggest_booking_date')
        .first
        .result['suggested_dates'],
  ),
);
```

**Web App (JavaScript):**
```javascript
// Send booking request
const response = await fetch('/customer/chat', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    message: "I want to book an oil change",
    customer_uid: firebase.auth().currentUser.uid,
    customer_name: firebase.auth().currentUser.displayName,
    session_id: sessionId
  })
});

const data = await response.json();
displayAIMessage(data.reply);
```

## Key Features at a Glance

### ✅ Intelligent Date Suggestions
- Based on actual service history
- Considers service type intervals
- Shows available time slots
- Explains reasoning

### ✅ Conversation Memory  
- Remembers vehicle from earlier
- Remembers service type mentioned
- Only asks for missing info
- Natural conversation flow

### ✅ Comprehensive Validation
- Verifies vehicle ownership
- Checks service exists
- Validates date/time
- Confirms slot availability

### ✅ Clear Confirmations
- Booking ID for reference
- All booking details
- Status explanation
- Next steps guidance

## Service Intervals Reference

| Service Type | Recommended Interval | Keywords |
|--------------|---------------------|----------|
| Oil Change / PMS | 3 months | "oil", "pms", "change oil", "preventive" |
| Tire Services | 6 months | "tire", "rotation", "alignment", "balance" |
| Brake Services | 6 months | "brake", "brakes", "brake fluid" |
| Coolant Services | 12 months | "coolant", "radiator", "flush" |

## Common Customer Questions

**Q: How does the AI know when I'm due for service?**
A: The AI checks your vehicle's service history and the recommended interval for each service type. For example, oil changes are typically every 3 months.

**Q: Can I book for multiple vehicles at once?**
A: Currently, each booking is for one vehicle. To book multiple vehicles, make separate bookings for each one.

**Q: What if my preferred time isn't available?**
A: The AI will suggest alternative times on the same day or nearby dates with availability.

**Q: How do I know my booking was successful?**
A: You'll receive a confirmation with your Booking ID and all details. You can also check anytime by asking "show my bookings".

**Q: Can I reschedule after booking?**
A: Yes! Just say "reschedule my appointment" and the AI will help you choose a new date and time.

## Troubleshooting

### Issue: Date suggestions seem wrong
**Check:**
- Is the vehicle's last service date recorded correctly?
- Is the service frequency set in the vehicle record?
- Does the service type match expected keywords?

### Issue: Can't create booking
**Common causes:**
- Vehicle plate doesn't match customer's registered vehicles
- Service name not found in catalog
- Requested date/time is in the past
- Time slot is already fully booked

### Issue: Booking not showing up
**Check:**
- Booking status (Pending, Confirmed, Completed, Cancelled)
- Use correct customer_uid from Firebase Auth
- Check Firestore service_bookings collection

## Support & Documentation

- **Full Documentation:** `BOOKING_SYSTEM_GUIDE.md`
- **Conversation Examples:** `BOOKING_CONVERSATION_EXAMPLES.md`
- **Test Suite:** `test_booking_flow.py`
- **Implementation Summary:** `../BOOKING_ENHANCEMENT_SUMMARY.md`

## Contact

For issues or questions:
- **Email:** caltexautopro2026@gmail.com
- **Check Logs:** `ai_assistant/logs/` directory

---

**Ready to use!** The booking system is fully functional and ready for customer interactions. 🚗✨
