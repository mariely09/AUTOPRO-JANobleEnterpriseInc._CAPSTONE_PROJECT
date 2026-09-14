# 📱 QR Code Setup Guide - AutoPro APK Download

## ✅ Current Setup Status

The QR code on the website's mobile app section is **properly configured** and ready to use!

## 🎯 What the QR Code Does

When users scan the QR code on your website:
1. Their phone camera opens the link: `https://yoursite.com/download/autopro.apk`
2. The browser automatically downloads the **AutoPro.apk** file
3. Users can then install the app on their Android device

## 📂 File Structure

```
AUTOMOTIVE_SERVICE/
├── automotive_website/
│   ├── static/
│   │   └── download/
│   │       └── autopro.apk          ← 174.83 MB APK file
│   ├── templates/
│   │   └── index.html               ← QR code section
│   ├── caltexautopro.py             ← Flask download route
│   └── test_qr.html                 ← QR code test page
└── automotive_mobile/
    └── build/app/outputs/flutter-apk/
        └── app-debug.apk            ← Source APK
```

## 🔧 Technical Implementation

### 1. Flask Download Route (`caltexautopro.py`)

```python
@app.route('/download/autopro.apk')
def download_apk():
    """Serve the AutoPro APK for direct download."""
    apk_dir = os.path.join(os.path.dirname(__file__), 'static', 'download')
    apk_path = os.path.join(apk_dir, 'autopro.apk')
    
    if not os.path.exists(apk_path):
        return 'APK not found', 404
    
    response = send_from_directory(
        apk_dir, 
        'autopro.apk',
        as_attachment=True,
        download_name='AutoPro.apk'
    )
    
    # No-cache headers ensure latest version
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    
    return response
```

### 2. QR Code Generation (`index.html`)

```javascript
// Dynamically generate QR code based on current domain
var apkUrl = window.location.origin + '/download/autopro.apk';

var qrApi = 'https://api.qrserver.com/v1/create-qr-code/' +
            '?size=260x260' +              // High resolution
            '&data=' + encodeURIComponent(apkUrl) +
            '&color=1a202c' +               // Dark blue/gray
            '&bgcolor=ffffff' +             // White background
            '&margin=2' +                   // Small margin
            '&qzone=1' +                    // Quiet zone
            '&ecc=H';                       // High error correction

document.getElementById('apkQrImg').src = qrApi;
```

### 3. QR Code Features

✅ **Dynamic URL** - Adapts to any domain (localhost or production)  
✅ **High Resolution** - 260x260 pixels for better scanning  
✅ **Error Correction** - Level H for reliability even if partially obscured  
✅ **No Cache** - Always serves the latest APK version  
✅ **Error Handling** - Console logs and fallback messages  
✅ **URL Display** - Shows the download link for verification

## 🧪 Testing the QR Code

### Option 1: Using the Test Page

1. Start the Flask server:
   ```powershell
   cd automotive_website
   python caltexautopro.py
   ```

2. Open the test page:
   ```
   http://localhost:5000/test_qr.html
   ```

3. The test page will:
   - Display the QR code
   - Show the APK download URL
   - Test if the download link works
   - Display file size and status

### Option 2: Testing on the Main Website

1. Start the Flask server
2. Open: `http://localhost:5000`
3. Scroll to the **"Get the App"** section
4. The QR code should be visible in the left column
5. Use your phone to scan the QR code
6. Your phone should prompt to download the APK

### Option 3: Direct Link Test

Simply open in browser:
```
http://localhost:5000/download/autopro.apk
```

The APK should download immediately.

## 📱 User Instructions

### For Website Visitors:

1. **Scroll** to the "Your AutoPro Portal, Right in Your Pocket" section
2. **Scan** the QR code with your phone's camera app
3. **Tap** the notification to open the download link
4. **Allow** the download to complete (174 MB)
5. **Open** the downloaded file
6. **Enable** "Install from Unknown Sources" if prompted
7. **Install** the AutoPro app
8. **Open** the app and sign in

## 🔄 Updating the APK

When you build a new version of the mobile app:

### Manual Update:
```powershell
# 1. Build the new APK
cd automotive_mobile
flutter build apk --debug

# 2. Copy to website folder
Copy-Item "build\app\outputs\flutter-apk\app-debug.apk" `
          "..\automotive_website\static\download\autopro.apk" -Force

# 3. Restart Flask server (if running)
```

### Automated Script:
Create `update_apk.bat` in the root folder:
```batch
@echo off
echo ========================================
echo   AutoPro APK Update Script
echo ========================================
echo.

echo [1/3] Building APK...
cd automotive_mobile
call flutter build apk --debug
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: APK build failed!
    pause
    exit /b 1
)

echo [2/3] Copying to website...
copy /Y "build\app\outputs\flutter-apk\app-debug.apk" ^
        "..\automotive_website\static\download\autopro.apk"
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Copy failed!
    pause
    exit /b 1
)

echo [3/3] Verifying...
if exist "..\automotive_website\static\download\autopro.apk" (
    echo SUCCESS: APK updated successfully!
    dir "..\automotive_website\static\download\autopro.apk"
) else (
    echo ERROR: APK file not found after copy!
)

echo.
echo ========================================
echo   Update Complete!
echo ========================================
pause
```

## 🚀 Production Deployment

### For Render or Similar Hosting:

1. **Commit** the APK file to git:
   ```bash
   git add automotive_website/static/download/autopro.apk
   git commit -m "Update APK to latest version"
   git push
   ```

2. Render will **auto-deploy** the changes

3. The QR code will **automatically work** on your live domain

4. Users scanning the code will download from:
   ```
   https://your-production-domain.com/download/autopro.apk
   ```

### Important Notes for Production:

⚠️ **APK Size Warning**: The APK is ~175 MB. Ensure your hosting plan supports:
- Large file serving
- Sufficient bandwidth
- No file size limits

⚠️ **HTTPS Required**: For security, always serve APKs over HTTPS

⚠️ **Cache Control**: The no-cache headers ensure users always get the latest version

## 🎨 QR Code Styling

The QR code section in `index.html` features:

- ✨ White rounded container with shadow
- 📱 Responsive design (hides extra phones on mobile)
- 🎯 Prominent placement in "Get the App" section
- 🔍 URL display for debugging (visible below QR code)
- 💡 Console logging for troubleshooting

## 🐛 Troubleshooting

### QR Code Not Appearing?

**Check:**
1. QR Server API is accessible: https://api.qrserver.com
2. Browser console for JavaScript errors
3. Network tab shows the QR image loading

**Fix:**
- Hard refresh: `Ctrl + Shift + R`
- Check internet connection
- Try a different browser

### APK Download Fails?

**Check:**
1. File exists: `automotive_website/static/download/autopro.apk`
2. Flask route is registered (check server startup logs)
3. File permissions allow reading
4. Sufficient disk space

**Test:**
```powershell
# Verify file exists
Test-Path "automotive_website\static\download\autopro.apk"

# Check file size
Get-Item "automotive_website\static\download\autopro.apk" | 
  Select-Object Name, Length, LastWriteTime
```

### Wrong APK Version Downloading?

**Cause:** Browser or CDN caching

**Fix:**
1. Clear browser cache completely
2. Use incognito/private browsing mode
3. Check the APK's `LastWriteTime` timestamp
4. Verify Flask is sending no-cache headers

### QR Code Shows Wrong Domain?

**Check:**
1. `window.location.origin` in browser console
2. Flask is running on expected port
3. No proxy/redirect issues

**Fix:**
- Verify the base URL in browser address bar
- Check Flask startup logs for bind address
- Test direct APK URL in browser

## 📊 Current Status Summary

| Component | Status | Details |
|-----------|--------|---------|
| APK File | ✅ Present | 174.83 MB, Updated Sep 14, 2026 |
| Flask Route | ✅ Working | `/download/autopro.apk` |
| QR Code | ✅ Configured | Dynamic URL, High-res |
| Cache Control | ✅ Enabled | No-cache headers set |
| Error Handling | ✅ Implemented | Logs and fallbacks |
| Test Page | ✅ Created | `test_qr.html` |

## 🎯 Next Steps

1. ✅ **Test locally** - Use the test page to verify
2. ✅ **Test on phone** - Scan the QR code with your device
3. ✅ **Install APK** - Verify the app installs correctly
4. ✅ **Update docs** - Keep this guide updated with any changes
5. 🚀 **Deploy** - Push to production when ready

## 📞 Support

If users have issues:
1. Provide direct download link: `/download/autopro.apk`
2. Check device has space for 175+ MB file
3. Verify Android version compatibility (Android 5.0+)
4. Ensure "Unknown Sources" is enabled in Android settings

---

**Last Updated:** September 14, 2026  
**APK Version:** Latest with Google Sign-In fixes  
**Status:** ✅ Ready for Production
