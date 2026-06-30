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

  // ── Init ────────────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', () => {
    // Show loading state immediately
    document.getElementById('cuVehiclesList').innerHTML =
      '<div class="cu-empty" style="color:#718096;">Loading...</div>';

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

    if (!_userName) {
      // Fetch from Firestore (authenticated)
      const userDoc = await db.collection('users').doc(user.uid).get();
      if (userDoc.exists) _userName = userDoc.data().name || '';
    }
    if (!_userName && cpUser.email) {
      const snap = await db.collection('users').where('email', '==', cpUser.email).limit(1).get();
      if (!snap.empty) _userName = snap.docs[0].data().name || '';
    }

    const initials = _userName.split(' ').filter(Boolean).map(p => p[0]).join('').toUpperCase().slice(0, 2) || 'CU';
    document.getElementById('cuAvatar').textContent = initials;
    const headerNameEl = document.getElementById('cuHeaderName');
    if (headerNameEl) headerNameEl.textContent = _userName || 'Customer';
    loadVehicles();
  }

  // ── Vehicles ─────────────────────────────────────────────
  function loadVehicles() {
    db.collection('vehicles').onSnapshot(snap => {
      const all = snap.docs.map(d => ({ id: d.id, ...d.data() }));

      // Filter by owner name — exact match like Flutter
      _vehicles = all.filter(v => {
        const owner = (v.owner || '').toLowerCase().trim();
        const name = _userName.toLowerCase().trim();
        return owner === name;
      });

      updateStats();
      renderVehicles();
    });
  }

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
    if (v.status === 'Under Maintenance') return 'Under Maintenance';
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
    const statuses = _vehicles.map(v => computeStatus(v));
    document.getElementById('cuTotalVehicles').textContent = _vehicles.length;
    document.getElementById('cuTotalVehiclesIcon').innerHTML = fleetIconSvg(_vehicles, 20);
    document.getElementById('cuActive').textContent       = statuses.filter(s => s === 'On Track' || s === 'Scheduled').length;
    document.getElementById('cuMaintenance').textContent  = statuses.filter(s => s === 'Under Maintenance').length;
    document.getElementById('cuOverdue').textContent      = statuses.filter(s => s === 'Overdue').length;
    document.getElementById('cuDueThisWeek').textContent  = statuses.filter(s => s === 'Due This Week').length;
    document.getElementById('cuDueSoon').textContent      = statuses.filter(s => s === 'Due Today').length;
  }

  function statusStyle(status) {
    switch (status) {
      case 'Overdue':           return { color: '#E8001C',  bg: 'rgba(232,0,28,0.08)',   label: 'Overdue' };
      case 'Due Today':         return { color: '#0033A0',  bg: 'rgba(0,51,160,0.08)',    label: 'Due Today' };
      case 'Due This Week':     return { color: '#dd6b20',  bg: 'rgba(221,107,32,0.08)', label: 'Due This Week' };
      case 'Due Soon':          return { color: '#d97706',  bg: 'rgba(217,119,6,0.08)',  label: 'Due Soon' };
      case 'Under Maintenance': return { color: '#ea580c',  bg: 'rgba(234,88,12,0.08)',  label: 'Under Maintenance' };
      default:                  return { color: '#16a34a',  bg: 'rgba(22,163,74,0.08)',  label: 'Active' }; // On Track + Scheduled
    }
  }

  function renderVehicles() {
    const el = document.getElementById('cuVehiclesList');
    if (!_vehicles.length) {
      el.innerHTML = '<div class="cu-empty">No vehicles registered under your name.</div>';
      return;
    }

    el.innerHTML = `<div class="cu-vehicles-grid">${_vehicles.map(v => {
      const status = computeStatus(v);
      const { color, bg, label } = statusStyle(status);

      return `
        <div class="cu-vehicle-card" onclick="cuShowVehicle('${v.id}')">
          <div class="cu-vehicle-card-header">
            <div style="flex:1;min-width:0;">
              <div class="cu-vehicle-plate">${v.plate || '—'}</div>
              <div class="cu-vehicle-desc">${v.desc || '—'}</div>
            </div>
            <span class="cu-vehicle-status-badge" style="background:${bg};color:${color};">${label}</span>
          </div>
          <div class="cu-vehicle-card-body">
            <div class="cu-vehicle-meta-row">
              <div class="cu-vehicle-meta-item">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 5v5l3 3"/></svg>
                <span>${v.odo ? String(v.odo).replace(/\s*km$/i, '') + ' km' : '—'}</span>
              </div>
              <div class="cu-vehicle-meta-item">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
                <span>${v.lastSvcDate ? fmtDateLong(v.lastSvcDate) : '—'}</span>
              </div>
            </div>
          </div>
          <div class="cu-vehicle-card-footer">
            <span>View details</span>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
          </div>
        </div>`;
    }).join('')}</div>`;
  }

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

    // Show modal immediately with a loading state for the booking banner
    document.getElementById('cuModalDetails').innerHTML = `
      ${detailRow('#718096', 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 5v5l3 3', 'Last Service Odometer', v.lastSvcOdo ? Number(String(v.lastSvcOdo).replace(/[^0-9]/g, '')).toLocaleString() + ' km' : '—')}
      ${detailRow('#2b6cb0', 'M3 4h18v18H3zM16 2v4M8 2v4M3 10h18', 'Last Service', v.lastSvcDate ? fmtDateLong(v.lastSvcDate) : '—')}
      ${detailRow(color, 'M8 6l4-4 4 4M8 18l4 4 4-4M4 12h16', 'Next PMS Due', fmtDateLong(nextPms))}
      ${detailRow(color, 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z', 'Status', `<span style="background:${bg};color:${color};padding:3px 10px;border-radius:20px;font-size:0.78rem;font-weight:700;">${statusLabel}</span>`)}
      <div id="cuModalBookingBanner" style="margin-top:14px;"></div>
    `;

    document.getElementById('cuVehicleModal').classList.add('active');

    // Check for active booking on this vehicle
    if (status === 'Overdue') {
      try {
        const user = auth.currentUser;
        const snap = await db.collection('service_bookings')
          .where('vehicleId', '==', v.id)
          .where('status', 'in', ['Approved', 'Pending'])
          .limit(1)
          .get();
        const banner = document.getElementById('cuModalBookingBanner');
        if (!banner) return;
        if (!snap.empty) {
          // Already has an active booking — show status instead
          const booking = snap.docs[0].data();
          const bStatus = booking.status || 'Pending';
          const bDate = booking.preferredDate ? fmtDateLong(booking.preferredDate) : '—';
          const isApproved = bStatus === 'Approved';
          banner.innerHTML = `
            <div style="padding:12px;background:${isApproved ? '#f0fdf4' : '#fffbeb'};border-radius:12px;border:1.5px solid ${isApproved ? '#c6f6d5' : '#fde68a'};">
              <div style="display:flex;align-items:center;gap:12px;">
                <div style="width:38px;height:38px;background:${isApproved ? 'rgba(22,163,74,0.1)' : 'rgba(217,119,6,0.1)'};border-radius:10px;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="${isApproved ? '#16a34a' : '#d97706'}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
                </div>
                <div style="flex:1;">
                  <div style="font-size:12px;font-weight:700;color:${isApproved ? '#16a34a' : '#d97706'};">Service ${isApproved ? 'Booked & Confirmed' : 'Booking Pending'}</div>
                  <div style="font-size:11px;color:#718096;margin-top:2px;">Scheduled for ${bDate}</div>
                </div>
                <a href="customer_my_bookings.html" style="padding:8px 14px;background:${isApproved ? '#16a34a' : '#d97706'};border:none;border-radius:8px;color:white;font-size:12px;font-weight:700;cursor:pointer;text-decoration:none;white-space:nowrap;">View</a>
              </div>
            </div>`;
        } else {
          // No active booking — show Book Now banner
          banner.innerHTML = `
            <div style="padding:12px;background:#fff5f5;border-radius:12px;border:1.5px solid #fed7d7;">
              <div style="display:flex;align-items:center;gap:12px;">
                <div style="width:38px;height:38px;background:rgba(232,0,28,0.1);border-radius:10px;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#E8001C" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
                </div>
                <div style="flex:1;">
                  <div style="font-size:12px;font-weight:700;color:#E8001C;">PMS is overdue</div>
                  <div style="font-size:11px;color:#718096;margin-top:2px;">Book a service now to avoid further issues.</div>
                </div>
                <a href="customer_book_service.html?vehicleId=${v.id}" style="padding:8px 14px;background:#E8001C;border:none;border-radius:8px;color:white;font-size:12px;font-weight:700;cursor:pointer;text-decoration:none;white-space:nowrap;">Book</a>
              </div>
            </div>`;
        }
      } catch(e) {
        console.error('Booking check failed:', e);
      }
    }
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

  // ── Helpers ──────────────────────────────────────────────
  window.cuShowNotifications = function () { /* future */ };
  window.cuShowProfile = function () { /* future */ };

  window.sfLogout = window.cuLogout = function () {
    if (!confirm('Are you sure you want to logout?')) return;
    auth.signOut().then(() => {
      sessionStorage.removeItem('cpUser');
      window.location.href = '/index.html';
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


