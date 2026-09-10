# Push Notifications Guide - OneSignal Implementation

## How Push Notifications Work in Your App

### Overview
Your Caltex AutoPro app uses **OneSignal** to send push notifications to user devices. The system automatically:
1. Registers each user's device when they login
2. Associates their device with their Firebase UID
3. Sends targeted notifications based on user role and events

---

## Architecture

```
[App Login] → [OneSignal Registration] → [Device Token Saved] → [Notifications Sent]
     ↓                    ↓                       ↓                      ↓
  Firebase UID      OneSignal SDK          Firestore users       OneSignal API
                  (device token)         (oneSignalId field)    (push to device)
```

---

## Step-by-Step Flow

### 1. **App Initialization (main.dart)**

When the app starts:

```dart
// Initialize OneSignal with your App ID
OneSignal.initialize('c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea');

// Request permission to show notifications
await OneSignal.Notifications.requestPermission(true);
```

**What happens:**
- OneSignal SDK contacts OneSignal servers
- Device registers and gets a unique **subscription ID**
- User sees permission dialog: "Allow AutoPro to send notifications?"

### 2. **User Login (login.dart)**

When user logs in successfully:

```dart
// Link OneSignal subscription to Firebase UID
OneSignal.login(user.uid);

// Opt-in to push notifications
await OneSignal.User.pushSubscription.optIn();

// Save OneSignal subscription ID to Firestore
final subscriptionId = OneSignal.User.pushSubscription.id;
await FirebaseFirestore.instance
    .collection('users')
    .doc(user.uid)
    .update({'oneSignalId': subscriptionId});
```

**What happens:**
- OneSignal links the device token to the Firebase UID
- Subscription ID is saved in Firestore `users` collection
- Device is now ready to receive notifications

### 3. **Sending Notifications**

#### From Admin Dashboard (notifications.dart):

```dart
// Send to specific user by Firebase UID
await NotificationsService.sendPush(
  targetRole: 'customer',
  targetUid: 'user123',  // Firebase UID
  title: 'Service Ready',
  message: 'Your vehicle maintenance is complete!',
  data: {'type': 'maintenance', 'id': 'maint_456'},
);
```

#### From Backend (Flask/Python):

```python
import requests

def send_push_notification(user_uid, title, message):
    # Get OneSignal ID from Firestore
    user_doc = firestore.collection('users').document(user_uid).get()
    onesignal_id = user_doc.get('oneSignalId')
    
    # Send via OneSignal API
    response = requests.post(
        'https://api.onesignal.com/notifications',
        headers={
            'Authorization': 'Basic YOUR_REST_API_KEY',
            'Content-Type': 'application/json'
        },
        json={
            'app_id': 'c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea',
            'include_subscription_ids': [onesignal_id],
            'headings': {'en': title},
            'contents': {'en': message},
            'data': {'type': 'info'}
        }
    )
```

### 4. **Device Receives Notification**

When notification arrives:

```dart
// Notification click handler (in main.dart or notifications.dart)
OneSignal.Notifications.addClickListener((event) {
  final data = event.notification.additionalData;
  
  // Navigate based on notification type
  if (data?['type'] == 'maintenance') {
    Navigator.push(...); // Go to maintenance details
  } else if (data?['type'] == 'booking') {
    Navigator.push(...); // Go to bookings
  }
});
```

**What happens:**
- Notification appears in device notification tray
- User taps notification
- App opens and navigates to relevant screen

---

## Current Implementation

### Auto-Registration on Login

**File:** `automotive_mobile/lib/login.dart`

Every user login automatically:
1. ✅ Calls `OneSignal.login(uid)`
2. ✅ Opts in to push notifications
3. ✅ Saves subscription ID to Firestore
4. ✅ Updates on token refresh

### Notification Sending

**File:** `automotive_mobile/lib/notifications.dart`

```dart
class NotificationsService {
  static Future<void> sendPush({
    required String targetRole,
    String? targetUid,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    // Get target user(s) OneSignal IDs from Firestore
    List<String> subscriptionIds = [];
    
    if (targetUid != null) {
      // Send to specific user
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .get();
      final id = doc.data()?['oneSignalId'];
      if (id != null) subscriptionIds.add(id);
    } else {
      // Send to all users with specified role
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: targetRole)
          .get();
      
      for (var doc in query.docs) {
        final id = doc.data()['oneSignalId'];
        if (id != null) subscriptionIds.add(id);
      }
    }
    
    // Send via OneSignal API
    await http.post(
      Uri.parse('https://api.onesignal.com/notifications'),
      headers: {
        'Authorization': 'Basic YOUR_REST_API_KEY',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({
        'app_id': 'c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea',
        'include_subscription_ids': subscriptionIds,
        'headings': {'en': title},
        'contents': {'en': message},
        'data': data ?? {},
      }),
    );
  }
}
```

---

## Testing Push Notifications

### Method 1: From OneSignal Dashboard

1. **Go to:** https://dashboard.onesignal.com/
2. **Select** your app: Caltex AutoPro
3. **Click** "Messages" → "New Push"
4. **Choose** "Send to Particular Users"
5. **Enter** subscription ID (get from Firestore `users/{uid}/oneSignalId`)
6. **Write** title and message
7. **Send** notification

### Method 2: From Your App

```dart
// In admin dashboard or anywhere
await NotificationsService.sendPush(
  targetRole: 'customer',
  targetUid: 'specific_user_uid',  // or null for all customers
  title: 'Test Notification',
  message: 'This is a test push notification!',
  data: {'type': 'test'},
);
```

### Method 3: Using OneSignal REST API (Postman/cURL)

```bash
curl -X POST https://api.onesignal.com/notifications \
  -H "Authorization: Basic YOUR_REST_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea",
    "include_subscription_ids": ["subscription-id-here"],
    "headings": {"en": "Test Notification"},
    "contents": {"en": "Hello from OneSignal!"}
  }'
```

---

## Troubleshooting

### Problem: User not receiving notifications

**Check:**
1. ✅ User has granted notification permission
   ```dart
   final granted = OneSignal.User.pushSubscription.optedIn;
   ```

2. ✅ OneSignal ID is saved in Firestore
   ```dart
   final doc = await FirebaseFirestore.instance
       .collection('users')
       .doc(uid)
       .get();
   final oneSignalId = doc.data()?['oneSignalId'];
   // Should not be null or empty
   ```

3. ✅ App is using correct OneSignal App ID
   ```dart
   OneSignal.initialize('c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea');
   ```

4. ✅ Device has internet connection
5. ✅ App is running or in background (not force-closed)

### Problem: Duplicate notifications

**Solution:** Each login calls `OneSignal.login(uid)` which may create new subscriptions. This is **normal** - OneSignal handles it automatically.

### Problem: Notification not showing on Android

**Check:**
1. ✅ Notification permission granted
2. ✅ Battery optimization disabled for app
3. ✅ App not in "Do Not Disturb" mode
4. ✅ Notification channel enabled

---

## OneSignal Configuration

### App ID
```
c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea
```

### REST API Key
Get from: https://dashboard.onesignal.com/apps/YOUR_APP/settings
- Settings → Keys & IDs → REST API Key

### Where Used:
- **Mobile App:** `main.dart` (initialization)
- **Backend:** When sending notifications via API
- **Firestore:** `users` collection stores `oneSignalId` field

---

## Data Structure

### Firestore `users` Collection

```json
{
  "uid": "user123",
  "name": "John Doe",
  "email": "john@example.com",
  "role": "customer",
  "oneSignalId": "abc123-def456-ghi789",  // ← Device subscription ID
  "status": "active"
}
```

### OneSignal Notification Payload

```json
{
  "app_id": "c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea",
  "include_subscription_ids": ["abc123-def456-ghi789"],
  "headings": {"en": "Service Ready"},
  "contents": {"en": "Your vehicle maintenance is complete!"},
  "data": {
    "type": "maintenance",
    "maintenanceId": "maint_456",
    "vehicleId": "vehicle_789"
  }
}
```

---

## Best Practices

### ✅ DO:
- Store OneSignal subscription ID in Firestore for easy targeting
- Use `data` field to include action metadata
- Handle notification clicks to navigate to relevant screens
- Request permission at appropriate time (after login)
- Test notifications before sending to all users

### ❌ DON'T:
- Don't spam users with too many notifications
- Don't send sensitive data in notification payload
- Don't forget to handle notification clicks
- Don't send notifications to inactive users
- Don't hardcode subscription IDs in code

---

## Notification Types in Your App

### 1. **Maintenance Alerts**
- **Sent:** When DSS system detects maintenance needed
- **Target:** Vehicle owner (customer)
- **Example:** "Service Due: Your Honda Civic needs maintenance"

### 2. **Booking Confirmations**
- **Sent:** When booking is created/updated
- **Target:** Specific customer
- **Example:** "Booking Confirmed: Sep 15, 2026 at 10:00 AM"

### 3. **Admin Notifications**
- **Sent:** When customer updates profile, creates booking, etc.
- **Target:** All admins
- **Example:** "Profile Updated: John Doe updated their profile"

### 4. **Staff Assignments**
- **Sent:** When staff is assigned to a task
- **Target:** Specific staff member
- **Example:** "New Task: Inspect vehicle ABC-123"

---

## Security Considerations

### REST API Key
- **Never** expose in client-side code
- Store in **backend environment variables** only
- Rotate regularly if compromised

### User Privacy
- Get explicit permission before sending notifications
- Allow users to opt-out via settings
- Don't share subscription IDs publicly

---

## Quick Reference

### Initialize OneSignal
```dart
OneSignal.initialize('c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea');
```

### Request Permission
```dart
await OneSignal.Notifications.requestPermission(true);
```

### Login User
```dart
OneSignal.login(firebaseUid);
```

### Opt-In
```dart
await OneSignal.User.pushSubscription.optIn();
```

### Get Subscription ID
```dart
final id = OneSignal.User.pushSubscription.id;
```

### Send Notification
```dart
await NotificationsService.sendPush(
  targetRole: 'customer',
  targetUid: uid,
  title: 'Title',
  message: 'Message',
);
```

---

**Last Updated:** 2026-09-10  
**OneSignal SDK Version:** 5.0.0+  
**Status:** ✅ Fully Implemented and Working
