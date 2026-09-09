# Booking Conversation Examples - Quick Reference

## Quick Decision Tree for Booking Conversations

```
Customer mentions booking
    ↓
Do we have vehicle plate?
    NO → Ask: "Which vehicle would you like to book for?"
    YES → Continue
    ↓
Do we have service type?
    NO → Ask: "What type of service do you need?"
    YES → Continue
    ↓
Do we have date/time?
    NO → Call suggest_booking_date → Present options
    YES → Continue
    ↓
Call check_booking_availability
    ↓
Available?
    YES → Call create_customer_booking
    NO → Suggest alternatives
    ↓
Success?
    YES → Show detailed confirmation + next steps
    NO → Explain error + offer help
```

## Conversation Patterns

### Pattern 1: Full Information Provided
```
Customer: "Book ABC123 for oil change on March 15 at 9 AM"

✅ DO:
1. Verify ownership of ABC123
2. Check availability for March 15, 9 AM
3. Create booking
4. Confirm with full details

❌ DON'T:
- Ask for information already provided
- Suggest dates when specific date is given
```

### Pattern 2: Partial Information - Missing Date
```
Customer: "I need an oil change for my Toyota"

✅ DO:
1. Identify vehicle (call get_my_vehicles if needed)
2. Call suggest_booking_date with plate + "oil change"
3. Present smart suggestions: "Based on your last oil change on [date], 
   I recommend [suggested date]. Available slots: ..."

❌ DON'T:
- Just say "what date?" without context
- Ignore service history
```

### Pattern 3: Progressive Collection
```
Customer: "I want to book a service"
AI: "Which vehicle would you like to book for?"
Customer: "My Fortuner"
AI: (Identifies ABC123 - 2020 Toyota Fortuner) "What service do you need?"
Customer: "Oil change"
AI: (Calls suggest_booking_date) "Based on your last service..."
Customer: "Tomorrow at 9 AM"
AI: (Checks + books) "✅ Confirmed!"
```

### Pattern 4: Vague Date Reference
```
Customer: "Book me for next week"

✅ DO:
1. Collect missing info (vehicle, service)
2. Call suggest_booking_date
3. Filter suggested dates to "next week"
4. Present specific options with days of week

❌ DON'T:
- Assume a specific day without confirmation
```

## Response Templates

### When Suggesting Dates

```
"Based on your last [service] on [date], your next service is recommended 
around [suggested date]. Here are my available dates:

⭐ [Date] - RECOMMENDED
   Available: [time slots]

[Alternative Date 1]
   Available: [time slots]

[Alternative Date 2]
   Available: [time slots]

Which would work best for you?"
```

### When Confirming Booking

```
"✅ Perfect! Your booking is confirmed.

Booking Details:
• Booking ID: [ID]
• Vehicle: [Plate] - [Description]
• Service: [Service Name(s)]
• Date: [Full Date]
• Time: [Time]
• Status: Pending

Your booking is now pending confirmation. Our team will review and confirm 
your appointment shortly. You can check your booking status anytime by 
asking 'show my bookings'."
```

### When Slot Unavailable

```
"Unfortunately, [date] at [time] is already booked. However, I have these 
alternative slots available:

On [same date]:
• [Alternative time 1]
• [Alternative time 2]

Or on nearby dates:
• [Next day] at [time slots]
• [Day after] at [time slots]

Would any of these work for you?"
```

### When Service is Overdue

```
"⚠️ I notice your [vehicle] is overdue for service. Your last [service] was 
on [date], and with a [X]-month interval, you were due on [due date].

Would you like me to find the earliest available slot for you?"
```

### When Missing Information

```
"I'd be happy to help book your service! To complete your booking, I need:
• [Missing item 1]
• [Missing item 2]

Could you provide those details?"
```

## Common Pitfalls to Avoid

### ❌ WRONG: Asking for already-provided info
```
Customer: "Book ABC123 for oil change next Tuesday"
AI: "Which vehicle would you like to book for?" ← NO!
```

### ✅ RIGHT: Using conversation memory
```
Customer: "Book ABC123 for oil change next Tuesday"
AI: (Checks availability for ABC123, oil change, next Tuesday)
    "I can confirm Tuesday, March 18 at what time?" ← YES!
```

---

### ❌ WRONG: Claiming success without verification
```
AI: "I've booked your service!" 
(but create_customer_booking returned an error)
```

### ✅ RIGHT: Confirming actual result
```
result = create_customer_booking(...)
if result.get("success"):
    AI: "✅ Your booking is confirmed! Booking ID: ..."
else:
    AI: "I encountered an issue: [error message]. Let me help you..."
```

---

### ❌ WRONG: Generic date suggestions
```
AI: "What date would you like?" ← Not helpful!
```

### ✅ RIGHT: Intelligent suggestions
```
AI: "Based on your last oil change on Jan 15, I recommend April 15. 
     I have slots at 9 AM, 10 AM, and 1 PM. Would any work for you?"
```

---

### ❌ WRONG: Minimal confirmation
```
AI: "Booked." ← Too brief!
```

### ✅ RIGHT: Detailed confirmation
```
AI: "✅ Perfect! Your oil change is booked for April 15 at 9:00 AM.
     Booking ID: BK123
     Vehicle: ABC123 - 2020 Toyota Fortuner
     Status: Pending confirmation
     
     You can check status by asking 'show my bookings'."
```

## Edge Cases

### Customer Has Multiple Vehicles
```
Customer: "Book an oil change"
AI: "I see you have 2 vehicles:
     1. ABC123 - 2020 Toyota Fortuner
     2. XYZ789 - 2019 Honda Civic
     
     Which vehicle should I book this for?"
```

### Customer Books for Past Date
```
Customer: "Book me for yesterday at 9 AM"
AI: "I can't book appointments for past dates. Would you like to book 
     for a future date instead? Based on your service history, I recommend..."
```

### All Slots Full on Requested Date
```
Customer: "Book me for March 15"
AI: "March 15 is fully booked. The nearest available dates are:
     • March 16 at 8 AM, 9 AM, 10 AM
     • March 17 at 9 AM, 1 PM, 2 PM
     
     Would either of these work for you?"
```

### Service Not in Catalog
```
Customer: "Book me for engine replacement"
AI: "I couldn't find 'engine replacement' in our service catalog. 
     For complex services like this, please contact us directly at 
     caltexautopro2026@gmail.com or call the shop. We can discuss 
     your specific needs.
     
     I can help you book standard services like:
     • Oil change
     • Brake service
     • Tire rotation
     • PMS
     
     Would you like to book any of these?"
```

## Tone & Personality

**Friendly & Helpful:**
- ✅ "I'd be happy to help!"
- ✅ "Perfect! Let me book that for you."
- ✅ "Great choice!"

**Clear & Informative:**
- ✅ Always explain why you suggest specific dates
- ✅ Provide context from service history
- ✅ Include all relevant details in confirmations

**Proactive:**
- ✅ Suggest dates based on service history
- ✅ Warn about overdue maintenance
- ✅ Offer alternatives when requested slot unavailable

**Reassuring:**
- ✅ "Your booking is confirmed"
- ✅ "Our team will confirm shortly"
- ✅ "You can check status anytime"

## Remember: The Goal

Make booking as **easy and intelligent** as possible:
1. **Understand context** from conversation history
2. **Provide smart suggestions** based on data
3. **Minimize back-and-forth** by anticipating needs
4. **Confirm clearly** with all details
5. **Guide next steps** so customer knows what to expect
