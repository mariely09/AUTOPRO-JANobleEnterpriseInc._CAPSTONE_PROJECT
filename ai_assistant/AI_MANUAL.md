# Caltex AutoPro — AI Assistant Setup & Run Guide

---

## 🆕 Fresh Setup — For New Developers (After Pulling from Git)

Follow these steps **in order** if you just cloned or pulled the project for the first time.

---

### Step 1 — Install Python 3.13

Download and install Python 3.13 from https://www.python.org/downloads/  
During installation, **check "Add Python to PATH"**.

Verify it works:
```bat
python --version
```

---

### Step 2 — Create the Firebase Credentials File

The Firebase service account key is **not included in the repository** for security reasons.  
You need to create it manually.

1. Inside the `ai_assistant/` folder, create a new file named exactly:
   ```
   caltex-autopro-1e664-firebase-adminsdk-fbsvc-07b4fc625e.json
   ```
2. Paste the credentials content into that file (ask the project owner for the content).
3. Save the file.

> ⚠️ Never commit this file to Git. It is already listed in `.gitignore`.

---

### Step 3 — Create the `.env` File

Inside the `ai_assistant/` folder, create a file named `.env` with the following content:

```
FIREBASE_CREDENTIALS_PATH=./caltex-autopro-1e664-firebase-adminsdk-fbsvc-07b4fc625e.json
GROQ_API_KEY=gsk_...
GROQ_MODEL_PRIMARY=llama-3.1-8b-instant
GROQ_MODEL_SECONDARY=llama-3.3-70b-versatile
GROQ_MAX_OUTPUT_TOKENS=512
GROQ_MAX_HISTORY_MSGS=6
GROQ_MAX_TOOL_RESULT_CHARS=4000
```

Replace `gsk_...` with the actual Groq API key (ask the project owner).

> **Note:** `GROQ_MODEL_PRIMARY` is the default model (Llama 3.1 8B Instant).
> `GROQ_MODEL_SECONDARY` (Llama 3.3 70B Versatile) is used only for complex analysis requests.
> The legacy `GROQ_MODEL` variable still works as a fallback alias for the primary model.

---

### Step 4 — Create the Virtual Environment and Install Dependencies

```bat
cd ai_assistant
python -m venv venv
venv\Scripts\pip install -r requirements.txt
```

> This only needs to be done once. If the `venv/` folder already exists, skip to Step 5.

---

### Step 5 — Run the System

See the **Running the System** section below.

---

---

## Requirements
- Python 3.13
- Virtual environment at `ai_assistant/venv/` (created in Step 4)

---

## Running the System (2 terminals)

### Terminal 1 — AI Backend (FastAPI)

**Option A — double-click the batch file:**
```
ai_assistant\start.bat
```

**Option B — run manually:**
```bat
cd ai_assistant
venv\Scripts\uvicorn main:app --host 0.0.0.0 --port 8001 --reload
```

Health check: http://localhost:8001/health  
Interactive docs: http://localhost:8001/docs

---

### Terminal 2 — Flask Web Server

```bat
cd automotive_website
python caltexautopro.py
```

Web app: http://localhost:5001

---

## Port 8001 already in use?

```powershell
# Find what's using it
netstat -ano | findstr ":8001"

# Kill it (replace XXXX with the PID shown)
taskkill /F /PID XXXX
```

Then try starting again.

---

## Environment Variables (ai_assistant/.env)

```
FIREBASE_CREDENTIALS_PATH=./caltex-autopro-1e664-firebase-adminsdk-fbsvc-07b4fc625e.json
GROQ_API_KEY=gsk_...
GROQ_MODEL=llama-3.3-70b-versatile
```

---

## How It Works

```
Flutter Mobile / Web Browser
        │
        ▼
  POST /api/ai-chat        ← Flask proxy (port 5001)
  POST /api/ai-report         handles auth, CORS, rate-limit display
        │
        ▼
  POST /admin/chat         ← FastAPI AI backend (port 8001)
  POST /customer/chat
  POST /admin/report
        │
        ▼
  Groq LLM + Firestore tool calls
  (Firebase collections: stock_inventory, item_master,
   maintenance, service_bookings, issuances, deliveries,
   vehicles, users)
```

---

## Mobile App — AI Connection

The Flutter mobile app connects **directly** to the FastAPI backend (not through Flask).

| Client          | Default URL             | Note |
|-----------------|-------------------------|------|
| Android emulator | `http://10.0.2.2:8001` | 10.0.2.2 maps to host localhost |
| Physical device  | Use your LAN IP         | Pass via `--dart-define` |

**Run on physical device:**
```bat
flutter run --dart-define=AI_BACKEND_URL=http://192.168.1.X:8001
```

Replace `192.168.1.X` with your computer's local IP (`ipconfig` → IPv4 Address).

The backend must be started with `--host 0.0.0.0` (which `start.bat` already does).

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness check — returns `{"status":"ok","role":"admin"}` |
| POST | `/admin/chat` | Admin AI chat with session memory |
| POST | `/customer/chat` | Customer AI chat (scoped to their own data) |
| POST | `/admin/report` | Generate PDF or Excel report |
| GET | `/session/{id}` | Get session metadata |
| DELETE | `/session/{id}` | Clear session memory |

### Admin Chat Request
```json
{
  "message": "How many vehicles are in the fleet?",
  "session_id": "optional-uuid-for-memory-continuity"
}
```

### Customer Chat Request
```json
{
  "message": "Show me my vehicles",
  "customer_uid": "firebase-auth-uid",
  "customer_name": "Customer Full Name",
  "session_id": "optional"
}
```

### Report Generation
```
POST /admin/report?report_type=inventory&format=pdf
POST /admin/report?report_type=maintenance&format=excel
```
Valid `report_type`: `inventory`, `issuance`, `maintenance`, `vehicles`, `bookings`  
Valid `format`: `pdf`, `excel`

---

## Firebase Collections Used

| Collection | Used By |
|------------|---------|
| `stock_inventory` | Inventory tool, inventory report |
| `item_master` | Catalog tool, service pricing |
| `maintenance` | Maintenance tools, customer service history |
| `service_bookings` | Bookings tool, customer bookings |
| `issuances` | Issuance tool, issuance report |
| `deliveries` | Deliveries tool |
| `vehicles` | Fleet tool, PMS status, customer vehicles |
| `users` | User count tool, customer identity |

---

## Rate Limit Handling

The backend uses the **Groq free tier** (llama-3.3-70b-versatile).  
When the daily token limit is hit, the system:
1. Returns `{"rate_limited": true, "reset_in": "about X minutes"}` in the response
2. The frontend shows a clear banner — no crash, no error
3. The limit resets automatically (typically within 24 hours)

To avoid hitting limits: upgrade to a paid Groq plan, or switch to `llama-3.1-8b-instant`
in the `.env` file (faster, lower quality, uses fewer tokens).

---

## Groq Model Options

| Model | Speed | Quality | Tokens/day (free) |
|-------|-------|---------|-------------------|
| `llama-3.3-70b-versatile` | Medium | Best | ~14,400 |
| `llama-3.1-8b-instant` | Fast | Good | ~500,000 |

Change the model in `.env`:
```
GROQ_MODEL=llama-3.1-8b-instant
```
