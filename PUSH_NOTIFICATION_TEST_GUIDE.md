# Push Notification Testing Guide 🧪

## 3 Ways to Test Push Notifications

---

## Method 1: Test via OneSignal Dashboard (EASIEST!) ⭐

Ito ang pinaka-simple at mabilis na paraan!

### Step-by-Step:

1. **Pumunta sa OneSignal Dashboard**
   - https://app.onesignal.com
   - Login with your account

2. **Select Your App**
   - Click "AutoPro" (your app)

3. **Create New Message**
   - Left sidebar: Click **"Messages"**
   - Click **"New Push"** button

4. **Compose Message**
   ```
   Title: 🧪 Test Notification
   Message: This is a test push notification from OneSignal dashboard!
   ```

5. **Select Audience**
   - **Option A:** "Send to All Subscribers" (broadcast)
   - **Option B:** "Send to Specific Users"
     - Click "Add Filter"
     - Filter by "User Tag" or "External User ID"
     - Enter your test user's Firebase UID

6. **Send**
   - Click **"Review"**
   - Click **"Send Message"**

7. **Check Your Phone!**
   - Should receive notification within seconds
   - Works kahit nakaclose ang app!

**Result:** ✅ Direct push notification (walang in-app notification kasi hindi galing sa Firestore)

---

## Method 2: Test via Firebase Console (FULL FLOW) ⭐⭐

Ito ang best way to test ang BUONG system (Firestore → Firebase Function → OneSignal)

### Pre-requisite:
```powershell
# Make sure Firebase Functions are deployed
cd automotive_mobile
firebase deploy --only functions
```

### Step-by-Step:

1. **Pumunta sa Firebase Console**
   - https://console.firebase.google.com
   - Select your project

2. **Go to Firestore Database**
   - Left sidebar: Click **"Firestore Database"**
   - Should see your collections (users, vehicles, etc.)

3. **Find Your User ID**
   - Click **"users"** collection
   - Find your test user
   - Copy the **Document ID** (your user UID)
   - Example: `abc123xyz789`

4. **Create Test Notification**
   - Go back to Firestore root
   - Click **"+ Start collection"** (if notifications collection doesn't exist yet)
   - Or click **"notifications"** collection
   - Click **"+ Add document"**

5. **Fill the Form:**
   ```
   Document ID: (auto-generated)
   
   Field: title          Type: string
   Value: 🧪 Test Notification
   
   Field: message        Type: string
   Value: Testing push notification from Firebase Console!
   
   Field: targetUid      Type: string
   Value: <YOUR_USER_ID_HERE>  (paste your UID from step 3)
   
   Field: type           Type: string
   Value: test
   
   Field: timestamp      Type: timestamp
   Value: (leave default)
   
   Field: readBy         Type: map
   Value: {} (empty map)
   ```

6. **Click "Save"**
   - Document will be created instantly

7. **What Happens Next (Automatic!):**
   - ⚡ Firebase Function detects new document
   - 🔍 Reads title, message, targetUid
   - 📡 Calls OneSignal API
   - 📲 Push notification sent to your phone!

8. **Check Your Phone!**
   - Should receive push notification
   - Open app, should see in-app notification too (bell icon)

9. **Verify in Firebase Functions Logs:**
   ```powershell
   # Check if function executed
   cd automotive_mobile
   firebase functions:log
   ```
   
   Should see:
   ```
   ✅ Notifications sent to 1 users via OneSignal
   OneSignal response: {...}
   ```

**Result:** ✅ Both in-app + push notification (complete flow!)

---

## Method 3: Test via Mobile App Code (FOR DEVELOPERS) ⭐⭐⭐

Add a test button sa iyong mobile app para easy testing during development.

### Step 1: Create Test Button

Add this code sa any screen (halimbawa sa Settings or Admin Dashboard):

```dart
// Add to your Flutter widget
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Inside your widget build method:
ElevatedButton.icon(
  icon: Icon(Icons.notification_add),
  label: Text('Send Test Push Notification'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.orange,
    foregroundColor: Colors.white,
  ),
  onPressed: () async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Not logged in')),
        );
        return;
      }

      // Create test notification
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': '🧪 Test Notification',
        'message': 'Testing push notification at ${DateTime.now().toString()}',
        'targetUid': currentUser.uid,
        'type': 'test',
        'timestamp': FieldValue.serverTimestamp(),
        'readBy': {},
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Test notification sent! Check your phone.'),
          backgroundColor: Colors.green,
        ),
      );

      print('✅ Test notification created in Firestore');
    } catch (e) {
      print('❌ Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
  },
)
```

### Step 2: Use the Button

1. Open your mobile app
2. Navigate to the screen with the test button
3. Click **"Send Test Push Notification"**
4. Should see success message
5. Wait 2-3 seconds
6. Check notification tray!

**Result:** ✅ Both in-app + push notification

---

## Quick Comparison

| Method | Difficulty | Tests What? | Best For |
|--------|------------|-------------|----------|
| **OneSignal Dashboard** | ⭐ Easy | Push only | Quick push test |
| **Firebase Console** | ⭐⭐ Medium | Full flow | Testing complete system |
| **Mobile App Button** | ⭐⭐⭐ Advanced | Full flow | Development & debugging |

---

## Common Issues & Solutions

### ❌ Issue: "No subscribers found"

**Cause:** User device not registered with OneSignal

**Solution:**
1. Open mobile app
2. Login with your account
3. Check if OneSignal.login() is called
4. Check Firestore user document has `oneSignalId` field

```dart
// In mobile app main.dart or login screen
OneSignal.login(firebaseUserId);
```

---

### ❌ Issue: In-app notification OK, push wala

**Cause:** Firebase Function not deployed or not triggered

**Solution:**
```powershell
# Deploy functions
cd automotive_mobile
firebase deploy --only functions

# Check logs
firebase functions:log
```

Look for:
```
✅ Notifications sent to X users via OneSignal
```

If walang log:
- Function not deployed
- Function failed to trigger
- Check Firebase Console → Functions tab

---

### ❌ Issue: "Permission denied" or "Not authorized"

**Cause:** OneSignal credentials incorrect

**Solution:**
1. Check Render environment variables:
   - `ONESIGNAL_APP_ID`
   - `ONESIGNAL_REST_API_KEY`
2. Verify sa OneSignal dashboard (Settings → Keys & IDs)
3. Make sure values match exactly
4. Redeploy if needed

---

### ❌ Issue: "User not found" in OneSignal

**Cause:** External User ID not set

**Solution:**
```dart
// In mobile app after login
await OneSignal.login(firebaseUserId);

// Verify
final externalId = await OneSignal.User.getExternalId();
print('OneSignal External ID: $externalId');
// Should match Firebase UID
```

---

## Testing Checklist ✅

Before testing, make sure:

- [ ] Firebase Functions deployed (`firebase deploy --only functions`)
- [ ] OneSignal credentials in Render environment
- [ ] Mobile app installed on device
- [ ] User logged in to mobile app
- [ ] OneSignal.login() called with Firebase UID
- [ ] Notification permission allowed on device
- [ ] Device has internet connection

---

## Step-by-Step Full Test (Recommended)

### Complete Testing Flow:

#### 1️⃣ **Setup (One-time)**
```powershell
# Deploy Firebase Functions
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile
firebase deploy --only functions
```

#### 2️⃣ **Mobile App Setup**
- Install app on your phone
- Login with your account
- Allow notification permission when prompted

#### 3️⃣ **Verify OneSignal Registration**
Check if user is registered:
1. Go to OneSignal dashboard
2. Audience → All Users
3. Find your device
4. Should show your External User ID (Firebase UID)

#### 4️⃣ **Test via Firebase Console**
1. https://console.firebase.google.com
2. Firestore Database → notifications collection
3. Add document:
   ```
   title: "🧪 Test"
   message: "Hello from Firebase!"
   targetUid: <your_firebase_uid>
   type: "test"
   timestamp: (current timestamp)
   readBy: {}
   ```

#### 5️⃣ **Verify Results**
- [ ] In-app notification appeared (bell icon)
- [ ] Push notification received on phone
- [ ] Notification shows correct title & message
- [ ] Clicking notification opens app

#### 6️⃣ **Check Logs**
```powershell
cd automotive_mobile
firebase functions:log
```

Should see:
```
✅ Notifications sent to 1 users via OneSignal
OneSignal response: {"id": "..."}
```

---

## Advanced Testing: Multiple Users

### Test Broadcasting to All Admins:

**Firebase Console:**
```
title: "📢 Admin Announcement"
message: "This goes to all admins"
targetRole: "admin"  (NOT targetUid)
type: "announcement"
timestamp: (current)
readBy: {}
```

**What happens:**
- All users with `role: 'admin'` receive notification
- Both in-app + push

### Test to All Customers:
```
title: "📢 Customer Notice"
message: "Special promo today!"
targetRole: "customer"
type: "promo"
```

### Test to Everyone:
```
title: "🎉 Grand Opening"
message: "New branch opened!"
(NO targetRole or targetUid)
type: "announcement"
```

---

## Monitoring & Debugging

### View OneSignal Dashboard Statistics:
1. https://app.onesignal.com
2. Select "AutoPro"
3. Dashboard → Delivery tab
4. See:
   - Total sent
   - Delivered
   - Clicked
   - Failed

### View Firebase Functions Logs:
```powershell
# Real-time logs
firebase functions:log --follow

# Last 100 lines
firebase functions:log --limit 100

# Specific function
firebase functions:log --only sendNotifications
```

### Check Firestore Activity:
1. Firebase Console → Firestore Database
2. View `notifications` collection
3. Recent documents show recent tests

---

## Production Testing Checklist

Before going live:

- [ ] Test with real users (not just yourself)
- [ ] Test on both Android and iOS (if applicable)
- [ ] Test different scenarios:
  - [ ] Single user notification
  - [ ] Role-based notification
  - [ ] Broadcast notification
- [ ] Test with app open
- [ ] Test with app closed
- [ ] Test with app in background
- [ ] Verify notification sound/vibration
- [ ] Test notification tap action (opens app?)
- [ ] Check analytics in OneSignal dashboard
- [ ] Monitor Firebase Functions logs for errors

---

## Quick Test Commands

```powershell
# Deploy functions
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile
firebase deploy --only functions

# Watch logs in real-time
firebase functions:log --follow

# Check function status
firebase functions:list

# Test locally (optional)
firebase emulators:start --only functions
```

---

## Need Help?

**Check these files:**
- `PUSH_NOTIFICATION_FLOW_GUIDE.md` - How it works
- `NOTIFICATION_QUICK_REFERENCE.md` - Quick syntax
- `ONESIGNAL_SECURITY_SETUP.md` - Setup & deployment
- `ONESIGNAL_TEST_REPORT.md` - Configuration test results

**Or check logs:**
- Firebase Functions: `firebase functions:log`
- OneSignal Dashboard: https://app.onesignal.com
- Render Logs: Render Dashboard → Logs tab

---

## Summary: Easiest Way to Test NOW

**FASTEST TEST (30 seconds):**

1. Go to: https://app.onesignal.com
2. Select "AutoPro" app
3. Messages → New Push
4. Enter test message
5. Send to All
6. Check your phone! 📲

**COMPLETE SYSTEM TEST (2 minutes):**

1. Go to: https://console.firebase.google.com
2. Firestore Database → notifications
3. Add document with your user ID
4. Check phone for push + in-app notification
5. Check `firebase functions:log` for confirmation

**That's it!** 🎉

Need step-by-step help? Just ask! 😊
