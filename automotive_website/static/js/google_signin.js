/**
 * Google Sign-In Handler Module
 * After Google auth succeeds → sends OTP to user's email → verifies → redirects
 */

// ── OTP overlay HTML (injected into the page) ─────────────────────────────
function _gsInjectOtpOverlay() {
  if (document.getElementById('_gsOtpOverlay')) return;
  const overlay = document.createElement('div');
  overlay.id = '_gsOtpOverlay';
  overlay.style.cssText = [
    'position:fixed;inset:0;z-index:99999;',
    'display:none;align-items:center;justify-content:center;',
    'background:rgba(0,0,0,0.55);backdrop-filter:blur(4px);',
  ].join('');
  overlay.innerHTML = `
    <div style="background:#fff;border-radius:20px;width:360px;max-width:92vw;overflow:hidden;
                box-shadow:0 20px 60px rgba(0,0,0,0.25);animation:_gsFadeIn 0.22s ease;">
      <!-- Header -->
      <div style="background:linear-gradient(135deg,#E8001C,#9B0013);padding:1.25rem 1.5rem;
                  display:flex;align-items:center;gap:0.75rem;">
        <div style="width:40px;height:40px;background:rgba(255,255,255,0.18);border-radius:10px;
                    display:flex;align-items:center;justify-content:center;flex-shrink:0;">
          <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"
               fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07A19.5 19.5 0 0 1 4.99 12
                     19.79 19.79 0 0 1 1.97 3.5 2 2 0 0 1 3.95 1.36h3a2 2 0 0 1 2 1.72
                     12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91
                     a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7
                     A2 2 0 0 1 22 16.92z"/>
          </svg>
        </div>
        <div>
          <div style="color:#fff;font-size:0.95rem;font-weight:700;line-height:1.2;">Verify Your Identity</div>
          <div id="_gsOtpSubtitle" style="color:rgba(255,255,255,0.75);font-size:0.75rem;margin-top:2px;"></div>
        </div>
      </div>
      <!-- Body -->
      <div style="padding:1.5rem;">
        <p style="font-size:0.82rem;color:#718096;margin:0 0 1rem;text-align:center;line-height:1.6;">
          A 6-digit verification code was sent to your email.<br/>
          <span style="font-size:0.75rem;color:#a0aec0;">Expires in 5 minutes.</span>
        </p>
        <!-- OTP boxes -->
        <div id="_gsOtpRow" style="display:flex;gap:0.5rem;justify-content:center;margin-bottom:1rem;">
          ${[0,1,2,3,4,5].map(i =>
            `<input id="_gsOtp${i}" type="text" maxlength="1" inputmode="numeric"
              style="width:44px;height:52px;text-align:center;font-size:1.3rem;font-weight:700;
                     border:2px solid #e2e8f0;border-radius:10px;outline:none;
                     transition:border-color 0.15s;font-family:monospace;"
              onfocus="this.style.borderColor='#E8001C'"
              onblur="this.style.borderColor='#e2e8f0'">`
          ).join('')}
        </div>
        <!-- Error msg -->
        <div id="_gsOtpError" style="display:none;background:#fff5f5;border:1px solid #fecaca;
             border-radius:8px;padding:0.5rem 0.75rem;font-size:0.78rem;color:#c53030;
             margin-bottom:0.75rem;text-align:center;"></div>
        <!-- Verify button -->
        <button id="_gsOtpVerifyBtn"
          style="width:100%;padding:0.85rem;background:linear-gradient(135deg,#E8001C,#9B0013);
                 border:none;border-radius:10px;color:#fff;font-weight:700;font-size:0.95rem;
                 cursor:pointer;display:flex;align-items:center;justify-content:center;gap:0.5rem;
                 transition:opacity 0.2s;">
          Verify &amp; Continue
        </button>
        <!-- Resend -->
        <p style="text-align:center;margin:0.75rem 0 0;font-size:0.78rem;color:#718096;">
          Didn't receive the code?
          <button id="_gsResendBtn" type="button"
            style="background:none;border:none;color:#E8001C;font-weight:600;cursor:pointer;
                   font-size:0.78rem;padding:0;">Resend</button>
        </p>
      </div>
    </div>
    <style>
      @keyframes _gsFadeIn { from{opacity:0;transform:scale(0.96)} to{opacity:1;transform:scale(1)} }
    </style>
  `;
  document.body.appendChild(overlay);
  _gsBindOtpInputs();
}

// ── OTP input behaviour ────────────────────────────────────────────────────
function _gsBindOtpInputs() {
  for (let i = 0; i < 6; i++) {
    const box = document.getElementById('_gsOtp' + i);
    if (!box) continue;
    box.addEventListener('input', e => {
      box.value = e.target.value.replace(/\D/g, '').slice(0, 1);
      if (box.value && i < 5) document.getElementById('_gsOtp' + (i + 1)).focus();
      if (_gsAllFilled()) setTimeout(() => document.getElementById('_gsOtpVerifyBtn').click(), 80);
    });
    box.addEventListener('keydown', e => {
      if (e.key === 'Backspace') {
        if (box.value) { box.value = ''; } else if (i > 0) { document.getElementById('_gsOtp' + (i - 1)).focus(); }
      }
    });
    box.addEventListener('paste', e => {
      e.preventDefault();
      const digits = (e.clipboardData.getData('text') || '').replace(/\D/g, '').slice(0, 6);
      digits.split('').forEach((d, idx) => {
        const b = document.getElementById('_gsOtp' + idx);
        if (b) b.value = d;
      });
      const next = document.getElementById('_gsOtp' + Math.min(digits.length, 5));
      if (next) next.focus();
      if (_gsAllFilled()) setTimeout(() => document.getElementById('_gsOtpVerifyBtn').click(), 80);
    });
  }
}

function _gsAllFilled() {
  for (let i = 0; i < 6; i++) {
    const b = document.getElementById('_gsOtp' + i);
    if (!b || !b.value) return false;
  }
  return true;
}

function _gsGetOtpValue() {
  return [0,1,2,3,4,5].map(i => (document.getElementById('_gsOtp' + i) || {}).value || '').join('');
}

function _gsShowOtpOverlay(email) {
  _gsInjectOtpOverlay();
  const sub = document.getElementById('_gsOtpSubtitle');
  if (sub) sub.textContent = email;
  // Clear boxes and error
  for (let i = 0; i < 6; i++) {
    const b = document.getElementById('_gsOtp' + i);
    if (b) b.value = '';
  }
  const err = document.getElementById('_gsOtpError');
  if (err) { err.style.display = 'none'; err.textContent = ''; }
  const overlay = document.getElementById('_gsOtpOverlay');
  overlay.style.display = 'flex';
  setTimeout(() => { const b = document.getElementById('_gsOtp0'); if (b) b.focus(); }, 100);
}

function _gsHideOtpOverlay() {
  const overlay = document.getElementById('_gsOtpOverlay');
  if (overlay) overlay.style.display = 'none';
}

// ── Send OTP via server (dedicated endpoint — not the reset-password template) ──
async function _gsSendOtp(email, name) {
  const res = await fetch('/api/send-google-otp', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ to_email: email, to_name: name || email }),
  });
  const data = await res.json();
  if (!data.ok) throw new Error(data.error || 'Failed to send OTP email');
}

// ── Verify OTP ─────────────────────────────────────────────────────────────
async function _gsVerifyOtp(email, entered) {
  const snap = await firebase.firestore().collection('otp_requests').doc(email).get();
  if (!snap.exists) throw new Error('OTP not found. Please request a new one.');
  const { otp: stored, expiry } = snap.data();
  // Ensure expiry is parsed as UTC (append Z if missing)
  const expiryStr = expiry && !expiry.endsWith('Z') ? expiry + 'Z' : expiry;
  if (new Date() > new Date(expiryStr)) {
    await snap.ref.delete();
    throw new Error('OTP has expired. Please try again.');
  }
  if (entered !== stored) throw new Error('Incorrect OTP. Please try again.');
  await snap.ref.delete();
}

// ── Main module ────────────────────────────────────────────────────────────
const GoogleSignInModule = {
  _pendingUser: null,
  _pendingUserData: null,

  init: function() {
    console.log('GoogleSignInModule initialized');
    this.setupGoogleButton();
    _gsInjectOtpOverlay();
    this.checkRedirectResult();
  },

  setupGoogleButton: function() {
    const googleBtn = document.getElementById('googleBtn');
    if (!googleBtn) { console.warn('Google button not found'); return; }
    googleBtn.addEventListener('click', () => this.handleGoogleSignIn());
    console.log('Google button event listener attached');
  },

  handleGoogleSignIn: async function() {
    const googleBtn = document.getElementById('googleBtn');
    this.setButtonLoading(googleBtn, true);

    try {
      const provider = new firebase.auth.GoogleAuthProvider();
      provider.addScope('profile');
      provider.addScope('email');
      provider.setCustomParameters({ prompt: 'select_account' }); // always show account picker

      let user = null;
      try {
        const result = await firebase.auth().signInWithPopup(provider);
        user = result.user;
      } catch (popupError) {
        const code = popupError && popupError.code;
        const popupBlocked = (
          code === 'auth/popup-blocked' ||
          code === 'auth/popup-failed-to-open'
        );
        if (!popupBlocked) throw popupError;

        // Popup blocked (embedded browser, strict blocker, in-app webview…)
        // → fall back to a full-page redirect, which cannot be blocked.
        console.log('Popup blocked (' + code + ') — falling back to signInWithRedirect');
        sessionStorage.setItem('pendingGoogleSignIn', '1');
        // Safety net: if navigation never happens (some embedded webviews abort
        // external redirects), restore the button instead of spinning forever.
        // In normal browsers the page navigates away and this never fires.
        setTimeout(() => {
          if (firebase.auth().currentUser) return; // redirect completed elsewhere
          try { sessionStorage.removeItem('pendingGoogleSignIn'); } catch (_) {}
          this.setButtonLoading(googleBtn, false);
          this.showToast('Could not open Google Sign-In here. Please open this page in Chrome or Edge.', 'error');
        }, 8000);
        try {
          await firebase.auth().signInWithRedirect(provider);
        } catch (redirectError) {
          sessionStorage.removeItem('pendingGoogleSignIn');
          throw redirectError;
        }
        return; // page navigates away — flow continues in checkRedirectResult()
      }

      await this._continueAfterGoogleAuth(user, googleBtn);

    } catch (error) {
      console.error('Google Sign-In error:', error);
      this.setButtonLoading(googleBtn, false);
      const code = error && error.code;
      if (code === 'auth/popup-closed-by-user' || code === 'auth/cancelled-popup-request') {
        return; // user closed the picker — stay silent
      }
      this.showToast(this._friendlyError(error), 'error');
    }
  },

  // Runs after Google auth succeeded (via popup OR redirect): validate the
  // Firestore account, then start the OTP verification step.
  _continueAfterGoogleAuth: async function(user, googleBtn) {
    // Lookup user in Firestore
    const userData = await this.getOrCreateUser(user);

    // Validate status
    if (userData.status === 'inactive') {
      await firebase.auth().signOut();
      this.showToast('Your account has been deactivated. Please contact the administrator.', 'error');
      this.setButtonLoading(googleBtn, false);
      return;
    }
    if (userData.status === 'pending') {
      await firebase.auth().signOut();
      this.showToast('Your account is pending admin approval. You will be notified once approved.', 'error');
      this.setButtonLoading(googleBtn, false);
      return;
    }

    // Store pending data — will complete after OTP
    this._pendingUser     = user;
    this._pendingUserData = userData;

    this.setButtonLoading(googleBtn, false);

    // ── Send OTP to user's FIRESTORE email (not Google email) ──
    // Match mobile app behavior: use email from Firestore, fallback to Google email
    const userEmail = userData.email || user.email;
    const userName = userData.name || user.displayName || '';
    
    console.log('📧 Google email:', user.email);
    console.log('📧 Firestore email:', userData.email);
    console.log('📧 OTP will be sent to:', userEmail);
    console.log('👤 User name:', userName);

    this.showToast('Sending verification code to ' + userEmail + '…', 'success');
    await _gsSendOtp(userEmail, userName);

    // Show OTP overlay with the actual email that will receive OTP
    _gsShowOtpOverlay(userEmail);

    // Wire up verify button
    const verifyBtn = document.getElementById('_gsOtpVerifyBtn');
    const resendBtn = document.getElementById('_gsResendBtn');

    // Remove old listeners
    const newVerify = verifyBtn.cloneNode(true);
    verifyBtn.parentNode.replaceChild(newVerify, verifyBtn);
    const newResend = resendBtn.cloneNode(true);
    resendBtn.parentNode.replaceChild(newResend, resendBtn);

    document.getElementById('_gsOtpVerifyBtn').addEventListener('click', () => this._verifyAndContinue());
    document.getElementById('_gsResendBtn').addEventListener('click', () => this._resendOtp());
    _gsBindOtpInputs(); // re-bind after cloneNode
  },

  // Completes a sign-in that went through the full-page redirect fallback.
  // Called on every page load — resolves immediately when no redirect happened.
  checkRedirectResult: async function() {
    let pending = false;
    try { pending = sessionStorage.getItem('pendingGoogleSignIn') === '1'; } catch (_) {}

    let result = null;
    try {
      result = await firebase.auth().getRedirectResult();
    } catch (e) {
      console.error('getRedirectResult error:', e);
      if (pending) {
        try { sessionStorage.removeItem('pendingGoogleSignIn'); } catch (_) {}
        this.showToast(this._friendlyError(e), 'error');
      }
      return;
    }

    if (!result || !result.user) return; // no redirect flow just completed

    if (!pending) {
      // A redirect returned a user but we did not initiate it — reset cleanly.
      console.log('Unexpected redirect result — signing out');
      try { await firebase.auth().signOut(); } catch (_) {}
      return;
    }

    try { sessionStorage.removeItem('pendingGoogleSignIn'); } catch (_) {}
    console.log('Google Sign-In redirect result received:', result.user.uid);

    const googleBtn = document.getElementById('googleBtn');
    this.setButtonLoading(googleBtn, true);
    try {
      await this._continueAfterGoogleAuth(result.user, googleBtn);
    } catch (e) {
      console.error('Google redirect sign-in error:', e);
      this.setButtonLoading(googleBtn, false);
      this.showToast(this._friendlyError(e), 'error');
    }
  },

  // Maps Firebase/flow errors to clear, user-friendly messages.
  _friendlyError: function(error) {
    const code = (error && error.code) || '';
    const msg  = (error && error.message) || '';

    if (code === 'auth/unauthorized-domain') {
      return 'This domain is not authorized for Google Sign-In. Add it in Firebase Console → Authentication → Settings → Authorized domains.';
    }
    if (code === 'auth/operation-not-supported-in-this-environment') {
      return 'Google Sign-In is not available here. Please open this page in a normal browser (http:// or https://).';
    }
    if (code === 'auth/network-request-failed') {
      return 'Network error. Please check your internet connection.';
    }
    if (msg.includes('not found')) return 'User account not found. Please contact the administrator.';
    if (msg.includes('inactive'))   return 'Your account has been deactivated.';
    if (msg.includes('pending'))    return 'Your account is pending admin approval.';
    return 'Sign-in failed. Please try again.';
  },

  _verifyAndContinue: async function() {
    const entered = _gsGetOtpValue();
    if (entered.length < 6) {
      _gsShowOtpError('Please enter the 6-digit code.');
      return;
    }

    const btn = document.getElementById('_gsOtpVerifyBtn');
    const origHtml = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<span style="width:18px;height:18px;border:2.5px solid rgba(255,255,255,0.4);border-top-color:#fff;border-radius:50%;display:inline-block;animation:spin 0.8s linear infinite;"></span> Verifying…';

    try {
      // Verify OTP using the FIRESTORE email (where OTP was actually sent)
      const userEmail = this._pendingUserData.email || this._pendingUser.email;
      await _gsVerifyOtp(userEmail, entered);

      // OTP correct — store session and redirect
      _gsHideOtpOverlay();
      await this.storeUserSession(this._pendingUser, this._pendingUserData);

      // Check mustChangePassword
      if (this._pendingUserData.mustChangePassword) {
        window.location.href = 'change_password.html';
        return;
      }

      this.redirectByRole(this._pendingUserData.role || 'customer');

    } catch (e) {
      btn.disabled = false;
      btn.innerHTML = origHtml;
      _gsShowOtpError(e.message || 'Verification failed. Please try again.');
      // Clear boxes on wrong OTP
      if (e.message && e.message.includes('Incorrect')) {
        for (let i = 0; i < 6; i++) { const b = document.getElementById('_gsOtp' + i); if (b) b.value = ''; }
        const b = document.getElementById('_gsOtp0'); if (b) b.focus();
      }
    }
  },

  _resendOtp: async function() {
    const resendBtn = document.getElementById('_gsResendBtn');
    if (!this._pendingUser) return;
    resendBtn.disabled = true;
    resendBtn.textContent = 'Sending…';
    try {
      // Resend to FIRESTORE email (same as initial send)
      const userEmail = this._pendingUserData.email || this._pendingUser.email;
      const userName = this._pendingUserData.name || this._pendingUser.displayName || '';
      await _gsSendOtp(userEmail, userName);
      // Clear boxes
      for (let i = 0; i < 6; i++) { const b = document.getElementById('_gsOtp' + i); if (b) b.value = ''; }
      const b = document.getElementById('_gsOtp0'); if (b) b.focus();
      const err = document.getElementById('_gsOtpError');
      if (err) { err.style.display = 'none'; }
      this.showToast('New code sent!', 'success');
    } catch (e) {
      _gsShowOtpError('Failed to resend. Please try again.');
    } finally {
      resendBtn.disabled = false;
      resendBtn.textContent = 'Resend';
    }
  },

  getOrCreateUser: async function(googleUser) {
    const uid = googleUser.uid;
    const email = googleUser.email;
    const db = firebase.firestore();

    // Try by UID first (most reliable for Google sign-in)
    let doc = await db.collection('users').doc(uid).get();
    if (doc.exists) {
      console.log('✅ User found by UID:', uid);
      return doc.data();
    }

    // Fallback: search by Google email
    console.log('⚠️ User not found by UID, searching by email:', email);
    const snap = await db.collection('users').where('email', '==', email).limit(1).get();
    if (!snap.empty) {
      // Migrate to UID-keyed doc
      const data = snap.docs[0].data();
      console.log('✅ User found by email, migrating to UID-based doc');
      await db.collection('users').doc(uid).set(data);
      return data;
    }

    // Last resort: check if there's a googleEmail field
    console.log('⚠️ User not found by email, searching by googleEmail field');
    const googleEmailSnap = await db.collection('users').where('googleEmail', '==', email).limit(1).get();
    if (!googleEmailSnap.empty) {
      const data = googleEmailSnap.docs[0].data();
      console.log('✅ User found by googleEmail field');
      // Migrate to UID-keyed doc
      await db.collection('users').doc(uid).set(data);
      return data;
    }

    console.log('❌ User not found in Firestore: uid=' + uid + ', email=' + email);
    throw new Error('User account not found. Please contact the administrator.');
  },

  storeUserSession: async function(googleUser, userData) {
    // Fetch companyName from Firestore if not already in userData
    let companyName = userData.companyName || '';
    if (!companyName) {
      try {
        const doc = await firebase.firestore().collection('users').doc(googleUser.uid).get();
        if (doc.exists) companyName = doc.data().companyName || '';
      } catch(_) {}
    }
    const sessionData = {
      uid:         googleUser.uid,
      email:       googleUser.email,
      // Use Firestore name first — fall back to Google display name only if Firestore has none
      name:        (userData.name || '').trim() || (googleUser.displayName || '').trim() || googleUser.email,
      role:        userData.role || 'customer',
      photoUrl:    googleUser.photoURL || userData.photoUrl || '',
      companyName: companyName,
    };
    if (sessionData.role === 'admin')       sessionStorage.setItem('apUser', JSON.stringify(sessionData));
    else if (sessionData.role === 'staff')  sessionStorage.setItem('spUser', JSON.stringify(sessionData));
    else                                    sessionStorage.setItem('cpUser', JSON.stringify(sessionData));
  },

  redirectByRole: function(role) {
    const map = { admin:'admin_dashboard.html', staff:'staff_dashboard.html', customer:'customer_dashboard.html' };
    // Required by all dashboard auth guards: _loggedIn must be newer than _loggedOut
    localStorage.setItem('_loggedIn', Date.now().toString());
    localStorage.removeItem('_loggedOut');
    setTimeout(() => { window.location.href = map[role] || 'customer_dashboard.html'; }, 100);
  },

  showToast: function(message, type = 'error') {
    const toast = document.getElementById('toast');
    if (!toast) return;
    toast.textContent = message;
    toast.className = type === 'success' ? 'show success' : 'show';
    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => { toast.className = ''; }, 3500);
  },

  setButtonLoading: function(btn, loading) {
    if (!btn) return;
    btn.disabled = loading;
    btn.innerHTML = loading ? '<span class="spinner dark"></span>' : this.getGoogleButtonHTML();
  },

  getGoogleButtonHTML: function() {
    return `<svg class="g-logo" viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
      <path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
      <path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
      <path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
      <path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.18 1.48-4.97 2.31-8.16 2.31-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
      <path fill="none" d="M0 0h48v48H0z"/>
    </svg>Continue with Google`;
  },
};

function _gsShowOtpError(msg) {
  const err = document.getElementById('_gsOtpError');
  if (!err) return;
  err.textContent = msg;
  err.style.display = 'block';
}

// Auto-initialize
console.log('google_signin.js loaded');
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => GoogleSignInModule.init());
} else {
  GoogleSignInModule.init();
}
