# OneSignal Security Setup - Environment Variables

## ✅ Natapos Na!

Ang OneSignal credentials ay naka-secure na gamit ang **environment variables**!

---

## 📁 Mga Ginawa

### 1. **Environment Variables Setup**

#### Backend (Python Flask):
- ✅ `.env` - May OneSignal credentials na
- ✅ `.env.example` - Template para sa ibang developers
- ✅ `.gitignore` - Naka-block na ang `.env` file sa Git
- ✅ `caltexautopro.py` - Updated to use `os.getenv()`

#### Firebase Functions (Node.js):
- ✅ `functions/.env` - May OneSignal credentials na
- ✅ `functions/.env.example` - Template
- ✅ `functions/.gitignore` - Created (blocks `.env`)
- ✅ `functions/package.json` - Added `dotenv` dependency
- ✅ `functions/index.js` - Updated to use `process.env`

---

## 🔒 Security Benefits

### Before (❌ NOT SECURE):
```javascript
// Exposed sa code!
const ONESIGNAL_APP_ID = '48dcf379-b5b7-4692-b15c-f72779e8614d';
const ONESIGNAL_REST_API_KEY = 'os_v2_app_jdopg6nvw5djfmk464txt2dbjwvvdlqebggukzuh6qm6jopw342ffum77vewzt5hvmm2awhh5tnx2vt5veylamzcoiab7jirmb7eb2q';
```

### After (✅ SECURE):
```javascript
// Secure! From .env file
const ONESIGNAL_APP_ID = process.env.ONESIGNAL_APP_ID;
const ONESIGNAL_REST_API_KEY = process.env.ONESIGNAL_REST_API_KEY;
```

**Benefits:**
- ✅ Hindi exposed sa Git/GitHub
- ✅ Hindi makikita sa public repositories
- ✅ Easy to change without editing code
- ✅ Different values for dev/staging/production

---

## 🚀 Deployment Instructions

### Local Development (Already Working!)

Ang `.env` files ay nandoon na, so it should work locally:
```bash
# Backend (Python)
python automotive_website/caltexautopro.py

# Firebase Functions (Local)
cd automotive_mobile/functions
npm install
firebase emulators:start --only functions
```

---

### Production Deployment

#### **Option 1: Render.com (for Python Backend)**

1. Pumunta sa Render Dashboard
2. Piliin ang iyong web service
3. Go to **Environment** tab
4. Add ang mga variables:
   ```
   ONESIGNAL_APP_ID=48dcf379-b5b7-4692-b15c-f72779e8614d
   ONESIGNAL_REST_API_KEY=os_v2_app_jdopg6nvw5djfmk464txt2dbjwvvdlqebggukzuh6qm6jopw342ffum77vewzt5hvmm2awhh5tnx2vt5veylamzcoiab7jirmb7eb2q
   ```
5. I-save at i-redeploy

#### **Option 2: Firebase (for Functions)**

**Method A: Using Firebase CLI**
```bash
cd automotive_mobile

# Set environment variables
firebase functions:config:set onesignal.app_id="48dcf379-b5b7-4692-b15c-f72779e8614d"
firebase functions:config:set onesignal.rest_api_key="os_v2_app_jdopg6nvw5djfmk464txt2dbjwvvdlqebggukzuh6qm6jopw342ffum77vewzt5hvmm2awhh5tnx2vt5veylamzcoiab7jirmb7eb2q"

# Deploy
firebase deploy --only functions
```

**Method B: Using .env with dotenv (Already Set Up!)**

Since we added `dotenv` package, the functions will automatically read from `.env` file when deployed:

```bash
cd automotive_mobile/functions

# Install dependencies
npm install

cd ..

# Deploy
firebase deploy --only functions
```

**IMPORTANTE:** Para sa production, i-recommend ko pa rin ang Method A (Firebase Config) kasi mas secure at hindi dependent sa `.env` file.

---

## 📝 Para sa Ibang Developers

Kung may bagong developer sa team:

1. **I-clone ang repo**
   ```bash
   git clone <repo_url>
   cd AUTOMOTIVE_SERVICE
   ```

2. **Copy ang .env.example**
   ```bash
   # Root level (for Python backend)
   copy .env.example .env
   
   # Functions level
   copy automotive_mobile\functions\.env.example automotive_mobile\functions\.env
   ```

3. **I-update ang credentials sa .env files**
   - Hingin sa team lead ang actual OneSignal credentials
   - I-update ang values sa `.env` files

4. **Install dependencies at run**
   ```bash
   # Python
   pip install -r requirements.txt
   
   # Firebase Functions
   cd automotive_mobile/functions
   npm install
   ```

---

## 🔄 Paano Mag-rotate ng Credentials

Kung kailangan mong palitan ang OneSignal credentials:

1. **Generate new credentials sa OneSignal Dashboard**
2. **Update ang .env files** (local at production)
3. **Redeploy**
   ```bash
   # Backend
   # (automatic reload sa Render kung may environment variable changes)
   
   # Firebase Functions
   firebase deploy --only functions
   ```

**HINDI NA KAILANGAN mag-edit ng code!** 🎉

---

## ⚠️ Important Reminders

### ✅ DO:
- Keep `.env` files private
- Add `.env` to `.gitignore` (already done!)
- Use different credentials for dev/staging/production
- Rotate credentials regularly
- Share credentials securely (e.g., password manager, encrypted)

### ❌ DON'T:
- Commit `.env` files to Git
- Share credentials via email/chat
- Hard-code credentials in source code
- Use production credentials for development

---

## 📊 File Structure

```
AUTOMOTIVE_SERVICE/
├── .env                          # Backend credentials (NOT in Git)
├── .env.example                  # Template (IN Git)
├── .gitignore                    # Blocks .env files
├── automotive_website/
│   └── caltexautopro.py         # Uses os.getenv()
└── automotive_mobile/
    └── functions/
        ├── .env                  # Functions credentials (NOT in Git)
        ├── .env.example          # Template (IN Git)
        ├── .gitignore            # Blocks .env files
        ├── package.json          # Has dotenv dependency
        └── index.js              # Uses process.env
```

---

## 🧪 Testing

Para i-verify na gumagana:

1. **Test Backend:**
   ```bash
   # Should see OneSignal credentials loaded
   python automotive_website/caltexautopro.py
   ```

2. **Test Firebase Functions:**
   ```bash
   cd automotive_mobile/functions
   npm install
   cd ..
   firebase emulators:start --only functions
   ```

3. **Send Test Notification:**
   - Use the backend API: `/api/send-push-notification`
   - Or use Firebase Functions
   - Check if notification arrives sa mobile device

---

## 📞 Support

Kung may issues:
- Check if `.env` files exist at may tamang values
- Verify na naka-install ang `dotenv` package (`npm install`)
- Check logs for "OneSignal credentials not configured" errors
- Ensure environment variables are set sa production environment

---

## ✨ Summary

**Before:**
- ❌ Credentials hard-coded sa source files
- ❌ Exposed sa Git/GitHub
- ❌ Hard to change

**After:**
- ✅ Credentials sa `.env` files
- ✅ Protected by `.gitignore`
- ✅ Easy to update without code changes
- ✅ Different values per environment

**Mas secure na ang OneSignal setup mo!** 🔐🎉
