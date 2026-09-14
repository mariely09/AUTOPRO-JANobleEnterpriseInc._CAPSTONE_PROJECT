@echo off
REM ============================================================
REM AutoPro APK Build and Deploy Script
REM ============================================================
echo.
echo ========================================
echo   AutoPro APK Build and Deploy
echo ========================================
echo.

REM Navigate to Flutter project
cd automotive_mobile

echo [1/6] Cleaning previous builds...
call flutter clean
if errorlevel 1 (
    echo ERROR: Flutter clean failed
    pause
    exit /b 1
)

echo.
echo [2/6] Getting dependencies...
call flutter pub get
if errorlevel 1 (
    echo ERROR: Failed to get dependencies
    pause
    exit /b 1
)

echo.
echo [3/6] Building release APK...
echo Choose build type:
echo   1. Universal APK (larger, compatible with all devices)
echo   2. Split APKs (smaller, device-specific)
echo.
set /p BUILD_TYPE="Enter choice (1 or 2): "

if "%BUILD_TYPE%"=="1" (
    echo Building universal APK...
    call flutter build apk --release
    set "SOURCE_APK=build\app\outputs\flutter-apk\app-release.apk"
) else if "%BUILD_TYPE%"=="2" (
    echo Building split APKs...
    call flutter build apk --split-per-abi --release
    echo Using ARM64 version (most common)...
    set "SOURCE_APK=build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
) else (
    echo Invalid choice. Defaulting to universal APK...
    call flutter build apk --release
    set "SOURCE_APK=build\app\outputs\flutter-apk\app-release.apk"
)

if errorlevel 1 (
    echo ERROR: Build failed
    pause
    exit /b 1
)

echo.
echo [4/6] Checking if APK was created...
if not exist "%SOURCE_APK%" (
    echo ERROR: APK file not found at %SOURCE_APK%
    pause
    exit /b 1
)

REM Get file size
for %%A in ("%SOURCE_APK%") do set SIZE=%%~zA
set /a SIZE_MB=%SIZE% / 1048576
echo APK Size: %SIZE_MB% MB

echo.
echo [5/6] Copying APK to website directory...
cd ..
set "TARGET_DIR=automotive_website\static\download"
set "TARGET_APK=%TARGET_DIR%\autopro.apk"

if not exist "%TARGET_DIR%" (
    echo Creating download directory...
    mkdir "%TARGET_DIR%"
)

copy /Y "automotive_mobile\%SOURCE_APK%" "%TARGET_APK%"
if errorlevel 1 (
    echo ERROR: Failed to copy APK
    pause
    exit /b 1
)

echo.
echo [6/6] Verifying deployment...
if exist "%TARGET_APK%" (
    for %%A in ("%TARGET_APK%") do set DEPLOYED_SIZE=%%~zA
    set /a DEPLOYED_SIZE_MB=%DEPLOYED_SIZE% / 1048576
    echo SUCCESS! APK deployed successfully
    echo Location: %TARGET_APK%
    echo Size: %DEPLOYED_SIZE_MB% MB
) else (
    echo ERROR: APK not found in target directory
    pause
    exit /b 1
)

echo.
echo ========================================
echo   Deployment Complete!
echo ========================================
echo.
echo Next steps:
echo   1. Test download: http://localhost:5000/download/autopro.apk
echo   2. Test QR code on homepage
echo   3. Install APK on test device
echo.
pause
