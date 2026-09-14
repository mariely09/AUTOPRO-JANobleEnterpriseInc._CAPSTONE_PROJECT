# 🚀 MANUAL CLOUD FUNCTIONS DEPLOYMENT GUIDE

**Problem:** Firebase CLI deployment timing out due to network issues.

**Solution:** Deploy manually via Firebase Console.

---

## 📋 WHAT YOU NEED TO DEPLOY

**3 Missing Functions:**
1. ✅ `sendNotifications` - **MOST CRITICAL** (sends push via OneSignal)
2. ⚠️ `sendPushNotification` - Callable function (optional, for manual push)
3. ⚠️ `checkDSSAlerts` - Scheduled alerts (optional, runs every hour)

---

## 🔧 DEPLOYMENT STEPS

### **Function 1: sendNotifications** (CRITICAL!)

This function automatically sends push notifications when Firestore notifications are created.

#### Step 1: Open Firebase Console
https://console.firebase.google.com/project/caltex-autopro-1e664/functions

#### Step 2: Click "Create Function"

#### Step 3: Configure:
- **Function name:** `sendNotifications`
- **Trigger type:** Cloud Firestore
- **Event type:** `onCreate` (Document Creation)
- **Document path:** `notifications/{docId}`
- **Runtime:** Node.js 20
- **Memory:** 256 MB
- **Timeout:** 60 seconds
- **Region:** us-central1

#### Step 4: Set Environment Variables

Click "Runtime, build, connections and security settings" → "Add variable":

| Variable Name | Value |
|---------------|-------|
| `ONESIGNAL_APP_ID` | `48dcf379-b5b7-4692-b15c-f72779e8614d` |
| `ONESIGNAL_REST_API_KEY` | `os_v2_app_jdopg6nvw5djfmk464txt2dbjwvvdlqebggukzuh6qm6jopw342ffum77vewzt5hvmm2awhh5tnx2vt5veylamzcoiab7jirmb7eb2q` |

#### Step 5: Add Dependencies (package.json)

```json
{
  "dependencies": {
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^6.0.0",
    "axios": "^1.6.0"
  }
}
```

#### Step 6: Add Function Code (index.js)

```javascript
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const axios = require('axios');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

// OneSignal credentials from environment variables
const ONESIGNAL_APP_ID = process.env.ONESIGNAL_APP_ID || '48dcf379-b5b7-4692-b15c-f72779e8614d';
const ONESIGNAL_REST_API_KEY = process.env.ONESIGNAL_REST_API_KEY || 'os_v2_app_jdopg6nvw5djfmk464txt2dbjwvvdlqebggukzuh6qm6jopw342ffum77vewzt5hvmm2awhh5tnx2vt5veylamzcoiab7jirmb7eb2q';

exports.sendNotifications = onDocumentCreated('notifications/{docId}', async (event) => {
  const notification = event.data.data();
  const { title, message, targetRole, targetUid } = notification;

  if (!title || !message) {
    console.error('Notification missing title or message');
    return;
  }

  try {
    let userIds = [];

    // If targetUid is specified, send to that specific user
    if (targetUid) {
      userIds = [targetUid];
    }
    // If targetRole is specified, send to all users with that role
    else if (targetRole) {
      const snapshot = await admin.firestore()
        .collection('users')
        .where('role', '==', targetRole)
        .get();
      userIds = snapshot.docs.map(doc => doc.id);
    }
    // If neither specified, send to all users
    else {
      const snapshot = await admin.firestore()
        .collection('users')
        .get();
      userIds = snapshot.docs.map(doc => doc.id);
    }

    if (userIds.length === 0) {
      console.log('No users found to send notification');
      return;
    }

    // Send via OneSignal
    const response = await axios.post(
      'https://api.onesignal.com/notifications',
      {
        app_id: ONESIGNAL_APP_ID,
        include_external_user_ids: userIds,
        headings: { en: title },
        contents: { en: message },
        data: { type: notification.type || 'info' },
      },
      {
        headers: {
          'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
          'Content-Type': 'application/json; charset=utf-8',
        },
      }
    );

    console.log(`Notifications sent to ${userIds.length} users via OneSignal`);
    console.log(`OneSignal response: ${response.data.id}`);
  } catch (error) {
    console.error('Error in sendNotifications:', error);
  }
});
```

#### Step 7: Click "Deploy"

Wait 2-3 minutes for deployment to complete.

---

## ✅ VERIFY DEPLOYMENT

### Method 1: Check Firebase Console
1. Go to: https://console.firebase.google.com/project/caltex-autopro-1e664/functions
2. Should see `sendNotifications` in the list
3. Status should show green checkmark

### Method 2: Run Test Script
```powershell
cd c:\Project\AUTOMOTIVE_SERVICE
python test_push_notification.py
```

**Expected output:**
- Notification created in Firestore ✅
- Check OneSignal dashboard - should see new message ✅
- Check customer device - should receive push 📱

### Method 3: Check Function Logs
1. Go to: https://console.firebase.google.com/project/caltex-autopro-1e664/functions/logs
2. Create a test notification (run test script)
3. Should see log: "Notifications sent to X users via OneSignal"

---

## 🎯 ALTERNATIVE: Try CLI Deployment Later

If your internet connection improves, you can try CLI deployment:

```powershell
# Navigate to project
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile

# Deploy all functions at once
firebase deploy --only functions

# Or deploy specific function
firebase deploy --only functions:sendNotifications
```

**Advantages of CLI deployment:**
- Deploys all 4 functions at once
- Easier to update code
- Uses local `index.js` file

**Current issue:** Network timeouts when uploading to Google Cloud Storage

---

## 📝 OPTIONAL FUNCTIONS (Deploy Later)

### Function 2: sendPushNotification (Callable)
- **Purpose:** Manual push notification via app/website
- **Priority:** LOW (can deploy later)
- **Trigger:** HTTPS Callable
- **Code:** See `automotive_mobile/functions/index.js` lines 124-186

### Function 3: checkDSSAlerts (Scheduled)
- **Purpose:** Hourly checks for stock/PMS alerts
- **Priority:** MEDIUM (nice to have)
- **Trigger:** Cloud Scheduler - every 1 hours
- **Code:** See `automotive_mobile/functions/index.js` lines 188-end

---

## ⚠️ IMPORTANT NOTES

1. **Environment Variables are CRITICAL**
   - Without OneSignal keys, function will fail silently
   - Double-check spelling and values

2. **Region must be us-central1**
   - Match your Firestore region
   - Otherwise may have cross-region latency

3. **Test immediately after deployment**
   - Run test script to verify
   - Check logs for errors
   - Verify push received on device

4. **If deployment fails:**
   - Check Firebase billing (must be on Blaze plan for Cloud Functions)
   - Check IAM permissions (must have Editor/Owner role)
   - Check network/firewall not blocking Google APIs

---

## 🆘 TROUBLESHOOTING

### Issue: "Deployment failed"
**Solutions:**
- Check Firebase project is on Blaze (pay-as-you-go) plan
- Check you're logged in with correct Google account
- Check APIs are enabled (Cloud Functions, Cloud Build)

### Issue: Function deployed but not triggering
**Solutions:**
- Check Firestore rules allow Cloud Functions to read
- Check environment variables are set correctly
- Check function logs for errors

### Issue: OneSignal not receiving
**Solutions:**
- Verify OneSignal APP_ID and API_KEY are correct
- Check OneSignal dashboard for failed deliveries
- Test with OneSignal REST API directly

---

## 📞 NEXT STEPS

1. **Deploy sendNotifications manually** (follow steps above)
2. **Wait 2-3 minutes** for deployment to complete
3. **Run test script** to verify: `python test_push_notification.py`
4. **Check results:**
   - Firebase Functions logs
   - OneSignal dashboard
   - Customer device
5. **Report back** with screenshot of deployment status

---

**Created:** September 14, 2026  
**Author:** Kiro AI Assistant
