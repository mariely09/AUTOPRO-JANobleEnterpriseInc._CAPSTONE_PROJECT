// admin_firebase.js — Connects admin dashboard to Firebase Firestore
// Replaces local data.js arrays with live Firestore data

(function () {
  'use strict';

  // ── Clear local data immediately so data.js hardcoded data doesn't show ──
  window.assets             = [];
  window.serviceTransactions = [];
  window.inventory          = [];
  window.itemMaster         = [];
  window.issuances          = [];
  window.users              = [];
  window.domains            = [];

  document.addEventListener('DOMContentLoaded', function () {
    if (typeof firebase === 'undefined') return;

    // If we already have a session, start Firestore listeners immediately
    // without waiting for the full auth state check (avoids blank table delay)
    var storedUser = sessionStorage.getItem('apUser');
    if (storedUser) {
      try {
        var u = JSON.parse(storedUser);
        if (u && u.uid) {
          _initFirestore({ uid: u.uid, email: u.email, displayName: u.name });
        }
      } catch(e) {}
    }

    // Wait for Firebase Auth before querying Firestore
    firebase.auth().onAuthStateChanged(function (user) {
      console.log('Firebase auth state changed, user:', user?.uid);
      
      if (!user) {
        // Only redirect if no session stored — avoids redirect during auth restore
        const stored = sessionStorage.getItem('apUser');
        if (!stored) {
          console.log('No apUser in sessionStorage and no Firebase user, redirecting to login');
          window.location.href = '/login.html';
        }
        return;
      }
      
      // User is authenticated - restore sessionStorage if needed
      if (!sessionStorage.getItem('apUser')) {
        console.log('apUser not in sessionStorage, storing from Firebase...');
        const userData = {
          uid: user.uid,
          email: user.email,
          name: user.displayName || '',
          role: 'admin',
        };
        sessionStorage.setItem('apUser', JSON.stringify(userData));
        console.log('Stored apUser:', userData);
      }
      
      // Only call _initFirestore again if we didn't already start it above
      if (!storedUser) {
        _initFirestore(user);
      }
    });
  });

  function _initFirestore(user) {
    const db = firebase.firestore();
    window.db = db;

    // ── Load user info from Firestore ──────────────────────
    const apUser = JSON.parse(sessionStorage.getItem('apUser') || '{}');
    if (user.uid) {
      db.collection('users').doc(apUser.uid).get().then(doc => {
        if (doc.exists) {
          const name = doc.data().name || apUser.name || 'Administrator';
          const nameEl = document.getElementById('adminName');
          if (nameEl) nameEl.textContent = name;
          // Update greeting with first name only
          const greetingNameEl = document.getElementById('adminNameGreeting');
          if (greetingNameEl) {
            const firstName = doc.data().firstName || name.trim().split(' ')[0];
            greetingNameEl.textContent = firstName;
          }
          const avatarEl = document.getElementById('adminAvatar');
          if (avatarEl) {
            const parts = name.trim().split(' ');
            avatarEl.textContent = parts.length >= 2
              ? (parts[0][0] + parts[1][0]).toUpperCase()
              : parts[0][0].toUpperCase();
          }
          // Also update sidebar footer
          const sidebarNameEl = document.getElementById('sidebarName');
          if (sidebarNameEl) sidebarNameEl.textContent = name;
          const sidebarAvatarEl = document.getElementById('sidebarAvatar');
          if (sidebarAvatarEl) {
            const parts2 = name.trim().split(' ');
            sidebarAvatarEl.textContent = parts2.length >= 2
              ? (parts2[0][0] + parts2[1][0]).toUpperCase()
              : parts2[0][0].toUpperCase();
          }
          // Also update avatar menu name
          const avatarMenuName = document.getElementById('adminAvatarName');
          if (avatarMenuName) avatarMenuName.textContent = name;
        }
      }).catch(() => {});
    }

    // ── Real-time listeners ────────────────────────────────

    // Vehicles
    db.collection('vehicles').onSnapshot(snap => {
      window._fbVehicles = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
      // Map to admin_functions.js expected format — all vehicles (no archived flag needed)
      window.assets = window._fbVehicles.map(v => {
        // Auto-calculate nextPMSDue from lastSvcDate + svcFreq months
        const lastSvc = v.lastSvcDate || v.lastServiceDate || '';
        const freq = parseInt(v.svcFreq || v.serviceFrequency) || 0;
        let nextPMSDue = v.nextPMSDue || '';
        if (lastSvc && freq > 0 && !nextPMSDue) {
          const d = new Date(lastSvc);
          if (!isNaN(d)) {
            d.setMonth(d.getMonth() + freq);
            nextPMSDue = d.toISOString().split('T')[0];
          }
        }
        // Auto-compute status from nextPMSDue if not explicitly set
        let status = v.status || '';
        if (status.toLowerCase() !== 'under maintenance' && status.toLowerCase() !== 'maintenance' && nextPMSDue) {
          const due = new Date(nextPMSDue);
          const now = new Date();
          const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
          const dueMidnight = new Date(due.getFullYear(), due.getMonth(), due.getDate());
          const diff = Math.round((dueMidnight - today) / 86400000);
          if (diff < 0) status = 'Overdue';
          else if (diff <= 30) status = 'PMS Due Soon';
          else status = 'Active';
        }
        return {
          id: v._id,
          assetNum: v.assetNum || v._id,
          plateNumber: v.plate || v.plateNumber || '',
          assetDescription: v.desc || v.assetDescription || '',
          type: v.type || 'truck',
          icon: (v.type || '').toLowerCase().includes('car') ? '🚗' : '🚛',
          owner: v.owner || v.ownerName || '',
          odometer: parseInt(String(v.odometer || v.odo || '0').replace(/[^0-9]/g, '')) || 0,
          lastSvcOdo: v.lastSvcOdo || v.lastServiceOdometer || '',
          svcFreq: v.svcFreq || v.serviceFrequency || '',
          status: _mapVehicleStatus(status),
          lastServiceDate: lastSvc,
          nextPMSDue: nextPMSDue,
          serviceFrequency: freq,
        };
      });
      window._fbVehiclesLoaded = true;
      if (typeof renderAssetsList === 'function') renderAssetsList();
      // Update header notification badge with PMS alerts from Firestore vehicles
      if (typeof renderAdminNotifications === 'function') renderAdminNotifications();
      // Generate PMS notifications → Firestore once per session (not on every snapshot update)
      if (typeof generateWebPMSNotifications === 'function' && !window._pmsNotifGenerated) {
        window._pmsNotifGenerated = true;
        generateWebPMSNotifications();
      }
      _updateOverviewStats();
      _adminDashSaveDataCache('vehicles');
      // ── Per-page vehicle cache ──
      try {
        var _vhUid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
        if (_vhUid) sessionStorage.setItem('vehiclesCache_' + _vhUid, JSON.stringify(window.assets.slice(0, 500)));
      } catch(e) {}
      // Render dashboard charts whenever vehicle/service data updates
      if (typeof window.renderDashboardCharts === 'function') window.renderDashboardCharts();
      // Re-render PMS calendar when vehicle data changes
      if (typeof window.renderPmsCalendar === 'function') window.renderPmsCalendar();
      // DSS-PMS readiness: vehicles loaded
      window._dssVehiclesReady = true;
      window._fbDSSPMSLoaded = true;
      if (window._dssDataReady && typeof renderDSSPMS === 'function') {
        const active = document.querySelector('.admin-section.active');
        if (active && active.id === 'dss-pms') renderDSSPMS();
      }
      // Trigger initial DSS-PMS render if pending
      if (!window._dssDataReady && window._dssPendingSection === 'dss-pms') {
        if (typeof window._onDSSDataReady === 'function') window._onDSSDataReady();
      }
    });

    // Maintenance / Services
    db.collection('maintenance').orderBy('createdAt', 'desc').onSnapshot(snap => {
      window._fbServices = snap.docs.map(d => ({ _id: d.id, ...d.data() })).filter(s => !s.archived);
      // Map to admin_functions.js expected format
      window.serviceTransactions = window._fbServices.map(s => ({
        serviceId: s._id,
        assetNum: s.assetNum || s.plate || '',
        plate: s.plate || '',
        assetDescription: s.desc || s.assetDescription || s.plate || '',
        mechanicName: s.mechanic || s.mechanicName || '',
        dateServiced: s.date || s.dateServiced || '',
        status: (s.status || 'pending').toLowerCase(),
        totalCost: (() => {
          // Use stored totalCost if available and > 0
          const stored = parseFloat(s.totalCost || s.cost || 0);
          if (stored > 0) return stored;
          // Otherwise calculate from svcRows + matRows
          const svcTotal = (s.svcRows || []).reduce((sum, r) => {
            return sum + (parseFloat(r.cost || r.unitCost || 0) * (parseFloat(r.qty || r.quantity || 1)));
          }, 0);
          const matTotal = (s.matRows || []).reduce((sum, r) => {
            return sum + (parseFloat(r.cost || r.unitCost || 0) * (parseFloat(r.qty || r.quantity || 1)));
          }, 0);
          return svcTotal + matTotal;
        })(),
        cost: (() => {
          const stored = parseFloat(s.totalCost || s.cost || 0);
          if (stored > 0) return '₱' + stored.toLocaleString('en-PH', {minimumFractionDigits:2});
          const svcTotal = (s.svcRows || []).reduce((sum, r) => sum + (parseFloat(r.cost || 0) * (parseFloat(r.qty || 1))), 0);
          const matTotal = (s.matRows || []).reduce((sum, r) => sum + (parseFloat(r.cost || 0) * (parseFloat(r.qty || 1))), 0);
          const calc = svcTotal + matTotal;
          return '₱' + calc.toLocaleString('en-PH', {minimumFractionDigits:2});
        })(),
        svcRows: s.svcRows || [],
        matRows: s.matRows || [],
        createdBy: s.createdBy || '',
        createdAt: s.createdAt || null,
      }));
      window._fbServicesLoaded = true;
      if (typeof renderServicesList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'asset-servicing') renderServicesList();
      }
      _updateServiceStats();
      _updateOverviewStats();
      _adminDashSaveDataCache('services');
      // ── Per-page services cache ──
      try {
        var _svUid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
        if (_svUid) sessionStorage.setItem('servicesCache_' + _svUid, JSON.stringify(window.serviceTransactions.slice(0, 500)));
      } catch(e) {}
      if (typeof window.renderDashboardCharts === 'function') window.renderDashboardCharts();
    });

    // Stock Inventory
    db.collection('stock_inventory').onSnapshot(snap => {
      window._fbInventory = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
      window.inventory = window._fbInventory.map(i => ({
        id: i._id,
        itemNum: i.num || i._id,
        supplierCode: i.supplierCode || '',
        sku: i.sku || '',
        itemName: i.name || '',
        commodityGroup: i.group || '',
        unit: i.uom || '',
        price: parseFloat(i.price || i.cost || 0),
        stock: parseInt(i.stock) || 0,
        minLevel: parseInt(i.min) || 0,
        maxLevel: parseInt(i.max) || 0,
        reorderQty: parseInt(i.reorder) || 0,
        // Compute status live — same logic as mobile app (stock==0 = Out, stock<=min = Low, stock>max = Over, else OK)
        status: (function() {
          var s = parseInt(i.stock) || 0;
          var mn = parseInt(i.min) || 0;
          var mx = parseInt(i.max) || 0;
          if (s === 0) return 'Out';
          if (s <= mn) return 'Low';
          if (mx > 0 && s > mx) return 'Over';
          return 'OK';
        })(),
        barcode: i.barcode || '',
        qrcode: i.qr || i.qrcode || '',
      }));
      window._fbInventoryLoaded = true;
      if (typeof renderInventoryList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'inventory') renderInventoryList();
      }
      _updateInventoryStats();
      _updateOverviewStats();
      _adminDashSaveDataCache('inventory');
      // ── Per-page inventory cache ──
      try {
        var _invUid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
        if (_invUid) sessionStorage.setItem('inventoryCache_' + _invUid, JSON.stringify(window.inventory.slice(0, 1000)));
      } catch(e) {}
      // DSS readiness: mark inventory loaded
      window._dssInventoryReady = true;
      window._fbDSSLoaded = true;
      window._fbDSSPMSLoaded = true;
      if (window._dssInventoryReady && window._dssIssuancesReady) {
        if (typeof window._onDSSDataReady === 'function') window._onDSSDataReady();
        // On subsequent updates re-render DSS if it's the active page
        if (window._dssDataReady && typeof renderDSS === 'function') {
          const active = document.querySelector('.admin-section.active');
          if (active && active.id === 'dss') renderDSS();
        }
      }
    });

    // Item Master
    db.collection('item_master').onSnapshot(snap => {
      window._fbItemMaster = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
      window.itemMaster = window._fbItemMaster.map(i => ({
        id: i._id,
        itemNum: i.num || i._id,
        supplierCode: i.supplierCode || '',
        oem: i.oem || '',
        itemName: i.name || '',
        description: i.desc || i.description || '',
        commodityGroup: i.group || '',
        uom: i.uom || '',
        cost: parseFloat(String(i.cost || 0).replace(/[₱,]/g, '')) || 0,
        itemType: i.type || 'Material',
        barcode: i.barcode || '',
        qrcode: i.qr || i.qrcode || '',
        sku: i.sku || '',
        archived: i.archived || false,
      }));
      window._fbItemMasterLoaded = true;
      // ── Persist item master for instant restore on next visit ──
      try {
        var _imUid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
        if (_imUid) {
          sessionStorage.setItem('imCache_' + _imUid, JSON.stringify(window.itemMaster.slice(0, 2000)));
        }
      } catch(e) {}
      // Stamp any already-computed issuance stats onto newly loaded items
      if (typeof window._computeItemIssuanceStats === 'function') window._computeItemIssuanceStats();
      // Update Total Items stat card on the dashboard
      if (typeof _setStat === 'function') _setStat('statTotalItems', (window._fbItemMaster || []).length);
      if (typeof renderItemMasterList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'item-master') renderItemMasterList();
      }
      // Notify transactions page so it can populate commodity group dropdown instantly
      if (typeof window._txnPopulateCommodityFilterDropdown === 'function') {
        window._txnPopulateCommodityFilterDropdown();
      }
    });

    // Issuances
    db.collection('issuances').orderBy('createdAt', 'desc').onSnapshot(snap => {
      window._fbIssuances = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
      window.issuances = window._fbIssuances.map(i => ({
        id: i._id,
        issuanceId: i._id,
        date: i.date || '',
        assetNum: i.assetNum || i.plate || '',
        plate: i.plate || '',
        assetDescription: i.assetDesc || '',
        itemNum: i.itemNum || '',
        itemName: i.itemName || '',
        itemType: i.itemType || 'Material',
        commodityGroup: i.commodityGroup || '',
        uom: i.uom || '',
        quantity: parseFloat(i.qty) || 0,
        unitCost: parseFloat(i.unitCost) || 0,
        subtotal: parseFloat(i.subtotal) || 0,
        createdBy: i.createdBy || '',
      }));
      if (typeof renderIssuancesList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'issuance') renderIssuancesList();
      }
      _updateIssuanceStats();
      // Compute per-item issuance stats (avg monthly, last month) for Item Master columns
      _computeItemIssuanceStats();
      _adminDashSaveDataCache('issuances');
      // ── Per-page issuances cache ──
      try {
        var _issUid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
        if (_issUid) sessionStorage.setItem('issuancesCache_' + _issUid, JSON.stringify(window.issuances.slice(0, 1000)));
      } catch(e) {}
      // Re-render top parts chart when issuances change
      if (typeof window.renderDashboardCharts === 'function') window.renderDashboardCharts();
      // DSS readiness: mark issuances loaded
      window._dssIssuancesReady = true;
      if (window._dssInventoryReady && window._dssIssuancesReady) {
        if (typeof window._onDSSDataReady === 'function') window._onDSSDataReady();
        // On subsequent updates re-render DSS if it's the active page
        if (window._dssDataReady && typeof renderDSS === 'function') {
          const active = document.querySelector('.admin-section.active');
          if (active && active.id === 'dss') renderDSS();
        }
      }
    });

    // Transactions
    db.collection('transactions').orderBy('createdAt', 'desc').onSnapshot(snap => {
      window._fbTransactions = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
      // ── Cache for instant restore ──
      try {
        var _txUid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
        if (_txUid) sessionStorage.setItem('txnCache_' + _txUid, JSON.stringify(window._fbTransactions.slice(0, 1000)));
      } catch(e) {}
      if (typeof renderInventoryTransactions === 'function') {
        renderInventoryTransactions();
      }
      _updateTransactionStats();
      if (typeof window.renderDashboardCharts === 'function') window.renderDashboardCharts();
    });

    // Users
    db.collection('users').onSnapshot(snap => {
      window._fbUsers = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
      window.users = window._fbUsers.map((u, idx) => ({
        id: u._id,
        firstName: u.firstName || '',
        lastName:  u.lastName  || '',
        name: u.name || '',
        username: u.username || u.email?.split('@')[0] || '',
        email: u.email || '',
        role: u.role || 'customer',
        status: u.status || 'active',
        companyName: u.companyName || '',
        phoneNumber: u.phoneNumber || '',
        mustChangePassword: u.mustChangePassword || false,
        createdAt: u.createdAt || '',
        photoUrl: u.photoUrl || '',
      }));
      window._fbUsersLoaded = true;
      // ── Cache for instant restore ──
      try {
        var _usUid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
        if (_usUid) sessionStorage.setItem('usersCache_' + _usUid, JSON.stringify(window.users.slice(0, 1000)));
      } catch(e) {}
      if (typeof renderUsersList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'users') renderUsersList();
      }
      _updateUserStats();
    });

    // Service Bookings — loaded globally so admin_service_bookings.html
    // can paint instantly from window._fbBookings instead of waiting for
    // its own per-page onSnapshot to return.
    db.collection('service_bookings').orderBy('createdAt', 'desc').onSnapshot(snap => {
      window._fbBookings = snap.docs.map(d => { var data = d.data(); data.id = d.id; return data; });
      // Persist for instant cache restore
      try {
        var _bkUid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
        if (_bkUid) {
          var _bkSave = window._fbBookings.map(function(d) {
            var copy = Object.assign({}, d);
            if (copy.createdAt && typeof copy.createdAt.toMillis === 'function') {
              copy.createdAt = { _ms: copy.createdAt.toMillis() };
            }
            return copy;
          });
          sessionStorage.setItem('bookingsCache_' + _bkUid, JSON.stringify(_bkSave.slice(0, 500)));
        }
      } catch(e) {}
      // If the bookings page is open, update it live
      if (typeof window.renderRescheduleList === 'function') {
        window._sbAllDocs = window._fbBookings;
        // Sync stats
        if (typeof window._sbUpdateStats === 'function') window._sbUpdateStats();
        window.renderRescheduleList();
      }
    }, function() {
      // Fallback: one-shot get if listener fails
      db.collection('service_bookings').orderBy('createdAt', 'desc').get().then(function(snap) {
        window._fbBookings = snap.docs.map(d => { var data = d.data(); data.id = d.id; return data; });
        if (typeof window.renderRescheduleList === 'function') {
          window._sbAllDocs = window._fbBookings;
          if (typeof window._sbUpdateStats === 'function') window._sbUpdateStats();
          window.renderRescheduleList();
        }
      });
    });

    // Deliveries (Receiving / PO) — loaded globally so admin_receiving.html
    // can paint instantly from window._fbDeliveries instead of waiting for
    // its own per-page onSnapshot + two extra .get() calls on every visit.
    db.collection('deliveries').orderBy('createdAt', 'desc').onSnapshot(snap => {
      window._fbDeliveries = snap.docs
        .map(d => { const data = d.data(); data.id = d.id; return data; })
        .filter(d => !d.archived);
      // Persist to sessionStorage (strip non-serialisable Timestamps)
      try {
        const _dlUid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
        if (_dlUid) {
          const _dlSave = window._fbDeliveries.map(function(d) {
            const copy = Object.assign({}, d);
            ['createdAt','receivedAt','archivedAt'].forEach(function(k) {
              if (copy[k] && typeof copy[k].toMillis === 'function') {
                copy[k] = { _ms: copy[k].toMillis() };
              }
            });
            return copy;
          });
          sessionStorage.setItem('deliveriesCache_' + _dlUid, JSON.stringify(_dlSave.slice(0, 500)));
        }
      } catch(e) {}
      // If the receiving page is open, refresh it live
      if (typeof window._rcvOnDeliveries === 'function') window._rcvOnDeliveries(window._fbDeliveries);
    }, function() {
      db.collection('deliveries').orderBy('createdAt', 'desc').get().then(snap => {
        window._fbDeliveries = snap.docs
          .map(d => { const data = d.data(); data.id = d.id; return data; })
          .filter(d => !d.archived);
        if (typeof window._rcvOnDeliveries === 'function') window._rcvOnDeliveries(window._fbDeliveries);
      });
    });

    // Domains
    db.collection('domains').onSnapshot(snap => {
      window._fbDomains = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
      window.domains = window._fbDomains.map(d => ({
        id: d._id,
        domainName: d.name || d.domainName || '',
        domainList: Array.isArray(d.values) ? d.values : (d.domainList || []),
      }));
      if (typeof renderDomainsList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'domains') renderDomainsList();
      }
    });

    // Notifications — merge role-targeted (targetRole:'admin') AND personal
    // (targetUid == uid) just like the mobile app does, so nothing is missed.
    // No orderBy to avoid requiring a composite index — sorted client-side instead.
    const uid = user.uid;
    let _adminRoleDocs     = [];
    let _adminPersonalDocs = [];

    function _mergeAdminNotifs() {
      const map = {};
      _adminRoleDocs.concat(_adminPersonalDocs).forEach(d => { map[d._id] = d; });
      window._fbNotifications = Object.values(map).sort((a, b) => {
        const aMs = a.createdAt?.toMillis?.() ?? 0;
        const bMs = b.createdAt?.toMillis?.() ?? 0;
        return bMs - aMs; // newest first
      });
      if (typeof renderAdminNotifications === 'function') renderAdminNotifications();

      // Update header badge — retry until the element exists (header loads async)
      const unread = window._fbNotifications.filter(n => {
        return (n.readBy || {})[uid] !== true;
      }).length;
      window._adminUnreadCount = unread; // cache for retry

      function _applyBadge() {
        const badge = document.getElementById('adminHeaderNotifBadge');
        if (badge) {
          badge.textContent = unread > 99 ? '99+' : unread;
          badge.style.display = unread > 0 ? 'flex' : 'none';
        } else {
          // Header not loaded yet — retry after a short delay
          setTimeout(_applyBadge, 300);
        }
      }
      _applyBadge();
    }

    // Listener 1: role-broadcast notifications for admin
    db.collection('notifications')
      .where('targetRole', '==', 'admin')
      .onSnapshot(snap => {
        _adminRoleDocs = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
        _mergeAdminNotifs();
      });

    // Listener 2: personal notifications addressed directly to this admin UID
    db.collection('notifications')
      .where('targetUid', '==', uid)
      .onSnapshot(snap => {
        _adminPersonalDocs = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
        _mergeAdminNotifs();
      });

  } // end _initFirestore

  // ── Stat updaters ──────────────────────────────────────────

  function _updateOverviewStats() {
    const vehicles = window._fbVehicles || [];
    const services = window._fbServices || [];
    const inventory = window._fbInventory || [];

    // Total vehicles
    const totalVehiclesEl = document.querySelector('#overview .stat-number');
    // Use specific IDs if available
    _setStat('statTotalVehicles', vehicles.length);

    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    // Count assets with PMS due within the next 7 days (inclusive of today),
    // using the same midnight-to-midnight calculation as the DSS PMS tab.
    const dueForPms = (window.assets || []).filter(a => {
      if (!a.nextPMSDue) return false;
      const due = new Date(a.nextPMSDue);
      const dueMidnight = new Date(due.getFullYear(), due.getMonth(), due.getDate());
      const diff = Math.round((dueMidnight - today) / 86400000);
      return diff >= 0 && diff <= 7;
    }).length;
    _setStat('statDueForPms', dueForPms);

    const lowStock = (window._fbInventory || []).filter(i =>
      (i.status || '').toLowerCase() === 'low' || ((i.stock ?? 0) <= (i.min ?? 0) && (i.min ?? 0) > 0)
    ).length;
    _setStat('statLowStock', lowStock);

    const oneWeekAgo = new Date(now - 7 * 86400000);
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const todayFormatted = `${months[now.getMonth()]} ${now.getDate()}, ${now.getFullYear()}`;
    const servicesToday = services.filter(s => (s.date || '') === todayFormatted).length;
    _setStat('statServicesWeek', servicesToday);

    _setStat('statTotalItems', (window._fbItemMaster || []).length);

    // Update the overview stat cards directly
    const statCards = document.querySelectorAll('#overview .stat-number');
    if (statCards[0]) statCards[0].textContent = vehicles.length;
    if (statCards[1]) statCards[1].textContent = dueForPms;
    if (statCards[2]) statCards[2].textContent = lowStock;
    if (statCards[3]) statCards[3].textContent = servicesToday;

    // Recent services table → Today's Service Schedule
    _renderTodayServices(services);
    _renderRecentServices(services);

    // ── Persist to sessionStorage for instant restore on next visit ──
    var _apUid = (function() {
      try { return (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || ''; } catch(e) { return ''; }
    })();
    if (_apUid) {
      try {
        var cacheKey = 'adminDashCache_' + _apUid;
        var todayEl  = document.getElementById('todayServicesList');
        var recentEl = document.getElementById('recentServicesList');
        sessionStorage.setItem(cacheKey, JSON.stringify({
          statTotalVehicles : vehicles.length,
          statDueForPms     : dueForPms,
          statLowStock      : lowStock,
          statServicesWeek  : servicesToday,
          statTotalUsers    : (window._fbUsers || []).length,
          statTotalItems    : (window._fbItemMaster || []).length,
          todayHtml         : todayEl  ? todayEl.innerHTML  : '',
          recentHtml        : recentEl ? recentEl.innerHTML : '',
          savedAt           : Date.now(),
        }));
      } catch(e) {}
    }
  }

  function _renderTodayServices(services) {
    const container = document.getElementById('todayServicesList');
    if (!container) return;
    container.innerHTML = '';

    const now = new Date();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const todayFormatted = `${months[now.getMonth()]} ${now.getDate()}, ${now.getFullYear()}`;

    const todayServices = services.filter(s => (s.date || '') === todayFormatted);

    if (!todayServices.length) {
      container.innerHTML = `<div style="padding:2.5rem 1rem;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:0.75rem;">
        <div style="width:48px;height:48px;background:#f0f4f8;border-radius:50%;display:flex;align-items:center;justify-content:center;">
          <svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#a0aec0" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
        </div>
        <div style="font-size:0.88rem;font-weight:600;color:#a0aec0;">No services scheduled for today</div>
      </div>`;
      return;
    }

    todayServices.forEach(s => {
      const row = document.createElement('div');
      row.className = 'table-row';
      row.style.gridTemplateColumns = '1fr 1.5fr 1fr 1fr';
      const status = (s.status || '').toLowerCase();
      const statusClass = status === 'completed' ? 'status-completed'
        : status === 'ongoing' ? 'status-pending' : 'status-pending';
      row.innerHTML = `
        <div><strong>${s.plate || '—'}</strong></div>
        <div>${_getFirstService(s)}</div>
        <div>${s.mechanic || '—'}</div>
        <div><span class="status-badge ${statusClass}">${s.status || '—'}</span></div>`;
      container.appendChild(row);
    });
  }

  function _renderRecentServices(services) {
    const container = document.getElementById('recentServicesList');
    if (!container) return;

    // Last 5 completed services sorted by date descending
    const completed = services
      .filter(s => (s.status || '').toLowerCase() === 'completed')
      .slice()
      .sort((a, b) => {
        const da = new Date(a.date || a.dateServiced || '');
        const db = new Date(b.date || b.dateServiced || '');
        return (isNaN(db) ? 0 : db) - (isNaN(da) ? 0 : da);
      })
      .slice(0, 5);

    if (!completed.length) {
      container.innerHTML = '<div style="padding:2.5rem 1rem;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:0.75rem;">'
        + '<div style="width:48px;height:48px;background:#f0f4f8;border-radius:50%;display:flex;align-items:center;justify-content:center;">'
        + '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#a0aec0" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>'
        + '</div>'
        + '<div style="font-size:0.88rem;font-weight:600;color:#a0aec0;">No completed services yet</div>'
        + '</div>';
      return;
    }

    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    function _fmtShort(d) {
      if (!d) return '—';
      // "Jan 5, 2025" → "Jan 5"
      const m = d.match(/^([A-Za-z]+)\s+(\d+)/);
      if (m) return m[1].slice(0,3) + ' ' + m[2];
      const dt = new Date(d);
      if (!isNaN(dt)) return months[dt.getMonth()] + ' ' + dt.getDate();
      return d;
    }

    container.innerHTML = '';
    completed.forEach(s => {
      const row = document.createElement('div');
      row.className = 'table-row';
      row.style.gridTemplateColumns = '1fr 1.5fr 1fr 100px';
      row.innerHTML =
        '<div><strong>' + (s.plate || '—') + '</strong></div>' +
        '<div>' + _getFirstService(s) + '</div>' +
        '<div>' + (s.mechanic || '—') + '</div>' +
        '<div style="font-size:0.8rem;color:#718096;">' + _fmtShort(s.date || s.dateServiced || '') + '</div>';
      container.appendChild(row);
    });
  }

  function _getFirstService(s) {
    const rows = s.svcRows || [];
    return rows.length ? (rows[0].name || '—') : (s.desc || '—');
  }

  function _updateServiceStats() {
    const services = window._fbServices || [];
    _setStat('totalServices', services.length);
    _setStat('ongoingServices',   services.filter(s => (s.status||'').toLowerCase() === 'ongoing').length);
    _setStat('completedServices', services.filter(s => (s.status||'').toLowerCase() === 'completed').length);
  }

  function _updateInventoryStats() {
    const inv = window.inventory || [];
    const total = inv.length;
    const outCount = inv.filter(i => i.stock === 0).length;
    const lowCount = inv.filter(i => i.stock > 0 && i.stock <= i.minLevel).length;
    const inCount  = inv.filter(i => i.stock > i.minLevel).length;
    _setStat('totalInventoryItems', total);
    _setStat('outOfStockCount', outCount);
    _setStat('lowStockCount', lowCount);
    _setStat('inStockCount', inCount);
    const totalValue = inv.reduce(function(s, i) {
      return s + (parseFloat(i.stock) || 0) * (parseFloat(i.price) || 0);
    }, 0);
    _setStat('totalInventoryValue', '₱' + totalValue.toLocaleString('en-PH', { minimumFractionDigits: 0 }));
  }

  function _updateIssuanceStats() {
    const iss = window._fbIssuances || [];
    _setStat('totalIssuances', iss.length);
    _setStat('totalIssuanceServices', iss.filter(i => i.itemType === 'Service').length);
    _setStat('totalMaterials', iss.filter(i => i.itemType === 'Material').length);
  }

  // ── Compute per-item issuance stats for Item Master columns ──────────────
  // Sets window._itemIssuanceStats: { [itemNum]: { avgMonthly, lastMonth } }
  //
  // avgMonthly = total qty issued ÷ number of calendar months in the span
  //              from the item's FIRST issuance month up to AND INCLUDING
  //              the CURRENT month.  This includes months with zero issuances
  //              so the average reflects true monthly consumption rate.
  //
  // lastMonth  = total qty issued in the previous calendar month (month before now).
  function _computeItemIssuanceStats() {
    var issuances = window.issuances || [];
    var now = new Date();
    var nowYear  = now.getFullYear();
    var nowMonth = now.getMonth(); // 0-indexed

    // Previous calendar month
    var lastMonthDate  = new Date(nowYear, nowMonth - 1, 1);
    var lastMonthYear  = lastMonthDate.getFullYear();
    var lastMonthMonth = lastMonthDate.getMonth(); // 0-indexed
    var lastMonthKey   = lastMonthYear + '-' + ('0' + (lastMonthMonth + 1)).slice(-2);

    // Parse any date string → { year, month (0-indexed) } or null
    function parseYearMonth(dateStr) {
      if (!dateStr) return null;
      // "May 7, 2026" / "May 7 2026"
      var m1 = dateStr.match(/^([A-Za-z]{3,})\s+\d+,?\s+(\d{4})/);
      if (m1) {
        var months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
        var mo = months.indexOf(m1[1].slice(0,3).toLowerCase());
        return mo >= 0 ? { year: parseInt(m1[2]), month: mo } : null;
      }
      // "1/7/2026"
      var m2 = dateStr.match(/^(\d{1,2})\/\d{1,2}\/(\d{4})/);
      if (m2) return { year: parseInt(m2[2]), month: parseInt(m2[1]) - 1 };
      // "2026-05-07"
      var m3 = dateStr.match(/^(\d{4})-(\d{2})-\d{2}/);
      if (m3) return { year: parseInt(m3[1]), month: parseInt(m3[2]) - 1 };
      var dt = new Date(dateStr);
      if (!isNaN(dt)) return { year: dt.getFullYear(), month: dt.getMonth() };
      return null;
    }

    // monthKey helper
    function toKey(year, month) { return year + '-' + ('0' + (month + 1)).slice(-2); }

    // Build per-itemNum buckets: 'YYYY-MM' → total qty
    // Also track the earliest issuance month per item.
    var buckets   = {}; // { itemNum: { 'YYYY-MM': qty } }
    var firstKeys = {}; // { itemNum: 'YYYY-MM' }  earliest month seen

    issuances.forEach(function(iss) {
      var num = (iss.itemNum || '').trim();
      if (!num) return;
      var qty = parseFloat(iss.quantity) || 0;
      if (!qty) return;
      var ym = parseYearMonth(iss.date);
      if (!ym) return;
      var key = toKey(ym.year, ym.month);
      if (!buckets[num]) buckets[num] = {};
      buckets[num][key] = (buckets[num][key] || 0) + qty;
      // Track the earliest key (string comparison works because format is YYYY-MM)
      if (!firstKeys[num] || key < firstKeys[num]) firstKeys[num] = key;
    });

    var stats = {};
    Object.keys(buckets).forEach(function(num) {
      var monthMap = buckets[num];

      // Total qty ever issued for this item
      var totalQty = Object.keys(monthMap).reduce(function(s, k) { return s + monthMap[k]; }, 0);

      // Number of full calendar months from first issuance through current month (inclusive)
      var firstKey = firstKeys[num]; // 'YYYY-MM'
      var fp = firstKey.split('-');
      var firstYear  = parseInt(fp[0]);
      var firstMonth = parseInt(fp[1]) - 1; // back to 0-indexed
      // Span = months between firstMonth and nowMonth (inclusive on both ends)
      var spanMonths = (nowYear - firstYear) * 12 + (nowMonth - firstMonth) + 1;
      if (spanMonths < 1) spanMonths = 1;

      var avgMonthly = Math.round((totalQty / spanMonths) * 10) / 10;

      var lastMonth = monthMap[lastMonthKey] || 0;

      stats[num] = { avgMonthly: avgMonthly, lastMonth: lastMonth };
    });

    window._itemIssuanceStats = stats;

    // Stamp onto window.itemMaster for the render function
    if (window.itemMaster) {
      window.itemMaster.forEach(function(item) {
        var s = stats[item.itemNum] || { avgMonthly: 0, lastMonth: 0 };
        item.avgMonthlyIssuance = s.avgMonthly;
        item.lastMonthIssuance  = s.lastMonth;
      });
    }

    // Re-render Item Master if it's the active section
    if (typeof renderItemMasterList === 'function') {
      var section = document.querySelector('.admin-section.active');
      if (!section || section.id === 'item-master') renderItemMasterList();
    }
  }

  // Expose so item_master snapshot can also trigger a recompute
  window._computeItemIssuanceStats = _computeItemIssuanceStats;

  function _updateTransactionStats() {
    const txns = window._fbTransactions || [];
    _setStat('txnTotal', txns.length);
    _setStat('txnIn', txns.filter(t => t.type === 'IN').length);
    _setStat('txnOut', txns.filter(t => t.type === 'OUT').length);
    const items = new Set(txns.map(t => t.item)).size;
    _setStat('txnItems', items);
  }

  function _updateUserStats() {
    const users = window._fbUsers || [];
    _setStat('userStatTotal', users.length);
    _setStat('statTotalUsers', users.length);
    _setStat('userStatActive', users.filter(u => (u.status || '').toLowerCase() === 'active').length);
    _setStat('userStatInactive', users.filter(u => (u.status || '').toLowerCase() !== 'active').length);
    // Patch user count into dashboard cache if it exists
    try {
      var _apUid2 = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
      if (_apUid2) {
        var _ck = 'adminDashCache_' + _apUid2;
        var _cached = JSON.parse(sessionStorage.getItem(_ck) || 'null');
        if (_cached) { _cached.statTotalUsers = users.length; sessionStorage.setItem(_ck, JSON.stringify(_cached)); }
      }
    } catch(e) {}
  }

  function _setStat(id, value) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  function _mapVehicleStatus(status) {
    const s = (status || '').toLowerCase();
    if (s === 'under maintenance' || s === 'maintenance') return 'maintenance';
    if (s === 'overdue' || s === 'pms overdue') return 'overdue';
    if (s === 'pms due soon' || s === 'due soon') return 'due-soon';
    if (s === 'inactive') return 'inactive';
    return 'active';
  }

  // ── Dashboard data cache helpers ─────────────────────────────────────────
  // Saves the raw Firestore arrays to sessionStorage so charts + tables can
  // render immediately on the next page load before new snapshots arrive.
  // Stored under one key per UID, split into 4 slots to stay under quota.
  function _adminDashSaveDataCache(slot) {
    try {
      var uid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
      if (!uid) return;
      var base = 'adminDashData_' + uid + '_';
      var slim = function(arr) {
        // Store only the fields needed by renderDashboardCharts + stats
        return (arr || []).slice(0, 500); // cap at 500 records to stay within quota
      };
      if (slot === 'vehicles')  sessionStorage.setItem(base + 'vehicles',  JSON.stringify(slim(window._fbVehicles)));
      if (slot === 'services')  sessionStorage.setItem(base + 'services',  JSON.stringify(slim(window._fbServices)));
      if (slot === 'inventory') sessionStorage.setItem(base + 'inventory', JSON.stringify(slim(window._fbInventory)));
      if (slot === 'issuances') sessionStorage.setItem(base + 'issuances', JSON.stringify(slim(window._fbIssuances)));
    } catch(e) { /* quota exceeded — fail silently */ }
  }

  // Called once on page load (before DOMContentLoaded) to hydrate window globals
  // from cache so charts can render without waiting for Firestore.
  window._adminDashRestoreDataCache = function() {
    try {
      var uid = (JSON.parse(sessionStorage.getItem('apUser') || '{}')).uid || '';
      if (!uid) return false;
      var base = 'adminDashData_' + uid + '_';
      var vRaw = sessionStorage.getItem(base + 'vehicles');
      var sRaw = sessionStorage.getItem(base + 'services');
      var iRaw = sessionStorage.getItem(base + 'inventory');
      var qRaw = sessionStorage.getItem(base + 'issuances');
      if (!vRaw && !sRaw) return false; // nothing cached yet

      if (vRaw) {
        window._fbVehicles = JSON.parse(vRaw);
        // Re-map to window.assets (needed by charts + stats)
        window.assets = window._fbVehicles.map(function(v) {
          var lastSvc = v.lastSvcDate || v.lastServiceDate || '';
          var freq = parseInt(v.svcFreq || v.serviceFrequency) || 0;
          var nextPMSDue = v.nextPMSDue || '';
          if (lastSvc && freq > 0 && !nextPMSDue) {
            var d = new Date(lastSvc);
            if (!isNaN(d)) { d.setMonth(d.getMonth() + freq); nextPMSDue = d.toISOString().split('T')[0]; }
          }
          return {
            id: v._id, assetNum: v.assetNum || v._id,
            plateNumber: v.plate || v.plateNumber || '',
            assetDescription: v.desc || v.assetDescription || '',
            type: v.type || 'truck',
            owner: v.owner || v.ownerName || '',
            odometer: parseInt(String(v.odometer || v.odo || '0').replace(/[^0-9]/g,'')) || 0,
            lastSvcOdo: v.lastSvcOdo || v.lastServiceOdometer || '',
            svcFreq: v.svcFreq || v.serviceFrequency || '',
            status: v.status || 'Active',
            lastServiceDate: lastSvc,
            nextPMSDue: nextPMSDue,
            serviceFrequency: freq,
          };
        });
      }
      if (sRaw) {
        window._fbServices = JSON.parse(sRaw);
        window.serviceTransactions = window._fbServices.map(function(s) {
          return {
            serviceId: s._id, plate: s.plate || '', assetNum: s.assetNum || s.plate || '',
            assetDescription: s.desc || s.assetDescription || s.plate || '',
            mechanic: s.mechanic || '', mechanicName: s.mechanic || '',
            date: s.date || s.dateServiced || '', dateServiced: s.date || s.dateServiced || '',
            status: (s.status || 'pending').toLowerCase(),
            svcRows: s.svcRows || [], matRows: s.matRows || [],
            cost: s.cost || '', createdAt: s.createdAt || null,
          };
        });
      }
      if (iRaw) {
        window._fbInventory = JSON.parse(iRaw);
        window.inventory = window._fbInventory.map(function(i) {
          return {
            id: i._id, itemNum: i.num || i._id, itemName: i.name || '',
            commodityGroup: i.group || '', unit: i.uom || '',
            stock: parseInt(i.stock) || 0, minLevel: parseInt(i.min) || 0,
            maxLevel: parseInt(i.max) || 0,
            status: (parseInt(i.stock)||0) === 0 ? 'Out' :
                    (parseInt(i.stock)||0) <= (parseInt(i.min)||0) ? 'Low' : 'OK',
          };
        });
      }
      if (qRaw) {
        window._fbIssuances = JSON.parse(qRaw);
        window.issuances = window._fbIssuances.map(function(i) {
          return {
            id: i._id, date: i.date || '', plate: i.plate || '',
            itemNum: i.itemNum || '', itemName: i.itemName || '',
            itemType: i.itemType || 'Material',
            quantity: parseFloat(i.qty) || 0, unitCost: parseFloat(i.unitCost) || 0,
          };
        });
      }
      return true;
    } catch(e) { return false; }
  };

})(); // end IIFE
