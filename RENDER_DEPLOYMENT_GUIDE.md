# Render Deployment Guide - Caltex AutoPro

## Issue: Deployment Failed After Pushing Environment Variable Changes

### Root Cause
After moving credentials to environment variables (`.env` file), the Render deployment fails because:
1. The `.env` file is **NOT pushed to GitHub** (by design, for security)
2. The application now expects environment variables to be set
3. Render doesn't have these environment variables configured yet

---

## Solution: Configure Environment Variables in Render

### Step 1: Login to Render Dashboard

1. Go to https://dashboard.render.com/
2. Login with your account
3. Find your **Caltex AutoPro** web service

### Step 2: Add Environment Variables

1. Click on your web service (e.g., "automotive-website" or "caltexautopro")
2. Go to **"Environment"** tab in the left sidebar
3. Click **"Add Environment Variable"**

Add these variables one by one:

#### Required Variables:

```
Key: SMTP_USER
Value: janobleenterpriseinc.autopro@gmail.com
```

```
Key: SMTP_APP_PASSWORD
Value: syet vege hyyj sqoq
```

```
Key: SMTP_FROM
Value: JA Noble Enterprise Inc <janobleenterpriseinc.autopro@gmail.com>
```

#### Optional but Recommended:

```
Key: FLASK_SECRET_KEY
Value: (generate a random string - see below)
```

```
Key: PYTHON_VERSION
Value: 3.11.0
```

### Step 3: Generate Flask Secret Key (Optional)

Use this Python command to generate a secure random key:

```python
import secrets
print(secrets.token_hex(32))
```

Or use this PowerShell command:
```powershell
-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 64 | ForEach-Object {[char]$_})
```

### Step 4: Save and Redeploy

1. After adding all environment variables, click **"Save Changes"**
2. Render will **automatically trigger a new deployment**
3. Wait for the deployment to complete (check the **"Logs"** tab)

---

## Verify Deployment

### Check Deployment Logs

In the **Logs** tab, you should see:
```
✅ Firebase Admin SDK initialized
✅ Flask app started successfully
```

If you see these errors:
```
⚠️ SMTP_APP_PASSWORD not set in .env file!
```

That means the environment variables are not configured yet.

### Test the Application

Once deployed successfully:

1. Visit your Render URL: `https://your-app-name.onrender.com/health`
2. You should see: `{"ok": true, "status": "healthy"}`

---

## Environment Variables Reference

### Current Required Variables:

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `SMTP_USER` | Gmail account for sending emails | `your-email@gmail.com` |
| `SMTP_APP_PASSWORD` | Gmail App Password (16 chars) | `xxxx xxxx xxxx xxxx` |
| `SMTP_FROM` | Email sender name and address | `Your Name <email@gmail.com>` |
| `FLASK_SECRET_KEY` | Secret key for Flask sessions | Random 64-char string |

### Optional Variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `FIREBASE_SERVICE_ACCOUNT` | Path to serviceAccountKey.json | Auto-detected |
| `PYTHON_VERSION` | Python version for deployment | 3.11.0 |

---

## Troubleshooting

### Problem: "SMTP_APP_PASSWORD not set" error

**Solution:** Make sure the environment variable name is **exactly** `SMTP_APP_PASSWORD` (case-sensitive)

### Problem: Deployment still fails after adding variables

**Possible causes:**
1. **Typo in variable names** - Check spelling and case
2. **Missing python-dotenv** - Should already be in `requirements.txt`
3. **Render cache issue** - Try **"Manual Deploy" → "Clear build cache & deploy"**

### Problem: Email sending fails

**Check:**
1. Gmail App Password is correct (16 characters)
2. 2-Step Verification is enabled on Gmail account
3. App Password is for "Mail" app type

---

## Architecture: How Environment Variables Work

### Local Development (Your Computer):
```
.env file (not in Git)
    ↓
python-dotenv loads variables
    ↓
caltexautopro.py uses os.environ.get()
```

### Production (Render):
```
Render Dashboard Environment Variables
    ↓
Automatically injected as environment variables
    ↓
caltexautopro.py uses os.environ.get()
```

**Note:** The `load_dotenv()` function in production does nothing (no `.env` file), but that's OK because Render provides the variables directly.

---

## Security Best Practices

### ✅ DO:
- Set environment variables in Render dashboard
- Use different credentials for dev/staging/production
- Rotate credentials regularly
- Use strong, unique Flask secret keys per environment

### ❌ DON'T:
- Commit `.env` file to Git
- Share credentials in Slack/email
- Use the same credentials across all environments
- Hardcode credentials in source code

---

## Quick Reference: Render Environment Variable Setup

### One-Time Setup (After Initial Deployment):

1. **Render Dashboard** → Your Service → **Environment** tab
2. Click **"Add Environment Variable"** for each:
   - `SMTP_USER` = janobleenterpriseinc.autopro@gmail.com
   - `SMTP_APP_PASSWORD` = syet vege hyyj sqoq
   - `SMTP_FROM` = JA Noble Enterprise Inc <janobleenterpriseinc.autopro@gmail.com>
3. Click **"Save Changes"**
4. Wait for auto-deployment to complete

### After Future Code Pushes:

**No action needed!** Environment variables persist across deployments.

---

## Additional Render Configuration (Optional)

### Build Command:
```bash
pip install -r requirements.txt
```

### Start Command:
```bash
cd automotive_website && gunicorn caltexautopro:app
```

Or if using Flask development server:
```bash
cd automotive_website && python caltexautopro.py
```

### Health Check Path:
```
/health
```

---

## Contact

If deployment issues persist:
1. Check **Render Logs** for specific error messages
2. Verify all environment variables are set correctly
3. Try **"Manual Deploy" → "Clear build cache & deploy"**

---

**Last Updated:** 2026-09-10
**Status:** Environment variables configured ✅
