# 📱 APK Deployment Note

## ⚠️ Important: APK Files Are Not in Git

APK files are **excluded from Git** because they exceed GitHub's 100 MB file size limit.

## 📂 Current Setup

- **Local APK Location**: `automotive_website/static/download/autopro.apk`
- **Git Status**: ❌ Not tracked (added to .gitignore)
- **Size**: ~175 MB (too large for GitHub)

## 🚀 How to Deploy APK

### For Local Development:
1. APK already exists at: `automotive_website/static/download/autopro.apk`
2. QR code on website will work locally
3. Download URL: `http://localhost:5000/download/autopro.apk`

### For Production (Render/Heroku):

#### Option 1: Manual Upload via FTP/SSH
```bash
# Upload APK to server
scp automotive_mobile/build/app/outputs/flutter-apk/app-debug.apk \
    user@server:/path/to/automotive_website/static/download/autopro.apk
```

#### Option 2: Use Cloud Storage (Recommended)
Upload APK to:
- **Firebase Storage**
- **AWS S3**
- **Google Cloud Storage**
- **Cloudinary**

Then update `index.html` QR code URL:
```javascript
var apkUrl = 'https://your-cloud-storage.com/autopro.apk';
```

#### Option 3: GitHub Releases
1. Create a GitHub Release
2. Attach APK as release asset
3. Get download URL
4. Update QR code to point to release URL

### Current .gitignore Entries:
```gitignore
# APK files (too large for Git, deploy separately)
*.apk
automotive_website/static/download/
automotive_website/static/apk/
```

## 🔄 Updating the APK

### Step 1: Build New APK
```bash
cd automotive_mobile
flutter build apk --debug
```

### Step 2: Copy to Website (Local)
```powershell
Copy-Item "build\app\outputs\flutter-apk\app-debug.apk" `
          "..\automotive_website\static\download\autopro.apk" -Force
```

### Step 3: Deploy to Production
Choose one of the deployment options above.

## 📝 Production Deployment Checklist

- [ ] Build latest APK with all fixes
- [ ] Test APK on Android device
- [ ] Upload APK to production storage
- [ ] Verify QR code URL is correct
- [ ] Test download from production website
- [ ] Update release notes

## 💡 Recommended: Use Firebase Storage

### Setup Firebase Storage for APK:

1. **Upload APK to Firebase Storage**:
   ```bash
   # Use Firebase Console or CLI
   firebase storage:upload app-debug.apk /apk/autopro.apk
   ```

2. **Get Public URL**:
   ```
   https://firebasestorage.googleapis.com/.../autopro.apk
   ```

3. **Update index.html**:
   ```javascript
   var apkUrl = 'https://firebasestorage.googleapis.com/.../autopro.apk';
   ```

4. **Benefits**:
   - ✅ No file size limits
   - ✅ Fast CDN delivery
   - ✅ Version control via Firebase
   - ✅ Download statistics
   - ✅ Easy updates

## 🎯 Quick Deploy Script

Create `deploy_apk.bat`:
```batch
@echo off
echo ====================================
echo    APK Deployment Script
echo ====================================
echo.

echo [1/3] Building APK...
cd automotive_mobile
call flutter build apk --debug
if errorlevel 1 goto error

echo [2/3] Copying to website folder...
copy /Y "build\app\outputs\flutter-apk\app-debug.apk" ^
       "..\automotive_website\static\download\autopro.apk"
if errorlevel 1 goto error

echo [3/3] Upload to production manually or via Firebase:
echo   firebase storage:upload build\app\outputs\flutter-apk\app-debug.apk /apk/autopro.apk
echo.
echo ✅ APK deployment complete!
echo    Local path: automotive_website\static\download\autopro.apk
echo    Size: ~175 MB
goto end

:error
echo ❌ Deployment failed!
exit /b 1

:end
pause
```

## 📊 File Size Info

- **app-debug.apk**: ~175 MB
- **GitHub limit**: 100 MB ❌
- **Git LFS limit**: 2 GB (but paid feature)
- **Firebase Storage**: Unlimited (with free tier limits)

## 🔐 Security Note

If you make the APK publicly accessible via URL:
- ✅ Users can download anytime
- ✅ No login required
- ⚠️ Make sure APK is signed properly
- ⚠️ Enable Google Play Protect checks

---

**Status**: APK excluded from Git, deploy separately  
**Current Commit**: Code changes only (no APK)  
**Date**: September 14, 2026
