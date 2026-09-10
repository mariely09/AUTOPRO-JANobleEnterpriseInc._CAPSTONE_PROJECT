# Render Environment Variables Setup
# Copy-paste these into Render Dashboard → Environment tab

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Render Environment Variables - Copy These!" -ForegroundColor Yellow
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "1. Go to: https://dashboard.render.com/" -ForegroundColor Green
Write-Host "2. Select your web service" -ForegroundColor Green
Write-Host "3. Go to 'Environment' tab" -ForegroundColor Green
Write-Host "4. Click 'Add Environment Variable' for each:" -ForegroundColor Green
Write-Host ""

Write-Host "---------------------------------------------------" -ForegroundColor Gray
Write-Host "Variable 1 of 3:" -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor Gray
Write-Host "Key:   SMTP_USER" -ForegroundColor Cyan
Write-Host "Value: janobleenterpriseinc.autopro@gmail.com" -ForegroundColor White
Write-Host ""

Write-Host "---------------------------------------------------" -ForegroundColor Gray
Write-Host "Variable 2 of 3:" -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor Gray
Write-Host "Key:   SMTP_APP_PASSWORD" -ForegroundColor Cyan
Write-Host "Value: syet vege hyyj sqoq" -ForegroundColor White
Write-Host ""

Write-Host "---------------------------------------------------" -ForegroundColor Gray
Write-Host "Variable 3 of 3:" -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor Gray
Write-Host "Key:   SMTP_FROM" -ForegroundColor Cyan
Write-Host "Value: JA Noble Enterprise Inc <janobleenterpriseinc.autopro@gmail.com>" -ForegroundColor White
Write-Host ""

Write-Host "---------------------------------------------------" -ForegroundColor Gray
Write-Host "Optional - Flask Secret Key (Recommended):" -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor Gray
Write-Host "Key:   FLASK_SECRET_KEY" -ForegroundColor Cyan
Write-Host "Value: (generate using command below)" -ForegroundColor White
Write-Host ""

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "After adding all variables:" -ForegroundColor Green
Write-Host "  1. Click 'Save Changes'" -ForegroundColor White
Write-Host "  2. Render will auto-deploy" -ForegroundColor White
Write-Host "  3. Wait for deployment to complete" -ForegroundColor White
Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Generate Flask Secret Key (run this):" -ForegroundColor Yellow
Write-Host "  python -c ""import secrets; print(secrets.token_hex(32))""" -ForegroundColor Cyan
Write-Host ""
