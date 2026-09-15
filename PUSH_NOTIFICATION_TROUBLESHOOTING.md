# 🔔 Push Notification Troubleshooting Guide

**Issues:**
1. ❌ Logo still showing on RIGHT side (large_icon not removed)
2. ❌ Notifications only appear when app is OPEN

---

## ❌ ISSUE 1: Logo sa Right Side

**Cause:** Cloud Function pa rin yung old code with `large_icon`

**Solution:** Manual update sa Firebase Console

### Steps:

1. **Go to Firebase Console Functions:**
   https://console.firebase.google.com/project/caltex-autopro-1e664/functions

2. **Click `sendNotifications`**

3. **Click "EDIT" or "SOURCE"**

4. **Find this code** (around line 90-100):
   ```javascript
   const response = await axios.post(
     'https://api.onesignal.com/notifications',
     {
       app_id: ONESIGNAL_APP_ID,
       include_external_user_ids: userIds,
       headings: { en: title },
       contents: { en: message },
       data: { type: notification.type || 'info' },
       large_icon: 'https://storage.googleapis.com/...',  // ← REMOVE THIS LINE
     },
   ```

5. **DELETE the `large_icon` line**

6. **Should look like:**
   ```javascript
   const response = await axios.post(
     'https://api.onesignal.com/notifications',
     {
       app_id: ONESIGNAL_APP_ID,
       include_external_user_ids: userIds,
       headings: { en: title },
       contents: { en: message },
       data: { type: notification.type || 'info' },
       // Small icon configured in AndroidManifest.xml
     },
   ```

7. **Click "DEPLOY"**

8. **Wait 1-2 minutes**

9. **Test notification again**

---

## ❌ ISSUE 2: Notifications Only When App is OPEN

This is MORE SERIOUS! OneSignal should work in background automatically.

### Possible Causes:

#### A. **User Not Subscribed to OneSignal**

**Check:**
1. Go to OneSignal Dashboard → Audience → All Users
2. Look for user's device
3. Check "Status" column - must be "Subscribed" (green)

**If "Permission Not Granted":**
- User needs to accept notification permission
- Uninstall and reinstall app
- When app opens, click "Allow" on notification permission prompt

#### B. **Battery Optimization Blocking Notifications**

Android kills apps to save battery, blocking background notifications.

**Fix on Device:**
```
Settings → Apps → AutoPro → Battery → Unrestricted
```

Or:
```
Settings → Battery → Battery Optimization → AutoPro → Don't optimize
```

#### C. **Notification Permission Not Granted**

**Check on Device:**
```
Settings → Apps → AutoPro → Notifications → Enabled?
```

**Should be:**
- ✅ Allow notifications: ON
- ✅ All categories: ON
- ✅ Lock screen: Show content

#### D. **OneSignal Not Initialized Properly**

**Test:**
1. Open app
2. Check logs for: "✅ OneSignal initialized"
3. Check logs for: "✅ Push re-opted in"
4. Check logs for: "✅ OneSignal subscription ID saved"

**If logs missing:**
- OneSignal not initializing
- Need to check main.dart initialization

#### E. **Device in Do Not Disturb Mode**

**Check:**
- Swipe down notification panel
- Look for crescent moon icon
- Turn off Do Not Disturb

#### F. **App Data Clearing / Fresh Install**

**Try:**
1. Uninstall AutoPro completely
2. Reinstall from QR code
3. Open app
4. Click "Allow" on notification permission
5. Login
6. Send test notification
7. Close app completely
8. Send another test notification
9. Check if notification appears

---

## 🧪 DIAGNOSTIC TESTS

### Test 1: Check OneSignal Subscription Status

1. **Open OneSignal Dashboard:**
   https://dashboard.onesignal.com/apps/48dcf379-b5b7-4692-b15c-f72779e8614d/audience

2. **Find user's device**

3. **Check status:**
   - ✅ Green dot = Subscribed (good!)
   - ❌ Gray dot = Not subscribed (problem!)

4. **Check "Last Session":**
   - Should be recent
   - If old = user not using app

### Test 2: Send Test from OneSignal Dashboard

1. **Go to:** https://dashboard.onesignal.com/apps/48dcf379-b5b7-4692-b15c-f72779e8614d/notifications/new

2. **Create new notification:**
   - Title: "Test from Dashboard"
   - Message: "Testing background notification"
   - Audience: Select specific user

3. **Send immediately**

4. **Close AutoPro app completely**

5. **Wait for notification**

6. **If received:**
   - ✅ OneSignal works
   - ❌ Problem is with Cloud Function

7. **If NOT received:**
   - ❌ OneSignal subscription issue
   - Check device settings

### Test 3: Foreground vs Background

**Test A: App OPEN (Foreground)**
```powershell
cd c:\Project\AUTOMOTIVE_SERVICE
python test_push_notification.py
```
- Open AutoPro app
- Keep app in foreground
- Run test script
- **Expected:** Dialog appears in app

**Test B: App CLOSED (Background)**
```powershell
python test_push_notification.py
```
- Close AutoPro app completely
- Swipe away from recent apps
- Run test script
- **Expected:** Notification in status bar

**Results:**
- ✅ Both work = All good!
- ✅ Foreground only = Background issue
- ❌ Neither work = OneSignal not configured

---

## ✅ PROPER SETUP CHECKLIST

### Device Settings:
- [ ] Notification permission granted
- [ ] Battery optimization: Unrestricted
- [ ] Do Not Disturb: OFF
- [ ] AutoPro notifications: Enabled

### OneSignal Dashboard:
- [ ] User status: Subscribed (green)
- [ ] Last session: Recent
- [ ] Push subscription ID: Present

### App:
- [ ] Latest APK installed (78.64 MB)
- [ ] User logged in
- [ ] OneSignal initialized (check logs)
- [ ] Permission popup appeared and accepted

### Cloud Function:
- [ ] `sendNotifications` deployed
- [ ] `large_icon` parameter removed
- [ ] Environment variables set correctly

---

## 🔧 QUICK FIXES

### Fix 1: Reset OneSignal Subscription

```dart
// In app, run this once:
await OneSignal.User.pushSubscription.optOut();
await Future.delayed(Duration(seconds: 2));
await OneSignal.User.pushSubscription.optIn();
```

### Fix 2: Force Permission Request

```dart
// In app:
final granted = await OneSignal.Notifications.requestPermission(true);
print('Permission: $granted');
```

### Fix 3: Check Subscription ID

```dart
// In app:
final subId = OneSignal.User.pushSubscription.id;
print('Subscription ID: $subId');
```

### Fix 4: Reinstall App

1. Uninstall AutoPro
2. Clear device cache
3. Restart device
4. Install fresh APK
5. Grant all permissions
6. Test notification

---

## 📊 EXPECTED BEHAVIOR

### ✅ CORRECT:
```
1. User logs in → Permission popup → Click "Allow"
2. OneSignal subscribes user
3. Subscription ID saved to Firestore
4. Cloud Function triggers on new notification
5. OneSignal sends push to device
6. Notification appears in status bar
7. Works whether app is open OR closed
```

### ❌ INCORRECT (Current):
```
1. User logs in ✅
2. OneSignal subscribes ✅
3. Cloud Function triggers ✅
4. Push sent ✅
5. Notification ONLY when app open ❌
6. No notification when app closed ❌
```

---

## 🆘 IF STILL NOT WORKING

### Option 1: Check Device Logs

```bash
# Connect Android device via USB
adb logcat | grep -i "onesignal\|notification\|autopro"
```

Look for errors like:
- "Permission denied"
- "Service not running"
- "Battery optimization"

### Option 2: Test with Different Device

Try on another Android phone:
- Different manufacturer
- Different Android version
- Fresh install

### Option 3: Contact OneSignal Support

If all settings correct but still not working:
- OneSignal Dashboard → Help & Support
- Provide: App ID, User ID, Test notification ID
- They can check server-side logs

---

## 📝 SUMMARY

**Issue 1 (Logo):** Need manual Cloud Function update  
**Issue 2 (Background):** Check device settings + OneSignal subscription  

**Most Common Cause:** Battery optimization killing app in background  
**Quick Fix:** Settings → Battery → AutoPro → Unrestricted  

---

**Created:** September 15, 2026  
**Author:** Kiro AI Assistant
