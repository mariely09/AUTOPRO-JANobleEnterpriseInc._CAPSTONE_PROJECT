(function () {
  'use strict';

  // ── Auth guard ──────────────────────────────────────────
  const stored = sessionStorage.getItem('cpUser');
  console.log('customer_dashboard.js loaded, cpUser in sessionStorage:', !!stored);
  
  if (!stored) { 
    console.log('No cpUser in sessionStorage, checking Firebase auth...');
    // Don't redirect immediately - wait for Firebase to initialize
    // The auth check below will handle the redirect
  }
  
  const cpUser = stored ? JSON.parse(stored) : {};
  console.log('cpUser data:', cpUser);

  const db   = firebase.firestore();
  const auth = firebase.auth();

  let _userName = '';
  let _vehicles = [];

  // ── sessionStorage cache keys (per-user) ─────────────────
  const _cpUid = cpUser.uid || '';
  const _CU_VEH_KEY    = 'cuVehiclesCache_'    + _cpUid;
  const _CU_RECENT_KEY = 'cuRecentSvcCache_'   + _cpUid;
  const _CU_STATS_KEY  = 'cuStatsCache_'       + _cpUid;

  // ── Restore cached data immediately (before auth resolves) ──
  // Removes the "Loading..." flash on every visit.
  (function _cuRestoreCache() {
    if (!_cpUid) return;
    try {
      // Vehicles list + count
      const rawVeh = sessionStorage.getItem(_CU_VEH_KEY);
      if (rawVeh) {
        const c = JSON.parse(rawVeh);
        if (c) {
          const el = document.getElementById('cuVehiclesList');
          if (el && c.html) el.innerHTML = c.html;
          const countEl = document.getElementById('cuVehiclesCount');
          if (countEl && c.count != null) countEl.textContent = c.count;
          // Restore _vehicles so cuShowVehicle modal works immediately
          if (Array.isArray(c.vehicles)) _vehicles = c.vehicles;
          // Banner name from session
          const firstName = (cpUser.name || 'Customer').trim().split(/\s+/)[0];
          const bannerEl = document.getElementById('cuBannerName');
          if (bannerEl) bannerEl.textContent = firstName + '!';
          const headerEl = document.getElementById('cuHeaderName');
          if (headerEl) headerEl.textContent = firstName;
          const avatarEl = document.getElementById('cuAvatar');
          if (avatarEl) {
            const initials = (cpUser.name || '').split(' ').filter(Boolean).map(p => p[0]).join('').toUpperCase().slice(0, 2) || 'CU';
            avatarEl.textContent = initials;
          }
        }
      }
      // Stats
      const rawStats = sessionStorage.getItem(_CU_STATS_KEY);
      if (rawStats) {
        const s = JSON.parse(rawStats);
        if (s) {
          const set = (id, v) => { const e = document.getElementById(id); if (e && v != null) e.textContent = v; };
          set('cuActive', s.active);
          set('cuMaintenance', s.maintenance);
          set('cuDueThisWeek', s.dueThisWeek);
          set('cuDueSoon', s.dueToday);
        }
      }
      // Recent services
      const rawRecent = sessionStorage.getItem(_CU_RECENT_KEY);
      if (rawRecent) {
        const r = JSON.parse(rawRecent);
        const el = document.getElementById('cuRecentServices');
        if (el && r && r.html) el.innerHTML = r.html;
      }
    } catch(e) {}
  })();

  // ── Init ────────────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', () => {
    // Show loading only if no cache has already rendered content
    const vehEl = document.getElementById('cuVehiclesList');
    if (vehEl && !vehEl.children.length) {
      vehEl.innerHTML = '<div class="cu-empty" style="color:#718096;">Loading...</div>';
    }

    // Wait for Firebase Auth before querying Firestore
    firebase.auth().onAuthStateChanged((user) => {
      console.log('Firebase auth state changed, user:', user?.uid);
      
      if (user) {
        console.log('Firebase user authenticated:', user.uid);
        // Store in sessionStorage if not already there
        if (!sessionStorage.getItem('cpUser')) {
          console.log('cpUser not in sessionStorage, storing from Firebase...');
          const userData = {
            uid: user.uid,
            email: user.email,
            name: cpUser.name || user.displayName || '',
            role: cpUser.role || 'customer',
          };
          sessionStorage.setItem('cpUser', JSON.stringify(userData));
          console.log('Stored cpUser:', userData);
        }
        loadUserInfo(user);
      } else {
        console.log('No Firebase user, redirecting to login');
        window.location.href = '/login.html';
      }
    });
  });

  // ── User info ────────────────────────────────────────────
  async function loadUserInfo(user) {
    // Use stored name immediately — fast path
    _userName = cpUser.name || '';
    let _companyName = cpUser.companyName || '';

    // Always fetch from Firestore to ensure companyName is resolved
    // (Google sign-in sessions may have name but not companyName)
    try {
      const userDoc = await db.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        if (!_userName) _userName = userDoc.data().name || '';
        _companyName = userDoc.data().companyName || _companyName;
      }
    } catch(e) { console.warn('Firestore UID lookup failed:', e); }

    if (!_userName && cpUser.email) {
      try {
        const snap = await db.collection('users').where('email', '==', cpUser.email).limit(1).get();
        if (!snap.empty) {
          if (!_userName) _userName = snap.docs[0].data().name || '';
          if (!_companyName) _companyName = snap.docs[0].data().companyName || '';
        }
      } catch(e) { console.warn('Firestore email lookup failed:', e); }
    }

    // Store companyName so vehicle filter can use it
    window._cpCompanyName = _companyName;
    // Also update cpUser in session with companyName if missing
    if (_companyName && !cpUser.companyName) {
      cpUser.companyName = _companyName;
      try { sessionStorage.setItem('cpUser', JSON.stringify(cpUser)); } catch(e) {}
    }

    const initials = _userName.split(' ').filter(Boolean).map(p => p[0]).join('').toUpperCase().slice(0, 2) || 'CU';
    document.getElementById('cuAvatar').textContent = initials;
    const headerNameEl = document.getElementById('cuHeaderName');
    // Show first name only — matches mobile _buildTopBar first-name logic
    const firstName = (_userName || 'Customer').trim().split(/\s+/)[0];
    if (headerNameEl) headerNameEl.textContent = firstName;
    // Set first name in banner greeting
    const bannerNameEl = document.getElementById('cuBannerName');
    if (bannerNameEl) bannerNameEl.textContent = firstName + '!';
    loadVehicles();
  }

  // ── Vehicles ─────────────────────────────────────────────
  // Track under-maintenance vehicle ids/plates from service_bookings.
  // null = stream not yet loaded (use vehicle doc status as fallback).
  // Set() = stream loaded but no active Under Maintenance bookings.
  window._cuUnderMaintenancePlates    = null;
  window._cuUnderMaintenanceVehicleIds = null;

  function loadVehicles() {
    const user = auth.currentUser;

    // ── Listen to service_bookings for Under Maintenance status ──
    db.collection('service_bookings')
      .where('customerId', '==', user.uid)
      .onSnapshot(bookingSnap => {
        // Replace with fresh Sets — null sentinel is only used before first snapshot
        window._cuUnderMaintenancePlates    = new Set();
        window._cuUnderMaintenanceVehicleIds = new Set();
        bookingSnap.docs.forEach(doc => {
          const data = doc.data();
          if ((data.status || '').toLowerCase() === 'under maintenance') {
            if (data.plate)     window._cuUnderMaintenancePlates.add((data.plate || '').toLowerCase());
            if (data.vehicleId) window._cuUnderMaintenanceVehicleIds.add(data.vehicleId);
          }
        });
        // Re-render if vehicles already loaded
        if (_vehicles.length) {
          updateStats();
          renderVehicles();
        }
      }, () => {}); // ignore booking stream errors silently

    // ── Also listen to maintenance collection for Ongoing records ──
    // This catches vehicles put Under Maintenance by staff/admin directly,
    // even when the service_bookings entry hasn't been updated yet.
    db.collection('maintenance')
      .where('status', '==', 'Ongoing')
      .onSnapshot(maintSnap => {
        if (!window._cuUnderMaintenancePlates) window._cuUnderMaintenancePlates = new Set();
        if (!window._cuUnderMaintenanceVehicleIds) window._cuUnderMaintenanceVehicleIds = new Set();
        // Get the current customer's vehicle plates/ids to filter
        const myPlates = new Set(_vehicles.map(v => (v.plate || '').toLowerCase()).filter(Boolean));
        const myIds    = new Set(_vehicles.map(v => v.id).filter(Boolean));
        // Remove previously added maintenance entries (refresh from scratch for this source)
        // We keep a separate set to track what was added by maintenance stream
        if (!window._cuMaintMaintenancePlates) window._cuMaintMaintenancePlates = new Set();
        if (!window._cuMaintMaintenanceIds)    window._cuMaintMaintenanceIds    = new Set();
        // Remove old maintenance-sourced entries from the shared sets
        window._cuMaintMaintenancePlates.forEach(p => window._cuUnderMaintenancePlates.delete(p));
        window._cuMaintMaintenanceIds.forEach(id => window._cuUnderMaintenanceVehicleIds.delete(id));
        window._cuMaintMaintenancePlates.clear();
        window._cuMaintMaintenanceIds.clear();
        // Add current Ongoing maintenance entries that belong to this customer
        maintSnap.docs.forEach(doc => {
          const data = doc.data();
          const plate     = (data.plate || data.plateNumber || '').toLowerCase();
          const vehicleId = data.vehicleId || '';
          const ownerId   = data.ownerId   || '';
          // Match by plate, vehicleId, or ownerId
          const isOwner = (plate && myPlates.has(plate)) ||
                          (vehicleId && myIds.has(vehicleId)) ||
                          (ownerId && user && ownerId === user.uid);
          if (!isOwner) return;
          if (plate)     { window._cuUnderMaintenancePlates.add(plate);    window._cuMaintMaintenancePlates.add(plate); }
          if (vehicleId) { window._cuUnderMaintenanceVehicleIds.add(vehicleId); window._cuMaintMaintenanceIds.add(vehicleId); }
        });
        if (_vehicles.length) {
          updateStats();
          renderVehicles();
        }
      }, () => {});

    db.collection('vehicles').onSnapshot(snap => {
      const all = snap.docs.map(d => ({ id: d.id, ...d.data() }));

      // Filter by ownerId (UID) OR owner name / company name — matches however the vehicle was registered
      _vehicles = all.filter(v => {
        // UID-based match (most reliable)
        if (user && v.ownerId && v.ownerId === user.uid) return true;
        // Name-based match (legacy / manual entry)
        const owner   = (v.owner || '').toLowerCase().trim();
        const name    = _userName.toLowerCase().trim();
        const company = (window._cpCompanyName || '').toLowerCase().trim();
        return (name && owner === name) || (company && owner === company);
      });

      updateStats();
      renderVehicles();
      // Load recent services only on the first vehicles snapshot
      if (!_recentServicesStarted) {
        _recentServicesStarted = true;
        loadRecentServices();
      }
    });
  }

  let _recentServicesStarted = false;

  // ── Date format helper (e.g. "2026-06-01" → "June 1, 2026") ──
  const _MONTHS_FULL = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  function fmtDateLong(dateStr) {
    if (!dateStr) return '—';
    const d = new Date(dateStr);
    if (isNaN(d)) return dateStr;
    return _MONTHS_FULL[d.getMonth()] + ' ' + d.getDate() + ', ' + d.getFullYear();
  }

  // ── Vehicle icon SVG based on type ───────────────────────
  function vehicleIconSvg(type, size) {
    const t = (type || '').toLowerCase();
    const s = size || 24;
    if (t.includes('truck')) {
      // Truck / delivery van
      return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="3" width="15" height="13" rx="2"/><path d="M16 8h4l3 5v3h-7V8z"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/></svg>`;
    }
    // Car (default)
    return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 17H3a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1l2-4h10l2 4h1a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-2"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="17.5" r="2.5"/></svg>`;
  }

  // ── Fleet icon based on vehicle types ────────────────────
  function fleetIconSvg(vehicles, size) {
    const s = size || 20;
    if (!vehicles.length) {
      return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 17H3a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1l2-4h10l2 4h1a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-2"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="17.5" r="2.5"/></svg>`;
    }
    const allTruck = vehicles.every(v => (v.type || '').toLowerCase().includes('truck'));
    const allCar = vehicles.every(v => !(v.type || '').toLowerCase().includes('truck'));
    if (allTruck) {
      // Truck icon
      return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="1" y="3" width="15" height="13" rx="2"/><path d="M16 8h4l3 5v3h-7V8z"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/></svg>`;
    }
    if (allCar) {
      // Car icon
      return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 17H3a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1l2-4h10l2 4h1a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-2"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="17.5" r="2.5"/></svg>`;
    }
    // Mixed fleet - commute icon
    return `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 17H3a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1l2-4h10l2 4h1a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-2"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="17.5" r="2.5"/><path d="M16 3v4M20 3v4"/></svg>`;
  }

  function computeStatus(v) {
    // _cuUnderMaintenancePlates is null until the service_bookings stream fires.
    // Once it fires it's a Set — empty means no active Under Maintenance bookings.
    if (window._cuUnderMaintenancePlates === null) {
      // Stream not loaded yet — fall back to the stale vehicle doc status
      if (v.status === 'Under Maintenance') return 'Under Maintenance';
    } else {
      // Stream has fired — these sets are the ground truth.
      // If booking moved to Completed, plate/id is no longer in the set.
      if (window._cuUnderMaintenancePlates.has((v.plate || '').toLowerCase())) return 'Under Maintenance';
      if (window._cuUnderMaintenanceVehicleIds && window._cuUnderMaintenanceVehicleIds.has(v.id)) return 'Under Maintenance';
    }
    const lastSvc = v.lastSvcDate || '';
    const freq = parseInt(v.svcFreq) || 0;
    if (!lastSvc || !freq) return 'On Track';
    const date = new Date(lastSvc);
    if (isNaN(date)) return 'On Track';
    const next = new Date(date);
    next.setMonth(next.getMonth() + freq);
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const nextMidnight = new Date(next.getFullYear(), next.getMonth(), next.getDate());
    const days = Math.round((nextMidnight - today) / 86400000);
    if (days < 0)   return 'Overdue';
    if (days === 0) return 'Due Today';
    if (days <= 7)  return 'Due This Week';
    if (days <= 14) return 'Due Soon';
    if (days <= 30) return 'Scheduled';
    return 'On Track';
  }

  function updateStats() {
    // Use live computeStatus() so Due Today is always accurate regardless of stale Firestore status
    const statuses = _vehicles.map(v => computeStatus(v));
    const overdue     = statuses.filter(s => s === 'Overdue').length;
    const dueToday    = statuses.filter(s => s === 'Due Today').length;
    const dueThisWeek = statuses.filter(s => s === 'Due This Week' || s === 'Due Soon').length;
    const maintenance = statuses.filter(s => s === 'Under Maintenance').length;
    const active      = statuses.filter(s => s === 'On Track' || s === 'Scheduled').length;

    const totalEl = document.getElementById('cuTotalVehicles');
    if (totalEl) totalEl.textContent = _vehicles.length;
    document.getElementById('cuActive').textContent         = active;
    document.getElementById('cuMaintenance').textContent    = maintenance;
    const overdueEl = document.getElementById('cuOverdue');
    if (overdueEl) overdueEl.textContent = overdue;
    document.getElementById('cuDueThisWeek').textContent    = dueThisWeek;
    document.getElementById('cuDueSoon').textContent        = dueToday;

    // ── Persist stats for instant restore ──
    try {
      sessionStorage.setItem(_CU_STATS_KEY, JSON.stringify({
        active, maintenance, dueThisWeek, dueToday,
      }));
    } catch(e) {}
    // Refresh the greeting banner whenever stats change (e.g. vehicle goes Under Maintenance)
    if (typeof _updateBannerFromCalEvents === 'function') _updateBannerFromCalEvents();
  }

  function statusStyle(status) {
    switch (status) {
      case 'Overdue':           return { color: '#E8001C',  bg: '#FFF5F5',  label: 'Overdue' };
      case 'Due Today':         return { color: '#0033A0',  bg: '#EEF2FF',  label: 'Due Today' };
      case 'Due This Week':     return { color: '#dd6b20',  bg: '#FFFBEB',  label: 'Due This Week' };
      case 'Due Soon':          return { color: '#d97706',  bg: '#FFF8E1',  label: 'Due Soon' };
      case 'Under Maintenance': return { color: '#ea580c',  bg: '#FFF8E1',  label: 'Under Maintenance' };
      default:                  return { color: '#16a34a',  bg: '#F0FFF4',  label: 'Active' };
    }
  }

  function renderVehicles() {
    const el = document.getElementById('cuVehiclesList');

    // Update vehicle count in header
    const countEl = document.getElementById('cuVehiclesCount');
    if (countEl) countEl.textContent = _vehicles.length + ' vehicle' + (_vehicles.length !== 1 ? 's' : '');

    if (!_vehicles.length) {
      el.innerHTML = '<div class="cu-empty">No vehicles registered under your name.</div>';
      return;
    }

    // ── SVGs for car / truck ──────────────────────────────────────────
    function vehicleSvg(isTruck, color) {
      const path = isTruck
        ? '<rect x="1" y="3" width="15" height="13" rx="2"/><path d="M16 8h4l3 5v3h-7V8z"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/>'
        : '<path d="M5 17H3a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h1l2-4h10l2 4h1a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-2"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="17.5" r="2.5"/>';
      return `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${path}</svg>`;
    }

    // ── Build the compact vehicle rows ───────────────────────────────
    const rowsHtml = _vehicles.map(v => {
      const status   = computeStatus(v);
      const { color, bg, label } = statusStyle(status);
      const isTruck  = (v.type || '').toLowerCase().includes('truck');
      const iconBg   = '#1a35601A'; // always dark tint for icon bg

      return `<div class="cu-vov-row" onclick="cuShowVehicle('${v.id}')">
        <div class="cu-vov-icon" style="background:${iconBg};">
          ${vehicleSvg(isTruck, '#1a3560')}
        </div>
        <div class="cu-vov-info">
          <div class="cu-vov-plate">${v.plate || '—'}</div>
          <div class="cu-vov-desc">${v.desc || '—'}</div>
        </div>
        <span class="cu-vov-badge" style="background:${color}1A;color:${color};">${label}</span>
        <button class="cu-vov-view-btn" onclick="event.stopPropagation();cuShowVehicle('${v.id}')">View</button>
      </div>`;
    }).join('');

    el.innerHTML = `
      <div class="cu-vov-body">
        <div class="cu-vov-list">${rowsHtml}</div>
      </div>`;

    // ── Persist for instant restore ──
    try {
      sessionStorage.setItem(_CU_VEH_KEY, JSON.stringify({
        html: el.innerHTML,
        count: countEl ? countEl.textContent : '',
        vehicles: _vehicles,
      }));
    } catch(e) {}
  }

  // ── Vehicle modal ─────────────────────────────────────────
  window.cuShowVehicle = async function (id) {
    const v = _vehicles.find(x => x.id === id);
    if (!v) return;

    const status = computeStatus(v);
    const { color, bg } = statusStyle(status);

    // Compute next PMS
    let nextPms = '—';
    let daysUntil = null;
    if (v.lastSvcDate && v.svcFreq) {
      const date = new Date(v.lastSvcDate);
      const months = parseInt(v.svcFreq);
      if (!isNaN(date) && months) {
        const next = new Date(date);
        next.setMonth(next.getMonth() + months);
        nextPms = next.toISOString().split('T')[0];
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const nextMidnight = new Date(next.getFullYear(), next.getMonth(), next.getDate());
        daysUntil = Math.round((nextMidnight - today) / 86400000);
      }
    }

    let statusLabel = status;
    if (status === 'Under Maintenance') {
      statusLabel = 'Under Maintenance';
    } else if (daysUntil !== null) {
      if (daysUntil < 0)       statusLabel = `Overdue ${Math.abs(daysUntil)} day${Math.abs(daysUntil) !== 1 ? 's' : ''}`;
      else if (daysUntil === 0) statusLabel = 'Due Today';
      else if (daysUntil <= 7)  statusLabel = `Due in ${daysUntil} day${daysUntil !== 1 ? 's' : ''} (This Week)`;
      else if (daysUntil <= 14) statusLabel = `Due in ${daysUntil} days (Due Soon)`;
      else if (daysUntil <= 30) statusLabel = `Due in ${daysUntil} days (Scheduled)`;
      else                      statusLabel = `Due in ${daysUntil} days (On Track)`;
    }

    document.getElementById('cuModalPlate').textContent = v.plate || '—';
    document.getElementById('cuModalDesc').textContent = v.desc || '—';

    // Check if this vehicle already has an active booking (Pending or Approved)
    let hasActiveBooking = false;
    let activeBookingStatus = '';
    let activeBookingDate = '';
    let activeBookingTime = '';
    let activeBookingPreviousDate = '';
    try {
      const bookSnap = await db.collection('service_bookings')
        .where('vehicleId', '==', v.id)
        .where('status', 'in', ['Pending', 'Approved'])
        .limit(1).get();
      if (!bookSnap.empty) {
        hasActiveBooking = true;
        const bData = bookSnap.docs[0].data();
        activeBookingStatus       = bData.status || 'Pending';
        activeBookingDate         = bData.preferredDate || '';
        activeBookingTime         = bData.preferredTime || '';
        activeBookingPreviousDate = bData.previousDate  || '';
      }
    } catch(e) { console.error('Booking check error:', e); }

    // Build overdue section: show "Already Booked" badge if booked, otherwise show Book button
    let overdueSection = '';
    if (status === 'Overdue') {
      if (hasActiveBooking) {
        const isRescheduled = activeBookingPreviousDate && activeBookingPreviousDate !== activeBookingDate;
        const isApproved    = activeBookingStatus === 'Approved';
        const badgeColor = isApproved ? '#16a34a' : '#d97706';
        const badgeBg    = isApproved ? 'rgba(22,163,74,0.08)' : 'rgba(217,119,6,0.08)';
        const badgeBorder= isApproved ? '#16a34a40' : '#d9770640';
        const badgeIcon  = isApproved
          ? '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>'
          : '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>';

        // Format date for display
        let formattedDate = '';
        if (activeBookingDate) {
          const parts = activeBookingDate.split('-');
          if (parts.length === 3) {
            const MONTHS_SHORT = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
            const m = parseInt(parts[1]) - 1;
            const d = parseInt(parts[2]);
            const y = parseInt(parts[0]);
            formattedDate = MONTHS_SHORT[m] + ' ' + d + ', ' + y;
          }
        }
        const dateTimeStr = formattedDate
          ? ' — ' + formattedDate + (activeBookingTime ? ', ' + activeBookingTime : '')
          : '';

        const badgeTitle = isRescheduled ? 'Booking Rescheduled' : 'Service Already Booked';
        let subText;
        if (isRescheduled) {
          subText = 'Rescheduled to' + (formattedDate ? ' ' + formattedDate + (activeBookingTime ? ', ' + activeBookingTime : '') : '') + '.';
        } else if (isApproved) {
          subText = 'Confirmed' + dateTimeStr + '.';
        } else {
          subText = 'Pending approval' + dateTimeStr + '.';
        }

        overdueSection = `
        <div style="margin-top:14px;padding:12px;background:${badgeBg};border-radius:12px;border:1.5px solid ${badgeBorder};">
          <div style="display:flex;align-items:center;gap:12px;">
            <div style="width:38px;height:38px;background:${badgeColor}18;border-radius:10px;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="${badgeColor}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><${badgeIcon}/></svg>
            </div>
            <div style="flex:1;">
              <div style="font-size:12px;font-weight:700;color:${badgeColor};">${badgeTitle}</div>
              <div style="font-size:11px;color:#718096;margin-top:2px;">${subText}</div>
            </div>
            <a href="customer_my_bookings.html" style="padding:6px 14px;background:${badgeColor};border:none;border-radius:8px;color:white;font-size:11px;font-weight:700;cursor:pointer;text-decoration:none;white-space:nowrap;">View</a>
          </div>
        </div>`;
      } else {
        overdueSection = `
        <div style="margin-top:14px;padding:12px;background:#fff5f5;border-radius:12px;border:1.5px solid #fed7d7;">
          <div style="display:flex;align-items:center;gap:12px;">
            <div style="width:38px;height:38px;background:rgba(0,75,95,0.1);border-radius:10px;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#004B5F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
            </div>
            <div style="flex:1;">
              <div style="font-size:12px;font-weight:700;color:#E8001C;">PMS is overdue</div>
              <div style="font-size:11px;color:#718096;margin-top:2px;">Book a service now to avoid further issues.</div>
            </div>
            <a href="customer_book_service.html?vehicleId=${v.id}" style="padding:8px 14px;background:#E8001C;border:none;border-radius:8px;color:white;font-size:12px;font-weight:700;cursor:pointer;text-decoration:none;white-space:nowrap;">Book</a>
          </div>
        </div>`;
      }
    }

    document.getElementById('cuModalDetails').innerHTML = `
      ${detailRow('#1a3560', 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 5v5l3 3', 'Last Service Odometer', v.lastSvcOdo ? Number(String(v.lastSvcOdo).replace(/[^0-9]/g, '')).toLocaleString() + ' km' : '—')}
      ${detailRow('#1a3560', 'M3 4h18v18H3zM16 2v4M8 2v4M3 10h18', 'Last Service', v.lastSvcDate ? fmtDateLong(v.lastSvcDate) : '—')}
      ${detailRow('#1a3560', 'M8 6l4-4 4 4M8 18l4 4 4-4M4 12h16', 'Next PMS Due', fmtDateLong(nextPms))}
      ${detailRow('#1a3560', 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z', 'Status', `<span style="background:${bg};color:${color};padding:3px 10px;border-radius:20px;font-size:0.78rem;font-weight:700;">${statusLabel}</span>`)}
      ${overdueSection}
    `;

    document.getElementById('cuVehicleModal').classList.add('active');
  };

  function detailRow(color, svgPath, label, value) {
    return `
      <div class="cu-detail-row">
        <div class="cu-detail-icon" style="background:${color}18;color:${color};">
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="${svgPath}"/></svg>
        </div>
        <div>
          <div class="cu-detail-label">${label}</div>
          <div class="cu-detail-value" style="color:${label === 'Status' || label === 'Next PMS Due' ? color : '#1a202c'};">${value}</div>
        </div>
      </div>`;
  }

  window.cuCloseModal = function () {
    document.getElementById('cuVehicleModal').classList.remove('active');
  };

  window.cuRequestReschedule = function (vehicleId, plate) {
    const dateInput = document.getElementById('cuRescheduleDate');
    const preferredDate = dateInput ? dateInput.value : '';
    if (!preferredDate) {
      alert('Please select a preferred reschedule date.');
      return;
    }
    const user = auth.currentUser;
    if (!user) return;

    // Check for existing pending request first
    db.collection('pms_reschedule_requests')
      .where('vehicleId', '==', vehicleId)
      .where('customerId', '==', user.uid)
      .where('status', '==', 'Pending')
      .limit(1).get()
      .then(function(snap) {
        if (!snap.empty) {
          alert('You already have a pending reschedule request for this vehicle. Please wait for the admin to review it.');
          return;
        }
        return db.collection('pms_reschedule_requests').add({
          vehicleId: vehicleId,
          plate: plate,
          customerId: user.uid,
          preferredDate: preferredDate,
          status: 'Pending',
          createdAt: firebase.firestore.FieldValue.serverTimestamp(),
        });
      }).then(function(ref) {
        if (!ref) return; // was blocked by duplicate check
        cuCloseModal();
        const toast = document.getElementById('cuToast');
        if (toast) {
          toast.textContent = '✅ Reschedule request sent! The admin will review it shortly.';
          toast.className = 'cu-toast show';
          setTimeout(function () { toast.className = 'cu-toast'; }, 4000);
        }
      }).catch(function (err) {
        alert('Failed to send request: ' + err.message);
      });
  };

  // Close modal on backdrop click
  document.getElementById('cuVehicleModal').addEventListener('click', function (e) {
    if (e.target === this) cuCloseModal();
  });

  // ── Recent Services ─────────────────────────────────────
  // Uses onSnapshot so the list updates live when a maintenance doc
  // transitions to "Completed" (admin marks service done).
  let _recentUnsubscribe = null;

  async function loadRecentServices() {
    const el = document.getElementById('cuRecentServices');
    if (!el) return;

    const user = auth.currentUser;
    if (!user) return;

    // Build the plate set — reuse already-filtered _vehicles when available
    let plates;
    if (_vehicles.length) {
      plates = new Set(_vehicles.map(v => (v.plate || '').toLowerCase()).filter(Boolean));
    } else {
      try {
        const userDoc = await db.collection('users').doc(user.uid).get();
        const uData   = userDoc.exists ? userDoc.data() : {};
        const uName   = (uData.name        || '').toLowerCase();
        const cName   = (uData.companyName || '').toLowerCase();
        const vSnap   = await db.collection('vehicles').get();
        plates = new Set(
          vSnap.docs
            .filter(d => {
              const v     = d.data();
              const owner = (v.owner || '').toLowerCase();
              if (v.ownerId === user.uid) return true;
              return (uName && owner === uName) || (cName && owner === cName);
            })
            .map(d => (d.data().plate || '').toLowerCase())
            .filter(Boolean)
        );
      } catch(e) {
        console.error('Recent services — vehicle plates error:', e);
        plates = new Set();
      }
    }

    if (!plates.size) {
      el.innerHTML = '<div class="cu-recent-empty">No completed services yet.</div>';
      return;
    }

    // Cancel any existing listener before starting a new one
    if (_recentUnsubscribe) { _recentUnsubscribe(); _recentUnsubscribe = null; }

    // Live listener on completed maintenance docs
    _recentUnsubscribe = db.collection('maintenance')
      .where('status', '==', 'Completed')
      .onSnapshot(mSnap => {
        let records = mSnap.docs
          .filter(d => plates.has((d.data().plate || '').toLowerCase()))
          .map(d => ({ id: d.id, ...d.data() }));

        // Sort newest first, cap at 5
        records.sort((a, b) => {
          const aTs = a.createdAt && a.createdAt.toMillis ? a.createdAt.toMillis() : 0;
          const bTs = b.createdAt && b.createdAt.toMillis ? b.createdAt.toMillis() : 0;
          return bTs - aTs;
        });
        records = records.slice(0, 5);

        if (!records.length) {
          el.innerHTML = '<div class="cu-recent-empty">No completed services yet.</div>';
          return;
        }

        const buildIcon = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#1a3560" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>`;

        el.innerHTML = records.map((r, i) => {
          const plate   = r.plate || '—';
          const desc    = r.desc  || r.vehicleDesc || '';
          const dateStr = r.serviceDate || r.date || (r.createdAt && r.createdAt.toDate ? _fmtDateShort(r.createdAt.toDate()) : '');
          const svcRows  = Array.isArray(r.svcRows) ? r.svcRows : [];
          const svcNames = svcRows.filter(x => x && x.name).map(x => x.name);
          const svcs     = Array.isArray(r.services) ? r.services : [];
          const svcText  = svcNames.length ? svcNames.join(', ')
                         : svcs.length     ? svcs.join(', ')
                         : (r.serviceType || r.type || 'Service');
          const isLast = i === records.length - 1;
          return `<div class="cu-recent-row">
            <div class="cu-recent-icon">${buildIcon}</div>
            <div style="flex:1;min-width:0;">
              <div class="cu-recent-svc">${_escR(svcText)}</div>
              <div class="cu-recent-plate">${_escR(plate)}${desc ? ' · ' + _escR(desc) : ''}</div>
            </div>
            ${dateStr ? `<div class="cu-recent-date" style="flex-shrink:0;margin:0 16px;white-space:nowrap;text-align:center;">${_escR(dateStr)}</div>` : ''}
            <div style="flex-shrink:0;"><div class="cu-recent-badge">Completed</div></div>
          </div>${!isLast ? '<div class="cu-recent-row-divider"></div>' : ''}`;
        }).join('');

        // Also refresh the vehicle list and stats — the vehicle's status field
        // in Firestore is updated to Active when the admin marks complete,
        // but the onSnapshot on vehicles will handle that automatically.
        // We trigger updateStats here as an extra safety net.
        if (_vehicles.length) updateStats();

        // Persist for instant restore on next page load
        try {
          sessionStorage.setItem(_CU_RECENT_KEY, JSON.stringify({ html: el.innerHTML }));
        } catch(e) {}
      }, e => {
        console.error('Recent services listener error:', e);
        el.innerHTML = '<div class="cu-recent-empty">Unable to load recent services.</div>';
      });
  }

  function _fmtDateShort(d) {
    if (!d) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[d.getMonth()] + ' ' + d.getDate() + ', ' + d.getFullYear();
  }
  function _escR(s) { return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

  // ── Helpers ──────────────────────────────────────────────
  window.cuShowNotifications = function () { /* future */ };
  window.cuShowProfile = function () { /* future */ };

  window.sfLogout = window.cuLogout = function () {
    if (!confirm('Are you sure you want to logout?')) return;
    localStorage.setItem('_loggedOut', Date.now().toString());
    // Clear dashboard cache so the next user doesn't see stale data
    try {
      sessionStorage.removeItem(_CU_VEH_KEY);
      sessionStorage.removeItem(_CU_STATS_KEY);
      sessionStorage.removeItem(_CU_RECENT_KEY);
    } catch(e) {}
    auth.signOut().finally(() => {
      sessionStorage.removeItem('cpUser');
      history.replaceState(null, '', '/index.html');
      window.location.replace('/index.html');
    });
  };

  // ── Smart AI Modal ────────────────────────────────────────
  let _aiLoaded = false, _aiVehicles = [], _aiMaintenance = [];

  window.cuOpenAI = function () {
    document.getElementById('cuAIOverlay').classList.add('active');
    if (!_aiLoaded) _loadAIData();
  };

  window.cuCloseAI = function () {
    document.getElementById('cuAIOverlay').classList.remove('active');
  };

  window.cuClearAI = function () {
    const msgs = document.getElementById('cuAIMessages');
    const welcome = document.getElementById('cuAIWelcome');
    msgs.innerHTML = '';
    msgs.appendChild(welcome);
    welcome.style.display = 'block';
    document.getElementById('cuAIChips').style.display = 'flex';
    document.getElementById('cuAIClearBtn').style.display = 'none';
  };

  async function _loadAIData() {
    _aiVehicles = _vehicles; // reuse already-loaded vehicles
    if (_aiVehicles.length) {
      const plates = _aiVehicles.map(v => v.plate).filter(Boolean).slice(0, 10);
      try {
        const mSnap = await db.collection('maintenance').where('plate', 'in', plates).get();
        _aiMaintenance = mSnap.docs.map(d => ({ id: d.id, ...d.data() }));
      } catch(e) { console.error('AI data load:', e); }
    }
    const sub = document.getElementById('cuAIWelcomeSub');
    if (sub) sub.textContent = _aiVehicles.length
      ? `Ask me anything about your ${_aiVehicles.length} vehicle${_aiVehicles.length !== 1 ? 's' : ''} — PMS status, maintenance history, and more.`
      : 'No vehicles found under your account.';
    _aiLoaded = true;
  }

  function _aiProcessQuery(q) {
    const ql = q.toLowerCase();
    if (!_aiVehicles.length) return 'No vehicles are registered under your name yet.';
    if (ql.includes('maintenance') || ql.includes('serviced')) {
      const list = _aiVehicles.filter(v => (v.status || '').toLowerCase().includes('maintenance'));
      return list.length ? 'Under maintenance:\n' + list.map(v => `• ${v.plate} — ${v.desc}`).join('\n')
        : 'None of your vehicles are currently under maintenance. ✅';
    }
    if (ql.includes('overdue') || ql.includes('past due')) {
      const list = _aiVehicles.filter(v => v.status === 'Overdue');
      return list.length ? 'PMS Overdue:\n' + list.map(v => `• ${v.plate} — ${v.desc}`).join('\n') + '\n\nPlease schedule a service soon!'
        : 'No vehicles are overdue for PMS. ✅';
    }
    if (ql.includes('due soon') || ql.includes('upcoming')) {
      const list = _aiVehicles.filter(v => v.status === 'PMS Due Soon');
      return list.length ? 'PMS Due Soon:\n' + list.map(v => `• ${v.plate} — ${v.desc}`).join('\n')
        : 'No vehicles have PMS due soon. ✅';
    }
    if (ql.includes('history') || ql.includes('service record') || ql.includes('completed')) {
      const done = _aiMaintenance.filter(m => (m.status || '').toLowerCase() === 'completed');
      if (!done.length) return 'No completed service records found for your vehicles.';
      const total = done.reduce((s, r) => {
        const raw = r.totalCost || r.cost || '0';
        return s + (typeof raw === 'number' ? raw : parseFloat(String(raw).replace(/[₱,]/g, '')) || 0);
      }, 0);
      return `You have ${done.length} completed service record${done.length !== 1 ? 's' : ''}.\nTotal spent: ₱${total.toLocaleString('en-PH', {minimumFractionDigits:2})}\n\nGo to "PMS History" tab to view full details.`;
    }
    if (ql.includes('summary') || ql.includes('status') || ql.includes('report')) {
      const active = _aiVehicles.filter(v => v.status === 'Active').length;
      const maint  = _aiVehicles.filter(v => (v.status || '').includes('Maintenance')).length;
      const over   = _aiVehicles.filter(v => v.status === 'Overdue').length;
      const soon   = _aiVehicles.filter(v => v.status === 'PMS Due Soon').length;
      return `Fleet Summary:\n✅ Active: ${active}\n🔧 Under Maintenance: ${maint}\n⚠️ PMS Overdue: ${over}\n📅 Due Soon: ${soon}\n🚗 Total: ${_aiVehicles.length}`;
    }
    if (ql.includes('vehicle') || ql.includes('fleet') || ql.includes('list') || ql.includes('all my')) {
      const lines = _aiVehicles.map(v => {
        const e = v.status === 'Active' ? '✅' : v.status === 'Under Maintenance' ? '🔧' : v.status === 'Overdue' ? '⚠️' : v.status === 'PMS Due Soon' ? '📅' : '•';
        return `${e} ${v.plate} — ${v.desc} (${v.status || 'Active'})`;
      }).join('\n');
      return `Your fleet (${_aiVehicles.length} vehicle${_aiVehicles.length !== 1 ? 's' : ''}):\n${lines}`;
    }
    return 'I can help you with:\n• Vehicle status & fleet summary\n• PMS overdue or due soon\n• Vehicles under maintenance\n• Service history & total cost\n\nTry asking: "Which vehicles are overdue?"';
  }

  window.cuAISend = function (preset) {
    const input = document.getElementById('cuAIInput');
    const text = (preset || input.value).trim();
    if (!text) return;

    document.getElementById('cuAIWelcome').style.display = 'none';
    document.getElementById('cuAIChips').style.display = 'none';
    document.getElementById('cuAIClearBtn').style.display = 'block';

    const msgs = document.getElementById('cuAIMessages');
    const userBubble = document.createElement('div');
    userBubble.className = 'cu-ai-bubble user';
    userBubble.textContent = text;
    msgs.appendChild(userBubble);
    input.value = '';
    input.style.height = 'auto';
    userBubble.scrollIntoView({ behavior: 'smooth' });

    if (!_aiLoaded) {
      const b = document.createElement('div');
      b.className = 'cu-ai-bubble bot';
      b.textContent = 'Loading your fleet data, please try again in a moment.';
      msgs.appendChild(b);
      return;
    }

    const typing = document.createElement('div');
    typing.className = 'cu-ai-typing';
    typing.innerHTML = '<span></span><span></span><span></span>';
    msgs.appendChild(typing);
    typing.scrollIntoView({ behavior: 'smooth' });

    setTimeout(() => {
      typing.remove();
      const botBubble = document.createElement('div');
      botBubble.className = 'cu-ai-bubble bot';
      botBubble.textContent = _aiProcessQuery(text);
      msgs.appendChild(botBubble);
      botBubble.scrollIntoView({ behavior: 'smooth' });
    }, 500);
  };

})();



