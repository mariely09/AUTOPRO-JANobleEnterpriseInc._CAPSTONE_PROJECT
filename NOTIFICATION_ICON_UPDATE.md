# 🎨 Push Notification Icon Update - AutoPro Logo

**Date:** September 14, 2026  
**Changes:** Updated push notification icon to use AutoPro logo instead of default icon

---

## ✅ WHAT WAS CHANGED

### 1. **AndroidManifest.xml** - Small Icon Configuration
**File:** `automotive_mobile/android/app/src/main/AndroidManifest.xml`

**Added:**
```xml
<!-- OneSignal Notification Icon (uses app launcher icon) -->
<meta-data
    android:name="com.onesignal.NotificationServiceExtension.small_icon"
    android:resource="@mipmap/ic_launcher" />

<!-- OneSignal Notification Accent Color (AutoPro red) -->
<meta-data
    android:name="com.onesignal.NotificationServiceExtension.notification_accent_color"
    android:resource="@color/notification_accent_color" />
```

**Result:**
- Small notification icon now uses AutoPro launcher icon
- Notification bar shows AutoPro logo
- Accent color is AutoPro red (#E8001C)

---

### 2. **colors.xml** - Brand Color Definition
**File:** `automotive_mobile/android/app/src/main/res/values/colors.xml` (NEW)

**Added:**
```xml
<color name="notification_accent_color">#E8001C</color>
```

**Result:**
- Notification uses AutoPro brand red color
- Matches app branding

---

### 3. **Cloud Function** - Large Icon URL
**File:** `automotive_mobile/functions/index.js`

**Updated `sendNotifications` and `sendPushNotification` functions:**
```javascript
large_icon: 'https://firebasestorage.googleapis.com/v0/b/caltex-autopro-1e664.firebasestorage.app/o/autopro_logo.png?alt=media',
```

**Result:**
- Large notification icon shows AutoPro logo
- Displayed in expanded notification view
- Logo fetched from Firebase Storage

---

## 📱 HOW IT LOOKS NOW

### Before (Default):
- 🔔 Generic notification icon (white bell or app icon outline)
- Gray accent color
- No logo in notification

### After (AutoPro):
- 🚗 AutoPro logo as notification icon
- Red accent color (#E8001C)
- Large AutoPro logo in expanded view

---

## 🚀 DEPLOYMENT STEPS

### Step 1: Upload Logo to Firebase Storage

**Need to upload AutoPro logo as `autopro_logo.png`:**

1. Go to: https://console.firebase.google.com/project/caltex-autopro-1e664/storage
2. Click "Upload file"
3. Select AutoPro logo image (PNG format, recommended 256x256px)
4. Name it: `autopro_logo.png`
5. Make it public (same rules as APK file)

**Or use existing logo if already uploaded**

---

### Step 2: Rebuild Android APK

Since AndroidManifest.xml was changed, need to rebuild APK:

```powershell
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile

# Clean build
flutter clean

# Build release APK
flutter build apk --release
```

**Output:** New APK with notification icon configuration  
**Location:** `build/app/outputs/flutter-apk/app-release.apk`

---

### Step 3: Deploy Updated Cloud Function

Cloud Function already updated with `large_icon` parameter. Need to redeploy:

```powershell
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile

# Deploy functions
firebase deploy --only functions
```

**Or:** Wait for automatic deployment if connected to GitHub

---

### Step 4: Distribute New APK

1. **Upload to Firebase Storage** (replace old autopro.apk)
2. **Users install new version** (via QR code)
3. **Notification icon will update** after new installation

---

## ⚠️ IMPORTANT NOTES

### Notification Icon Requirements:
1. **Small Icon (status bar):**
   - Must be transparent PNG
   - White silhouette on transparent background
   - Android uses app launcher icon automatically
   - Size: 24x24dp (various densities)

2. **Large Icon (expanded notification):**
   - Can be full-color PNG
   - Displayed as circle in notification
   - Recommended size: 256x256px
   - Hosted on Firebase Storage

3. **Accent Color:**
   - Used for small icon tinting
   - AutoPro red: #E8001C
   - Visible in status bar

---

## 🧪 TESTING

### Test 1: Send Test Notification

```powershell
cd c:\Project\AUTOMOTIVE_SERVICE
python test_push_notification.py
```

### Test 2: Check Notification Appearance

1. **Status bar:** Should show AutoPro logo (small icon)
2. **Pull down notification:** Should show full notification
3. **Expanded view:** Should show large AutoPro logo
4. **Color:** Red accent color visible

### Test 3: Real Scenario

1. **Staff marks vehicle as "Completed"**
2. **Customer receives notification**
3. **Check notification icon** - should be AutoPro logo

---

## 🎨 DESIGN SPECIFICATIONS

**Small Icon (Status Bar):**
- Format: PNG (transparent)
- Colors: White + Transparent only
- Size: 24x24dp base
  - mdpi: 24x24px
  - hdpi: 36x36px
  - xhdpi: 48x48px
  - xxhdpi: 72x72px
  - xxxhdpi: 96x96px

**Large Icon (Notification):**
- Format: PNG (full color)
- Size: 256x256px (will be displayed as circle)
- Background: Can be transparent or colored
- Recommend: Logo on white/transparent background

**Accent Color:**
- AutoPro Red: #E8001C
- Used for: Small icon tint, notification actions

---

## 📋 FILES MODIFIED

```
automotive_mobile/
├── android/
│   └── app/
│       └── src/
│           └── main/
│               ├── AndroidManifest.xml          # ✅ Added OneSignal icon config
│               └── res/
│                   └── values/
│                       └── colors.xml           # ✅ NEW - Brand colors
├── functions/
│   └── index.js                                 # ✅ Added large_icon URL
└── [Need to rebuild APK after changes]
```

---

## 🆘 TROUBLESHOOTING

### Issue: Icon not showing after update

**Solutions:**
1. Ensure new APK is installed (not old version)
2. Clear app cache and data
3. Uninstall and reinstall app
4. Check Firebase Storage logo URL is accessible

### Issue: Icon is generic (not AutoPro logo)

**Check:**
1. AndroidManifest.xml has correct meta-data
2. ic_launcher.png exists in mipmap folders
3. APK was rebuilt after manifest changes
4. New APK was distributed to users

### Issue: Large icon not showing

**Check:**
1. Firebase Storage logo URL is correct
2. Logo file is publicly accessible
3. Cloud Function redeployed with new code
4. Network connection available when notification sent

---

## ✅ NEXT STEPS

1. **Upload `autopro_logo.png`** to Firebase Storage
2. **Rebuild APK:** `flutter build apk --release`
3. **Upload new APK** to Firebase Storage (replace old one)
4. **Deploy Cloud Functions:** `firebase deploy --only functions`
5. **Test notifications** with test script
6. **Distribute new APK** to users via QR code

---

**Created:** September 14, 2026  
**Status:** Code updated, needs rebuild + redeploy  
**Author:** Kiro AI Assistant
