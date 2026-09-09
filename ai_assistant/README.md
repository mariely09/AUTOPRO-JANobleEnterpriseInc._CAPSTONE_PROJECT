# 🤖 Caltex AutoPro AI Assistant Backend

AI-powered conversational assistant for automotive service management with intelligent booking, service recommendations, and customer support.

---

## ✨ Features

### 🎯 Intelligent Booking System (NEW!)
- **Smart Date Suggestions** - AI analyzes service history and recommends optimal booking dates
- **Service Interval Detection** - Automatically knows intervals (oil: 3mo, tires: 6mo, brakes: 6mo, coolant: 12mo)
- **Conversation Memory** - Remembers vehicle and service details from conversation
- **Detailed Confirmations** - Complete booking details with booking ID and next steps
- **Real-time Availability** - Checks and suggests available time slots

[📖 Full Booking Documentation →](BOOKING_SYSTEM_GUIDE.md)  
[💬 Conversation Examples →](BOOKING_CONVERSATION_EXAMPLES.md)  
[🚀 Quick Start Guide →](BOOKING_QUICK_START.md)

### 👥 Customer Features
- ✅ View registered vehicles and PMS status
- ✅ Complete service history with cost tracking  
- ✅ Maintenance recommendations based on actual data
- ✅ Service pricing and catalog browsing
- ✅ Book, reschedule, and cancel appointments
- ✅ Customer-visible materials/products info

### 🔧 Admin Features  
- ✅ Query vehicles, maintenance, bookings across all customers
- ✅ Inventory management (stock levels, low stock alerts)
- ✅ User and customer management
- ✅ Generate PDF/Excel reports
- ✅ Complex analysis and recommendations

### 🛡️ Security & Privacy
- ✅ Customer UID injected server-side (cannot be spoofed)
- ✅ Vehicle ownership verification (4-pass lookup)
- ✅ Data isolation per customer  
- ✅ Privacy-first design (no stock/supplier info exposed to customers)

---

## 🚀 Quick Start

### Prerequisites
- Python 3.13+
- Firebase project with Firestore
- Groq API key

### Installation

```powershell
# 1. Install dependencies
pip install -r requirements.txt

# 2. Set up Firebase credentials
# Create: caltex-autopro-1e664-firebase-adminsdk-fbsvc-07b4fc625e.json
# (Get content from project owner)

# 3. Configure environment
# Create .env file with:
GROQ_API_KEY=gsk_your_key_here
FIREBASE_CREDENTIALS_PATH=./caltex-autopro-1e664-firebase-adminsdk-fbsvc-07b4fc625e.json

# 4. Run the server
python main.py
# Or: start.bat
```

Server runs on: `http://localhost:8000`

---

## 📡 API Endpoints

### Customer Chat
```http
POST /customer/chat
Content-Type: application/json

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
  "reply": "Based on your last oil change on Jan 15...",
  "session_id": "session_abc123",
  "tool_calls": [
    {
      "tool": "suggest_booking_date",
      "result": {...}
    }
  ]
}
```

### Admin Chat
```http
POST /admin/chat
Content-Type: application/json

{
  "message": "Show pending bookings for today",
  "session_id": "optional_session_id"
}
```

### Other Endpoints
- `GET /health` - Health check
- `GET /usage/customer/{uid}` - Customer usage stats
- `GET /usage/admin` - Admin usage stats
- `POST /admin/report` - Generate PDF/Excel reports
- `GET /session/{id}` - Session info
- `DELETE /session/{id}` - Clear session

---

## 🧪 Testing

### Run Booking System Tests
```powershell
cd ai_assistant
python test_booking_flow.py
```

**Tests:**
- ✅ Intelligent date suggestions
- ✅ Service interval detection
- ✅ Complete booking workflow
- ✅ Conversation memory
- ✅ Validation and error handling

### Run Customer AI Tests
```powershell
python test_customer_ai_cases.py
```

### Run Admin AI Tests
```powershell
python test_admin_ai_cases.py
```

---

## 📁 Project Structure

```
ai_assistant/
├── main.py                    # FastAPI server entry point
├── client.py                  # Groq LLM client with tool calling
├── customer_tools.py          # Customer-scoped tools (vehicles, bookings, etc.)
├── firestore_tools.py         # Admin-scoped tools (inventory, reports, etc.)
├── model_router.py            # Intent classification & model selection
├── intent_classifier.py       # Fast-path DB query classifier
├── session_store.py           # Conversation history management
├── cache_manager.py           # Firestore cache with TTL
├── usage_limiter.py           # Daily token/request limits
├── token_tracker.py           # Token usage analytics
├── report_generator.py        # PDF/Excel report generation
├── schemas.py                 # Pydantic request/response models
├── config.py                  # Settings & environment config
│
├── BOOKING_SYSTEM_GUIDE.md               # Complete booking docs
├── BOOKING_CONVERSATION_EXAMPLES.md      # Conversation patterns
├── BOOKING_QUICK_START.md                # Quick reference
├── test_booking_flow.py                  # Booking test suite
│
├── test_customer_ai_cases.py             # Customer AI tests
├── test_admin_ai_cases.py                # Admin AI tests
├── test_architecture.py                  # Architecture validation tests
├── AI_MANUAL.md                          # Setup guide
└── requirements.txt                      # Python dependencies
```

---

## 🔧 Key Components

### Intelligent Booking Flow

```
Customer: "I want to book an oil change"
    ↓
AI identifies vehicle
    ↓
suggest_booking_date() analyzes:
  • Last service date
  • Service type interval (oil = 3 months)
  • Available slots
    ↓
AI suggests: "Based on your last service on Jan 15,
             I recommend April 15 at 9 AM"
    ↓
Customer confirms
    ↓
check_booking_availability() verifies slot
    ↓
create_customer_booking() creates booking
    ↓
AI confirms with booking ID & details
```

### Customer Tools
- `get_my_vehicles()` - Customer's registered vehicles
- `get_my_service_history()` - Service/maintenance records
- `get_service_recommendations()` - PMS status & recommendations
- `get_service_prices()` - Service catalog with prices
- `suggest_booking_date()` - **NEW!** Intelligent date suggestions
- `check_booking_availability()` - Available time slots
- `create_customer_booking()` - Create new booking
- `get_my_bookings()` - View appointments
- `update_my_booking()` - Reschedule appointment
- `cancel_my_booking()` - Cancel appointment
- `estimate_service_cost()` - Cost estimation

### Admin Tools
- `get_vehicles()` - All vehicles with filters
- `get_maintenance_summary()` - Maintenance analytics
- `get_stock_levels()` - Inventory status
- `get_service_bookings()` - All bookings with filters
- `get_users()` - User management
- Reports: inventory, issuance, maintenance, vehicles, bookings

---

## 🎨 Service Intervals

The AI automatically detects service intervals:

| Service Type | Interval | Keywords |
|--------------|----------|----------|
| Oil Change / PMS | 3 months | "oil", "pms", "change oil" |
| Tire Services | 6 months | "tire", "rotation", "alignment" |
| Brake Services | 6 months | "brake", "brakes" |
| Coolant Services | 12 months | "coolant", "radiator", "flush" |

---

## 📊 Usage Limits

### Customer Limits
- **Daily Tokens:** 50,000
- **Daily Requests:** 100
- Resets at midnight

### Admin Limits
- **Daily Tokens:** 1,000,000
- **Daily Requests:** 1,000
- Resets at midnight

---

## 🔒 Security

### Customer Data Protection
- `customer_uid` always injected server-side from Firebase Auth
- Cannot be overridden by LLM or client
- Vehicle ownership verified via 4-pass lookup
- Customers can only access their own data

### Privacy Rules
Customers NEVER see:
- ❌ Stock quantities
- ❌ Supplier information
- ❌ Purchase costs
- ❌ Other customers' data
- ❌ Admin-only information

---

## 🐛 Troubleshooting

### Issue: Booking suggestions seem wrong
**Check:**
- Vehicle's last service date in Firestore
- Service frequency field in vehicle record
- Service type keywords match expected patterns

### Issue: Can't create booking
**Common causes:**
- Vehicle ownership verification failed
- Service not found in catalog
- Date/time in the past
- Time slot already booked

### Issue: "QUOTA_EXCEEDED" error
**Solution:** Firestore free tier limit reached. Wait a few minutes.

---

## 📚 Documentation

- [Booking System Guide](BOOKING_SYSTEM_GUIDE.md) - Complete technical docs
- [Conversation Examples](BOOKING_CONVERSATION_EXAMPLES.md) - How to handle conversations
- [Quick Start](BOOKING_QUICK_START.md) - Getting started guide
- [Setup Guide](AI_MANUAL.md) - Installation and configuration

---

## 🚀 Recent Updates

### v2.0 - Intelligent Booking System (Latest)
- ✨ NEW: `suggest_booking_date()` function
- ✨ Service interval detection (oil, tire, brake, coolant)
- ✨ Conversation memory for smoother booking flow
- ✨ Enhanced confirmation messages with booking IDs
- ✨ Comprehensive test suite for booking features
- 📖 Complete documentation suite

### v1.0 - Initial Release
- Customer & admin AI chat
- Basic booking (create, view, update, cancel)
- Service history & recommendations
- Inventory management
- Report generation

---

## 📞 Support

- **Email:** caltexautopro2026@gmail.com
- **Documentation:** See `BOOKING_*.md` files
- **Tests:** Run test suites for validation

---

## 🎯 Future Enhancements

Potential improvements:
- [ ] SMS/Email booking confirmations
- [ ] Push notifications for reminders
- [ ] Multi-vehicle batch booking
- [ ] Recurring maintenance schedules
- [ ] Real-time mechanic availability
- [ ] Calendar integration (Google, Outlook)
- [ ] Service package bundles
- [ ] Loyalty points integration

---

**Built with ❤️ for Caltex AutoPro - JA Noble Enterprise INC**

*Powered by Groq AI • Secured by Firebase • Built with Python & FastAPI*
