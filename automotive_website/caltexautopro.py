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
        os.path.join(os.path.dirname(__file__), 'firebase-credentials.json'),
        os.path.join(os.path.dirname(__file__), '..', 'firebase-credentials.json'),
        os.path.join(os.path.expanduser('~'), 'serviceAccountKey.json'),
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
app.secret_key = 'your-secret-key-change-this-in-production'
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
    """Quick liveness ping to the AI backend."""
    try:
        r = _requests_lib.get(f'{_AI_BACKEND_URL}/health', timeout=3)
        return r.status_code == 200
    except Exception:
        return False


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
        if not customer_uid or not customer_name:
            return jsonify({
                'success': False, 'offline': True,
                'answer': 'Customer identity missing. Please log in again.',
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
            return jsonify({'success': False, 'offline': True,
                            'answer': 'The AI service timed out. Please try again.'}), 503
        except Exception as e:
            return jsonify({'success': False, 'offline': True,
                            'answer': f'AI service error: {e}'}), 503

    # ── Admin chat ────────────────────────────────────────────────────────────
    if user_type != 'admin':
        return jsonify({'success': False, 'offline': True,
                        'answer': 'Unknown user type.'}), 400

    try:
        resp = _requests_lib.post(
            f'{_AI_BACKEND_URL}/admin/chat',
            json={'message': message, 'session_id': session_id},
            timeout=60,
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
            'answer':       payload.get('reply', ''),
            'session_id':   payload.get('session_id', ''),
            'rate_limited': payload.get('rate_limited', False),
            'reset_in':     payload.get('reset_in', ''),
            'tool_calls':   payload.get('tool_calls', []),
        })
    except _requests_lib.exceptions.ConnectionError:
        return jsonify({
            'success': False,
            'offline': True,
            'answer': 'The AI service is offline. Start it with: ai_assistant\\start.bat',
        }), 503
    except _requests_lib.exceptions.Timeout:
        return jsonify({
            'success': False,
            'offline': True,
            'answer': 'The AI service timed out. Please try again.',
        }), 503
    except Exception as e:
        return jsonify({
            'success': False,
            'offline': True,
            'answer': f'AI service error: {e}',
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

        resp = _requests_lib.post(
            f'{_AI_BACKEND_URL}/admin/report',
            params=params,
            json=filters if filters else None,   # body → filters dict
            timeout=90,
        )

        # Surface 400 errors (no records / future date) as JSON so the
        # frontend can show the real message instead of a generic failure.
        if resp.status_code == 400:
            try:
                detail = resp.json().get('detail', 'Report generation failed.')
            except Exception:
                detail = 'Report generation failed.'
            return jsonify({'success': False, 'error': detail}), 400

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
    except _requests_lib.exceptions.ConnectionError:
        return jsonify({'success': False, 'error': 'AI service offline'}), 503
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

# ── AI Settings page route ───────────────────────────────────────────────────
@app.route('/admin_ai_settings.html')
def admin_ai_settings():
    return render_template('admin_ai_settings.html')


# ── AI Settings API proxy ─────────────────────────────────────────────────────
# The Flask server proxies all /api/ai-settings/* requests to the FastAPI
# ai_assistant service.
#
# IMPORTANT: The ai_settings endpoints live on the LOCAL ai_assistant service
# (port 8001) — NOT the remote Render deployment.  We always talk to localhost
# for these management calls so they work whether the app is running locally or
# on a server.  The standard _AI_BACKEND_URL may point at Render for chat, but
# key management must only ever touch the locally-running instance.

_AI_ADMIN_TOKEN = os.environ.get('AI_ADMIN_TOKEN', 'caltex-admin-ai-2026')

# Local FastAPI URL — always localhost:8001 for AI settings management.
# Override with AI_SETTINGS_URL env var if your setup uses a different port.
_AI_SETTINGS_URL = os.environ.get('AI_SETTINGS_URL', 'http://localhost:8001').rstrip('/')


def _ai_settings_headers():
    """Common headers for AI settings requests to the FastAPI service."""
    return {
        'Content-Type': 'application/json',
        'X-Admin-Token': _AI_ADMIN_TOKEN,
    }


def _ai_settings_get(path, **kwargs):
    """GET helper that always uses the local AI service URL."""
    return _requests_lib.get(f'{_AI_SETTINGS_URL}{path}',
                              headers=_ai_settings_headers(), **kwargs)


def _ai_settings_post(path, **kwargs):
    return _requests_lib.post(f'{_AI_SETTINGS_URL}{path}',
                               headers=_ai_settings_headers(), **kwargs)


def _ai_settings_put(path, **kwargs):
    return _requests_lib.put(f'{_AI_SETTINGS_URL}{path}',
                              headers=_ai_settings_headers(), **kwargs)


def _ai_settings_delete(path, **kwargs):
    return _requests_lib.delete(f'{_AI_SETTINGS_URL}{path}',
                                 headers=_ai_settings_headers(), **kwargs)


def _offline_response():
    return jsonify({'success': False,
                    'error': 'AI service offline. Start it with ai_assistant\\start.bat'}), 503


@app.route('/api/ai-settings/status', methods=['GET'])
def ai_settings_status():
    """Get current AI service status and API key table."""
    try:
        resp = _ai_settings_get('/ai-settings/status', timeout=10)
        resp.raise_for_status()
        return jsonify(resp.json())
    except _requests_lib.exceptions.ConnectionError:
        return jsonify({'error': 'AI service offline'}), 503
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/ai-settings/logs', methods=['GET'])
def ai_settings_logs():
    """Get recent AI event log."""
    try:
        resp = _ai_settings_get('/ai-settings/logs', timeout=10)
        resp.raise_for_status()
        return jsonify(resp.json())
    except _requests_lib.exceptions.ConnectionError:
        return _offline_response()
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/ai-settings/keys', methods=['POST'])
def ai_settings_add_key():
    """Add a new Groq API key."""
    data = request.get_json(silent=True) or {}
    try:
        resp = _ai_settings_post('/ai-settings/keys', json=data, timeout=15)
        resp.raise_for_status()
        return jsonify(resp.json())
    except _requests_lib.exceptions.ConnectionError:
        return _offline_response()
    except _requests_lib.exceptions.HTTPError as e:
        try:
            detail = e.response.json().get('detail', str(e))
        except Exception:
            detail = str(e)
        return jsonify({'success': False, 'error': detail}), e.response.status_code
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# NOTE: /test must be registered BEFORE /<key_id> so Flask does not treat the
# literal string "test" as a key_id value.
@app.route('/api/ai-settings/keys/test', methods=['POST'])
def ai_settings_test_key():
    """Test a Groq API key connection without saving it."""
    data = request.get_json(silent=True) or {}
    try:
        resp = _ai_settings_post('/ai-settings/keys/test', json=data, timeout=30)
        resp.raise_for_status()
        return jsonify(resp.json())
    except _requests_lib.exceptions.ConnectionError:
        return _offline_response()
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/ai-settings/keys/<key_id>', methods=['PUT'])
def ai_settings_update_key(key_id):
    """Update an existing API key."""
    data = request.get_json(silent=True) or {}
    try:
        resp = _ai_settings_put(f'/ai-settings/keys/{key_id}', json=data, timeout=15)
        resp.raise_for_status()
        return jsonify(resp.json())
    except _requests_lib.exceptions.ConnectionError:
        return _offline_response()
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/ai-settings/keys/<key_id>', methods=['DELETE'])
def ai_settings_delete_key(key_id):
    """Delete an API key."""
    try:
        resp = _ai_settings_delete(f'/ai-settings/keys/{key_id}', timeout=10)
        resp.raise_for_status()
        return jsonify(resp.json())
    except _requests_lib.exceptions.ConnectionError:
        return _offline_response()
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/ai-settings/rotation', methods=['PUT'])
def ai_settings_rotation():
    """Update rotation settings."""
    data = request.get_json(silent=True) or {}
    try:
        resp = _ai_settings_put('/ai-settings/rotation', json=data, timeout=10)
        resp.raise_for_status()
        return jsonify(resp.json())
    except _requests_lib.exceptions.ConnectionError:
        return _offline_response()
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/ai-settings/reload', methods=['POST'])
def ai_settings_reload():
    """Force-reload API keys from Firestore."""
    try:
        resp = _ai_settings_post('/ai-settings/reload', timeout=10)
        resp.raise_for_status()
        return jsonify(resp.json())
    except _requests_lib.exceptions.ConnectionError:
        return _offline_response()
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


# ── Run ──────────────────────────────────────────────────────
if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5001)


# ── Setup / Admin Tools ──────────────────────────────────────
@app.route('/setup_notifications.html')
def setup_notifications():
    """Setup page to create notifications collection in Firestore"""
    return render_template('setup_notifications.html')

@app.route('/fix_item_numbers.html')
def fix_item_numbers():
    """One-time utility to fix duplicate item numbers in item_master"""
    return render_template('fix_item_numbers.html')

