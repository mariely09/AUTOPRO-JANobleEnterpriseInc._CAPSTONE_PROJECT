# 🚀 DSS Notifications Test - Quick Start

**5-Minute Test Guide** para sa Stock at PMS push notifications

---

## ⚡ Quick Test (All-in-One)

```bash
python test_dss_notifications.py --test all
```

Tapos trigger sa mobile app:
1. Open AutoPro mobile app
2. Login as Admin
3. Go to **Decision Support System**
4. Wait 2-5 seconds for notification

---

## 📱 Step-by-Step Guide

### **STEP 1: Run Test Script** ⚙️
```bash
cd c:\Project\AUTOMOTIVE_SERVICE
python test_dss_notifications.py --test all
```

**Expected Output:**
```
============================================================
        TEST: All DSS Alerts (Stock + PMS)
============================================================

STEP 1: Setting up Stock Replenishment test data...
✅ Created test item: TEST-STOCK-001
ℹ️     Name: Test Item _DSS_TEST_DATA_
ℹ️     Stock: 0 (OUT OF STOCK)
ℹ️     Min: 10, Max: 50, Reorder: 20

STEP 1: Setting up PMS Scheduling test data...
✅ Created test vehicle: TEST-ABC-123
ℹ️     Owner: Test Owner _DSS_TEST_DATA_
ℹ️     Next PMS: 2026-08-15 (OVERDUE by 30 days)
ℹ️     Service Frequency: 3 months

STEP 2: Deleting deduplication guard...
✅ Deleted dedup guard for 2026-09-14

STEP 3: Triggering DSS alerts...
```

---

### **STEP 2: Trigger Alerts** 📲

**Choose ONE option:**

#### **Option A: Mobile App** (Fastest)
1. Open AutoPro mobile app on your device
2. Login as Admin
3. Tap menu → **Decision Support System**
4. Screen opens → alerts automatically trigger
5. Wait **2-5 seconds**

#### **Option B: Web App**
1. Open browser: `http://localhost:5000`
2. Login as Admin
3. Click **Decision Support System**
4. Click **"Generate Daily Alerts"** button
5. Check mobile device for notification

---

### **STEP 3: Check Notifications** ✅

**You should receive 2 notifications:**

#### 📱 **Notification 1: Stock Alert**
```
🚨 URGENT: Out of Stock
Test Item _DSS_TEST_DATA_ is out of stock. 
Immediate reorder needed.
```
**Tap action:** Opens Stock Replenishment tab

#### 📱 **Notification 2: PMS Alert**
```
🚗 PMS Overdue
TEST-ABC-123 is overdue for maintenance
```
**Tap action:** Opens PMS Scheduling tab

---

### **STEP 4: Cleanup** 🧹
```bash
python test_dss_notifications.py --cleanup
```

**Output:**
```
============================================================
              CLEANUP: Removing Test Data
============================================================

✅ Removed test stock item: TEST-STOCK-001
✅ Removed test vehicle: TEST-ABC-123
✅ Cleanup complete! Removed 2 test items
```

---

## 🐛 Troubleshooting

### **Walang notification?**

**Quick Fix 1:** Delete dedup guard manually
```
1. Firestore Console → dss_alert_log
2. Delete document: 2026-09-14 (today)
3. Re-trigger sa mobile app
```

**Quick Fix 2:** Check battery settings
```
Device Settings → Apps → AutoPro → Battery → Unrestricted
```

**Quick Fix 3:** Check OneSignal
```
Mobile App → Settings → Enable Notifications (ON)
```

### **May error sa Python?**

**Missing package:**
```bash
python -m pip install firebase-admin python-dotenv
```

**Credential error:**
```bash
# Check .env file contains:
FIREBASE_CREDENTIALS_PATH=automotive_website/serviceAccountKey.json
```

---

## 📊 Test Checklist

- [ ] Run: `python test_dss_notifications.py --test all`
- [ ] Open mobile app as Admin
- [ ] Go to Decision Support System
- [ ] Wait 2-5 seconds
- [ ] Receive 2 notifications (Stock + PMS)
- [ ] Tap Stock notification → Opens Stock tab ✅
- [ ] Tap PMS notification → Opens PMS tab ✅
- [ ] Run: `python test_dss_notifications.py --cleanup`

---

## ⏱️ Expected Timing

| Action | Time |
|--------|------|
| Script setup | ~2 seconds |
| Trigger alerts | ~1 second |
| Notification delivery | ~2-5 seconds |
| Total | ~5-10 seconds |

---

## 🎯 What's Being Tested

✅ **Stock Replenishment Alerts**
- Critical stock (out of stock = 0)
- Low stock (below minimum threshold)
- Notification creation
- Notification delivery via OneSignal
- Navigation to Stock tab

✅ **PMS Scheduling Alerts**
- Overdue maintenance (past nextPMS date)
- Due soon maintenance
- Notification creation
- Notification delivery via OneSignal
- Navigation to PMS tab

✅ **System Components**
- Cloud Function: `checkDSSAlerts`
- Mobile App: DSS alert generation
- OneSignal: Push notification delivery
- Firestore: Dedup guard (`dss_alert_log`)

---

## 📚 For More Details

**Full Documentation:** `DSS_NOTIFICATION_TEST_GUIDE.md`

**Quick commands:**
```bash
# Test stock only
python test_dss_notifications.py --test stock

# Test PMS only
python test_dss_notifications.py --test pms

# Test everything
python test_dss_notifications.py --test all

# Remove test data
python test_dss_notifications.py --cleanup
```

---

## ✨ Success!

If you see both notifications and they navigate correctly:

**🎉 DSS Push Notifications are working perfectly!**

The system will now:
- Automatically check stock every hour
- Send alerts for low/out of stock items
- Check PMS schedules every hour
- Send alerts for overdue maintenance
- All admins and staff receive notifications

---

**Next:** Train staff on daily DSS routine 📋  
**Tip:** Run "Generate Daily Alerts" every morning! ☀️
