# 🔐 Google Sign-In Updates - Mobile & Website

## 📱 What Changed

Both the **mobile app** and **website** now follow the same Google Sign-In flow:

### ✅ Key Changes:

1. **OTP sent to Firestore email** (not Google email)
2. **User name from Firestore** (not Google display name)
3. **Enhanced user lookup** with 3-step fallback
4. **Better debug logging** for troubleshooting

---

## 🔄 Authentication Flow

### Step-by-Step Process:

```
1. User clicks "Continue with Google"
   ↓
2. Google account picker appears
   ↓
3. User selects Google account (e.g., john.google@gmail.com)
   ↓
4. System authenticates with Firebase using Google credentials
   ↓
5. System looks up user in Firestore users collection
   Priority: UID → email → googleEmail
   ↓
6. System retrieves user data from Firestore:
   - email: "john.work@company.com"
   - name: "John Doe"
   - role: "customer"
   - status: "active"
   ↓
7. OTP is sent to: john.work@company.com (Firestore email)
   Email greeting: "Hi John Doe" (Firestore name)
   ↓
8. User enters OTP from their Firestore email
   ↓
9. OTP verified → User signed in ✅
```

---

## 📧 Email Routing Logic

### Mobile App (`google_sign_in.dart`):

```dart
// Get email from Firestore, fallback to Google email
final userEmail = (userData['email'] as String?) ?? email;
final userName = (userData['name'] as String?) ?? name;

// Send OTP to Firestore email
await _sendOtp(email: userEmail, name: userName);
```

### Website (`google_signin.js`):

```javascript
// Get email from Firestore, fallback to Google email
const userEmail = userData.email || user.email;
const userName = userData.name || user.displayName || '';

// Send OTP to Firestore email
await _gsSendOtp(userEmail, userName);
```

---

## 🔍 User Lookup Strategy (3-Step Fallback)

Both platforms use the same lookup strategy:

### 1. **By UID** (Most Reliable)
```javascript
firestore.collection('users').doc(uid).get()
```
- Best for returning users
- UID never changes

### 2. **By Email Field**
```javascript
firestore.collection('users').where('email', '==', googleEmail).limit(1).get()
```
- For users registered with email/password who later use Google
- Migrates to UID-based doc on first Google sign-in

### 3. **By googleEmail Field** (Optional)
```javascript
firestore.collection('users').where('googleEmail', '==', googleEmail).limit(1).get()
```
- For systems that store Google email separately
- Allows different primary email vs Google account email

If all fail → Error: "User account not found"

---

## 🎯 Example Scenarios

### Scenario 1: Different Emails
```
Google Account: employee@gmail.com
Firestore Email: employee@company.com

Flow:
1. Sign in with employee@gmail.com
2. OTP sent to: employee@company.com ✅
3. User checks company email for OTP
```

### Scenario 2: Same Email
```
Google Account: customer@gmail.com
Firestore Email: customer@gmail.com

Flow:
1. Sign in with customer@gmail.com
2. OTP sent to: customer@gmail.com ✅
3. User checks same email for OTP
```

### Scenario 3: No Firestore Email
```
Google Account: user@gmail.com
Firestore Email: null/undefined

Flow:
1. Sign in with user@gmail.com
2. Fallback: OTP sent to user@gmail.com ✅
3. Uses Google email as backup
```

---

## 🛠️ Debug Logging

### Mobile App Console:
```
📧 Google email: miks030905@gmail.com
📧 Firestore email: mike.santos@company.com
📧 OTP will be sent to: mike.santos@company.com
👤 User name: Mike Santos
```

### Website Console:
```
📧 Google email: miks030905@gmail.com
📧 Firestore email: mike.santos@company.com
📧 OTP will be sent to: mike.santos@company.com
👤 User name: Mike Santos
```

---

## ✅ Testing Checklist

### Mobile App:
- [ ] Google sign-in works (no error 10)
- [ ] OTP sent to correct email (Firestore email)
- [ ] Email has correct name (Firestore name)
- [ ] OTP verification works
- [ ] User redirected to correct dashboard

### Website:
- [ ] Google sign-in works (popup or redirect)
- [ ] OTP sent to correct email (Firestore email)
- [ ] Email has correct name (Firestore name)
- [ ] OTP verification works
- [ ] User redirected to correct dashboard

---

## 🔥 Firebase Configuration Required

### For Mobile App:
1. Add SHA-1 fingerprint to Firebase Console
2. Download updated `google-services.json`
3. Rebuild app: `flutter build apk`

### For Website:
1. Add authorized domain to Firebase Console
2. Enable Google Sign-In provider
3. Configure OAuth consent screen

---

## 📝 Firestore Data Structure

### Required Fields:
```json
{
  "email": "user@email.com",  // Primary email (OTP destination)
  "name": "User Name",        // Display name
  "role": "customer|admin|staff",
  "status": "active|pending|inactive"
}
```

### Optional Fields:
```json
{
  "googleEmail": "google@account.com",  // Google account email
  "photoUrl": "https://...",
  "companyName": "Company Name",
  "mustChangePassword": false
}
```

---

## 🚀 Benefits

1. ✅ **Better security** - Users control which email receives OTP
2. ✅ **Professional emails** - OTP goes to work email, not personal
3. ✅ **Consistent UX** - Same flow on mobile and web
4. ✅ **Better debugging** - Console logs show exact email routing
5. ✅ **Flexible** - Supports different email scenarios

---

## 🔧 Troubleshooting

### Issue: "User account not found"
**Solution**: User must be registered in Firestore first

### Issue: OTP not received
**Check**: 
1. Is email field set in Firestore?
2. Check spam folder
3. Check EmailJS quota/status
4. View debug logs for actual email used

### Issue: Wrong email receives OTP
**Check**: 
1. What's in `userData.email`?
2. Is it the expected Firestore email?
3. Check console logs for email routing

---

## 📚 Related Files

### Mobile App:
- `automotive_mobile/lib/google_sign_in.dart`
- `automotive_mobile/GOOGLE_SIGN_IN_FIX.md`

### Website:
- `automotive_website/static/js/google_signin.js`
- `automotive_website/templates/google_sign_in.html`

### Backend:
- Flask endpoint: `/api/send-google-otp` (sends email via EmailJS)
