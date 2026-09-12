# 🔧 Google Sign-In Fix - Developer Error (10)

## 📌 Problem
Google Sign-In fails with error:
```
GoogleSignIn.signIn PlatformException: sign_in_failed
com.google.android.gms.common.api.ApiException: 10
```

## ✅ Solution: Add SHA-1 Fingerprint to Firebase

### Your SHA-1 Fingerprint:
```
09:60:63:08:F1:DC:64:4B:C8:63:52:37:F5:34:D1:03:FA:DC:3B:B7
```

---

## 🔥 Steps to Fix in Firebase Console

### Step 1: Open Firebase Console
1. Go to: https://console.firebase.google.com
2. Select your **CALTEX-AUTOPRO** project

### Step 2: Add SHA-1 Fingerprint
1. Click ⚙️ **Project Settings** (gear icon at top-left)
2. Scroll down to **Your apps** section
3. Find your Android app: `com.example.automotive_mobile`
4. Click **Add fingerprint** button
5. Paste: `09:60:63:08:F1:DC:64:4B:C8:63:52:37:F5:34:D1:03:FA:DC:3B:B7`
6. Click **Save**

### Step 3: Download Updated Config
1. After adding SHA-1, click **Download google-services.json**
2. Replace the file at:
   ```
   automotive_mobile\android\app\google-services.json
   ```

### Step 4: Rebuild the App
```bash
cd automotive_mobile
flutter clean
flutter build apk --debug
```

### Step 5: Install and Test
```powershell
$env:Path += ";C:\Users\CarlaVillafranca\AppData\Local\Android\sdk\platform-tools"
adb -s R83W711DP9J install -r "build\app\outputs\flutter-apk\app-debug.apk"
```

---

## 🎯 Why This Happens

Google Sign-In requires your app's SHA-1 fingerprint to be registered in Firebase Console. The SHA-1 fingerprint comes from your **debug.keystore** file:

- **Debug Keystore Location**: `C:\Users\CarlaVillafranca\.android\debug.keystore`
- **SHA-1**: `09:60:63:08:F1:DC:64:4B:C8:63:52:37:F5:34:D1:03:FA:DC:3B:B7`

When you build the APK, it's signed with this keystore. Google checks if the SHA-1 matches what's registered in Firebase. If not → Error 10.

---

## 📱 After Adding SHA-1

Once you add the SHA-1 to Firebase:
1. ✅ Google Sign-In will work
2. ✅ OTP will be sent to the user's Firestore email
3. ✅ User can verify and sign in

---

## 🔐 For Release Build (Production)

When building a release APK, you'll need to add the **release keystore SHA-1** as well:

```bash
keytool -list -v -keystore path\to\release.keystore -alias your_alias
```

Add both debug and release SHA-1 fingerprints to Firebase.

---

## ❓ Need Help?

If you don't have access to Firebase Console, ask the project owner/admin to add this SHA-1 for you.
