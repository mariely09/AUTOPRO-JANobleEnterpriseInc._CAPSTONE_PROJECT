# -*- coding: utf-8 -*-
from flask import Flask, render_template, request, jsonify, redirect, url_for, session
import smtplib
import os
import json as _json
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import timedelta

# ── Firebase Admin SDK ───────────────────────────────────────────────────────
# Requires: pip install firebase-admin
# Place your service account JSON at the path below, or set
# GOOGLE_APPLICATION_CREDENTIALS env var to point to it.
import firebase_admin
from firebase_admin import credentials, auth as fb_auth

_SERVICE_ACCOUNT_PATH = os.environ.get(
    'FIREBASE_SERVICE_ACCOUNT',
    None
)

# Search multiple common locations for the service account key
if not _SERVICE_ACCOUNT_PATH or not os.path.exists(_SERVICE_ACCOUNT_PATH):
    _SEARCH_PATHS = [
        os.path.join(os.path.dirname(__file__), 'serviceAccountKey.json'),
        os.path.join(os.path.dirname(__file__), '..', 'serviceAccountKey.json'),
        os.path.join(os.path.dirname(__file__), '..', 'AI_ASSISTANT', 'serviceAccountKey.json'),
        # ai_assistant service folder (same Firebase project — shared Admin SDK)
        os.path.join(os.path.dirname(__file__), '..', 'ai_assistant', 'caltex-autopro-1e664-firebase-adminsdk-fbsvc-07b4fc625e.json'),
        os.path.join(os.path.dirname(__file__), '..', 'ai_assistant', 'serviceAccountKey.json'),
        os.path.join(os.path.dirname(__file__), 'firebase-credentials.json'),
        os.path.join(os.path.dirname(__file__), '..', 'firebase-credentials.json'),
        os.path.expanduser(os.path.join('~', 'serviceAccountKey.json')),
    ]
    for _p in _SEARCH_PATHS:
        if os.path.exists(_p):
            _SERVICE_ACCOUNT_PATH = _p
            break
    else:
        _SERVICE_ACCOUNT_PATH = os.path.join(os.path.dirname(__file__), 'serviceAccountKey.json')

if not firebase_admin._apps:
    try:
        cred = credentials.Certificate(_SERVICE_ACCOUNT_PATH)
        firebase_admin.initialize_app(cred)
        print('✅ Firebase Admin SDK initialized')
    except Exception as _e:
        print(f'⚠️  Firebase Admin SDK not initialized: {_e}')
        print('   Place serviceAccountKey.json next to caltexautopro.py to enable Auth deletion.')

app = Flask(__name__)
app.config['JSON_AS_ASCII'] = False
app.secret_key = os.environ.get('FLASK_SECRET_KEY', 'your-secret-key-change-this-in-production')
# Always pick up template edits without a server restart (Flask otherwise
# disables auto-reload when debug=False).
app.config['TEMPLATES_AUTO_RELOAD'] = True
app.jinja_env.auto_reload = True
import jinja2
app.jinja_loader = jinja2.FileSystemLoader(app.template_folder, encoding='utf-8')
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=7)

# ── No-cache headers for all authenticated pages ─────────────
# Prevents browser bfcache from restoring dashboard pages after logout.
_AUTHENTICATED_PAGES = {
    'admin_dashboard', 'admin_inventory_items', 'admin_inventory_stock',
    'admin_vehicles', 'admin_vehicle_maintenance', 'admin_users', 'admin_dss',
    'admin_domains', 'admin_service_bookings', 'admin_receiving',
    'staff_dashboard', 'staff_inventory', 'staff_maintenance', 'staff_vehicle_list',
    'customer_dashboard', 'customer_pms_history', 'customer_book_service',
    'pms_history_details', 'notifications', 'profile', 'change_password',
    'ai_usage_controls',
    'help_support',
}

@app.after_request
def add_no_cache_headers(response):
    from flask import request as _req
    endpoint = _req.endpoint or ''
    if endpoint in _AUTHENTICATED_PAGES:
        response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
    return response

# ── Email config (Gmail SMTP) ────────────────────────────────
# Set SMTP_APP_PASSWORD as an environment variable, or paste the
# 16-character Gmail App Password directly below.
# To generate: Gmail → Settings → Security → 2-Step Verification → App Passwords
SMTP_HOST     = 'smtp.gmail.com'
SMTP_PORT     = 587
SMTP_USER     = 'caltexautopro2026@gmail.com'
SMTP_PASSWORD = os.environ.get('SMTP_APP_PASSWORD', 'kvvp uflz pbdc rcyv')
SMTP_FROM     = 'JA Noble Enterprise Inc <caltexautopro2026@gmail.com>'

@app.route('/health', methods=['GET'])
def health():
    """Liveness ping — used by mobile app to warm up Render cold starts."""
    return jsonify({'ok': True, 'status': 'healthy'}), 200


@app.route('/api/send-google-otp', methods=['POST'])
def send_google_otp():
    """Send a Google Sign-In OTP email via EmailJS (same template as mobile app)."""
    import random, datetime as _dt, requests as _requests
    data     = request.get_json(silent=True) or {}
    to_email = data.get('to_email', '').strip()
    to_name  = (data.get('to_name', '') or '').strip() or to_email

    if not to_email:
        return jsonify({'ok': False, 'error': 'Missing email'}), 400

    otp    = str(random.randint(100000, 999999))
    expiry = (_dt.datetime.utcnow() + _dt.timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%S') + 'Z'

    # Store OTP in Firestore via Firebase Admin
    try:
        from firebase_admin import firestore as fa_firestore
        db = fa_firestore.client()
        db.collection('otp_requests').document(to_email).set({
            'otp':       otp,
            'expiry':    expiry,
            'email':     to_email,
            'createdAt': fa_firestore.SERVER_TIMESTAMP,
        })
    except Exception as e:
        return jsonify({'ok': False, 'error': f'Firestore error: {e}'}), 500

    # ── Send via EmailJS — same template as mobile app ──────────────────────
    EMAILJS_SERVICE  = 'service_i906b4o'
    EMAILJS_TEMPLATE = 'template_6kkir1s'
    EMAILJS_KEY      = 'DqRrjCkUnf9w2L_sv'

    try:
        res = _requests.post(
            'https://api.emailjs.com/api/v1.0/email/send',
            headers={
                'Content-Type': 'application/json',
                'origin': 'https://dashboard.emailjs.com',
            },
            json={
                'service_id':  EMAILJS_SERVICE,
                'template_id': EMAILJS_TEMPLATE,
                'user_id':     EMAILJS_KEY,
                'template_params': {
                    'to_email':       to_email,
                    'to_name':        to_name,
                    'email':          to_email,
                    'otp_code':       otp,
                    'otp':            otp,
                    'expiry_minutes': '5',
                    # Purpose: Sign-In Verification
                    'email_title':    'Sign-In Verification',
                    'email_heading':  'Sign-In Verification',
                    'email_intro':    f'Hi {to_name}, someone is signing in to your AutoPro account using Google.\nUse the code below to verify your identity.',
                    'steps_heading':  'Verify your sign-in:',
                    'step1_icon':  '📲', 'step1_title': 'Enter the code',     'step1_desc': 'Enter the 6-digit code in the verification screen.',
                    'step2_icon':  '✅', 'step2_title': 'Access your account', 'step2_desc': 'Once verified, you will be signed in to your dashboard.',
                    'step3_icon':  '🔒', 'step3_title': 'Stay secure',         'step3_desc': 'Never share this code. We will never ask for it.',
                    'footer_note': 'If you did not attempt to sign in, please secure your account immediately.',
                },
            },
            timeout=15,
        )
        if res.status_code != 200:
            print(f'❌ EmailJS error {res.status_code}: {res.text}')
            return jsonify({'ok': False, 'error': f'EmailJS error ({res.status_code})'}), 500

        print(f'✅ Google OTP email sent via EmailJS → {to_email}')
        return jsonify({'ok': True})

    except Exception as e:
        print(f'❌ Google OTP email error: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/send-push-notification', methods=['POST'])
def send_push_notification():
    """Send OneSignal push notification to specific subscription IDs."""
    import urllib.request, json as _json
    data             = request.get_json(silent=True) or {}
    subscription_ids = data.get('subscription_ids', [])
    title            = data.get('title', 'AutoPro Notification')
    message          = data.get('message', '')
    notif_type       = data.get('type', 'info')

    if not subscription_ids or not message:
        return jsonify({'ok': False, 'error': 'Missing subscription_ids or message'}), 400

    ONESIGNAL_APP_ID  = 'c4f82ac7-5340-4e7a-877d-1d38a6f6f8ea'
    ONESIGNAL_API_KEY = 'os_v7_app_yt4cvr2f1hkhvh5ldu4k637i51snjeyuythen3fd61ae1yhnprpy6kbxvn9kjd1pqdhygsqmlrouas4kfuydft32nkgj5flbra3oo5q'

    payload = {
        'app_id':         ONESIGNAL_APP_ID,
        'include_aliases': {
            'external_id': subscription_ids,
        },
        'target_channel': 'push',
        'headings':       {'en': title},
        'contents':       {'en': message},
        'data':           {'type': notif_type},
    }
    req = urllib.request.Request(
        'https://api.onesignal.com/notifications',
        data=_json.dumps(payload).encode('utf-8'),
        headers={
            'Authorization': f'Basic {ONESIGNAL_API_KEY}',
            'Content-Type':  'application/json; charset=utf-8',
        },
        method='POST'
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = resp.read().decode('utf-8')
            print(f'✅ OneSignal push sent → {resp.status}: {body}')
            return jsonify({'ok': True, 'status': resp.status})
    except Exception as e:
        print(f'❌ OneSignal push error: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/update-user-email-password', methods=['POST'])
def update_user_email_password():
    """Update Firebase Auth email and/or password for a user. Called when admin edits a not-yet-logged-in user's email."""
    data     = request.get_json(silent=True) or {}
    uid      = data.get('uid', '').strip()
    new_email    = data.get('new_email', '').strip()
    new_password = data.get('new_password', '').strip()

    if not uid:
        return jsonify({'ok': False, 'error': 'Missing uid'}), 400
    if not firebase_admin._apps:
        return jsonify({'ok': False, 'error': 'Firebase Admin SDK not initialized.'}), 503

    try:
        kwargs = {}
        if new_email:    kwargs['email']    = new_email
        if new_password: kwargs['password'] = new_password
        if kwargs:
            fb_auth.update_user(uid, **kwargs)
        print(f'✅ Updated Auth user {uid}: {list(kwargs.keys())}')
        return jsonify({'ok': True})
    except fb_auth.UserNotFoundError:
        return jsonify({'ok': False, 'error': 'User not found in Firebase Auth.'}), 404
    except Exception as e:
        print(f'❌ update_user_email_password error: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/delete-user', methods=['POST'])
def delete_user():
    """Delete a Firebase Auth user by UID. Firestore doc is deleted client-side."""
    data = request.get_json(silent=True) or {}
    uid  = data.get('uid', '').strip()

    if not uid:
        return jsonify({'ok': False, 'error': 'Missing uid'}), 400

    if not firebase_admin._apps:
        return jsonify({'ok': False, 'error': 'Firebase Admin SDK not initialized. Add serviceAccountKey.json.'}), 503

    try:
        fb_auth.delete_user(uid)
        print(f'✅ Deleted Auth user: {uid}')
        return jsonify({'ok': True})
    except fb_auth.UserNotFoundError:
        # Already deleted — treat as success
        print(f'ℹ️  Auth user not found (already deleted?): {uid}')
        return jsonify({'ok': True})
    except Exception as e:
        print(f'❌ delete_user error: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/cleanup-orphaned-users', methods=['POST'])
def cleanup_orphaned_users():
    """Remove Firestore user docs whose Firebase Auth account no longer exists."""
    if not firebase_admin._apps:
        return jsonify({'ok': False, 'error': 'Firebase Admin SDK not initialized.'}), 503

    try:
        from firebase_admin import firestore as fa_firestore
        db = fa_firestore.client()
        users_ref = db.collection('users')
        docs = users_ref.stream()

        deleted = []
        for doc in docs:
            uid = doc.id
            try:
                fb_auth.get_user(uid)
            except fb_auth.UserNotFoundError:
                # Auth account doesn't exist — delete Firestore doc
                doc.reference.delete()
                deleted.append(uid)
                print(f'🧹 Cleaned up orphaned user doc: {uid}')
            except Exception:
                # Other errors (network, etc.) — skip this doc
                pass

        print(f'✅ Cleanup complete. Removed {len(deleted)} orphaned doc(s).')
        return jsonify({'ok': True, 'deleted': deleted, 'count': len(deleted)})
    except Exception as e:
        print(f'❌ cleanup error: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/send-approval-email', methods=['POST'])
def send_approval_email():
    data     = request.get_json(silent=True) or {}
    to_email = data.get('to_email', '').strip()
    to_name  = data.get('to_name', 'User').strip()

    if not to_email:
        print('❌ send-approval-email: missing to_email')
        return jsonify({'ok': False, 'error': 'Missing email'}), 400

    print(f'📧 Sending approval email → {to_email} ({to_name})')

    subject   = 'Your AutoPro Account Has Been Approved!'
    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">
  <tr><td align="center">
    <table width="520" cellpadding="0" cellspacing="0"
           style="background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.10);">
      <tr>
        <td style="background:#E8001C;padding:30px 40px 0;text-align:center;">
          <div style="font-size:13px;font-weight:700;letter-spacing:4px;color:rgba(255,255,255,.8);margin-bottom:6px;">CALTEX</div>
          <div style="font-size:22px;font-weight:800;color:#fff;letter-spacing:2px;">AutoPro</div>
          <div style="background:#fff;border-radius:24px 24px 0 0;height:22px;margin-top:20px;"></div>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 40px 40px;">
          <h1 style="margin:0 0 8px;text-align:center;font-size:22px;font-weight:800;color:#1a202c;">Account Approved!</h1>
          <p style="margin:0 0 26px;text-align:center;font-size:13px;color:#718096;line-height:1.6;">
            Hi <strong>{to_name}</strong>, great news!<br/>
            Your AutoPro account has been approved by the administrator.
          </p>
          <div style="background:#f0fff4;border:1px solid #9ae6b4;border-radius:12px;padding:20px 24px;margin-bottom:26px;text-align:center;">
            <p style="margin:0;font-size:15px;font-weight:700;color:#276749;">You're all set!</p>
            <p style="margin:6px 0 0;font-size:13px;color:#2f855a;">
              Your account <strong>{to_email}</strong> is now active.<br/>
              You can sign in to the AutoPro app right now.
            </p>
          </div>
          <p style="margin:0 0 10px;font-size:13px;font-weight:700;color:#4a5568;">Getting started:</p>
          <table cellpadding="0" cellspacing="0" width="100%">
            <tr><td style="padding:5px 0;">
              <span style="display:inline-block;width:22px;height:22px;background:#E8001C;border-radius:50%;color:#fff;font-size:11px;font-weight:700;text-align:center;line-height:22px;margin-right:10px;">1</span>
              <span style="font-size:13px;color:#4a5568;">Open the <strong>AutoPro</strong> mobile app</span>
            </td></tr>
            <tr><td style="padding:5px 0;">
              <span style="display:inline-block;width:22px;height:22px;background:#E8001C;border-radius:50%;color:#fff;font-size:11px;font-weight:700;text-align:center;line-height:22px;margin-right:10px;">2</span>
              <span style="font-size:13px;color:#4a5568;">Sign in with your registered email and password</span>
            </td></tr>
            <tr><td style="padding:5px 0;">
              <span style="display:inline-block;width:22px;height:22px;background:#E8001C;border-radius:50%;color:#fff;font-size:11px;font-weight:700;text-align:center;line-height:22px;margin-right:10px;">3</span>
              <span style="font-size:13px;color:#4a5568;">Explore your dashboard and manage your vehicles</span>
            </td></tr>
          </table>
          <hr style="border:none;border-top:1px solid #e2e8f0;margin:26px 0;"/>
          <p style="margin:0;font-size:12px;color:#a0aec0;text-align:center;line-height:1.6;">
            Need help? Contact us at <a href="mailto:caltexautopro2026@gmail.com" style="color:#E8001C;">caltexautopro2026@gmail.com</a>
          </p>
        </td>
      </tr>
      <tr>
        <td style="background:#f7f8fa;padding:18px 40px;text-align:center;border-top:1px solid #e2e8f0;">
          <p style="margin:0;font-size:11px;color:#a0aec0;line-height:1.6;">
            &copy; 2025 AutoPro &middot; JA Noble Enterprise INC<br/>
            This is an automated message &mdash; please do not reply.
          </p>
        </td>
      </tr>
    </table>
  </td></tr>
</table>
</body>
</html>"""

    try:
        msg = MIMEMultipart('alternative')
        msg['Subject'] = subject
        msg['From']    = SMTP_FROM
        msg['To']      = to_email
        msg.attach(MIMEText(html_body, 'html'))
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.ehlo()
            server.starttls()
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(SMTP_USER, to_email, msg.as_string())
        print(f'✅ Approval email delivered → {to_email}')
        return jsonify({'ok': True})
    except smtplib.SMTPAuthenticationError:
        print(f'❌ SMTP auth failed for approval email → {to_email}')
        return jsonify({'ok': False, 'error': 'SMTP auth failed'}), 500
    except Exception as e:
        print(f'❌ Approval email error → {to_email}: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/send-welcome-email', methods=['POST'])
def send_welcome_email():
    data = request.get_json(silent=True) or {}
    to_email      = data.get('to_email', '').strip()
    to_name       = data.get('to_name', '').strip()
    temp_password = data.get('temp_password', '').strip()
    role          = data.get('role', '').strip()

    if not to_email or not temp_password:
        return jsonify({'ok': False, 'error': 'Missing required fields'}), 400

    subject = f'Welcome to AutoPro - {to_name}'
    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  <title>AutoPro — Welcome to Your Account</title>
</head>
<body style="margin:0;padding:0;background:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;">

<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">
  <tr><td align="center">

    <table width="520" cellpadding="0" cellspacing="0"
           style="background:#fff;border-radius:16px;overflow:hidden;
                  box-shadow:0 4px 24px rgba(0,0,0,.10);">

      <!-- ── Red Header ── -->
      <tr>
        <td style="background:#E8001C;padding:30px 40px 0;text-align:center;">
        </td>
      </tr>

      <!-- ── Body ── -->
      <tr>
        <td style="padding:8px 40px 40px;">

          <!-- Title -->
          <h1 style="margin:0 0 8px;text-align:center;font-size:22px;
                     font-weight:800;color:#1a202c;">Welcome to AutoPro!</h1>
          <p style="margin:0 0 26px;text-align:center;font-size:13px;
                    color:#718096;line-height:1.6;">
            Hi <strong>{to_name}</strong>, your account has been created.<br/>
            Here are your login credentials:
          </p>

          <!-- Credentials Box -->
          <div style="background:#f7f8fa;border:1px solid #e2e8f0;border-radius:12px;
                      padding:20px 24px;margin-bottom:26px;">
            <table cellpadding="0" cellspacing="0" width="100%">
              <tr>
                <td style="padding:8px 0;font-size:12px;color:#718096;
                           font-weight:700;text-transform:uppercase;width:130px;">
                  Email
                </td>
                <td style="padding:8px 0;font-size:13px;font-weight:600;color:#1a202c;">
                  {to_email}
                </td>
              </tr>
              <tr style="border-top:1px solid #e2e8f0;">
                <td style="padding:8px 0;font-size:12px;color:#718096;
                           font-weight:700;text-transform:uppercase;">
                  Temp Password
                </td>
                <td style="padding:8px 0;">
                  <span style="background:#E8001C;color:#fff;font-size:14px;
                               font-weight:700;padding:5px 14px;border-radius:6px;
                               letter-spacing:2px;">
                    {temp_password}
                  </span>
                </td>
              </tr>
              <tr style="border-top:1px solid #e2e8f0;">
                <td style="padding:8px 0;font-size:12px;color:#718096;
                           font-weight:700;text-transform:uppercase;">
                  Role
                </td>
                <td style="padding:8px 0;font-size:13px;font-weight:600;color:#1a202c;">
                  {role.capitalize()}
                </td>
              </tr>
            </table>
          </div>

          <!-- What's Next -->
          <table cellpadding="0" cellspacing="0" width="100%" style="margin-bottom:26px;">
            <tr>
              <td style="padding:0 0 12px;">
                <div style="font-size:13px;font-weight:700;color:#1a202c;">What happens next?</div>
              </td>
            </tr>
            <tr>
              <td>
                <table cellpadding="0" cellspacing="0" width="100%">
                  <tr>
                    <td style="width:40px;vertical-align:top;padding:0 12px 14px 0;">
                      <div style="width:36px;height:36px;background:#fff0f0;border-radius:10px;
                                  text-align:center;line-height:36px;font-size:18px;">📱</div>
                    </td>
                    <td style="vertical-align:top;padding-bottom:14px;">
                      <div style="font-size:13px;font-weight:700;color:#1a202c;margin-bottom:2px;">Open the app</div>
                      <div style="font-size:12px;color:#718096;line-height:1.5;">Download or open the <strong>AutoPro</strong> mobile app on your device.</div>
                    </td>
                  </tr>
                  <tr>
                    <td style="width:40px;vertical-align:top;padding:0 12px 14px 0;">
                      <div style="width:36px;height:36px;background:#fff0f0;border-radius:10px;
                                  text-align:center;line-height:36px;font-size:18px;">🔑</div>
                    </td>
                    <td style="vertical-align:top;padding-bottom:14px;">
                      <div style="font-size:13px;font-weight:700;color:#1a202c;margin-bottom:2px;">Sign in with your credentials</div>
                      <div style="font-size:12px;color:#718096;line-height:1.5;">Use the email and temporary password above to log in for the first time.</div>
                    </td>
                  </tr>
                  <tr>
                    <td style="width:40px;vertical-align:top;padding:0 12px 0 0;">
                      <div style="width:36px;height:36px;background:#fff0f0;border-radius:10px;
                                  text-align:center;line-height:36px;font-size:18px;">🔒</div>
                    </td>
                    <td style="vertical-align:top;">
                      <div style="font-size:13px;font-weight:700;color:#1a202c;margin-bottom:2px;">Set your own password</div>
                      <div style="font-size:12px;color:#718096;line-height:1.5;">You'll be prompted to change your password immediately after your first login.</div>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>

          <hr style="border:none;border-top:1px solid #e2e8f0;margin:26px 0;"/>

          <p style="margin:0;font-size:12px;color:#a0aec0;text-align:center;line-height:1.6;">
            Need help? Contact us at
            <a href="mailto:janobleenterprisesinc@gmail.com"
               style="color:#E8001C;">janobleenterprisesinc@gmail.com</a>
          </p>

        </td>
      </tr>

    </table>

  </td></tr>
</table>

</body>
</html>"""

    try:
        msg = MIMEMultipart('alternative')
        msg['Subject'] = subject
        msg['From']    = SMTP_FROM
        msg['To']      = to_email
        msg.attach(MIMEText(html_body, 'html'))

        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.ehlo()
            server.starttls()
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(SMTP_USER, to_email, msg.as_string())

        return jsonify({'ok': True})
    except smtplib.SMTPAuthenticationError:
        print('SMTP Authentication failed - check email credentials')
        return jsonify({'ok': False, 'error': 'Email service authentication failed. Please contact administrator.'}), 500
    except smtplib.SMTPException as e:
        print(f'SMTP error: {e}')
        return jsonify({'ok': False, 'error': 'Failed to send email. Please try again later.'}), 500
    except Exception as e:
        print(f'Email error: {e}')
        return jsonify({'ok': False, 'error': 'An error occurred while sending email.'}), 500

# ── Landing / Home ──────────────────────────────────────────
@app.route('/')
@app.route('/index.html')
def index():
    return render_template('index.html')

@app.route('/download/autopro.apk')
def download_apk():
    """Serve the AutoPro APK for direct download. Always serves the latest file."""
    from flask import send_from_directory
    import os
    apk_dir = os.path.join(os.path.dirname(__file__), 'static', 'apk')
    apk_path = os.path.join(apk_dir, 'autopro.apk')
    if not os.path.exists(apk_path):
        return 'APK not found. Run build_and_deploy_apk.bat first.', 404
    response = send_from_directory(apk_dir, 'autopro.apk',
                                   as_attachment=True,
                                   download_name='AutoPro.apk')
    # Prevent browser from caching the old APK
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    return response

# ── Auth ────────────────────────────────────────────────────
@app.route('/login.html')
def login():
    return render_template('login.html')

@app.route('/api/redirect-to-dashboard', methods=['POST'])
def redirect_to_dashboard():
    """
    Endpoint for login.html to redirect to the appropriate dashboard.
    Expects: { role: 'admin' | 'staff' | 'customer' }
    """
    data = request.get_json(silent=True) or {}
    role = data.get('role', 'customer').lower()
    
    # Map role to dashboard
    dashboard_map = {
        'admin': '/admin_dashboard.html',
        'staff': '/staff_dashboard.html',
        'customer': '/customer_dashboard.html',
    }
    
    target = dashboard_map.get(role, '/customer_dashboard.html')
    print(f'Redirecting user with role "{role}" to {target}')
    
    return jsonify({'ok': True, 'redirect': target})

@app.route('/forgot_password.html')
def forgot_password():
    return render_template('forgot_password.html')

@app.route('/regsiter.html')
def register():
    return render_template('regsiter.html')

# ── Admin ────────────────────────────────────────────────────
@app.route('/admin_dashboard.html')
def admin_dashboard():
    return render_template('admin_dashboard.html')

@app.route('/admin_transactions.html')
def admin_transactions():
    return render_template('admin_transactions.html')

@app.route('/admin_issuances.html')
def admin_issuances():
    return render_template('admin_issuances.html')

@app.route('/admin_inventory_itemaster.html')
def admin_inventory_items():
    return render_template('admin_inventory_itemaster.html')

@app.route('/admin_inventory_stock.html')
def admin_inventory_stock():
    return render_template('admin_inventory_stock.html')

@app.route('/admin_vehicle_list.html')
def admin_vehicles():
    return render_template('admin_vehicle_list.html')

@app.route('/admin_vehicle_maintenance.html')
def admin_vehicle_maintenance():
    return render_template('admin_vehicle_maintenance.html')

@app.route('/admin_users.html')
def admin_users():
    return render_template('admin_users.html')

@app.route('/admin_dss.html')
def admin_dss():
    return render_template('admin_dss.html')

@app.route('/admin_domain_management.html')
def admin_domains():
    return render_template('admin_domain_management.html')

@app.route('/admin_service_bookings.html')
def admin_service_bookings():
    return render_template('admin_service_bookings.html')

@app.route('/admin_receiving.html')
def admin_receiving():
    return render_template('admin_receiving.html')

@app.route('/print_layout.html')
def print_layout():
    return render_template('print_layout.html')

@app.route('/admin_sidebar.html')
def admin_sidebar():
    return render_template('admin_sidebar.html')

@app.route('/admin_header.html')
def admin_header():
    return render_template('admin_header.html')

@app.route('/calendarview_widget.html')
def calendarview_widget():
    return render_template('calendarview_widget.html')

@app.route('/notifications.html')
def notifications():
    return render_template('notifications.html')

@app.route('/profile.html')
def profile():
    return render_template('profile.html')

@app.route('/ai_usage_controls.html')
def ai_usage_controls():
    return render_template('ai_usage_controls.html')

@app.route('/change_password.html')
def change_password():
    return render_template('change_password.html')

@app.route('/help_support.html')
def help_support():
    return render_template('help_support.html')

# ── Staff ────────────────────────────────────────────────────
@app.route('/staff_dashboard.html')
def staff_dashboard():
    return render_template('staff_dashboard.html')

@app.route('/staff_inventory.html')
def staff_inventory():
    return render_template('staff_inventory.html')

@app.route('/staff_maintenance.html')
def staff_maintenance():
    return render_template('staff_maintenance.html')

@app.route('/staff_vehicle_list.html')
def staff_vehicle_list():
    return render_template('staff_vehicle_list.html')

# ── Customer ─────────────────────────────────────────────────
@app.route('/customer_dashboard.html')
def customer_dashboard():
    return render_template('customer_dashboard.html')

@app.route('/customer_pms_history.html')
def customer_pms_history():
    return render_template('customer_pms_history.html')

@app.route('/customer_book_service.html')
def customer_book_service():
    return render_template('customer_book_service.html')

@app.route('/pms_history_details.html')
def pms_history_details():
    return render_template('pms_history_details.html')

@app.route('/customer_smart_ai.html')
def customer_smart_ai():
    return render_template('customer_smart_ai_widget.html')

@app.route('/customer_header.html')
def customer_header():
    return render_template('customer_header.html')

@app.route('/customer_sidebar.html')
def customer_sidebar():
    return render_template('customer_sidebar.html')

# ── Admin AI Backend Proxy ─────────────────────────────────────────────────────
# The admin AI is served by the standalone FastAPI service in ai_assistant/.
# Start it with:  cd ai_assistant && venv\Scripts\uvicorn main:app --port 8001
#
# The Flask server acts as a proxy so the browser never talks directly to the
# FastAPI service (avoids CORS and keeps auth in one place).
#
# Only admin requests are proxied.  Customer AI chat keeps its local JS fallback.

import requests as _requests_lib

# Base URL of the ai_assistant FastAPI service — override via env var if needed.
# Default points to the deployed Render backend.
_AI_BACKEND_URL = os.environ.get('AI_BACKEND_URL', 'https://caltex-autopro-capstone-project.onrender.com').rstrip('/')


def _ai_backend_available() -> bool:
    """Quick liveness ping to the AI backend. Uses a longer timeout to handle Render cold starts."""
    try:
        r = _requests_lib.get(f'{_AI_BACKEND_URL}/health', timeout=60)
        return r.status_code == 200
    except Exception:
        return False


def _sanitise_admin_reply(reply: str) -> str:
    """
    Strip any leaked report_payload JSON that the LLM included without the
    proper fenced-block wrapper.  This prevents raw JSON from appearing in
    the chat bubble when the regex in ai_chat() doesn't match.

    Also converts a reply that is ONLY a bare JSON object (starts with '{')
    into a plain conversational fallback message.
    """
    import re as _re2, json as _json2

    if not reply:
        return reply

    # 1. Remove fenced report_payload blocks (should already be caught above,
    #    but handles edge-cases where the fence label has extra whitespace).
    cleaned = _re2.sub(r'```report_payload[\s\S]*?```', '', reply, flags=_re2.DOTALL).strip()

    # 2. Remove bare JSON objects that contain "report_type" — these are
    #    unfenced report_payload blobs the LLM leaked into its reply.
    cleaned = _re2.sub(
        r'\{[^{}]*"report_type"[^{}]*\}',
        '',
        cleaned,
        flags=_re2.DOTALL,
    ).strip()

    # 3. If what's left is still just a JSON object, replace entirely.
    if cleaned.startswith('{') and cleaned.endswith('}'):
        try:
            obj = _json2.loads(cleaned)
            if 'report_type' in obj:
                return "I've noted your report request. Please use the Download button above to generate and download the report."
        except Exception:
            pass

    return cleaned or reply


# ── AI Usage Controls (Profile → Settings → AI Usage Controls) ──────────────
# Server-side proxy to the ai_assistant settings + usage endpoints. The
# frontend NEVER talks to the AI service directly, and every call here is
# verified against Firebase ID tokens so only authenticated admins can read
# or change AI settings.

def _require_admin():
    """
    Verify the caller is an authenticated admin and return their claims,
    or None. Checks, in order:
      1. Bearer Firebase ID token — admin via custom claim (admin/role), or
      2. the Firestore `users/{uid}.role == 'admin'` (via the shared
         ai_assistant/firebase_client module already used by this app).
    """
    auth_header = request.headers.get('Authorization', '')
    token = auth_header[7:].strip() if auth_header.startswith('Bearer ') else ''
    if not token:
        return None
    try:
        claims = fb_auth.verify_id_token(token)
    except Exception:
        return None

    # 1. Custom claims, if present.
    if claims.get('admin') or claims.get('role') == 'admin':
        return claims

    # 2. Firestore role lookup via this app's own Firebase Admin client
    #    (initialized at startup). The earlier version imported a
    #    `firestore_client` module that doesn't exist in this service, which
    #    raised ModuleNotFoundError and silently failed every admin check.
    try:
        from firebase_admin import firestore as _fa
        _db = _fa.client()
        udoc = _db.collection('users').document(claims['uid']).get()
        if udoc.exists:
            role = (udoc.to_dict().get('role') or '').strip().lower()
            if role == 'admin':
                return claims
    except Exception:
        pass

    return None


@app.route('/api/ai-settings', methods=['GET'])
def api_ai_settings_get():
    claims = _require_admin()
    if not claims:
        return jsonify({'success': False, 'error': 'Admin authentication required.'}), 403
    try:
        resp = _requests_lib.get(f'{_AI_BACKEND_URL}/ai-settings', timeout=30)
        resp.raise_for_status()
        return jsonify(resp.json())
    except Exception:
        return jsonify({'success': False,
                        'error': 'The AI service is unreachable right now. Please try again.'}), 503


@app.route('/api/ai-settings', methods=['PUT'])
def api_ai_settings_put():
    claims = _require_admin()
    if not claims:
        return jsonify({'success': False, 'error': 'Admin authentication required.'}), 403
    data = request.get_json(silent=True) or {}
    allowed = {
        'customer_ai_enabled', 'customer_token_limit', 'dev_access_enabled',
        'dev_bypass_token_limit', 'dev_access_while_paused',
    }
    payload = {k: v for k, v in data.items() if k in allowed}
    if not payload:
        return jsonify({'success': False, 'error': 'No valid settings provided.'}), 400
    try:
        resp = _requests_lib.put(f'{_AI_BACKEND_URL}/ai-settings', json=payload, timeout=30)
        resp.raise_for_status()
        return jsonify(resp.json())
    except Exception:
        return jsonify({'success': False,
                        'error': 'Could not save AI settings. Please try again.'}), 503


@app.route('/api/ai-chat', methods=['POST'])
def ai_chat():
    """Proxy AI chat to ai_assistant FastAPI service with session memory.

    - user_type == 'admin'    → POST /admin/chat
    - user_type == 'customer' → POST /customer/chat  (scoped to that customer)

    The backend returns a session_id which the frontend must send back on the
    next request — this is how server-side conversational memory works.
    """
    data          = request.get_json(silent=True) or {}
    message       = (data.get('message') or '').strip()
    user_type     = data.get('user_type', 'customer')
    session_id    = (data.get('session_id') or '').strip() or None
    customer_uid  = (data.get('customer_uid') or '').strip()
    customer_name = (data.get('customer_name') or '').strip()

    if not message:
        return jsonify({'success': False, 'error': 'Empty message'}), 400

    # ── Customer chat ─────────────────────────────────────────────────────────
    if user_type == 'customer':
        if not customer_uid:
            return jsonify({
                'success': False, 'offline': True,
                'answer': 'Customer identity missing. Please log in again.',
            }), 400

        # ── Resolve customer_name from Firestore if not provided ─────────────
        if not customer_name:
            try:
                from firestore_client import get_db as _get_db
                _udb = _get_db()
                _udoc = _udb.collection('users').doc(customer_uid).get()
                if _udoc.exists:
                    customer_name = (_udoc.to_dict().get('name') or '').strip()
            except Exception:
                pass

        if not customer_name:
            return jsonify({
                'success': False, 'offline': True,
                'answer': 'Could not resolve your account name. Please refresh and try again.',
            }), 400
        try:
            resp = _requests_lib.post(
                f'{_AI_BACKEND_URL}/customer/chat',
                json={
                    'message':       message,
                    'customer_uid':  customer_uid,
                    'customer_name': customer_name,
                    'session_id':    session_id,
                },
                timeout=60,
            )
            resp.raise_for_status()
            payload = resp.json()
            return jsonify({
                'success':      True,
                'answer':       payload.get('reply', ''),
                'session_id':   payload.get('session_id', ''),
                'rate_limited': payload.get('rate_limited', False),
                'reset_in':     payload.get('reset_in', ''),
                'tool_calls':   payload.get('tool_calls', []),
            })
        except _requests_lib.exceptions.ConnectionError:
            return jsonify({'success': False, 'offline': True,
                            'answer': 'The AI service is offline.'}), 503
        except _requests_lib.exceptions.Timeout:
            return jsonify({'success': False, 'offline': True, 'cold_start': True,
                            'answer': 'The AI service is starting up (cold start). Please try again in a few seconds.'}), 503
        except _requests_lib.exceptions.HTTPError as e:
            status = e.response.status_code if e.response is not None else 0
            # Try to get a structured reply from the FastAPI response body first
            try:
                body = e.response.json() if e.response is not None else {}
                ai_reply = body.get('reply', '') or body.get('detail', '')
            except Exception:
                ai_reply = ''
            if ai_reply:
                # FastAPI returned a friendly reply — surface it directly
                return jsonify({
                    'success': True,
                    'answer': ai_reply,
                    'session_id': '',
                    'tool_calls': [],
                })
            if status == 503:
                msg = 'The AI service is temporarily unavailable. Please try again in a moment.'
            elif status == 429:
                msg = 'The AI service has reached its usage limit. Please try again later.'
            else:
                msg = 'The AI service could not process your request right now. Please try again in a moment.'
            return jsonify({'success': False, 'offline': True, 'answer': msg}), 503
        except Exception:
            return jsonify({
                'success': False,
                'offline': True,
                'answer': "I'm having trouble reaching the AI service right now. Please try again in a moment.",
            }), 503

    # ── Admin chat ────────────────────────────────────────────────────────────
    if user_type != 'admin':
        return jsonify({'success': False, 'offline': True,
                        'answer': 'Unknown user type.'}), 400

    try:
        resp = _requests_lib.post(
            f'{_AI_BACKEND_URL}/admin/chat',
            json={'message': message, 'session_id': session_id},
            timeout=90,
        )
        resp.raise_for_status()
        payload = resp.json()

        # ── Rate limit check ──────────────────────────────────────────────────
        if payload.get('rate_limited'):
            return jsonify({
                'success':      True,
                'rate_limited': True,
                'reset_in':     payload.get('reset_in', ''),
                'answer':       payload.get('reply', ''),
                'session_id':   payload.get('session_id', ''),
            })

        # ── Report payload extraction ─────────────────────────────────────────
        # The AI embeds a ```report_payload ... ``` JSON block in its reply
        # when it detects a report request. We parse it here so the frontend
        # receives clean structured data — no fragile regex on the raw message.
        import re as _re
        import json as _json

        ai_reply    = payload.get('reply', '')
        rp_match    = _re.search(
            r'```report_payload\s*\n(.*?)\n```',
            ai_reply, _re.DOTALL
        )

        if rp_match:
            try:
                rp = _json.loads(rp_match.group(1).strip())
            except (_json.JSONDecodeError, ValueError):
                rp = {}

            if rp.get('report_type'):
                # Strip the JSON block from the visible reply
                clean_reply = _re.sub(
                    r'\n?```report_payload\s*\n.*?\n```',
                    '', ai_reply, flags=_re.DOTALL
                ).strip()

                # Pull date filters out of the filters dict (they are query-param
                # level, not body-level filters, but we normalise them here)
                raw_filters  = rp.get('filters') or {}
                report_month = raw_filters.pop('month',      None)
                report_start = raw_filters.pop('start_date', None)
                report_end   = raw_filters.pop('end_date',   None)

                # Normalise format: "xlsx" → "excel"
                raw_fmt = (rp.get('format') or 'pdf').lower().replace('xlsx', 'excel')

                # ── Future-date guard ─────────────────────────────────────────
                # Validate date filters before setting report_ready so the
                # frontend never shows a download button for future / empty ranges.
                from datetime import date as _date_cls
                import re as _re2

                _MONTHS_SHORT = ['Jan','Feb','Mar','Apr','May','Jun',
                                 'Jul','Aug','Sep','Oct','Nov','Dec']

                def _parse_date_simple(s):
                    """Return a date object or None — tolerates many formats."""
                    if not s:
                        return None
                    for fmt in ('%Y-%m-%d', '%B %d, %Y', '%b %d, %Y',
                                '%d %B %Y', '%d %b %Y', '%m/%d/%Y', '%d/%m/%Y'):
                        try:
                            from datetime import datetime as _dt2
                            return _dt2.strptime(s.strip(), fmt).date()
                        except ValueError:
                            pass
                    return None

                def _is_future(date_str):
                    d = _parse_date_simple(date_str)
                    return d is not None and d > _date_cls.today()

                def _month_is_future(month_str):
                    if not month_str:
                        return False
                    m = _re2.match(r'([A-Za-z]+)\s+(\d{4})', month_str.strip())
                    if not m:
                        return False
                    abbr = m.group(1)[:3].capitalize()
                    if abbr not in _MONTHS_SHORT:
                        return False
                    mo_idx = _MONTHS_SHORT.index(abbr) + 1
                    yr = int(m.group(2))
                    today = _date_cls.today()
                    return yr > today.year or (yr == today.year and mo_idx > today.month)

                _future = (
                    _is_future(report_start)
                    or _is_future(report_end)
                    or _month_is_future(report_month)
                )

                if _future:
                    # Tell the user clearly — no download button
                    _label = report_month or (
                        f"{report_start} to {report_end}"
                        if report_start or report_end
                        else "the requested period"
                    )
                    _no_data_msg = (
                        f"No records found for **{_label}** — that date range is in the future. "
                        f"Reports can only be generated for dates with existing historical data."
                    )
                    return jsonify({
                        'success':    True,
                        'answer':     _no_data_msg,
                        'session_id': payload.get('session_id', ''),
                    })

                return jsonify({
                    'success':           True,
                    'report_ready':      True,
                    'report_type':       rp['report_type'],
                    'report_format':     raw_fmt,   # "pdf" | "excel" | "both"
                    'report_month':      report_month,
                    'report_start_date': report_start,
                    'report_end_date':   report_end,
                    'report_filters':    raw_filters,  # forwarded to report generator
                    'session_id':        payload.get('session_id', ''),
                    'answer':            clean_reply or f'Your {rp["report_type"]} report is ready.',
                })
        

        return jsonify({
            'success':      True,
            'answer':       _sanitise_admin_reply(payload.get('reply', '')),
            'session_id':   payload.get('session_id', ''),
            'rate_limited': payload.get('rate_limited', False),
            'reset_in':     payload.get('reset_in', ''),
            'tool_calls':   payload.get('tool_calls', []),
        })
    except _requests_lib.exceptions.ConnectionError:
        return jsonify({
            'success': False,
            'offline': True,
            'answer': 'The AI service is offline.',
        }), 503
    except _requests_lib.exceptions.Timeout:
        return jsonify({
            'success': False,
            'offline': True,
            'cold_start': True,
            'answer': 'The AI service is starting up (cold start). Please try again in a few seconds.',
        }), 503
    except _requests_lib.exceptions.HTTPError as e:
        status = e.response.status_code if e.response is not None else 0
        # Try to get a structured reply from the FastAPI response body first
        try:
            body = e.response.json() if e.response is not None else {}
            ai_reply = body.get('reply', '') or body.get('detail', '')
        except Exception:
            ai_reply = ''
        if ai_reply:
            return jsonify({
                'success': True,
                'answer': ai_reply,
                'session_id': '',
                'tool_calls': [],
            })
        if status == 503:
            msg = 'The AI service is temporarily unavailable. Please try again in a moment.'
        elif status == 429:
            msg = 'The AI service has reached its usage limit. Please try again later.'
        else:
            msg = 'The AI service could not process your request right now. Please try again in a moment.'
        return jsonify({'success': False, 'offline': True, 'answer': msg}), 503
    except Exception:
        return jsonify({
            'success': False,
            'offline': True,
            'answer': "I'm having trouble reaching the AI service right now. Please try again in a moment.",
        }), 503


@app.route('/api/ai-health', methods=['GET'])
def ai_health_check():
    """Check if the AI backend service is reachable."""
    if _ai_backend_available():
        return jsonify({'online': True, 'status': 'ok', 'mode': 'ai_assistant'})
    return jsonify({'online': False, 'error': 'ai_assistant service not reachable'}), 503


@app.route('/api/ai-session/<session_id>', methods=['DELETE'])
def ai_clear_session(session_id):
    """Clear server-side session memory for a given session."""
    try:
        _requests_lib.delete(
            f'{_AI_BACKEND_URL}/session/{session_id}',
            timeout=5,
        )
    except Exception:
        pass  # best-effort; don't fail if backend is down
    return jsonify({'success': True, 'cleared': session_id})


@app.route('/api/ai-report', methods=['POST'])
def ai_generate_report():
    """Generate PDF or Excel report by proxying to ai_assistant FastAPI service.

    Request body:
        report_type: "inventory" | "issuance" | "maintenance" | "vehicles" | "bookings"
        format:      "pdf" | "excel"  (default: "pdf")
        month:       optional month filter, e.g. "March 2026"
        start_date:  optional range start, e.g. "2026-03-01" (takes priority over month)
        end_date:    optional range end, e.g. "2026-03-31"
    """
    from flask import send_file
    import io as _io

    # ── Admin-only enforcement (independent of the AI intent router) ─────────
    # Report generation is an administrative feature. Even if a customer
    # reaches this endpoint directly, the request is rejected before any
    # report data is retrieved or generated.
    if _require_admin() is None:
        return jsonify({
            'success': False,
            'error': ('Sorry, administrative report generation is only '
                      'available to authorized administrators.'),
        }), 403

    data        = request.get_json(silent=True) or {}
    report_type = data.get('report_type', '').strip().lower()
    file_format = (data.get('format', 'pdf') or 'pdf').strip().lower().replace('xlsx', 'excel')
    month       = (data.get('month') or '').strip() or None
    start_date  = (data.get('start_date') or '').strip() or None
    end_date    = (data.get('end_date') or '').strip() or None
    filters     = data.get('filters') or {}   # dict forwarded from ai_chat

    valid_types = ('inventory', 'issuance', 'maintenance', 'vehicles', 'bookings')
    if report_type not in valid_types:
        return jsonify({
            'success': False,
            'error': f'Invalid report_type. Use: {", ".join(valid_types)}',
        }), 400

    try:
        params = {'report_type': report_type, 'format': file_format}
        if start_date or end_date:
            if start_date:
                params['start_date'] = start_date
            if end_date:
                params['end_date'] = end_date
        elif month:
            params['month'] = month

        # Attempt the report request — retry once after a warm-up delay if the
        # backend is cold-starting (Render free tier can take 30–50 s to wake).
        def _do_report_request():
            return _requests_lib.post(
                f'{_AI_BACKEND_URL}/admin/report',
                params=params,
                json=filters if filters else None,
                timeout=120,
            )

        try:
            resp = _do_report_request()
        except (_requests_lib.exceptions.ConnectionError,
                _requests_lib.exceptions.Timeout):
            # Backend may be cold-starting — warm it up then retry once
            import time as _time
            try:
                _requests_lib.get(f'{_AI_BACKEND_URL}/health', timeout=60)
            except Exception:
                pass
            _time.sleep(2)
            resp = _do_report_request()

        # Surface 400 errors (no records / future date) as JSON so the
        # frontend can show the real message instead of a generic failure.
        if resp.status_code == 400:
            try:
                detail = resp.json().get('detail', 'No records found for the selected period.')
            except Exception:
                detail = 'No records found for the selected period.'
            return jsonify({'success': False, 'error': detail}), 400

        # Surface 503 / 500 with real detail
        if resp.status_code in (500, 503):
            try:
                detail = resp.json().get('detail', 'Report generation failed.')
            except Exception:
                detail = f'Report generation failed (status {resp.status_code}).'
            return jsonify({'success': False, 'error': detail}), resp.status_code

        resp.raise_for_status()

        ext      = '.pdf' if file_format == 'pdf' else '.xlsx'
        mimetype = ('application/pdf' if file_format == 'pdf'
                    else 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        if start_date or end_date:
            _sd = (start_date or '').replace(' ', '_')
            _ed = (end_date or '').replace(' ', '_')
            safe_suffix = f'_{_sd}_to_{_ed}' if _sd and _ed else f'_{_sd or _ed}'
        elif month:
            safe_suffix = f'_{month.replace(" ", "_")}'
        else:
            safe_suffix = ''
        filename = f'{report_type}_report{safe_suffix}{ext}'

        response = send_file(
            _io.BytesIO(resp.content),
            mimetype=mimetype,
            as_attachment=True,
            download_name=filename,
        )
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Cache-Control'] = 'no-store'
        return response
    except (_requests_lib.exceptions.ConnectionError,
            _requests_lib.exceptions.Timeout):
        return jsonify({
            'success': False,
            'error': 'Cannot reach the AI service. It may be starting up (Render cold start) — '
                     'please wait 30–60 seconds and try again.'
        }), 503
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/customer_my_bookings.html')
def customer_my_bookings():
    return render_template('customer_my_bookings.html')


@app.route('/privacy_policy.html')
def privacy_policy():
    return render_template('privacy_policy.html')


@app.route('/terms_condiion.html')
def terms_conditions():
    return render_template('terms_condiion.html')


@app.route('/api/send-notification-email', methods=['POST'])
def send_notification_email():
    """
    Send a PMS/alert notification email to admin users (by role) or a specific
    customer (by UID).  Called by admin_functions.js generateWebPMSNotifications.

    Request body:
        title      : str  – notification title
        message    : str  – notification body text
        type       : str  – "warning" | "info" | "success"
        targetRole : str  – "admin" | "staff" | "" (empty = use targetUid)
        targetUid  : str  – Firebase UID of a specific user (used when targetRole is empty)
    """
    import firebase_admin.firestore as _fs

    data        = request.get_json(silent=True) or {}
    title       = data.get('title',       'AutoPro Notification').strip()
    message     = data.get('message',     '').strip()
    notif_type  = data.get('type',        'info').strip()
    target_role = data.get('targetRole',  '').strip()
    target_uid  = data.get('targetUid',   '').strip()

    if not message:
        return jsonify({'ok': False, 'error': 'Missing message'}), 400

    colour_map = {'warning': '#E8001C', 'success': '#38a169', 'info': '#003087'}
    icon_map   = {'warning': '⚠️',      'success': '✅',       'info': 'ℹ️'}
    accent  = colour_map.get(notif_type, '#003087')
    icon    = icon_map.get(notif_type, 'ℹ️')
    subject = f'{icon} {title}'

    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">
  <tr><td align="center">
    <table width="520" cellpadding="0" cellspacing="0"
           style="background:#fff;border-radius:16px;overflow:hidden;
                  box-shadow:0 4px 24px rgba(0,0,0,.10);">
      <tr>
        <td style="background:#E8001C;padding:30px 40px 0;text-align:center;">
          <div style="font-size:13px;font-weight:700;letter-spacing:4px;
                      color:rgba(255,255,255,.8);margin-bottom:6px;">CALTEX</div>
          <div style="font-size:22px;font-weight:800;color:#fff;letter-spacing:2px;">AutoPro</div>
          <div style="background:#fff;border-radius:24px 24px 0 0;height:22px;margin-top:20px;"></div>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 40px 40px;">
          <div style="text-align:center;margin-bottom:18px;">
            <span style="display:inline-block;background:{accent}18;
                         border:1.5px solid {accent}40;border-radius:24px;
                         padding:6px 18px;font-size:12px;font-weight:700;
                         color:{accent};letter-spacing:0.5px;">
              {icon} &nbsp;{title}
            </span>
          </div>
          <div style="background:#f7f8fa;border-radius:12px;padding:18px 20px;
                      margin-bottom:20px;">
            <p style="margin:0;font-size:13px;color:#1a202c;line-height:1.7;">{message}</p>
          </div>
          <p style="margin:0;font-size:12px;color:#a0aec0;text-align:center;line-height:1.6;">
            Log in to the AutoPro portal to view more details.
          </p>
        </td>
      </tr>
      <tr>
        <td style="background:#f7f8fa;padding:18px 40px;text-align:center;
                   border-top:1px solid #e2e8f0;">
          <p style="margin:0;font-size:11px;color:#a0aec0;line-height:1.6;">
            &copy; 2025 AutoPro &middot; JA Noble Enterprise Inc<br/>
            102 National Highway, Brgy. Landayan, San Pedro, Laguna<br/>
            This is an automated message &mdash; please do not reply.
          </p>
        </td>
      </tr>
    </table>
  </td></tr>
</table>
</body>
</html>"""

    # ── Resolve recipient emails from Firestore ──────────────────────────────
    try:
        fdb = _fs.client()
        recipients = []
        if target_uid:
            # Single user
            doc = fdb.collection('users').document(target_uid).get()
            if doc.exists:
                d     = doc.to_dict()
                email = (d.get('email') or '').strip()
                name  = (d.get('name')  or 'User').strip()
                if email:
                    recipients.append({'email': email, 'name': name})
        elif target_role:
            # All users with that role
            docs = fdb.collection('users').where('role', '==', target_role).stream()
            for doc in docs:
                d     = doc.to_dict()
                email = (d.get('email') or '').strip()
                name  = (d.get('name')  or target_role.capitalize()).strip()
                if email:
                    recipients.append({'email': email, 'name': name})
    except Exception as e:
        print(f'❌ send-notification-email Firestore error: {e}')
        return jsonify({'ok': False, 'error': f'Firestore lookup failed: {e}'}), 500

    if not recipients:
        return jsonify({'ok': True, 'sent': 0, 'note': 'No recipients found'})

    # ── Send one email per recipient ─────────────────────────────────────────
    sent   = 0
    errors = []
    for r in recipients:
        personalized = html_body.replace(
            'Log in to the AutoPro portal',
            f'Hi <strong>{r["name"]}</strong> — log in to the AutoPro portal'
        )
        try:
            msg = MIMEMultipart('alternative')
            msg['Subject'] = subject
            msg['From']    = SMTP_FROM
            msg['To']      = r['email']
            msg.attach(MIMEText(personalized, 'html'))
            with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
                server.ehlo()
                server.starttls()
                server.login(SMTP_USER, SMTP_PASSWORD)
                server.sendmail(SMTP_USER, r['email'], msg.as_string())
            print(f'✅ Notification email → {r["email"]}')
            sent += 1
        except Exception as e:
            print(f'❌ Notification email error → {r["email"]}: {e}')
            errors.append({'email': r['email'], 'error': str(e)})

    return jsonify({'ok': True, 'sent': sent, 'errors': errors})


@app.route('/api/send-booking-email', methods=['POST'])
def send_booking_email():
    """
    Send a booking confirmation email to admin/staff when a customer books a service.

    Request body:
        customer_name  : str  – customer who made the booking
        vehicles       : list – [{ plate, desc, services: [str] }]
        preferred_date : str  – e.g. "Aug 12, 2026"
        preferred_time : str  – e.g. "10:00 AM"
        notes          : str  – optional customer notes
        target_roles   : list – ["admin", "staff"] — which roles to email
    """
    import firebase_admin.firestore as _fs

    data           = request.get_json(silent=True) or {}
    customer_name  = data.get('customer_name', 'Customer').strip()
    vehicles       = data.get('vehicles', [])        # list of {plate, desc, services}
    preferred_date = data.get('preferred_date', '').strip()
    preferred_time = data.get('preferred_time', '').strip()
    notes          = data.get('notes', '').strip()
    target_roles   = data.get('target_roles', ['admin', 'staff'])

    if not vehicles or not preferred_date or not preferred_time:
        return jsonify({'ok': False, 'error': 'Missing required fields'}), 400

    # ── Build per-vehicle rows for the email ──
    vehicle_rows = ''
    for v in vehicles:
        plate = v.get('plate', '—')
        desc  = v.get('desc', '')
        svcs  = ', '.join(v.get('services', []))
        vehicle_rows += f"""
        <tr>
          <td style="padding:10px 14px;font-size:13px;font-weight:600;
                     color:#1a202c;border-bottom:1px solid #f0f4f8;">{plate}</td>
          <td style="padding:10px 14px;font-size:12px;color:#718096;
                     border-bottom:1px solid #f0f4f8;">{desc}</td>
          <td style="padding:10px 14px;font-size:12px;color:#E8001C;font-weight:600;
                     border-bottom:1px solid #f0f4f8;">{svcs}</td>
        </tr>"""

    notes_row = ''
    if notes:
        notes_row = f"""
        <div style="margin-top:18px;background:#fffbeb;border-left:4px solid #d97706;
                    border-radius:0 10px 10px 0;padding:12px 16px;">
          <p style="margin:0;font-size:12px;font-weight:700;color:#92400e;">
            📝 Customer Notes
          </p>
          <p style="margin:6px 0 0;font-size:13px;color:#1a202c;">{notes}</p>
        </div>"""

    html_template = f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">
  <tr><td align="center">
    <table width="560" cellpadding="0" cellspacing="0"
           style="background:#fff;border-radius:16px;overflow:hidden;
                  box-shadow:0 4px 24px rgba(0,0,0,.10);">
      <!-- Header -->
      <tr>
        <td style="background:#E8001C;padding:30px 40px 0;text-align:center;">
          <div style="font-size:13px;font-weight:700;letter-spacing:4px;
                      color:rgba(255,255,255,.8);margin-bottom:6px;">CALTEX</div>
          <div style="font-size:22px;font-weight:800;color:#fff;letter-spacing:2px;">AutoPro</div>
          <div style="background:#fff;border-radius:24px 24px 0 0;height:22px;margin-top:20px;"></div>
        </td>
      </tr>
      <!-- Body -->
      <tr>
        <td style="padding:8px 40px 36px;">
          <!-- Badge -->
          <div style="text-align:center;margin-bottom:18px;">
            <span style="display:inline-block;background:#003087;
                         border-radius:24px;padding:7px 20px;
                         font-size:12px;font-weight:700;color:#fff;letter-spacing:0.5px;">
              📅 &nbsp;New Service Booking
            </span>
          </div>
          <p style="margin:0 0 20px;font-size:13px;color:#718096;
                    text-align:center;line-height:1.7;">
            A customer has booked a service appointment.<br/>
            Please review the details below.
          </p>

          <!-- Info cards row -->
          <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:20px;">
            <tr>
              <td width="50%" style="padding-right:8px;vertical-align:top;">
                <div style="background:#f7f8fa;border-radius:10px;padding:14px 16px;">
                  <div style="font-size:10px;font-weight:700;color:#a0aec0;
                               text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">
                    Customer
                  </div>
                  <div style="font-size:14px;font-weight:700;color:#1a202c;">
                    {customer_name}
                  </div>
                </div>
              </td>
              <td width="50%" style="padding-left:8px;vertical-align:top;">
                <div style="background:#f7f8fa;border-radius:10px;padding:14px 16px;">
                  <div style="font-size:10px;font-weight:700;color:#a0aec0;
                               text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">
                    Date &amp; Time
                  </div>
                  <div style="font-size:13px;font-weight:700;color:#1a202c;">
                    {preferred_date}
                  </div>
                  <div style="font-size:12px;color:#718096;margin-top:2px;">
                    {preferred_time}
                  </div>
                </div>
              </td>
            </tr>
          </table>

          <!-- Vehicle & services table -->
          <div style="font-size:11px;font-weight:700;color:#4a5568;
                      text-transform:uppercase;letter-spacing:0.5px;margin-bottom:8px;">
            Vehicles &amp; Services
          </div>
          <table width="100%" cellpadding="0" cellspacing="0"
                 style="border:1px solid #e2e8f0;border-radius:10px;overflow:hidden;
                        border-collapse:separate;border-spacing:0;">
            <thead>
              <tr style="background:#f7f8fa;">
                <th style="padding:9px 14px;font-size:11px;font-weight:700;color:#718096;
                           text-align:left;border-bottom:1px solid #e2e8f0;">Plate</th>
                <th style="padding:9px 14px;font-size:11px;font-weight:700;color:#718096;
                           text-align:left;border-bottom:1px solid #e2e8f0;">Vehicle</th>
                <th style="padding:9px 14px;font-size:11px;font-weight:700;color:#718096;
                           text-align:left;border-bottom:1px solid #e2e8f0;">Services</th>
              </tr>
            </thead>
            <tbody>{vehicle_rows}</tbody>
          </table>

          {notes_row}

          <!-- Status badge -->
          <div style="margin-top:20px;text-align:center;">
            <span style="display:inline-block;background:#f0fdf4;
                         border:1.5px solid #c6f6d5;border-radius:20px;
                         padding:6px 18px;font-size:12px;font-weight:700;color:#276749;">
              ✅ &nbsp;Status: Confirmed
            </span>
          </div>

          <p style="margin:20px 0 0;font-size:12px;color:#a0aec0;
                    text-align:center;line-height:1.6;">
            Log in to the AutoPro admin portal to view or manage this booking.
          </p>
        </td>
      </tr>
      <!-- Footer -->
      <tr>
        <td style="background:#f7f8fa;padding:18px 40px;text-align:center;
                   border-top:1px solid #e2e8f0;">
          <p style="margin:0;font-size:11px;color:#a0aec0;line-height:1.6;">
            &copy; 2025 AutoPro &middot; JA Noble Enterprise Inc<br/>
            102 National Highway, Brgy. Landayan, San Pedro, Laguna<br/>
            This is an automated message &mdash; please do not reply.
          </p>
        </td>
      </tr>
    </table>
  </td></tr>
</table>
</body>
</html>"""

    # ── Fetch admin & staff emails from Firestore ──
    try:
        fdb = _fs.client()
        recipients = []
        for role in target_roles:
            docs = fdb.collection('users').where('role', '==', role).stream()
            for doc in docs:
                d = doc.to_dict()
                email = (d.get('email') or '').strip()
                name  = (d.get('name')  or role.capitalize()).strip()
                if email:
                    recipients.append({'email': email, 'name': name})
    except Exception as e:
        print(f'❌ Firestore lookup error: {e}')
        return jsonify({'ok': False, 'error': f'Firestore lookup failed: {e}'}), 500

    if not recipients:
        print('⚠️ send-booking-email: no recipients found for roles', target_roles)
        return jsonify({'ok': True, 'sent': 0, 'note': 'No recipients found'})

    # ── Send one email per recipient ──
    sent = 0
    errors = []
    for r in recipients:
        personalized = html_template.replace(
            'Please review the details below.',
            f'Hi <strong>{r["name"]}</strong>, please review the details below.'
        )
        try:
            msg = MIMEMultipart('alternative')
            msg['Subject'] = f'📅 New Service Booking — {customer_name}'
            msg['From']    = SMTP_FROM
            msg['To']      = r['email']
            msg.attach(MIMEText(personalized, 'html'))
            with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
                server.ehlo()
                server.starttls()
                server.login(SMTP_USER, SMTP_PASSWORD)
                server.sendmail(SMTP_USER, r['email'], msg.as_string())
            print(f'✅ Booking email → {r["email"]}')
            sent += 1
        except Exception as e:
            print(f'❌ Booking email error → {r["email"]}: {e}')
            errors.append({'email': r['email'], 'error': str(e)})

    return jsonify({'ok': True, 'sent': sent, 'errors': errors})


@app.route('/api/send-alert-email', methods=['POST'])
def send_alert_email():
    """
    Send an alert/notification email to a user.
    Called by the Flutter background_dss task when emailEnabled = true.

    Request body:
        to_email  : str  – recipient email address
        to_name   : str  – recipient display name (optional)
        title     : str  – notification title  (e.g. "PMS Overdue")
        message   : str  – notification body
        type      : str  – "warning" | "info" | "success"
    """
    data       = request.get_json(silent=True) or {}
    to_email   = data.get('to_email', '').strip()
    to_name    = data.get('to_name',  '').strip() or 'AutoPro User'
    title      = data.get('title',    'AutoPro Notification').strip()
    message    = data.get('message',  '').strip()
    notif_type = data.get('type',     'info').strip()

    if not to_email or not message:
        return jsonify({'ok': False, 'error': 'Missing to_email or message'}), 400

    colour_map = {'warning': '#E8001C', 'success': '#38a169', 'info': '#003087'}
    icon_map   = {'warning': '⚠️',      'success': '✅',       'info': 'ℹ️'}
    accent = colour_map.get(notif_type, '#003087')
    icon   = icon_map.get(notif_type, 'ℹ️')
    subject = f'{icon} {title}'

    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">
  <tr><td align="center">
    <table width="520" cellpadding="0" cellspacing="0"
           style="background:#fff;border-radius:16px;overflow:hidden;
                  box-shadow:0 4px 24px rgba(0,0,0,.10);">
      <tr>
        <td style="background:#E8001C;padding:30px 40px 0;text-align:center;">
          <div style="font-size:13px;font-weight:700;letter-spacing:4px;
                      color:rgba(255,255,255,.8);margin-bottom:6px;">CALTEX</div>
          <div style="font-size:22px;font-weight:800;color:#fff;letter-spacing:2px;">AutoPro</div>
          <div style="background:#fff;border-radius:24px 24px 0 0;height:22px;margin-top:20px;"></div>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 40px 40px;">
          <div style="text-align:center;margin-bottom:18px;">
            <span style="display:inline-block;background:{accent}18;
                         border:1.5px solid {accent}40;border-radius:24px;
                         padding:6px 18px;font-size:12px;font-weight:700;
                         color:{accent};letter-spacing:0.5px;">
              {icon}&nbsp; {title}
            </span>
          </div>
          <p style="margin:0 0 20px;text-align:center;font-size:13px;
                    color:#718096;line-height:1.6;">
            Hi <strong>{to_name}</strong>,<br/>
            You have a new notification from the AutoPro system.
          </p>
          <div style="background:#f7f8fa;border-left:4px solid {accent};
                      border-radius:0 10px 10px 0;padding:16px 20px;margin-bottom:26px;">
            <p style="margin:0;font-size:14px;font-weight:600;
                      color:#1a202c;line-height:1.6;">{message}</p>
          </div>
          <p style="margin:0 0 6px;font-size:12px;color:#a0aec0;
                    text-align:center;line-height:1.6;">
            You are receiving this because you have <strong>Email Notifications</strong>
            enabled in your AutoPro alert settings.<br/>
            To manage preferences: AutoPro app → Notifications → Manage Alerts.
          </p>
          <hr style="border:none;border-top:1px solid #e2e8f0;margin:24px 0;"/>
          <p style="margin:0;font-size:12px;color:#a0aec0;text-align:center;line-height:1.6;">
            Need help? Contact us at
            <a href="mailto:janobleenterprisesinc@gmail.com"
               style="color:#E8001C;">janobleenterprisesinc@gmail.com</a>
          </p>
        </td>
      </tr>
      <tr>
        <td style="background:#f7f8fa;padding:18px 40px;text-align:center;
                   border-top:1px solid #e2e8f0;">
          <p style="margin:0;font-size:11px;color:#a0aec0;line-height:1.6;">
            &copy; 2025 AutoPro &middot; JA Noble Enterprise Inc<br/>
            102 National Highway, Brgy. Landayan, San Pedro, Laguna<br/>
            This is an automated message &mdash; please do not reply.
          </p>
        </td>
      </tr>
    </table>
  </td></tr>
</table>
</body>
</html>"""

    try:
        msg = MIMEMultipart('alternative')
        msg['Subject'] = subject
        msg['From']    = SMTP_FROM
        msg['To']      = to_email
        msg.attach(MIMEText(html_body, 'html'))
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.ehlo()
            server.starttls()
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(SMTP_USER, to_email, msg.as_string())
        print(f'✅ Alert email delivered → {to_email} [{title}]')
        return jsonify({'ok': True})
    except smtplib.SMTPAuthenticationError:
        print(f'❌ SMTP auth failed → {to_email}')
        return jsonify({'ok': False, 'error': 'SMTP auth failed'}), 500
    except Exception as e:
        print(f'❌ Alert email error → {to_email}: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/api/send-reschedule-email', methods=['POST'])
def send_reschedule_email():
    """Send email notification when a booking is rescheduled by admin."""
    data      = request.get_json(silent=True) or {}
    to_email  = data.get('to_email', '').strip()
    to_name   = data.get('to_name', 'Customer').strip()
    plate     = data.get('plate', '').strip()
    old_date  = data.get('old_date', '').strip()
    new_date  = data.get('new_date', '').strip()
    services  = data.get('services', '').strip()

    if not to_email:
        return jsonify({'ok': False, 'error': 'Missing to_email'}), 400

    print(f'📧 Sending reschedule email → {to_email} ({to_name})')

    subject = 'Your Booking Has Been Rescheduled'
    html_body = f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"/></head>
<body style="margin:0;padding:0;background:#f0f2f5;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f0f2f5;padding:40px 0;">
  <tr><td align="center">
    <table width="520" cellpadding="0" cellspacing="0"
           style="background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,.10);">
      <tr>
        <td style="background:#E8001C;padding:30px 40px 0;text-align:center;">
          <div style="font-size:13px;font-weight:700;letter-spacing:4px;color:rgba(255,255,255,.8);margin-bottom:6px;">CALTEX</div>
          <div style="font-size:22px;font-weight:800;color:#fff;letter-spacing:2px;">AutoPro</div>
          <div style="background:#fff;border-radius:24px 24px 0 0;height:22px;margin-top:20px;"></div>
        </td>
      </tr>
      <tr>
        <td style="padding:8px 40px 40px;">
          <h1 style="margin:0 0 8px;text-align:center;font-size:22px;font-weight:800;color:#1a202c;">Booking Rescheduled</h1>
          <p style="margin:0 0 26px;text-align:center;font-size:13px;color:#718096;line-height:1.6;">
            Hi <strong>{to_name}</strong>,<br/>
            Your service booking has been rescheduled by the shop administrator.
          </p>
          <div style="background:#fffbeb;border:1px solid #f6e05e;border-radius:12px;padding:20px 24px;margin-bottom:26px;">
            <table cellpadding="0" cellspacing="0" width="100%">
              <tr>
                <td style="padding:8px 0;font-size:12px;color:#718096;font-weight:700;text-transform:uppercase;width:130px;">Vehicle</td>
                <td style="padding:8px 0;font-size:14px;font-weight:700;color:#1a202c;">{plate}</td>
              </tr>
              <tr style="border-top:1px solid #e2e8f0;">
                <td style="padding:8px 0;font-size:12px;color:#718096;font-weight:700;text-transform:uppercase;">Services</td>
                <td style="padding:8px 0;font-size:13px;color:#4a5568;">{services}</td>
              </tr>
              <tr style="border-top:1px solid #e2e8f0;">
                <td style="padding:8px 0;font-size:12px;color:#718096;font-weight:700;text-transform:uppercase;">Previous Date</td>
                <td style="padding:8px 0;font-size:13px;color:#e53e3e;font-weight:600;text-decoration:line-through;">{old_date}</td>
              </tr>
              <tr style="border-top:1px solid #e2e8f0;">
                <td style="padding:8px 0;font-size:12px;color:#718096;font-weight:700;text-transform:uppercase;">New Date</td>
                <td style="padding:8px 0;font-size:14px;color:#38a169;font-weight:700;">{new_date}</td>
              </tr>
            </table>
          </div>
          <p style="margin:0 0 10px;font-size:13px;color:#4a5568;text-align:center;line-height:1.6;">
            If you have any concerns about this change, please contact us or visit the shop during business hours.
          </p>
          <div style="text-align:center;margin-top:20px;">
            <span style="display:inline-block;background:#f7f8fa;border-radius:8px;padding:10px 20px;font-size:12px;color:#718096;">
              Shop Hours: Mon-Sat 8:00 AM - 5:00 PM | Sunday: Closed
            </span>
          </div>
          <hr style="border:none;border-top:1px solid #e2e8f0;margin:26px 0;"/>
          <p style="margin:0;font-size:12px;color:#a0aec0;text-align:center;line-height:1.6;">
            Need help? Contact us at <a href="mailto:caltexautopro2026@gmail.com" style="color:#E8001C;">caltexautopro2026@gmail.com</a>
          </p>
        </td>
      </tr>
      <tr>
        <td style="background:#f7f8fa;padding:18px 40px;text-align:center;border-top:1px solid #e2e8f0;">
          <p style="margin:0;font-size:11px;color:#a0aec0;line-height:1.6;">
            &copy; 2025 AutoPro &middot; JA Noble Enterprise INC<br/>
            This is an automated message &mdash; please do not reply.
          </p>
        </td>
      </tr>
    </table>
  </td></tr>
</table>
</body>
</html>"""

    try:
        msg = MIMEMultipart('alternative')
        msg['Subject'] = subject
        msg['From']    = SMTP_FROM
        msg['To']      = to_email
        msg.attach(MIMEText(html_body, 'html'))
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.ehlo()
            server.starttls()
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(SMTP_USER, to_email, msg.as_string())
        print(f'✅ Reschedule email delivered → {to_email}')
        return jsonify({'ok': True})
    except smtplib.SMTPAuthenticationError:
        print(f'❌ SMTP auth failed for reschedule email → {to_email}')
        return jsonify({'ok': False, 'error': 'SMTP auth failed'}), 500
    except Exception as e:
        print(f'❌ Reschedule email error → {to_email}: {e}')
        return jsonify({'ok': False, 'error': str(e)}), 500




def _offline_response():
    return jsonify({'success': False,
                    'error': 'AI service offline. Start it with ai_assistant\\start.bat'}), 503


@app.route('/setup_notifications.html')
def setup_notifications():
    """Setup page to create notifications collection in Firestore"""
    return render_template('setup_notifications.html')

@app.route('/fix_item_numbers.html')
def fix_item_numbers():
    """One-time utility to fix duplicate item numbers in item_master"""
    return render_template('fix_item_numbers.html')

@app.route('/admin_archive.html')
def admin_archive():
    """Archive page for archived item master records"""
    return render_template('admin_archive.html')


# ── Run ──────────────────────────────────────────────────────
if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5001))
    app.run(debug=False, host='0.0.0.0', port=port)

