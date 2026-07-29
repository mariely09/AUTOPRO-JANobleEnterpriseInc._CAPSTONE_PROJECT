@echo off
echo ============================================
echo  AutoPro APK Build + Deploy
echo ============================================

cd /d "d:\Project\AUTOMOTIVE_SERVICE\automotive_mobile"

echo [1/4] Building release APK...
call flutter build apk --release
if errorlevel 1 (
    echo ERROR: Flutter build failed.
    pause
    exit /b 1
)

echo [2/4] Copying APK to website static folder...
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "..\automotive_website\static\apk\autopro.apk"
if errorlevel 1 (
    echo ERROR: Could not copy APK.
    pause
    exit /b 1
)

echo [3/4] Detecting local IP address...
for /f "tokens=2 delims=:" %%A in ('ipconfig ^| findstr /C:"IPv4 Address"') do (
    set LOCAL_IP=%%A
    goto :found_ip
)
:found_ip
set LOCAL_IP=%LOCAL_IP: =%
echo     Local IP: %LOCAL_IP%

echo [4/4] Updating QR code URL in index.html...
set INDEX_FILE="..\automotive_website\templates\index.html"
powershell -Command "(Get-Content %INDEX_FILE%) -replace 'data=http%3A%2F%2F[^&]+%3A5001%2Fdownload%2Fautopro\.apk', ('data=http%3A%2F%2F' + '%LOCAL_IP%' + '%3A5001%2Fdownload%2Fautopro.apk') | Set-Content %INDEX_FILE%"

echo.
echo ============================================
echo  Done!
echo ============================================
echo  APK:     automotive_website\static\apk\autopro.apk
echo  QR URL:  http://%LOCAL_IP%:5001/download/autopro.apk
echo.
echo  Phone must be on the SAME WiFi network as this PC.
echo  Make sure Flask is running: python caltexautopro.py
echo ============================================
pause
