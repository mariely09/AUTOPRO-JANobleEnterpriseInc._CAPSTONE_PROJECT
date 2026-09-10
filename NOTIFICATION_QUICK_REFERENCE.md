# Push Notification Quick Reference 📱

## TL;DR - Super Simple Explanation

**Q: Paano mag-send ng push notification?**  
**A: Create lang ng document sa Firestore! Automatic na ang push!**

```dart
// Ganito lang! Automatic na mag-push notification!
await FirebaseFirestore.instance.collection('notifications').add({
  'title': 'Hello!',
  'message': 'This will appear as push notification!',
  'targetRole': 'admin',  // or 'customer', 'staff'
});
```

**Yun lang! Tapos na!** ✅

---

## The Magic 🪄

```
YOU CREATE THIS:                         USERS GET THIS:
┌─────────────────┐                     ┌─────────────────────────┐
│ Firestore Doc   │                     │ 🔔 In-App Notification  │
│ notifications/  │  ──────────────>    │    (Bell Icon)          │
│   {title, msg}  │      AUTOMATIC!     │                         │
└─────────────────┘                     │ 📲 Push Notification    │
                                        │    (Phone Alert)        │
                                        └─────────────────────────┘
```

---

## Quick Examples

### Send to ALL Admins
```dart
FirebaseFirestore.instance.collection('notifications').add({
  'title': '🎉 New Booking',
  'message': 'Juan booked a service',
  'targetRole': 'admin',
});
```

### Send to ONE Customer
```dart
FirebaseFirestore.instance.collection('notifications').add({
  'title': '✅ Service Done',
  'message': 'Your car is ready!',
  'targetUid': customerId,
});
```

### Send to EVERYONE
```dart
FirebaseFirestore.instance.collection('notifications').add({
  'title': '📢 Announcement',
  'message': 'We are open tomorrow!',
  // No targetRole = everyone
});
```

---

## Required Fields

| Field | Type | Required? | Description |
|-------|------|-----------|-------------|
| `title` | String | ✅ YES | Notification title |
| `message` | String | ✅ YES | Notification content |
| `targetRole` | String | Optional | 'admin', 'staff', or 'customer' |
| `targetUid` | String | Optional | Specific user ID |
| `type` | String | Optional | For filtering/styling |
| `timestamp` | Timestamp | Auto | Server timestamp |
| `readBy` | Map | Auto | Tracks who read it |

---

## Targeting Rules

| Scenario | Code | Who Gets It? |
|----------|------|--------------|
| **One Person** | `'targetUid': 'abc123'` | That user only |
| **All Admins** | `'targetRole': 'admin'` | All admin users |
| **All Staff** | `'targetRole': 'staff'` | All staff users |
| **All Customers** | `'targetRole': 'customer'` | All customers |
| **Everyone** | No target fields | All registered users |

---

## How to Test (3 Ways)

### 1️⃣ Test Button in App
```dart
ElevatedButton(
  onPressed: () async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'title': '🧪 Test',
      'message': 'Testing 1, 2, 3...',
      'targetUid': FirebaseAuth.instance.currentUser!.uid,
    });
  },
  child: Text('Send Test Notification'),
)
```

### 2️⃣ OneSignal Dashboard
1. https://app.onesignal.com
2. Messages → New Push
3. Send test message

### 3️⃣ Firebase Console
1. https://console.firebase.google.com
2. Firestore Database
3. Add document to `notifications` collection manually

---

## Troubleshooting Checklist

**Not receiving push notifications?**

- [ ] Firebase Functions deployed? (`firebase deploy --only functions`)
- [ ] OneSignal credentials in Render environment?
- [ ] User has `oneSignalId` in Firestore?
- [ ] Phone notification permission allowed?
- [ ] App logged in via `OneSignal.login(userId)`?
- [ ] Check Firebase Functions logs (`firebase functions:log`)

---

## Important Notes ⚠️

1. **Automatic Process:**
   - You DON'T manually call OneSignal API
   - You DON'T write push notification code
   - Just create Firestore document = automatic push!

2. **Same Content, Two Places:**
   - Firestore document = In-app notification
   - OneSignal API = Push notification
   - Same title & message for both!

3. **Requires Setup:**
   - ✅ Firebase Functions deployed
   - ✅ OneSignal credentials configured
   - ✅ Users logged in via `OneSignal.login()`

---

## Common Use Cases

### ✅ Booking Confirmed
```dart
'title': '✅ Booking Confirmed'
'message': 'Your booking for Jan 15 has been confirmed'
'targetUid': customerId
```

### 🔧 Service Started
```dart
'title': '🔧 Service Started'
'message': 'Your vehicle ABC-1234 is now being serviced'
'targetUid': customerId
```

### 👤 New Registration (to Admins)
```dart
'title': '👤 New Registration'
'message': 'Juan Dela Cruz registered a new account'
'targetRole': 'admin'
```

### 📦 Low Stock Alert (to Admins)
```dart
'title': '⚠️ Low Stock Alert'
'message': 'Brake Pads stock is running low (5 left)'
'targetRole': 'admin'
```

### 📢 System Announcement (to Everyone)
```dart
'title': '📢 Holiday Notice'
'message': 'We will be closed on December 25-26'
// No target = everyone
```

---

## Pro Tips 💡

### 1. Use Emojis in Titles
```dart
'title': '✅ Success'  // Good!
'title': '❌ Error'    // Clear!
'title': '🎉 New'      // Attractive!
```

### 2. Keep Messages Short
```dart
// Good ✅
'message': 'Your car is ready for pickup'

// Too long ❌
'message': 'Your vehicle with plate number ABC-1234 has completed its maintenance service and is now ready for pickup at our shop located at...'
```

### 3. Include Action Context
```dart
// Better ✅
'title': '✅ Booking #123 Confirmed'
'message': 'Service scheduled for Jan 15 at 2:00 PM'

// Less helpful ❌
'title': 'Confirmed'
'message': 'Your request was confirmed'
```

---

## Files to Check

| File | Purpose |
|------|---------|
| `automotive_mobile/functions/index.js` | Firebase Function (auto-send push) |
| `automotive_mobile/lib/main.dart` | OneSignal initialization |
| `.env` | OneSignal credentials (local) |
| Render Dashboard → Environment | OneSignal credentials (production) |

---

## Summary

**To send push notification:**
```dart
FirebaseFirestore.instance.collection('notifications').add({
  'title': 'Your Title',
  'message': 'Your Message',
  'targetRole': 'admin', // or targetUid
});
```

**That's it! Firebase Function does the rest!** ✨

---

**Need more details? Check:**
- `PUSH_NOTIFICATION_FLOW_GUIDE.md` - Full technical explanation
- `ONESIGNAL_SETUP_GUIDE.md` - Setup instructions
- `ONESIGNAL_SECURITY_SETUP.md` - Security & deployment
