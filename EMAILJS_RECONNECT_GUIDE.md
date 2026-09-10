# EmailJS Gmail Reconnection Guide

## Problem
**Error 412:** "Gmail API: Invalid grant. Please reconnect your Gmail account"

This happens when:
- Gmail password was changed
- Gmail account security settings changed
- EmailJS lost authorization to send emails
- 2-Step Verification was enabled/disabled

---

## Solution: Reconnect Gmail Account

### Step 1: Login to EmailJS Dashboard

1. Go to: https://dashboard.emailjs.com/
2. Login with your EmailJS account

### Step 2: Navigate to Email Services

1. Click **"Email Services"** in the left sidebar
2. You should see your service: **service_i906b4o**
3. Click on it to open settings

### Step 3: Reconnect Gmail

You'll see one of these scenarios:

#### Scenario A: "Reconnect" Button Visible
1. Click the **"Reconnect Gmail"** or **"Reconnect Account"** button
2. A Google OAuth popup will appear
3. Select your Gmail account: **janobleenterpriseinc.autopro@gmail.com**
4. Click **"Allow"** to grant permissions
5. Done! ✅

#### Scenario B: Need to Remove & Re-add Service
1. Click **"Delete Service"** (don't worry, settings are saved)
2. Click **"Add New Service"**
3. Select **"Gmail"**
4. Click **"Connect Account"**
5. Google OAuth popup appears
6. Select: **janobleenterpriseinc.autopro@gmail.com**
7. Click **"Allow"**
8. Fill in:
   - **Service ID:** service_i906b4o (must be same as before!)
   - **Service Name:** Gmail (or any name)
9. Click **"Create Service"**
10. Done! ✅

---

## Verify Connection

### Test Email Send

1. In EmailJS Dashboard, go to your service
2. Click **"Test"** or **"Send Test Email"**
3. Enter a test email address
4. Click **"Send Test"**
5. Check if email is received

### Test in Your App

1. Go to your forgot password page
2. Enter an email
3. Click "Send OTP"
4. Should work now! No more 412 error

---

## Important Notes

### ⚠️ Keep These IDs the Same

When reconnecting, make sure to use:
- **Service ID:** `service_i906b4o`
- **Template ID:** `template_6kkir1s`
- **Public Key:** `DqRrjCkUnf9w2L_sv`

These are hardcoded in your app. If you change them, you need to update:
- `automotive_website/templates/forgot_password.html`
- `automotive_mobile/lib/google_sign_in.dart`
- `automotive_mobile/lib/forgot_password.dart`
- `automotive_mobile/lib/admin_users.dart`

### 🔐 Gmail Security Settings

For EmailJS to work with Gmail:
1. **2-Step Verification** must be **ENABLED**
2. **App Passwords** are not used (EmailJS uses OAuth)
3. **Less secure app access** is not needed (deprecated by Google)

### 🚨 Common Issues

| Error | Solution |
|-------|----------|
| "Invalid grant" | Reconnect Gmail (follow steps above) |
| "Authentication failed" | Check Gmail password is correct |
| "Permission denied" | Grant all requested permissions in OAuth popup |
| "Service not found" | Verify Service ID is correct |

---

## Alternative: Use SMTP Directly (Not Recommended)

If EmailJS keeps failing, you can switch to direct SMTP, but this requires:
1. Gmail App Password (16 characters)
2. Backend server to handle SMTP (can't do from browser)
3. More complex setup

EmailJS is easier - just reconnect! 😊

---

## Need More Help?

### EmailJS Support
- Documentation: https://www.emailjs.com/docs/
- FAQ: https://www.emailjs.com/docs/faq/
- Contact: https://www.emailjs.com/contact/

### Gmail OAuth Issues
- Google Account Security: https://myaccount.google.com/security
- Make sure 2-Step Verification is enabled
- Check for any security alerts

---

**Status After Reconnection:**
- [ ] Gmail reconnected in EmailJS Dashboard
- [ ] Test email sent successfully
- [ ] App forgot password works
- [ ] No more 412 errors

**Last Updated:** 2026-09-10
