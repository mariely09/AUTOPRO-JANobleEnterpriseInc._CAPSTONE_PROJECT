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
      
      _initFirestore(user);
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
      // Map to admin_functions.js expected format
      window.assets = window._fbVehicles.map(v => {
        // Auto-calculate nextPMSDue from lastSvcDate + svcFreq months
        const lastSvc = v.lastSvcDate || v.lastServiceDate || '';
        const freq = parseInt(v.svcFreq || v.serviceFrequency) || 2;
        let nextPMSDue = v.nextPMSDue || '';
        if (lastSvc && !nextPMSDue) {
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
      if (typeof renderAssetsList === 'function') renderAssetsList();
      // Update header notification badge with PMS alerts from Firestore vehicles
      if (typeof renderAdminNotifications === 'function') renderAdminNotifications();
      // Generate PMS notifications → Firestore once per session (not on every snapshot update)
      if (typeof generateWebPMSNotifications === 'function' && !window._pmsNotifGenerated) {
        window._pmsNotifGenerated = true;
        generateWebPMSNotifications();
      }
      _updateOverviewStats();
      // Render dashboard charts whenever vehicle/service data updates
      if (typeof window.renderDashboardCharts === 'function') window.renderDashboardCharts();
      // Re-render PMS calendar when vehicle data changes
      if (typeof window.renderPmsCalendar === 'function') window.renderPmsCalendar();
      // DSS-PMS readiness: vehicles loaded
      window._dssVehiclesReady = true;
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
      window._fbServices = snap.docs.map(d => ({ _id: d.id, ...d.data() }));
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
      if (typeof renderServicesList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'asset-servicing') renderServicesList();
      }
      _updateServiceStats();
      _updateOverviewStats();
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
      if (typeof renderInventoryList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'inventory') renderInventoryList();
      }
      _updateInventoryStats();
      _updateOverviewStats();
      // DSS readiness: mark inventory loaded
      window._dssInventoryReady = true;
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
        itemName: i.name || '',
        description: i.desc || i.description || '',
        commodityGroup: i.group || '',
        uom: i.uom || '',
        cost: parseFloat(String(i.cost || 0).replace(/[₱,]/g, '')) || 0,
        itemType: i.type || 'Material',
        barcode: i.barcode || '',
        qrcode: i.qr || i.qrcode || '',
        sku: i.sku || '',
      }));
      if (typeof renderItemMasterList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'item-master') renderItemMasterList();
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
        name: u.name || '',
        username: u.username || u.email?.split('@')[0] || '',
        email: u.email || '',
        role: u.role || 'customer',
        status: u.status || 'active',
        createdAt: u.createdAt || '',
        photoUrl: u.photoUrl || '',
      }));
      if (typeof renderUsersList === 'function') {
        const section = document.querySelector('.admin-section.active');
        if (!section || section.id === 'users') renderUsersList();
      }
      _updateUserStats();
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

    // Update the overview stat cards directly
    const statCards = document.querySelectorAll('#overview .stat-number');
    if (statCards[0]) statCards[0].textContent = vehicles.length;
    if (statCards[1]) statCards[1].textContent = dueForPms;
    if (statCards[2]) statCards[2].textContent = lowStock;
    if (statCards[3]) statCards[3].textContent = servicesToday;

    // Recent services table → Today's Service Schedule
    _renderTodayServices(services);
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
      container.innerHTML = `<div style="padding:1.5rem;text-align:center;color:#718096;font-size:0.9rem;">No services scheduled for today.</div>`;
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

})(); // end IIFE
