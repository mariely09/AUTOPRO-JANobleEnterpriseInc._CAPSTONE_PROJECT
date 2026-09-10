# Push Notification Flow Guide - Paano Gumagana?

## 📱 Overview

Ang push notification system mo ay **AUTOMATIC**! 

**Simple Explanation:**
> Kapag may bagong document sa **`notifications`** collection sa Firestore, automatic na magpapadala ng **push notification** via OneSignal sa mobile devices!

---

## 🔄 How It Works (Step-by-Step)

### Step 1: May Gagawa ng Notification (In-App)
Kahit saan sa system mo, pag may event (booking, registration, etc.), lumilikha ng **in-app notification**:

```dart
// Example: Customer registered
await FirebaseFirestore.instance.collection('notifications').add({
  'title': '👤 New Account Registered',
  'message': 'Juan Dela Cruz (juan@email.com) has created a new account.',
  'targetRole': 'admin',  // Sino ang makakakita
  'type': 'account',
  'timestamp': FieldValue.serverTimestamp(),
  'readBy': {},
});
```

### Step 2: Firebase Function Automatically Triggers! ⚡
Pagka-create ng document sa `notifications` collection, **automatic** na mag-trigger ang Firebase Function:

```javascript
// Automatic trigger - HINDI MO KAILANGAN I-CALL!
exports.sendNotifications = onDocumentCreated('notifications/{docId}', async (event) => {
  const notification = event.data.data();
  const { title, message, targetRole, targetUid } = notification;
  
  // Kukunin ang users based sa targetRole o targetUid
  // Automatic magpapadala via OneSignal
});
```

### Step 3: OneSignal Sends Push Notification 📲
Ang Firebase Function ay:
1. Kukunin ang target users (based sa `targetRole` or `targetUid`)
2. Magpapadala ng push notification via OneSignal API
3. Makikita ng users sa mobile device (kahit nakaclose ang app!)

### Step 4: Users See Both! 👀

**In-App Notification (Bell Icon):**
- Makikita sa loob ng app
- May badge count
- Pwedeng i-click para makita details
- Stored sa Firestore

**Push Notification (Device Notification):**
- Lalabas sa notification tray ng phone
- Kahit nakaclose ang app
- May sound/vibration
- Pwedeng i-tap para buksan ang app

---

## 📊 Notification Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  EVENT HAPPENS (Booking, Registration, etc.)                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     v
┌─────────────────────────────────────────────────────────────┐
│  CREATE DOCUMENT in Firestore 'notifications' collection    │
│  {                                                           │
│    title: "New Booking",                                    │
│    message: "Juan booked a service",                        │
│    targetRole: "admin"                                      │
│  }                                                           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     v
┌─────────────────────────────────────────────────────────────┐
│  FIREBASE FUNCTION AUTO-TRIGGERS (sendNotifications)        │
│  - Reads the new document                                   │
│  - Gets target users (based on targetRole/targetUid)        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     v
┌─────────────────────────────────────────────────────────────┐
│  ONESIGNAL API CALL                                         │
│  - Sends push notification to user devices                  │
│  - Uses user's OneSignal external_id (user UID)            │
└────────────────────┬────────────────────────────────────────┘
                     │
                     v
┌─────────────────────────────────────────────────────────────┐
│  USER RECEIVES BOTH:                                        │
│  ✅ In-App Notification (bell icon)                         │
│  ✅ Push Notification (device notification tray)            │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Target Audiences (Sino ang Makakakita?)

### Option 1: Specific User (`targetUid`)
```dart
// Send to ONE specific user
await FirebaseFirestore.instance.collection('notifications').add({
  'title': 'Service Complete',
  'message': 'Your vehicle is ready!',
  'targetUid': 'customer_user_id_here',  // Specific customer
});
```

**Result:** 
- In-app notification ✅
- Push notification ✅
- **1 user lang** makakakita

---

### Option 2: By Role (`targetRole`)
```dart
// Send to ALL users with specific role
await FirebaseFirestore.instance.collection('notifications').add({
  'title': 'New Booking',
  'message': 'Customer booked a service',
  'targetRole': 'admin',  // All admins
});
```

**Result:**
- In-app notification ✅ (all admins)
- Push notification ✅ (all admins)
- **Lahat ng admin** makakakita

**Available Roles:**
- `admin` - All administrators
- `staff` - All staff members
- `customer` - All customers

---

### Option 3: Everyone (No targetRole/targetUid)
```dart
// Send to EVERYONE (broadcast)
await FirebaseFirestore.instance.collection('notifications').add({
  'title': 'System Maintenance',
  'message': 'System will be down tomorrow 2AM-4AM',
  // No targetRole or targetUid = everyone
});
```

**Result:**
- In-app notification ✅ (everyone)
- Push notification ✅ (everyone)
- **Lahat ng users** makakakita

---

## 📝 Notification Document Structure

```javascript
{
  // Required fields
  "title": "Notification Title",
  "message": "Notification message content",
  
  // Targeting (at least one, or none for broadcast)
  "targetRole": "admin",        // Optional: 'admin', 'staff', 'customer'
  "targetUid": "user_id_here",  // Optional: specific user ID
  
  // Additional info
  "type": "booking",            // Optional: 'booking', 'account', 'maintenance', etc.
  "timestamp": ServerTimestamp, // Auto-generated
  "readBy": {},                 // Tracks who read the notification
  
  // Optional metadata
  "bookingId": "booking_123",   // Link to related document
  "vehicleId": "vehicle_456",
  "customerId": "customer_789"
}
```

---

## 🔍 Real Examples sa Iyong System

### Example 1: New Account Registration
**Location:** `automotive_mobile/lib/register.dart`

```dart
await FirebaseFirestore.instance.collection('notifications').add({
  'title': '👤 New Account Registered',
  'message': '$firstName $lastName ($email) has created a new account.',
  'targetRole': 'admin',  // Only admins see this
  'type': 'account',
  'timestamp': FieldValue.serverTimestamp(),
  'readBy': {},
});
```

**What Happens:**
1. ✅ In-app notification created (bell icon)
2. ✅ Firebase Function auto-triggers
3. ✅ Push notification sent to ALL admin devices
4. ✅ Admins see notification kahit hindi naka-open ang app

---

### Example 2: Vehicle Under Maintenance
**Location:** `automotive_mobile/lib/admin_service_bookings.dart`

```dart
FirebaseFirestore.instance.collection('notifications').add({
  'title': '🔧 Vehicle Under Maintenance',
  'message': 'Your vehicle $plate is now under maintenance. We will notify you once the service is completed.',
  'targetUid': customerId,  // Specific customer only
  'type': 'maintenance',
  'timestamp': FieldValue.serverTimestamp(),
  'readBy': {},
});
```

**What Happens:**
1. ✅ In-app notification for customer
2. ✅ Firebase Function auto-triggers
3. ✅ Push notification sent to THAT customer's device only
4. ✅ Customer sees notification immediately

---

### Example 3: Service Completed
**Location:** `automotive_mobile/lib/admin_vehicle_maintenance.dart`

```dart
await FirebaseFirestore.instance.collection('notifications').add({
  'title': '✅ Service Completed',
  'message': 'Your vehicle ${plate} has been serviced and is ready for pickup.',
  'targetUid': customerId,  // Specific customer
  'type': 'completed',
  'timestamp': FieldValue.serverTimestamp(),
  'readBy': {},
});
```

**What Happens:**
1. ✅ Customer sees in-app notification
2. ✅ Push notification sent automatically
3. ✅ Customer gets alert kahit nasa labas

---

## ⚙️ Important Settings

### User OneSignal ID Setup

Para makatanggap ang user ng push notifications, dapat may `oneSignalId` field sa user document:

```dart
// When user logs in to mobile app
await FirebaseFirestore.instance.collection('users').doc(userId).update({
  'oneSignalId': oneSignalSubscriptionId,
});
```

**Paano kukunin ang OneSignal ID?**
```dart
// In mobile app (Flutter)
OneSignal.initialize('48dcf379-b5b7-4692-b15c-f72779e8614d');

// Set external user ID (Firebase UID)
OneSignal.login(firebaseUserId);

// OneSignal will automatically link the device to this user
```

---

## 🧪 Testing Push Notifications

### Method 1: Test via Code
```dart
// Add this anywhere in your app (temporary test button)
ElevatedButton(
  onPressed: () async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'title': '🧪 Test Notification',
      'message': 'This is a test push notification!',
      'targetUid': FirebaseAuth.instance.currentUser!.uid,
      'type': 'test',
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': {},
    });
    print('Test notification created!');
  },
  child: Text('Send Test Notification'),
)
```

### Method 2: Test via OneSignal Dashboard
1. Go to https://app.onesignal.com
2. Select your "AutoPro" app
3. Messages → New Push
4. Enter title & message
5. Select target users
6. Send

### Method 3: Check Firebase Functions Logs
```bash
cd automotive_mobile
firebase functions:log
```

Look for:
```
✅ Notifications sent to X users via OneSignal
OneSignal response: {notification_id}
```

---

## 🐛 Troubleshooting

### Issue: Hindi Dumarating ang Push Notification

**Check 1: User has OneSignal ID?**
```dart
// Check Firestore user document
final userDoc = await FirebaseFirestore.instance
  .collection('users')
  .doc(userId)
  .get();
  
print('OneSignal ID: ${userDoc.data()?['oneSignalId']}');
// Should NOT be null or empty
```

**Check 2: Permission Allowed?**
```dart
// Check notification permission
final permission = await OneSignal.Notifications.permission;
print('Permission: $permission'); // Should be true
```

**Check 3: Firebase Function Deployed?**
```bash
firebase deploy --only functions
```

**Check 4: Check Firebase Functions Logs**
```bash
firebase functions:log
```

**Check 5: Verify OneSignal Credentials**
- Check Render environment variables
- Verify App ID matches OneSignal dashboard
- Verify REST API Key is correct

---

### Issue: In-App Notification OK, Push Notification Wala

**Possible Causes:**
1. ❌ Firebase Function not deployed
2. ❌ OneSignal credentials incorrect
3. ❌ User's device not registered with OneSignal
4. ❌ User disabled notifications sa phone settings
5. ❌ App not logged in to OneSignal

**Solution:**
```bash
# Redeploy functions
cd automotive_mobile
firebase deploy --only functions

# Check logs
firebase functions:log
```

---

## 📱 User Experience

### Customer Scenario:
1. Customer books a service via mobile app
2. **Admin receives:**
   - 🔔 In-app notification (bell icon)
   - 📲 Push notification on phone
3. Admin accepts the booking
4. **Customer receives:**
   - 🔔 In-app notification
   - 📲 Push notification: "Your booking was accepted!"

### All Automatic! Zero Manual Work! 🎉

---

## ✨ Summary

| Feature | Status | How It Works |
|---------|--------|-------------|
| **In-App Notifications** | ✅ | Stored in Firestore `notifications` collection |
| **Push Notifications** | ✅ | Auto-triggered via Firebase Function |
| **Targeting** | ✅ | By role (`targetRole`) or user (`targetUid`) |
| **Real-time** | ✅ | Instant delivery via OneSignal |
| **No Manual Sending** | ✅ | 100% automatic on document create |

---

## 🎯 Key Takeaways

1. **ONE ACTION = TWO NOTIFICATIONS**
   - Create document sa Firestore = In-app + Push notification

2. **AUTOMATIC = ZERO CODE NEEDED**
   - Firebase Function handles everything
   - Just create the Firestore document!

3. **FLEXIBLE TARGETING**
   - Specific user (`targetUid`)
   - By role (`targetRole`)
   - Everyone (no target)

4. **SAME CONTENT, DIFFERENT CHANNELS**
   - Same `title` and `message`
   - Shows in app (bell icon)
   - Shows on device (notification tray)

---

**Walang kailangang gawin pa! Automatic na lahat!** 🚀

Basta may internet connection at naka-deploy ang Firebase Functions, gagana na ang push notifications! 🎉
