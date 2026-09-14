const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const axios = require('axios');

// Load environment variables from .env file (for local development)
require('dotenv').config();

admin.initializeApp();

// OneSignal credentials from environment variables
// Set these in Firebase Functions config or .env file
const ONESIGNAL_APP_ID = process.env.ONESIGNAL_APP_ID || '48dcf379-b5b7-4692-b15c-f72779e8614d';
const ONESIGNAL_REST_API_KEY = process.env.ONESIGNAL_REST_API_KEY || 'os_v2_app_jdopg6nvw5djfmk464txt2dbjwvvdlqebggukzuh6qm6jopw342ffum77vewzt5hvmm2awhh5tnx2vt5veylamzcoiab7jirmb7eb2q';

/**
 * Callable function: deleteUser
 * Only callable by authenticated admin users.
 * Deletes a user from Firebase Auth by UID.
 */
exports.deleteUser = onCall(async (request) => {
  // Must be authenticated
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be authenticated.');
  }

  // Check caller is admin
  const callerDoc = await admin.firestore()
    .collection('users')
    .doc(request.auth.uid)
    .get();

  if (!callerDoc.exists || callerDoc.data().role !== 'admin') {
    throw new HttpsError('permission-denied', 'Only admins can delete users.');
  }

  const { uid } = request.data;
  if (!uid) {
    throw new HttpsError('invalid-argument', 'UID is required.');
  }

  // Delete from Firebase Auth
  await admin.auth().deleteUser(uid);

  return { success: true };
});

/**
 * Trigger: sendNotifications
 * Automatically sends push notifications when a document is created in the notifications collection.
 * Uses OneSignal to send notifications.
 */
exports.sendNotifications = onDocumentCreated('notifications/{docId}', async (event) => {
  const notification = event.data.data();
  const { title, message, targetRole, targetUid } = notification;

  if (!title || !message) {
    console.error('Notification missing title or message');
    return;
  }

  try {
    let userIds = [];

    // If targetUid is specified, send to that specific user
    if (targetUid) {
      userIds = [targetUid];
    }
    // If targetRole is specified, send to all users with that role
    else if (targetRole) {
      const snapshot = await admin.firestore()
        .collection('users')
        .where('role', '==', targetRole)
        .get();
      userIds = snapshot.docs.map(doc => doc.id);
    }
    // If neither specified, send to all users
    else {
      const snapshot = await admin.firestore()
        .collection('users')
        .get();
      userIds = snapshot.docs.map(doc => doc.id);
    }

    if (userIds.length === 0) {
      console.log('No users found to send notification');
      return;
    }

    // Send via OneSignal
    const response = await axios.post(
      'https://api.onesignal.com/notifications',
      {
        app_id: ONESIGNAL_APP_ID,
        include_external_user_ids: userIds,
        headings: { en: title },
        contents: { en: message },
        data: { type: notification.type || 'info' },
        // Large icon (logo) for Android notifications
        large_icon: 'https://storage.googleapis.com/caltex-autopro-1e664.firebasestorage.app/autopro_logo.png',
        // Small icon is configured in AndroidManifest.xml
      },
      {
        headers: {
          'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
          'Content-Type': 'application/json; charset=utf-8',
        },
      }
    );

    console.log(`Notifications sent to ${userIds.length} users via OneSignal`);
    console.log(`OneSignal response: ${response.data.body.id}`);
  } catch (error) {
    console.error('Error in sendNotifications:', error);
  }
});

/**
 * Callable function: sendPushNotification
 * Sends a push notification to a specific user or role via OneSignal.
 * Can be called from the app or website.
 */
exports.sendPushNotification = onCall(async (request) => {
  // Must be authenticated
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be authenticated.');
  }

  const { userId, title, body, type = 'info' } = request.data;

  if (!title || !body) {
    throw new HttpsError('invalid-argument', 'Title and body are required.');
  }

  try {
    let userIds = [];

    // If userId provided, send to that specific user
    if (userId) {
      const userDoc = await admin.firestore()
        .collection('users')
        .doc(userId)
        .get();

      if (!userDoc.exists) {
        throw new HttpsError('not-found', `User ${userId} not found.`);
      }

      userIds = [userId];
    } else {
      // Otherwise, send to current user
      userIds = [request.auth.uid];
    }

    // Send via OneSignal
    const response = await axios.post(
      'https://api.onesignal.com/notifications',
      {
        app_id: ONESIGNAL_APP_ID,
        include_external_user_ids: userIds,
        headings: { en: title },
        contents: { en: body },
        data: { type: type },
        // Large icon (logo) for Android notifications
        large_icon: 'https://storage.googleapis.com/caltex-autopro-1e664.firebasestorage.app/autopro_logo.png',
      },
      {
        headers: {
          'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
          'Content-Type': 'application/json; charset=utf-8',
        },
      }
    );

    console.log(`Push notification sent to ${userIds.length} user(s) via OneSignal`);
    console.log(`OneSignal response: ${response.data.body.id}`);

    return {
      success: true,
      messageId: response.data.body.id,
      message: 'Push notification sent successfully'
    };
  } catch (error) {
    console.error('Error sending push notification:', error);
    throw new HttpsError('internal', 'Failed to send push notification: ' + error.message);
  }
});

/**
 * Scheduled function: checkDSSAlerts
 * Runs every hour to check for stock and PMS alerts
 * Sends push notifications to admins and customers via OneSignal
 */
exports.checkDSSAlerts = onSchedule('every 1 hours', async (context) => {
  try {
    const db = admin.firestore();
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    // ── STOCK ALERTS FOR ADMINS ──
    console.log('Checking stock levels...');
    const stockSnapshot = await db.collection('stock_inventory').get();
    const issuancesSnapshot = await db.collection('issuances').get();

    // Build consumption map
    const consumptionMap = {};
    issuancesSnapshot.docs.forEach(doc => {
      const data = doc.data();
      const itemNum = data.itemNum || '';
      const qty = typeof data.qty === 'number' ? data.qty : parseFloat(data.qty) || 0;
      const dateStr = data.date || '';
      
      if (itemNum && qty > 0) {
        if (!consumptionMap[itemNum]) consumptionMap[itemNum] = [];
        consumptionMap[itemNum].push({ date: dateStr, qty });
      }
    });

    // Check each stock item
    const criticalStockItems = [];
    const lowStockItems = [];

    stockSnapshot.docs.forEach(doc => {
      const data = doc.data();
      const itemNum = data.num || data.itemNum || doc.id;
      const stock = parseInt(data.stock) || 0;
      const min = parseInt(data.min) || 0;
      const max = parseInt(data.max) || 0;
      const reorder = parseInt(data.reorder) || 0;
      const name = data.name || itemNum;
      const uom = data.uom || '';

      // Calculate consumption rate
      const records = consumptionMap[itemNum] || [];
      const totalConsumed = records.reduce((sum, r) => sum + r.qty, 0);
      
      let earliest = null;
      records.forEach(r => {
        const d = parseIssuanceDate(r.date);
        if (d && (!earliest || d < earliest)) earliest = d;
      });

      const daySpan = earliest ? Math.ceil((now - earliest) / 86400000) : 30;
      const dailyRate = totalConsumed > 0 ? totalConsumed / daySpan : 0;
      const daysLeft = dailyRate > 0 ? Math.floor(stock / dailyRate) : (stock > 0 ? 999 : 0);

      // Determine priority
      if (stock === 0) {
        criticalStockItems.push({
          name, itemNum, stock, min, max, reorder, uom,
          priority: 'Out of Stock',
          recommendQty: reorder,
          daysLeft: 0
        });
      } else if (stock <= min) {
        const deficit = Math.max(0, max - stock);
        const recommendQty = deficit > reorder ? deficit : reorder;
        lowStockItems.push({
          name, itemNum, stock, min, max, reorder, uom,
          priority: 'Low Stock',
          recommendQty,
          daysLeft
        });
      }
    });

    // Send admin notifications for critical stock via OneSignal
    if (criticalStockItems.length > 0) {
      const adminUsers = await db.collection('users').where('role', '==', 'admin').get();
      const adminIds = adminUsers.docs.map(doc => doc.id);
      
      if (adminIds.length > 0) {
        const item = criticalStockItems[0];
        await axios.post(
          'https://api.onesignal.com/notifications',
          {
            app_id: ONESIGNAL_APP_ID,
            include_external_user_ids: adminIds,
            headings: { en: '🚨 URGENT: Out of Stock' },
            contents: { en: `${item.name} is out of stock. Immediate reorder needed.` },
            data: { type: 'critical_stock', itemNum: item.itemNum },
          },
          {
            headers: {
              'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
              'Content-Type': 'application/json; charset=utf-8',
            },
          }
        );
        console.log(`Sent critical stock alert to ${adminIds.length} admins via OneSignal`);
      }
    }

    // Send admin notifications for low stock via OneSignal
    if (lowStockItems.length > 0) {
      const adminUsers = await db.collection('users').where('role', '==', 'admin').get();
      const adminIds = adminUsers.docs.map(doc => doc.id);
      
      if (adminIds.length > 0) {
        const item = lowStockItems[0];
        await axios.post(
          'https://api.onesignal.com/notifications',
          {
            app_id: ONESIGNAL_APP_ID,
            include_external_user_ids: adminIds,
            headings: { en: '⚠️ Low Stock Alert' },
            contents: { en: `${item.name} is low (${item.stock} ${item.uom}). Recommend ordering ${item.recommendQty} ${item.uom}.` },
            data: { type: 'low_stock', itemNum: item.itemNum },
          },
          {
            headers: {
              'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
              'Content-Type': 'application/json; charset=utf-8',
            },
          }
        );
        console.log(`Sent low stock alert to ${adminIds.length} admins via OneSignal`);
      }
    }

    // ── PMS ALERTS ──
    console.log('Checking PMS schedules...');
    const vehiclesSnapshot = await db.collection('vehicles').get();
    const overdueVehicles = [];
    const dueSoonVehicles = [];
    const dueThisWeekVehicles = [];

    vehiclesSnapshot.docs.forEach(doc => {
      const data = doc.data();
      const plate = data.plate || '';
      const desc = data.desc || '';
      const lastSvcDate = data.lastSvcDate || '';
      const svcFreq = parseInt(data.svcFreq) || 0;

      if (!lastSvcDate || !svcFreq) return;

      const lastDate = new Date(lastSvcDate);
      const nextDate = new Date(lastDate.getFullYear(), lastDate.getMonth() + svcFreq, lastDate.getDate());
      const nextMidnight = new Date(nextDate.getFullYear(), nextDate.getMonth(), nextDate.getDate());
      const daysUntil = Math.floor((nextMidnight - today) / 86400000);

      if (daysUntil < 0) {
        overdueVehicles.push({ plate, desc, daysUntil, nextDate: nextMidnight });
      } else if (daysUntil <= 7) {
        dueSoonVehicles.push({ plate, desc, daysUntil, nextDate: nextMidnight });
      } else if (daysUntil <= 14) {
        dueThisWeekVehicles.push({ plate, desc, daysUntil, nextDate: nextMidnight });
      }
    });

    // Send admin PMS alerts via OneSignal
    const adminUsers = await db.collection('users').where('role', '==', 'admin').get();
    const adminIds = adminUsers.docs.map(doc => doc.id);
    
    if (overdueVehicles.length > 0 && adminIds.length > 0) {
      const v = overdueVehicles[0];
      await axios.post(
        'https://api.onesignal.com/notifications',
        {
          app_id: ONESIGNAL_APP_ID,
          include_external_user_ids: adminIds,
          headings: { en: '🚨 PMS Overdue' },
          contents: { en: `${v.plate} is ${Math.abs(v.daysUntil)} day(s) overdue for maintenance.` },
          data: { type: 'pms_overdue', plate: v.plate },
        },
        {
          headers: {
            'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
            'Content-Type': 'application/json; charset=utf-8',
          },
        }
      );
      console.log(`Sent PMS overdue alert to ${adminIds.length} admins via OneSignal`);
    }

    if (dueSoonVehicles.length > 0 && adminIds.length > 0) {
      const v = dueSoonVehicles[0];
      await axios.post(
        'https://api.onesignal.com/notifications',
        {
          app_id: ONESIGNAL_APP_ID,
          include_external_user_ids: adminIds,
          headings: { en: '⚠️ PMS Due Soon' },
          contents: { en: `${v.plate} is due for maintenance in ${v.daysUntil} day(s).` },
          data: { type: 'pms_due_soon', plate: v.plate },
        },
        {
          headers: {
            'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
            'Content-Type': 'application/json; charset=utf-8',
          },
        }
      );
      console.log(`Sent PMS due soon alert to ${adminIds.length} admins via OneSignal`);
    }

    if (dueThisWeekVehicles.length > 0 && adminIds.length > 0) {
      const v = dueThisWeekVehicles[0];
      await axios.post(
        'https://api.onesignal.com/notifications',
        {
          app_id: ONESIGNAL_APP_ID,
          include_external_user_ids: adminIds,
          headings: { en: '📅 PMS Due This Week' },
          contents: { en: `${v.plate} is due for maintenance this week (${v.daysUntil} days).` },
          data: { type: 'pms_due_this_week', plate: v.plate },
        },
        {
          headers: {
            'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
            'Content-Type': 'application/json; charset=utf-8',
          },
        }
      );
      console.log(`Sent PMS due this week alert to ${adminIds.length} admins via OneSignal`);
    }

    // Send customer PMS alerts via OneSignal (only for their vehicles)
    const customerUsers = await db.collection('users').where('role', '==', 'customer').get();
    for (const customerDoc of customerUsers.docs) {
      const customerId = customerDoc.id;
      
      // Find vehicles owned by this customer
      const customerVehicles = vehiclesSnapshot.docs.filter(vDoc => {
        const vData = vDoc.data();
        return vData.ownerId === customerId || vData.customerId === customerId;
      });

      for (const vDoc of customerVehicles) {
        const data = vDoc.data();
        const plate = data.plate || '';
        const lastSvcDate = data.lastSvcDate || '';
        const svcFreq = parseInt(data.svcFreq) || 0;

        if (!lastSvcDate || !svcFreq) continue;

        const lastDate = new Date(lastSvcDate);
        const nextDate = new Date(lastDate.getFullYear(), lastDate.getMonth() + svcFreq, lastDate.getDate());
        const nextMidnight = new Date(nextDate.getFullYear(), nextDate.getMonth(), nextDate.getDate());
        const daysUntil = Math.floor((nextMidnight - today) / 86400000);

        if (daysUntil < 0) {
          await axios.post(
            'https://api.onesignal.com/notifications',
            {
              app_id: ONESIGNAL_APP_ID,
              include_external_user_ids: [customerId],
              headings: { en: '🚨 Your PMS is Overdue' },
              contents: { en: `${plate} is ${Math.abs(daysUntil)} day(s) overdue for maintenance.` },
              data: { type: 'customer_pms_overdue', plate: plate },
            },
            {
              headers: {
                'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
                'Content-Type': 'application/json; charset=utf-8',
              },
            }
          );
        } else if (daysUntil <= 7) {
          await axios.post(
            'https://api.onesignal.com/notifications',
            {
              app_id: ONESIGNAL_APP_ID,
              include_external_user_ids: [customerId],
              headings: { en: '⚠️ Your PMS is Due Soon' },
              contents: { en: `${plate} is due for maintenance in ${daysUntil} day(s).` },
              data: { type: 'customer_pms_due_soon', plate: plate },
            },
            {
              headers: {
                'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
                'Content-Type': 'application/json; charset=utf-8',
              },
            }
          );
        } else if (daysUntil <= 14) {
          await axios.post(
            'https://api.onesignal.com/notifications',
            {
              app_id: ONESIGNAL_APP_ID,
              include_external_user_ids: [customerId],
              headings: { en: '📅 Your PMS is Due This Week' },
              contents: { en: `${plate} is due for maintenance this week (${daysUntil} days).` },
              data: { type: 'customer_pms_due_this_week', plate: plate },
            },
            {
              headers: {
                'Authorization': `Basic ${ONESIGNAL_REST_API_KEY}`,
                'Content-Type': 'application/json; charset=utf-8',
              },
            }
          );
        }
      }
    }

    console.log('DSS alerts check completed');
    return { success: true };
  } catch (error) {
    console.error('Error in checkDSSAlerts:', error);
  }
});

/**
 * Helper: Parse issuance date strings
 */
function parseIssuanceDate(dateStr) {
  if (!dateStr) return null;
  
  // Try ISO format: "2025-04-29"
  const iso = new Date(dateStr);
  if (!isNaN(iso.getTime())) return iso;
  
  // Try M/D/YYYY or MM/DD/YYYY: "4/29/2026"
  const slashParts = dateStr.split('/');
  if (slashParts.length === 3) {
    const m = parseInt(slashParts[0]);
    const d = parseInt(slashParts[1]);
    const y = parseInt(slashParts[2]);
    if (!isNaN(m) && !isNaN(d) && !isNaN(y)) {
      return new Date(y, m - 1, d);
    }
  }
  
  return null;
}

/**
 * Callable function: setupNotificationsCollection
 * Creates the notifications collection with sample documents on first run.
 * Safe to call multiple times - only creates if collection doesn't exist.
 */
exports.setupNotificationsCollection = onCall(async (request) => {
  // Must be authenticated
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be authenticated.');
  }

  try {
    const db = admin.firestore();
    const notificationsRef = db.collection('notifications');
    
    // Check if collection has any documents
    const snapshot = await notificationsRef.limit(1).get();
    
    if (!snapshot.empty) {
      return {
        success: true,
        message: 'Notifications collection already exists',
        created: false
      };
    }

    // Sample notifications to create
    const sampleNotifications = [
      {
        id: 'd1_admin_welcome',
        data: {
          title: 'Welcome Admin',
          message: 'Welcome to AutoPro Admin Dashboard. You can now manage vehicles, users, and maintenance records.',
          type: 'info',
          targetRole: 'admin',
          createdAt: admin.firestore.Timestamp.now(),
        }
      },
      {
        id: 'd2_maintenance_due',
        data: {
          title: 'Maintenance Due',
          message: 'Vehicle ABC-123 requires scheduled maintenance. Please schedule it as soon as possible.',
          type: 'warning',
          targetRole: 'staff',
          createdAt: admin.firestore.Timestamp.now(),
        }
      },
      {
        id: 'd3_service_complete',
        data: {
          title: 'Service Complete',
          message: 'Your vehicle service has been completed. Please pick it up at your earliest convenience.',
          type: 'success',
          targetRole: 'customer',
          createdAt: admin.firestore.Timestamp.now(),
        }
      },
      {
        id: 'd4_system_maintenance',
        data: {
          title: 'System Maintenance',
          message: 'System maintenance scheduled for tonight at 10 PM. Please save your work.',
          type: 'warning',
          targetRole: 'admin',
          createdAt: admin.firestore.Timestamp.now(),
        }
      },
      {
        id: 'd5_new_vehicle',
        data: {
          title: 'New Vehicle Added',
          message: 'A new vehicle (Toyota Camry 2024) has been added to the system. Please review it.',
          type: 'info',
          targetRole: 'staff',
          createdAt: admin.firestore.Timestamp.now(),
        }
      },
      {
        id: 'd6_special_offer',
        data: {
          title: 'Special Offer',
          message: 'Get 20% off on your next service! Use code SAVE20 at checkout.',
          type: 'success',
          targetRole: 'customer',
          createdAt: admin.firestore.Timestamp.now(),
        }
      }
    ];

    // Create all documents in batch
    const batch = db.batch();
    for (const notification of sampleNotifications) {
      const docRef = notificationsRef.doc(notification.id);
      batch.set(docRef, notification.data);
    }
    
    await batch.commit();
    console.log(`Created notifications collection with ${sampleNotifications.length} documents`);

    return {
      success: true,
      message: `Notifications collection created with ${sampleNotifications.length} sample documents`,
      created: true,
      documentCount: sampleNotifications.length
    };
  } catch (error) {
    console.error('Error setting up notifications collection:', error);
    throw new HttpsError('internal', 'Failed to setup notifications collection: ' + error.message);
  }
});
