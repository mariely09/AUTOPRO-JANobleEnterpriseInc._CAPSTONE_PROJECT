# AutoPro Mobile APK - Build & Deploy Guide

## Overview
This guide covers the complete workflow for building, testing, and deploying the AutoPro mobile application APK.

---

## 🔨 Building the Release APK

### Prerequisites
- Flutter SDK installed and configured
- Android SDK with Build Tools
- Java Development Kit (JDK) 17

### Build Steps

#### 1. Navigate to Flutter Project
```powershell
cd c:\Project\AUTOMOTIVE_SERVICE\automotive_mobile
```

#### 2. Clean Previous Builds
```powershell
flutter clean
```

#### 3. Get Dependencies
```powershell
flutter pub get
```

#### 4. Build Release APK

**Option A: Universal APK (Single file, larger size)**
```powershell
flutter build apk --release
```
- Output: `build\app\outputs\flutter-apk\app-release.apk`
- Size: ~40-50 MB
- Compatible: All Android devices

**Option B: Split APKs (Smaller files, recommended)**
```powershell
flutter build apk --split-per-abi --release
```
- Outputs:
  - `app-armeabi-v7a-release.apk` (32-bit ARM) - ~20 MB
  - `app-arm64-v8a-release.apk` (64-bit ARM) - ~25 MB ⭐ Most common
  - `app-x86_64-release.apk` (64-bit Intel) - ~28 MB
- Users get the appropriate version for their device

#### 5. Increment Version (Before Building)
Update `pubspec.yaml`:
```yaml
version: 1.0.1+2  # Format: MAJOR.MINOR.PATCH+BUILD_NUMBER
```

---

## 📦 Deploying to Website

### Step 1: Copy APK to Website Directory
```powershell
# For universal APK
Copy-Item "automotive_mobile\build\app\outputs\flutter-apk\app-release.apk" "automotive_website\static\download\autopro.apk"

# For split APK (copy the arm64-v8a version - most common)
Copy-Item "automotive_mobile\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "automotive_website\static\download\autopro.apk"
```

### Step 2: Verify Deployment
1. Check file exists:
```powershell
Test-Path "automotive_website\static\download\autopro.apk"
```

2. Check file size:
```powershell
(Get-Item "automotive_website\static\download\autopro.apk").Length / 1MB
```

### Step 3: Test Download
1. Start your Flask server
2. Visit: `http://your-domain/download/autopro.apk`
3. File should download immediately

---

## 📱 QR Code Implementation

### How It Works
The QR code on `index.html` automatically generates a scannable code that:
1. Points to: `https://your-domain.com/download/autopro.apk`
2. Uses QR Server API with optimized settings:
   - **Size**: 300x300px (high resolution)
   - **Margin**: 10px (adequate scanning area)
   - **Color**: Dark (#1a202c) on white background
   - **Format**: PNG

### User Experience
1. **Scan with Camera**: User opens camera app
2. **Detect Link**: Camera detects the download URL
3. **Click Notification**: User taps the notification
4. **Download Starts**: APK downloads to device
5. **Install Prompt**: Android asks to install
6. **Grant Permission**: User allows installation from browser
7. **App Installs**: AutoPro app is installed

### Testing the QR Code
1. Visit your website on desktop
2. Scroll to "Get the App" section
3. Use your phone's camera to scan the QR code
4. Verify download starts

---

## ⚠️ Important Security Notes

### Current Configuration (Development)
- **Signing**: Debug keys (NOT for production)
- **App ID**: `com.example.automotive_mobile` (Should be changed)

### For Production Deployment

#### 1. Create a Keystore
```powershell
keytool -genkey -v -keystore autopro-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias autopro
```

#### 2. Create `key.properties`
Create `automotive_mobile\android\key.properties`:
```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=autopro
storeFile=../autopro-release-key.jks
```

#### 3. Update `build.gradle.kts`
In `automotive_mobile\android\app\build.gradle.kts`:

```kotlin
// Add before android block
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ... existing config ...
    
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

#### 4. Update Application ID
In `automotive_mobile\android\app\build.gradle.kts`:
```kotlin
defaultConfig {
    applicationId = "com.janoble.autopro"  // Change this
    // ... rest of config
}
```

---

## 🔍 Troubleshooting

### APK Won't Install on Device
**Problem**: "App not installed" error

**Solutions**:
1. Enable "Install from Unknown Sources" in Android settings
2. Check storage space on device
3. Uninstall previous version if exists
4. Verify APK is not corrupted (check file size)

### QR Code Not Scanning
**Problem**: Camera doesn't detect QR code

**Solutions**:
1. Ensure adequate lighting
2. Hold camera 6-12 inches from screen
3. Try different QR scanner app
4. Check QR code is fully visible (not truncated)
5. Verify internet connection (QR image loads from API)

### Download Fails
**Problem**: APK download doesn't start

**Solutions**:
1. Check Flask server is running
2. Verify APK file exists in `static/download/`
3. Check file permissions
4. Test direct URL: `http://your-domain/download/autopro.apk`
5. Check browser console for errors

### Old APK Version Cached
**Problem**: Users download old version

**Solution**: 
- Already handled! The Flask route includes cache-busting headers:
```python
response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
```

---

## 📊 Build Information

### Current App Configuration
- **App Name**: JA Noble - Authorized Caltex Service Partner
- **Package**: com.example.automotive_mobile (⚠️ Change for production)
- **Version**: 1.0.0+1
- **Min SDK**: 21 (Android 5.0)
- **Target SDK**: 34 (Android 14)

### APK Sizes (Approximate)
- Universal APK: ~45 MB
- ARM64 APK: ~22 MB
- ARM32 APK: ~18 MB
- x86_64 APK: ~26 MB

---

## 🚀 Quick Deploy Checklist

- [ ] Update version in `pubspec.yaml`
- [ ] Run `flutter clean`
- [ ] Run `flutter pub get`
- [ ] Build release APK
- [ ] Copy APK to `static/download/autopro.apk`
- [ ] Test download URL works
- [ ] Test QR code scanning
- [ ] Verify APK installs on test device
- [ ] Check app launches successfully

---

## 📝 Version History Template

Keep track of deployments:

```
v1.0.1 (Build 2) - 2026-09-14
- Fixed booking flow validation
- Updated UI colors
- Deployed to website

v1.0.0 (Build 1) - 2026-09-01
- Initial release
- Basic features implemented
```

---

## 🔗 Related Files

- **Flutter Project**: `automotive_mobile/`
- **APK Storage**: `automotive_website/static/download/autopro.apk`
- **Download Route**: `automotive_website/caltexautopro.py` (line 596)
- **QR Code Implementation**: `automotive_website/templates/index.html`

---

## 📞 Support

For issues or questions:
- Check Flutter logs: `flutter doctor -v`
- Check build logs for errors
- Verify Android SDK installation
- Test on physical device (not just emulator)

---

**Last Updated**: September 14, 2026
