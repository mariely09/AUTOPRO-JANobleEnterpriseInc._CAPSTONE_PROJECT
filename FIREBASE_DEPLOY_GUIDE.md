# Firebase Functions Deployment Guide 🔥

## Current Status
✅ Firebase CLI installed successfully (v15.30.0)  
❌ Not logged in yet

---

## Step 1: Login to Firebase

**Run this command:**
```powershell
firebase login
```

**What will happen:**
1. Browser window will open
2. Google login page appears
3. Select your Google account (the one with Firebase access)
4. Grant permissions to Firebase CLI
5. Browser shows "Success! You can close this window"
6. Return to terminal

**After successful login:**
```
✔  Success! Logged in as your@email.com
```

---

## Step 2: Verify Project

**Check if you're in the right directory:**
```powershell
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile
```

**List available Firebase projects:**
```powershell
firebase projects:list
```

**Should show your project** (something like: `autopro-XXXXX`)

---

## Step 3: Select Project (if needed)

**If not selected yet:**
```powershell
firebase use <your-project-id>
```

**Example:**
```powershell
firebase use autopro-12345
```

---

## Step 4: Install Function Dependencies

**Make sure dependencies are installed:**
```powershell
cd functions
npm install
cd ..
```

---

## Step 5: Deploy Functions

**Deploy all functions:**
```powershell
firebase deploy --only functions
```

**What happens:**
- Uploads your functions to Firebase
- Shows progress for each function
- Takes 1-3 minutes

**Expected output:**
```
✔  functions[sendNotifications(us-central1)] Successful create operation.
✔  functions[sendPushNotification(us-central1)] Successful create operation.
✔  Deploy complete!
```

---

## Step 6: Verify Deployment

**Check deployed functions:**
```powershell
firebase functions:list
```

**Should show:**
- `sendNotifications` - Auto-trigger on Firestore
- `sendPushNotification` - Callable function
- `deleteUser` - User management
- Other functions...

---

## Troubleshooting

### Issue: "Permission denied" or "Insufficient permissions"

**Solution:**
- Make sure you're logged in with the correct Google account
- Account must have Firebase Admin access
- Try: `firebase logout` then `firebase login` again

### Issue: "Project not found"

**Solution:**
```powershell
firebase use --add
```
Select your project from the list

### Issue: Node version warning

**Current:** Node v24.15.0  
**Required:** Node v18

**Solution (optional):**
- Install nvm (Node Version Manager)
- Switch to Node 18: `nvm use 18`
- Or ignore the warning (usually still works)

### Issue: "Function deployment failed"

**Check:**
1. Internet connection
2. Firebase billing enabled (Blaze plan required for functions)
3. Check logs: `firebase functions:log`

---

## Alternative: Manual Steps

If automatic deployment fails, follow these manual steps:

### 1. Login
```powershell
firebase login
```

### 2. Navigate to project
```powershell
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile
```

### 3. Install dependencies
```powershell
cd functions
npm install
cd ..
```

### 4. Deploy
```powershell
firebase deploy --only functions
```

---

## After Successful Deployment

You can now test the complete flow:

1. Go to Firebase Console
2. Firestore Database
3. Create a test notification document
4. Automatic push notification will be sent!

See `PUSH_NOTIFICATION_TEST_GUIDE.md` for detailed testing instructions.

---

## Quick Commands Reference

```powershell
# Login
firebase login

# List projects
firebase projects:list

# Use project
firebase use <project-id>

# Deploy functions
firebase deploy --only functions

# View logs
firebase functions:log

# List deployed functions
firebase functions:list

# Logout
firebase logout
```

---

## Next Steps

After deployment:
1. Test via Firebase Console (create notification document)
2. Check Firebase Functions logs
3. Verify push notification received
4. Check OneSignal dashboard for delivery stats

Ready to proceed! 🚀
