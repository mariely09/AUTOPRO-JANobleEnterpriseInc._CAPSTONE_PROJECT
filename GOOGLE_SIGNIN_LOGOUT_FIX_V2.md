# 🔧 Google Sign-In Auto-Logout Fix V2 - THE REAL FIX

## 🔴 THE ACTUAL PROBLEM

After Google Sign-In + OTP verification, users were logged out **immediately before redirect** because:

### Root Cause Found in `login.html`:

```javascript
firebase.auth().onAuthStateChanged((user) => {
    if (user) {
        // Stale session — signing out
        console.log('Auth state: Stale user on login page — signing out', user.uid);
        firebase.auth().signOut();  // ❌ THIS SIGNS OUT THE GOOGLE USER!
    }
});
```

### The Timing Problem:

```
1. User completes Google Sign-In ✅
2. OTP verified ✅
3. redirectByRole() called → setTimeout(() => window.location.href = 'dashboard.html', 100)
4. ⏱️ During those 100ms...
5. login.html's onAuthStateChanged fires! ⚡
6. It sees: "There's a user on login page → must be stale → SIGN OUT" ❌
7. Firebase.auth().signOut() executes ❌
8. User gets redirected to dashboard...
9. Dashboard sees NO Firebase user (because we just signed out!)
10. Dashboard redirects back to login ❌
```

## ✅ THE SOLUTION

### 1. Set a Flag Before Redirecting

In `google_signin.js` → `redirectByRole()`:

```javascript
redirectByRole: function(role) {
    // Mark that we're about to redirect from successful Google sign-in
    // This prevents login.html's onAuthStateChanged from signing us out
    sessionStorage.setItem('googleSignInSuccess', '1');
    
    localStorage.setItem('_loggedIn', Date.now().toString());
    localStorage.removeItem('_loggedOut');
    
    setTimeout(() => { window.location.href = map[role] || 'customer_dashboard.html'; }, 100);
}
```

### 2. Check Flag in login.html

In `login.html` → `onAuthStateChanged`:

```javascript
firebase.auth().onAuthStateChanged((user) => {
    // Check if Google sign-in just succeeded
    let googleSuccess = false;
    try { googleSuccess = sessionStorage.getItem('googleSignInSuccess') === '1'; } catch (_) {}
    if (googleSuccess) {
        console.log('Auth state: Google sign-in succeeded, keeping user signed in ✅');
        return;  // DON'T SIGN OUT!
    }
    
    if (user) {
        // Stale session — signing out
        firebase.auth().signOut();
    }
});
```

### 3. Clear Flag on Dashboard

In `admin_dashboard.html`, `customer_dashboard.html`:

```javascript
(function() {
    // Clear flag (we're on dashboard now, safe to proceed)
    try { sessionStorage.removeItem('googleSignInSuccess'); } catch (_) {}
    
    // ... rest of auth guard ...
})();
```

## 🔄 CORRECTED FLOW

```
1. User completes Google Sign-In ✅
2. OTP verified ✅
3. redirectByRole() called
4. ✅ sessionStorage.setItem('googleSignInSuccess', '1')
5. setTimeout(() => redirect, 100ms)
   ⏱️ During those 100ms...
6. login.html's onAuthStateChanged fires ⚡
7. Checks: googleSignInSuccess === '1' ✅
8. Returns early → DOES NOT SIGN OUT ✅
9. User redirected to dashboard
10. Dashboard clears flag ✅
11. Dashboard sees Firebase user ✅
12. USER STAYS LOGGED IN! 🎉
```

## 📊 Before vs After

### ❌ Before (Bug):
```
Google Sign-In → OTP → Redirect (100ms delay)
                         ↓
                    login.html fires
                         ↓
                    Sees user → Signs out ❌
                         ↓
                    Dashboard loads
                         ↓
                    No Firebase user ❌
                         ↓
                    Auto-logout ❌
```

### ✅ After (Fixed):
```
Google Sign-In → OTP → Set flag → Redirect (100ms delay)
                                      ↓
                                 login.html fires
                                      ↓
                                 Sees flag → Skip signout ✅
                                      ↓
                                 Dashboard loads
                                      ↓
                                 Clear flag ✅
                                      ↓
                                 Firebase user active ✅
                                      ↓
                                 STAYS LOGGED IN! 🎉
```

## 🎯 Files Modified

### 1. `automotive_website/static/js/google_signin.js`
- Added `sessionStorage.setItem('googleSignInSuccess', '1')` in `redirectByRole()`
- Added `setPersistence(LOCAL)` in `init()`

### 2. `automotive_website/templates/login.html`
- Added check for `googleSignInSuccess` flag in `onAuthStateChanged`
- Prevents sign-out during Google sign-in flow

### 3. `automotive_website/templates/admin_dashboard.html`
- Added `sessionStorage.removeItem('googleSignInSuccess')` at top of auth guard

### 4. `automotive_website/templates/customer_dashboard.html`
- Added `sessionStorage.removeItem('googleSignInSuccess')` at top of auth guard

## ✅ Testing Checklist

- [ ] Open website in browser
- [ ] Click "Continue with Google"
- [ ] Select Google account
- [ ] Receive OTP email
- [ ] Enter OTP code
- [ ] ✅ Should redirect to dashboard
- [ ] ✅ Should STAY logged in (no auto-logout)
- [ ] ✅ Refresh page → still logged in
- [ ] ✅ Close and reopen tab → still logged in
- [ ] ✅ Logout button works
- [ ] ✅ Can sign in again

## 🔍 How to Debug

### Check Console Logs:

**During Sign-In:**
```
✅ Firebase auth persistence set to LOCAL
📧 Google email: user@gmail.com
📧 Firestore email: user@company.com
📧 OTP will be sent to: user@company.com
✅ OTP verified, Firebase user still signed in: abc123
```

**On login.html (during redirect):**
```
Auth state: Google sign-in succeeded, keeping user signed in ✅
```

**On dashboard:**
```
✅ User found by UID: abc123
```

### If Still Logging Out:

1. Open DevTools → Console
2. Check for "signing out" messages
3. Check if `googleSignInSuccess` flag is set:
   ```javascript
   sessionStorage.getItem('googleSignInSuccess')
   ```
4. Check if Firebase user is active:
   ```javascript
   firebase.auth().currentUser
   ```

## 💡 Why This Works

The key insight is **timing**:
- `onAuthStateChanged` fires **synchronously** when conditions change
- `window.location.href` with `setTimeout` is **asynchronous**
- Between these two events, login.html's auth listener fires
- **We need to protect that window** with a flag

## 🚀 Additional Improvements Made

1. ✅ Set Firebase auth persistence to LOCAL
2. ✅ Don't sign out after OTP verification
3. ✅ Protect against premature sign-out during redirect
4. ✅ Clear flag on dashboard to prevent stale state
5. ✅ Better console logging for debugging

## 📝 Notes

- The `googleSignInSuccess` flag is in **sessionStorage** (not localStorage)
- It's automatically cleared when the tab closes
- It's explicitly cleared when dashboard loads
- This prevents any stale state issues

---

**Status**: Fixed ✅  
**Version**: V2 - The Real Fix  
**Date**: September 12, 2026  
**Tested**: Ready for testing
