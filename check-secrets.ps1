# Security Check Script - Run before git push
# Usage: .\check-secrets.ps1

Write-Host "Security Pre-Push Checklist" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

$allClear = $true

# Check 1: .env file
Write-Host "1. Checking .env protection..." -ForegroundColor Yellow
if (Test-Path ".env") {
    $ignored = git check-ignore .env 2>$null
    if ($ignored -eq ".env") {
        Write-Host "   [OK] .env file exists and is ignored" -ForegroundColor Green
    } else {
        Write-Host "   [FAIL] .env is NOT in .gitignore!" -ForegroundColor Red
        $allClear = $false
    }
} else {
    Write-Host "   [WARN] .env file not found" -ForegroundColor Yellow
}

# Check 2: Sensitive files not tracked
Write-Host ""
Write-Host "2. Checking for tracked sensitive files..." -ForegroundColor Yellow
$dangerousPatterns = @(
    "serviceAccountKey.json",
    "google-services.json",
    "GoogleService-Info.plist",
    ".groq_key"
)

$foundSensitive = $false
foreach ($pattern in $dangerousPatterns) {
    $tracked = git ls-files | Select-String -Pattern $pattern -SimpleMatch
    if ($tracked) {
        Write-Host "   [FAIL] DANGER: $pattern is tracked!" -ForegroundColor Red
        $allClear = $false
        $foundSensitive = $true
    }
}

if (-not $foundSensitive) {
    Write-Host "   [OK] No sensitive files are tracked" -ForegroundColor Green
}

# Check 3: Staged changes contain secrets
Write-Host ""
Write-Host "3. Scanning staged changes for secrets..." -ForegroundColor Yellow
$staged = git diff --cached
if ($staged) {
    $foundSecret = $false
    
    if ($staged -match "syet vege hyyj sqoq") {
        Write-Host "   [FAIL] SMTP password found in staged changes!" -ForegroundColor Red
        $allClear = $false
        $foundSecret = $true
    }
    
    if ($staged -match "AIzaSy[A-Za-z0-9_-]{33}") {
        Write-Host "   [FAIL] Firebase API key found in staged changes!" -ForegroundColor Red
        $allClear = $false
        $foundSecret = $true
    }
    
    if (-not $foundSecret) {
        Write-Host "   [OK] No secrets detected in staged changes" -ForegroundColor Green
    }
} else {
    Write-Host "   [INFO] No staged changes to scan" -ForegroundColor Gray
}

# Check 4: .env.example exists
Write-Host ""
Write-Host "4. Checking for .env.example..." -ForegroundColor Yellow
if (Test-Path ".env.example") {
    Write-Host "   [OK] .env.example exists" -ForegroundColor Green
} else {
    Write-Host "   [WARN] .env.example not found" -ForegroundColor Yellow
}

# Final verdict
Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
if ($allClear) {
    Write-Host "ALL CHECKS PASSED - Safe to push!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "SECURITY ISSUES FOUND - DO NOT PUSH!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Fix the issues above before pushing to GitHub." -ForegroundColor Yellow
    exit 1
}
