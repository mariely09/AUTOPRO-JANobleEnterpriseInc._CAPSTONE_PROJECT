@echo off
title AutoPro QR Code Test
color 0A

echo ========================================
echo   AutoPro QR Code Testing Tool
echo ========================================
echo.

REM Check if APK exists
echo [1/4] Checking APK file...
if exist "automotive_website\static\download\autopro.apk" (
    echo     [32m✓[0m APK file found!
    for %%F in ("automotive_website\static\download\autopro.apk") do (
        echo     Size: %%~zF bytes (approx. 174 MB)
        echo     Modified: %%~tF
    )
) else (
    echo     [31m✗[0m APK file NOT found!
    echo     Expected location: automotive_website\static\download\autopro.apk
    echo.
    echo     Please copy the APK first:
    echo     Copy-Item "automotive_mobile\build\app\outputs\flutter-apk\app-debug.apk" ^
    echo               "automotive_website\static\download\autopro.apk"
    pause
    exit /b 1
)

echo.
echo [2/4] Checking Flask app...
if exist "automotive_website\caltexautopro.py" (
    echo     [32m✓[0m Flask app found!
) else (
    echo     [31m✗[0m Flask app NOT found!
    pause
    exit /b 1
)

echo.
echo [3/4] Starting Flask server...
echo     Press Ctrl+C to stop the server when done testing
echo.

cd automotive_website

REM Start Flask in background (if possible) or just run it
echo ========================================
echo   Server Starting...
echo ========================================
echo.
echo   Main Website:  http://localhost:5000
echo   Test Page:     http://localhost:5000/test_qr.html
echo   APK Download:  http://localhost:5000/download/autopro.apk
echo.
echo ========================================
echo.

python caltexautopro.py

echo.
echo ========================================
echo   Server Stopped
echo ========================================
pause
