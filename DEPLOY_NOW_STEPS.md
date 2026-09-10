# 🚀 Deploy Firebase Functions NOW - Step by Step

## Your Project Info:
- **Project ID:** `caltex-autopro-1e664`
- **Functions Location:** `c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile\functions`

---

## STEP 1: Login to Firebase

Open **PowerShell** or **Command Prompt** and run:

```powershell
firebase login
```

**What happens:**
1. Prompt: "Enable Gemini in Firebase features?" 
   - Type: **`n`** (No) and press Enter
2. Browser opens for Google login
3. Select your Google account
4. Grant permissions
5. See "Success!" message

---

## STEP 2: Navigate to Mobile Project

```powershell
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile
```

---

## STEP 3: Set Firebase Project

```powershell
firebase use caltex-autopro-1e664
```

**Expected output:**
```
Now using project caltex-autopro-1e664
```

---

## STEP 4: Install Function Dependencies

```powershell
cd functions
npm install
cd ..
```

**Expected output:**
```
added X packages...
```

This installs the `dotenv` package and other dependencies.

---

## STEP 5: Deploy Functions! 🚀

```powershell
firebase deploy --only functions
```

**What you'll see:**
```
=== Deploying to 'caltex-autopro-1e664'...

i  deploying functions
i  functions: ensuring required API is enabled...
✔  functions: required API is enabled
i  functions: preparing codebase for deployment
✔  functions: codebase uploaded successfully

The following functions will deploy:
  - sendNotifications (Firestore trigger)
  - sendPushNotification (Callable)
  - deleteUser (Callable)
  - checkDSSAlerts (Scheduled)
  - setupNotificationsCollection (Callable)

? Would you like to proceed with deployment? Yes

Deploying functions...
✔  functions[sendNotifications] Successful create operation.
✔  functions[sendPushNotification] Successful create operation.
✔  functions[deleteUser] Successful create operation.
✔  functions[checkDSSAlerts] Successful create operation.
✔  functions[setupNotificationsCollection] Successful create operation.

✔  Deploy complete!

Function URL (sendPushNotification):
  https://us-central1-caltex-autopro-1e664.cloudfunctions.net/sendPushNotification
```

**This takes 2-5 minutes.** ☕

---

## STEP 6: Verify Deployment

```powershell
firebase functions:list
```

**Should show:**
```
┌───────────────────────────────┬────────────┬─────────┐
│ Function Name                 │ Location   │ Status  │
├───────────────────────────────┼────────────┼─────────┤
│ sendNotifications             │ us-central1│ ACTIVE  │
│ sendPushNotification          │ us-central1│ ACTIVE  │
│ deleteUser                    │ us-central1│ ACTIVE  │
│ checkDSSAlerts                │ us-central1│ ACTIVE  │
│ setupNotificationsCollection  │ us-central1│ ACTIVE  │
└───────────────────────────────┴────────────┴─────────┘
```

---

## ⚠️ Possible Issues & Solutions

### Issue 1: "Firebase CLI needs to be authenticated"

**Solution:**
```powershell
firebase logout
firebase login
```

---

### Issue 2: "Billing account not configured"

**Error message:**
```
Cloud Functions deployment requires the pay-as-you-go (Blaze) billing plan.
```

**Solution:**
1. Go to: https://console.firebase.google.com
2. Select project: `caltex-autopro-1e664`
3. Click "Upgrade" button
4. Select "Blaze (Pay as you go)" plan
5. Add credit card (won't charge unless you exceed free tier)
6. Retry deployment

**Free tier includes:**
- 2 million function invocations/month
- 400,000 GB-seconds/month
- 200,000 CPU-seconds/month
- More than enough for your app!

---

### Issue 3: "Permission denied"

**Solution:**
- Make sure you're logged in with the correct Google account
- Account must have "Owner" or "Editor" role in Firebase project
- Check in Firebase Console → Project Settings → Users and permissions

---

### Issue 4: Node version warning

**Warning:**
```
npm WARN EBADENGINE Unsupported engine { required: { node: '18' } }
```

**Solution:**
- Ignore warning (usually still works)
- Or install Node 18 using nvm (Node Version Manager)

---

## After Successful Deployment ✅

Your Firebase Functions are now LIVE! 🎉

---

## NEXT: Test the Complete System!

### Test Method 1: Via Firebase Console

1. **Go to Firebase Console:**
   https://console.firebase.google.com/project/caltex-autopro-1e664/firestore

2. **Open Firestore Database**

3. **Find your User ID:**
   - Click "users" collection
   - Find your user document
   - Copy the Document ID (your UID)

4. **Create Test Notification:**
   - Go to "notifications" collection (or create it)
   - Click "Add document"
   - Fill in:
     ```
     Document ID: (auto-generate)
     
     title: "🧪 Test Push Notification"
     message: "Testing complete flow: Firestore → Function → OneSignal!"
     targetUid: "<PASTE_YOUR_USER_ID_HERE>"
     type: "test"
     timestamp: (current timestamp)
     readBy: {} (empty map)
     ```
   - Click "Save"

5. **Check Your Phone!** 📱
   - Should receive push notification within 2-3 seconds
   - Also check in-app notification (bell icon)

6. **Verify in Logs:**
   ```powershell
   firebase functions:log
   ```
   
   Should see:
   ```
   ✅ Notifications sent to 1 users via OneSignal
   OneSignal response: {"id": "..."}
   ```

---

### Test Method 2: Via OneSignal Dashboard

1. Go to: https://app.onesignal.com
2. Select "AutoPro" app
3. Messages → New Push
4. Create and send test message
5. Check phone immediately

---

## Monitoring & Logs

### View Function Logs (Real-time):
```powershell
firebase functions:log --follow
```

### View Specific Function Logs:
```powershell
firebase functions:log --only sendNotifications
```

### Check Function Status:
```powershell
firebase functions:list
```

### View in Firebase Console:
https://console.firebase.google.com/project/caltex-autopro-1e664/functions

---

## Summary of Commands

```powershell
# 1. Login
firebase login

# 2. Navigate
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile

# 3. Set project
firebase use caltex-autopro-1e664

# 4. Install dependencies
cd functions
npm install
cd ..

# 5. Deploy
firebase deploy --only functions

# 6. Verify
firebase functions:list

# 7. View logs
firebase functions:log
```

---

## What These Functions Do:

### 1. **sendNotifications** (Auto-trigger)
- Triggers when document created in `notifications` collection
- Reads title, message, targetRole/targetUid
- Automatically sends push notification via OneSignal
- **This is the magic function!** 🪄

### 2. **sendPushNotification** (Callable)
- Can be called from mobile app
- Manually send push notifications
- Used for custom notifications

### 3. **deleteUser** (Callable)
- Admin function to delete users
- Removes from Firebase Auth

### 4. **checkDSSAlerts** (Scheduled - runs every hour)
- Checks for low stock alerts
- Checks for overdue maintenance
- Automatically notifies admins/customers

### 5. **setupNotificationsCollection** (Callable)
- Sets up notifications collection on first run
- Creates sample notifications

---

## Ready to Deploy!

**Run these commands in order:**

1. `firebase login`
2. `cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile`
3. `firebase use caltex-autopro-1e664`
4. `cd functions && npm install && cd ..`
5. `firebase deploy --only functions`

**Then test via Firebase Console!** 🚀

---

## Need Help?

If you encounter any errors:
1. Copy the error message
2. Check the "Possible Issues & Solutions" section above
3. Check Firebase Functions logs: `firebase functions:log`
4. Ask for help with the specific error message

Good luck! 🍀
