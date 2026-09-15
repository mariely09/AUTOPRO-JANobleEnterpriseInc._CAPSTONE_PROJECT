# 🧪 DSS Push Notifications Test Guide

Complete guide for testing Stock Replenishment and PMS Scheduling push notifications.

---

## 📋 Prerequisites

### 1. **Python Environment**
```bash
python -m pip install firebase-admin python-dotenv
```

### 2. **Firebase Credentials**
Ensure `.env` file contains:
```env
FIREBASE_CREDENTIALS_PATH=path/to/serviceAccountKey.json
```

### 3. **Mobile App Setup**
- ✅ AutoPro mobile app installed on test device
- ✅ Logged in as Admin
- ✅ OneSignal push notifications enabled
- ✅ Battery optimization disabled (Settings → Apps → AutoPro → Battery → Unrestricted)

---

## 🚀 Quick Start

### **Test Everything (Recommended)**
```bash
python test_dss_notifications.py --test all
```

### **Test Stock Alerts Only**
```bash
python test_dss_notifications.py --test stock
```

### **Test PMS Alerts Only**
```bash
python test_dss_notifications.py --test pms
```

### **Cleanup After Testing**
```bash
python test_dss_notifications.py --cleanup
```

---

## 📊 What the Script Does

### **Stock Replenishment Test**
1. ✅ Creates test item: `TEST-STOCK-001`
   - Stock: 0 (out of stock)
   - Min: 10, Max: 50, Reorder: 20
2. ✅ Deletes today's dedup guard (`dss_alert_log`)
3. ✅ Provides instructions to trigger alerts
4. ✅ Verifies notification was sent

### **PMS Scheduling Test**
1. ✅ Creates test vehicle: `TEST-ABC-123`
   - Next PMS: 30 days overdue
   - Service Frequency: 3 months
2. ✅ Deletes today's dedup guard
3. ✅ Provides instructions to trigger alerts
4. ✅ Verifies notification was sent

---

## 📱 How to Trigger Alerts (3 Options)

### **OPTION A: Mobile App (RECOMMENDED)**
1. Open AutoPro mobile app
2. Login as Admin
3. Go to: Menu → **Decision Support System**
4. Alerts trigger automatically when screen opens
5. OR tap **"Generate Daily Alerts"** button
6. **Wait 2-5 seconds**
7. Check notification appears

### **OPTION B: Web App**
1. Open web app (localhost:5000 or your domain)
2. Login as Admin
3. Go to: **Decision Support System**
4. Click **"Generate Daily Alerts"** button
5. Check mobile device for notification

### **OPTION C: Automatic (Cloud Function)**
1. Wait for next hour (runs every hour)
2. Example: If now is 2:30 PM, wait until 3:00 PM
3. Notification appears automatically

---

## ✅ Expected Results

### **📱 Stock Replenishment Notification**
```
Title: 🚨 URGENT: Out of Stock
Message: Test Item _DSS_TEST_DATA_ is out of stock. Immediate reorder needed.
Tap Action: Opens Stock Replenishment tab in DSS
Data: { type: 'critical_stock', itemNum: 'TEST-STOCK-001' }
```

### **📱 PMS Scheduling Notification**
```
Title: 🚗 PMS Overdue
Message: TEST-ABC-123 is overdue for maintenance
Tap Action: Opens PMS Scheduling tab in DSS
Data: { type: 'pms_overdue', plate: 'TEST-ABC-123' }
```

---

## 🔍 Verification Steps

### 1. **Check Mobile Notification**
- ✅ Notification appears on device
- ✅ Correct title and message
- ✅ Tap opens correct DSS tab

### 2. **Check Firestore**
```
Collection: dss_alert_log
Document: 2026-09-14 (today's date)
Field: sentAt (timestamp)
```

### 3. **Check Cloud Function Logs**
```
Firebase Console → Functions → checkDSSAlerts → Logs
Look for: "Sent critical stock alert to X admins via OneSignal"
```

### 4. **Check OneSignal Dashboard**
```
OneSignal Console → Messages → Delivered Messages
Should see recent notification delivery
```

---

## 🐛 Troubleshooting

### **Problem: No notification appears**

**Solution 1: Check OneSignal Subscription**
```
1. Mobile app → Settings → Notifications
2. Verify "Enable Notifications" is ON
3. Check OneSignal subscription status is active
```

**Solution 2: Check Battery Optimization**
```
Device Settings → Apps → AutoPro → Battery → Unrestricted
```

**Solution 3: Verify Test Data**
```bash
# Re-run setup
python test_dss_notifications.py --test all

# Check Firestore Console
stock_inventory → TEST-STOCK-001 (should exist, stock: 0)
vehicles → TEST-ABC-123 (should exist, overdue nextPMS)
```

**Solution 4: Delete Dedup Guard**
```bash
Firestore Console → dss_alert_log → Delete today's document
Then re-trigger alerts
```

### **Problem: Duplicate notifications**

**Solution:**
```bash
# Only run once per day
# If testing multiple times, cleanup first:
python test_dss_notifications.py --cleanup

# Then run test again:
python test_dss_notifications.py --test all
```

### **Problem: Notification doesn't navigate to correct screen**

**Solution:**
```
1. Check notification data payload
2. Verify notification.dart handles 'critical_stock' and 'pms_overdue' types
3. Check AdminDSS widget accepts initialTab parameter
```

---

## 🧹 Cleanup

### **Always cleanup after testing:**
```bash
python test_dss_notifications.py --cleanup
```

### **What cleanup removes:**
- ✅ Test stock item: `TEST-STOCK-001`
- ✅ Test vehicle: `TEST-ABC-123`
- ✅ Any other data with `_DSS_TEST_DATA_` marker

### **Manual cleanup (Firestore Console):**
```
1. stock_inventory → Delete TEST-STOCK-001
2. vehicles → Delete TEST-ABC-123
3. dss_alert_log → Delete today's document (optional)
```

---

## 📊 Test Report Template

After testing, document results:

```markdown
## DSS Notification Test Report

**Date:** 2026-09-14
**Tester:** [Your Name]
**Device:** [Android/iOS]

### Stock Replenishment Alert
- [ ] Test data created successfully
- [ ] Notification received
- [ ] Correct title and message
- [ ] Tap action works (opens Stock tab)
- [ ] Timing: ___ seconds

### PMS Scheduling Alert
- [ ] Test data created successfully
- [ ] Notification received
- [ ] Correct title and message
- [ ] Tap action works (opens PMS tab)
- [ ] Timing: ___ seconds

### Issues Found
[List any issues]

### Notes
[Additional observations]
```

---

## 🔧 Advanced Testing

### **Test with Real Data**

Instead of test data, use existing inventory:

```bash
# 1. Find a real low-stock item in Firestore
stock_inventory → [any item] → Set stock: 0

# 2. Delete dedup guard
dss_alert_log → Delete today's document

# 3. Trigger alerts
Mobile App → DSS → Generate Daily Alerts

# 4. Reset stock value after testing
stock_inventory → [item] → Restore original stock value
```

### **Test Timing**

Measure notification delivery time:

```python
# Add to test script
import time

start_time = time.time()
# ... trigger alerts ...
# ... wait for notification ...
end_time = time.time()
print(f"Delivery time: {end_time - start_time:.2f} seconds")
```

**Expected timing:**
- Firestore write: ~0.5s
- Cloud Function trigger: ~1-2s
- OneSignal delivery: ~1-2s
- **Total: 2-5 seconds**

### **Test Multiple Scenarios**

```bash
# Scenario 1: Out of stock (critical)
stock_inventory → item → stock: 0

# Scenario 2: Low stock (warning)
stock_inventory → item → stock: 5, min: 10

# Scenario 3: PMS overdue (critical)
vehicles → vehicle → nextPMS: "2026-01-01"

# Scenario 4: PMS due soon (warning)
vehicles → vehicle → nextPMS: "2026-09-20" (6 days from now)
```

---

## 📚 Related Documentation

- **Main Documentation:** `USER_MANUAL.md` (Section 6.6)
- **Algorithm Details:** `ALGORITHM.md`
- **Deployment Guide:** `DEPLOY_NOW_STEPS.md`
- **OneSignal Setup:** `ONESIGNAL_DEPLOYMENT_READY.md`
- **Cloud Functions:** `automotive_mobile/functions/index.js`

---

## 🎯 Success Criteria Checklist

- [ ] Python script runs without errors
- [ ] Test data created in Firestore
- [ ] Dedup guard deleted successfully
- [ ] Stock alert notification received
- [ ] PMS alert notification received
- [ ] Tap action navigates correctly
- [ ] Notification timing under 5 seconds
- [ ] Cleanup removes all test data
- [ ] No duplicate notifications
- [ ] Cloud Function logs show success

---

## 💡 Pro Tips

1. **Test early in the day** - Dedup guard resets daily
2. **Use real device** - Emulators may have OneSignal issues
3. **Check internet connection** - Notifications require network
4. **Monitor Cloud Function logs** - Real-time debugging
5. **Keep OneSignal dashboard open** - Verify delivery status
6. **Test on multiple devices** - Android and iOS behavior may differ
7. **Document issues immediately** - Include screenshots and logs

---

## 🆘 Support

If issues persist:

1. **Check Cloud Function logs:**
   ```
   Firebase Console → Functions → checkDSSAlerts → Logs
   ```

2. **Check OneSignal logs:**
   ```
   OneSignal Console → Messages → Delivery Logs
   ```

3. **Check Firestore data:**
   ```
   - stock_inventory → TEST-STOCK-001
   - vehicles → TEST-ABC-123
   - dss_alert_log → [today's date]
   ```

4. **Test with Firebase Messaging test:**
   ```bash
   # Send test notification directly
   Firebase Console → Cloud Messaging → Send test message
   ```

---

## ✨ Next Steps

After successful testing:

1. ✅ Remove test data
2. ✅ Document test results
3. ✅ Train admins/staff on DSS alerts
4. ✅ Set up daily alert routine (morning check)
5. ✅ Monitor Cloud Function usage
6. ✅ Review notification logs weekly

---

**Script Version:** 1.0  
**Last Updated:** 2026-09-14  
**Compatible with:** AutoPro v1.0+
