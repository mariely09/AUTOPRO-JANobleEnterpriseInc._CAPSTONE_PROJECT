# 📱 APK Download & QR Code Update

## ✅ What Was Updated

The QR code on the website's index.html now points to the **latest APK build** with all the Google Sign-In fixes.

## 📂 File Structure

```
automotive_website/
├── static/
│   └── download/
│       └── autopro.apk  ← Latest APK (copied from mobile build)
├── caltexautopro.py     ← Updated APK download route
└── templates/
    └── index.html        ← QR code already configured correctly
```

## 🔄 Changes Made

### 1. Created Download Folder
```
automotive_website/static/download/
```

### 2. Copied Latest APK
```powershell
Copy-Item "automotive_mobile\build\app\outputs\flutter-apk\app-debug.apk" 
          "automotive_website\static\download\autopro.apk"
```

### 3. Updated Flask Route (caltexautopro.py)
```python
@app.route('/download/autopro.apk')
def download_apk():
    apk_dir = os.path.join(os.path.dirname(__file__), 'static', 'download')
    # ... serves autopro.apk with no-cache headers
```

### 4. QR Code Configuration (index.html)
```javascript
var apkUrl = window.location.origin + '/download/autopro.apk';
```

## 🎯 How It Works

### User Flow:
```
1. User visits website index page
2. Scans QR code in "Get the App" section
3. Browser opens: https://yoursite.com/download/autopro.apk
4. APK downloads automatically
5. User installs APK on Android device
```

### QR Code Generation:
- Uses `api.qrserver.com` API
- 130x130 pixels
- Dark blue on white background
- Generated dynamically on page load
- Always points to latest APK

## 📱 Latest APK Includes

✅ Google Sign-In with OTP verification  
✅ Firestore email routing (not Google email)  
✅ SHA-1 fingerprint registered in Firebase  
✅ Auth persistence fixes (no auto-logout)  
✅ Enhanced user lookup (3-step fallback)  
✅ Debug logging for troubleshooting  

## 🔄 How to Update APK

### Option 1: Manual Copy (Quick)
```powershell
# 1. Build new APK
cd automotive_mobile
flutter build apk --debug

# 2. Copy to website
Copy-Item "build\app\outputs\flutter-apk\app-debug.apk" 
          "..\automotive_website\static\download\autopro.apk" -Force
```

### Option 2: Automated Script
Create `update_apk.bat`:
```batch
@echo off
echo Building APK...
cd automotive_mobile
call flutter build apk --debug
echo Copying to website...
copy /Y "build\app\outputs\flutter-apk\app-debug.apk" "..\automotive_website\static\download\autopro.apk"
echo Done! APK updated.
pause
```

## 🚀 Deployment

### Local Testing:
1. Run Flask server: `python caltexautopro.py`
2. Open: `http://localhost:5000`
3. Scroll to "Get the App" section
4. Scan QR code with phone
5. APK should download

### Production (Render):
1. Commit changes to git
2. Push to repository
3. Render auto-deploys
4. QR code on live site updates automatically

## 📝 Notes

### Cache Headers:
The Flask route sends **no-cache headers** to ensure users always get the latest APK:
```python
response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
response.headers['Pragma'] = 'no-cache'
response.headers['Expires'] = '0'
```

### APK Naming:
- Internal name: `autopro.apk`
- Download name: `AutoPro.apk` (user-friendly)

### Security:
- APK is served as `as_attachment=True` (forces download)
- No authentication required (public download)
- Static folder is served by Flask

## 🎨 QR Code Styling

The QR code section in index.html features:
- White container with rounded corners
- Shadow effect for depth
- Mobile responsive (hides on small screens via CSS)
- Hover states on surrounding elements

## 🔧 Troubleshooting

### QR Code Not Updating:
1. Hard refresh browser: `Ctrl+Shift+R`
2. Clear browser cache
3. Check QR code URL in browser console

### APK Download Fails:
1. Check file exists: `automotive_website/static/download/autopro.apk`
2. Check Flask server logs
3. Test route directly: `http://localhost:5000/download/autopro.apk`

### QR Code Shows Wrong URL:
1. Check `window.location.origin` in browser console
2. Verify Flask route matches
3. Ensure no redirect issues

---

**Status**: ✅ Updated  
**APK Version**: Latest (with Google Sign-In fixes)  
**Date**: September 14, 2026
