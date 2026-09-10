# OneSignal Configuration Checker
Write-Host "`n=== OneSignal Configuration Check ===" -ForegroundColor Cyan

# Check Flutter dependencies
Write-Host "`n1. Checking Flutter dependencies..." -ForegroundColor Yellow
cd automotive_mobile
$pubspecContent = Get-Content pubspec.yaml -Raw
if ($pubspecContent -match "onesignal_flutter") {
    Write-Host "   ✅ onesignal_flutter found in pubspec.yaml" -ForegroundColor Green
} else {
    Write-Host "   ❌ onesignal_flutter NOT found in pubspec.yaml" -ForegroundColor Red
}

# Check for OneSignal initialization in main.dart
Write-Host "`n2. Checking OneSignal initialization..." -ForegroundColor Yellow
$mainContent = Get-Content lib\main.dart -Raw
if ($mainContent -match "OneSignal\.initialize") {
    Write-Host "   ✅ OneSignal.initialize found in main.dart" -ForegroundColor Green
    if ($mainContent -match "c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea") {
        Write-Host "   ✅ App ID matches: c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  App ID might be different" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ❌ OneSignal.initialize NOT found" -ForegroundColor Red
}

# Check AndroidManifest permissions
Write-Host "`n3. Checking Android permissions..." -ForegroundColor Yellow
$manifestPath = "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifestPath) {
    $manifestContent = Get-Content $manifestPath -Raw
    if ($manifestContent -match "POST_NOTIFICATIONS") {
        Write-Host "   ✅ POST_NOTIFICATIONS permission found" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️  POST_NOTIFICATIONS permission missing" -ForegroundColor Yellow
    }
    if ($manifestContent -match "INTERNET") {
        Write-Host "   ✅ INTERNET permission found" -ForegroundColor Green
    } else {
        Write-Host "   ❌ INTERNET permission missing" -ForegroundColor Red
    }
} else {
    Write-Host "   ❌ AndroidManifest.xml not found" -ForegroundColor Red
}

# Check for API endpoint usage
Write-Host "`n4. Checking API endpoints..." -ForegroundColor Yellow
$wrongEndpoint = Select-String -Path "lib\*.dart" -Pattern "onesignal\.com/api/v1" -Quiet
if ($wrongEndpoint) {
    Write-Host "   ⚠️  Found old API endpoint (onesignal.com/api/v1)" -ForegroundColor Yellow
    Write-Host "      Should be: api.onesignal.com" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ Using correct API endpoint (api.onesignal.com)" -ForegroundColor Green
}

# List all files with OneSignal code
Write-Host "`n5. Files with OneSignal code:" -ForegroundColor Yellow
$files = Select-String -Path "lib\*.dart" -Pattern "OneSignal|ONESIGNAL" -List | Select-Object -ExpandProperty Path
foreach ($file in $files) {
    $relativePath = $file -replace [regex]::Escape((Get-Location).Path + "\"), ""
    Write-Host "   - $relativePath" -ForegroundColor Cyan
}

# Check for different API keys
Write-Host "`n6. Checking API keys..." -ForegroundColor Yellow
$apiKeyFiles = Select-String -Path "lib\*.dart","../automotive_website/*.py" -Pattern "os_v\d+_app_" -AllMatches
$uniqueKeys = $apiKeyFiles | ForEach-Object { 
    if ($_.Line -match "(os_v\d+_app_[a-z0-9]+)") { 
        $matches[1].Substring(0, [Math]::Min(30, $matches[1].Length)) 
    } 
} | Sort-Object -Unique

Write-Host "   Found $($uniqueKeys.Count) different API key(s):" -ForegroundColor Cyan
foreach ($key in $uniqueKeys) {
    Write-Host "   - $key..." -ForegroundColor White
}

if ($uniqueKeys.Count -gt 1) {
    Write-Host "   ⚠️  Multiple API keys detected - should be consistent" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ Using single API key" -ForegroundColor Green
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Verify REST API Key in OneSignal Dashboard (Settings → Keys & IDs)" -ForegroundColor White
Write-Host "2. Update API keys in code if needed" -ForegroundColor White
Write-Host "3. Run: flutter clean && flutter pub get" -ForegroundColor White
Write-Host "4. Rebuild app and test on device" -ForegroundColor White
Write-Host "5. Check OneSignal dashboard for new subscribers`n" -ForegroundColor White

cd ..
