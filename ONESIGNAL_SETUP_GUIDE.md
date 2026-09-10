# OneSignal Setup Guide - Paano Magpalit ng OneSignal ID

## Hakbang 1: Gumawa ng Bagong OneSignal App

1. **Pumunta sa OneSignal Dashboard**
   - Bisitahin: https://onesignal.com
   - Mag-login sa iyong account (o gumawa ng bago kung wala ka pa)

2. **Gumawa ng Bagong App**
   - I-click ang **"New App/Website"** button
   - Pangalanan ang app: **"Automotive Service"**
   - Piliin ang platform: **Android** at/o **iOS**

3. **I-configure ang Platform**
   
   **Para sa Android:**
   - Piliin "Google Android (FCM)"
   - Kailangan mo ng **Firebase Server Key** at **Firebase Sender ID**
   - Kukunin mo ito sa Firebase Console → Project Settings → Cloud Messaging
   
   **Para sa iOS:**
   - Piliin "Apple iOS (APNs)"
   - Kailangan ng APNs Certificate o Key
   - I-upload ang iyong .p12 certificate file

4. **Kunin ang Credentials**
   - Pagkatapos mag-setup, pumunta sa **Settings → Keys & IDs**
   - Makikita mo ang:
     - **OneSignal App ID** (halimbawa: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
     - **REST API Key** (halimbawa: `os_v2_app_...`)

---

## Hakbang 2: I-update ang Configuration Files

### 2.1 Backend (Python Flask) - `caltexautopro.py`

```python
# Palitan ang mga sumusunod na lines (mga line 197-198):
ONESIGNAL_APP_ID  = 'LAGAY_DITO_ANG_BAGONG_APP_ID'
ONESIGNAL_API_KEY = 'LAGAY_DITO_ANG_BAGONG_REST_API_KEY'
```

### 2.2 Firebase Functions - `automotive_mobile/functions/index.js`

```javascript
// Palitan ang mga sumusunod na lines (mga line 10-11):
const ONESIGNAL_APP_ID = 'LAGAY_DITO_ANG_BAGONG_APP_ID';
const ONESIGNAL_REST_API_KEY = 'LAGAY_DITO_ANG_BAGONG_REST_API_KEY';
```

**IMPORTANTE:** May bug din sa API endpoint! Dapat palitan ang:
```javascript
// MALING URL (line 89, 151, 267):
'https://onesignal.com/api/v1/notifications'

// TAMANG URL:
'https://api.onesignal.com/notifications'
```

### 2.3 Mobile App (Flutter) - `automotive_mobile/lib/main.dart`

```dart
// Palitan ang OneSignal initialization (usually sa initState o main function):
OneSignal.initialize('LAGAY_DITO_ANG_BAGONG_APP_ID');
```

---

## Hakbang 3: I-update ang Environment Variables

Kung gumagamit ka ng `.env` file para sa secrets:

```bash
# .env file
ONESIGNAL_APP_ID=LAGAY_DITO_ANG_BAGONG_APP_ID
ONESIGNAL_REST_API_KEY=LAGAY_DITO_ANG_BAGONG_REST_API_KEY
```

Pagkatapos, i-load ito sa Python:
```python
import os
from dotenv import load_dotenv

load_dotenv()

ONESIGNAL_APP_ID = os.getenv('ONESIGNAL_APP_ID')
ONESIGNAL_API_KEY = os.getenv('ONESIGNAL_REST_API_KEY')
```

---

## Hakbang 4: I-rebuild ang Mobile App

```bash
# 1. Lumipat sa mobile directory
cd automotive_mobile

# 2. Clean at get dependencies
flutter clean
flutter pub get

# 3. Rebuild ang app
flutter run

# O para sa release build:
flutter build apk --release
```

---

## Hakbang 5: I-redeploy ang Firebase Functions

```bash
# Lumipat sa functions directory
cd automotive_mobile/functions

# Install dependencies (kung kailangan)
npm install

# Deploy to Firebase
firebase deploy --only functions
```

---

## Hakbang 6: I-test ang Push Notifications

1. **I-install ang updated app** sa mobile device
2. **Payagan ang notification permission** kapag nag-prompt
3. **Tingnan sa OneSignal Dashboard:**
   - Pumunta sa **Audience → All Users**
   - Dapat makita mo ang bagong subscribers
4. **Subukan mag-send ng test notification:**
   - Sa OneSignal dashboard: **Messages → New Push**
   - Piliin ang test user
   - I-send ang message

---

## Summary ng Files na Dapat I-update

✅ **Backend:**
- `automotive_website/caltexautopro.py` (lines 197-198)

✅ **Firebase Functions:**
- `automotive_mobile/functions/index.js` (lines 10-11, 89, 151, 267)

✅ **Mobile App:**
- `automotive_mobile/lib/main.dart` (OneSignal.initialize)

✅ **Environment:**
- `.env` file (recommended for security)

---

## ⚠️ Mga Dapat Tandaan

1. **Huwag i-commit ang API Keys sa Git!**
   - Siguraduhing nasa `.gitignore` ang `.env` file
   - Gumamit ng environment variables

2. **Test muna sa Development**
   - Gumawa ng separate OneSignal app para sa dev at production

3. **I-update ang Documentation**
   - I-update ang `USER_MANUAL.md` kung may changes

4. **Backup ang Old Keys**
   - Bago palitan, i-backup muna ang old OneSignal credentials

---

## Troubleshooting

**Hindi tumatanggap ng notifications?**
- Check kung naka-allow ang notification permission sa device
- Verify sa OneSignal dashboard kung may subscribers
- Check ang device logs: `flutter logs` o `adb logcat`

**"Invalid App ID" error?**
- Double-check kung tama ang App ID (walang extra spaces)
- Sigurado ba na naka-initialize ang OneSignal sa main.dart?

**REST API errors?**
- Verify kung tama ang REST API Key
- Check kung nag-expire na ba ang key (renewable sa dashboard)

---

## Support

Para sa karagdagang tulong:
- OneSignal Documentation: https://documentation.onesignal.com
- OneSignal Dashboard: https://app.onesignal.com
