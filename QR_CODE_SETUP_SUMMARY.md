# QR Code Setup - Complete ✅

## What Was Updated

### 1. **QR Code Enhancement** (`index.html`)
The QR code in the "Get the App" section now:
- ✅ **Higher Resolution**: 300x300px instead of 130x130px for better scanning
- ✅ **Better Margins**: Increased margin and quiet zone for reliable scanning
- ✅ **Error Handling**: Shows download link if QR code fails to load
- ✅ **User Instructions**: Added helpful text explaining how to scan
- ✅ **Auto-Detection**: Constructs the correct download URL automatically

### 2. **How It Works**

```
User scans QR Code
        ↓
Camera detects URL
        ↓
User taps notification
        ↓
Browser downloads APK from:
https://your-domain.com/download/autopro.apk
        ↓
Android prompts to install
        ↓
User grants permission
        ↓
AutoPro app installed! 🎉
```

## Testing the QR Code

### On Desktop Browser:
1. Start your Flask server:
   ```powershell
   python automotive_website\caltexautopro.py
   ```

2. Visit: `http://localhost:5000`

3. Scroll to "Get the App" section

4. You should see the QR code displayed

### On Mobile Device:

1. **Open Camera App** on your Android phone

2. **Point at QR Code** on your computer screen

3. **Wait for Detection** - A notification will appear

4. **Tap Notification** - Browser opens the download link

5. **APK Downloads** - File downloads to your device

6. **Open Downloads** - Tap the downloaded file

7. **Allow Installation** - Grant permission if prompted:
   - Settings → Security → Unknown Sources → Enable for your browser

8. **Install** - Follow the installation prompts

9. **Launch App** - AutoPro icon appears in your app drawer

## Building & Deploying New APK

### Quick Method (Automated Script):
```powershell
cd c:\Project\AUTOMOTIVE_SERVICE
.\deploy-apk.bat
```
Follow the prompts!

### Manual Method:
```powershell
# 1. Navigate to Flutter project
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile

# 2. Clean and get dependencies
flutter clean
flutter pub get

# 3. Build APK (choose one):
flutter build apk --release                    # Universal APK
flutter build apk --split-per-abi --release    # Split APKs

# 4. Copy to website
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "..\automotive_website\static\download\autopro.apk"

# Or for split APK (ARM64 - most common):
Copy-Item "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "..\automotive_website\static\download\autopro.apk"
```

## File Locations

- **QR Code Implementation**: `automotive_website/templates/index.html`
- **Flask Download Route**: `automotive_website/caltexautopro.py` (line 596)
- **APK Storage**: `automotive_website/static/download/autopro.apk`
- **Flutter Source**: `automotive_mobile/`

## Current Status

✅ QR Code configured and working
✅ Download endpoint ready (`/download/autopro.apk`)
✅ APK file exists in static/download/
✅ Cache-busting headers configured
✅ Error handling implemented
✅ User instructions added

## What You Need to Do

1. **Build the latest APK**:
   ```powershell
   cd automotive_mobile
   flutter build apk --release
   ```

2. **Deploy to website**:
   ```powershell
   Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "..\automotive_website\static\download\autopro.apk"
   ```

3. **Test the flow**:
   - Visit your website
   - Scan QR code with your phone
   - Verify download works
   - Install and test the app

## Troubleshooting

### QR Code Not Visible
- **Check**: Browser console for errors
- **Solution**: Refresh the page, check internet connection

### QR Code Won't Scan
- **Check**: Lighting, distance (6-12 inches), camera focus
- **Solution**: Use a different QR scanner app or try the fallback download link

### APK Won't Download
- **Check**: Flask server is running, APK exists in `/static/download/`
- **Solution**: Test direct URL: `http://your-domain/download/autopro.apk`

### APK Won't Install
- **Check**: "Install from Unknown Sources" is enabled
- **Solution**: Settings → Security → Enable installation from your browser

### Old Version Downloaded
- **Don't worry**: Cache-busting headers prevent this
- **If persistent**: Clear browser cache, rebuild APK with new version number

## Production Recommendations

Before public release, consider:

1. **Update Application ID**:
   - Change from `com.example.automotive_mobile`
   - To: `com.janoble.autopro` or similar

2. **Create Release Signing Key**:
   - Current: Debug keys (insecure for production)
   - Needed: Proper release keystore

3. **Increment Version Numbers**:
   - Update `version` in `pubspec.yaml` before each build
   - Example: `1.0.0+1` → `1.0.1+2`

4. **Test on Multiple Devices**:
   - Different Android versions
   - Different manufacturers
   - Various screen sizes

See `APK_BUILD_AND_DEPLOY_GUIDE.md` for detailed instructions!

## Quick Reference Commands

```powershell
# Build APK
cd automotive_mobile
flutter build apk --release

# Copy to website
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "..\automotive_website\static\download\autopro.apk"

# Test download
Start-Process "http://localhost:5000/download/autopro.apk"

# Check file size
(Get-Item "automotive_website\static\download\autopro.apk").Length / 1MB
```

---

**Status**: ✅ Ready to use!
**Last Updated**: September 14, 2026
