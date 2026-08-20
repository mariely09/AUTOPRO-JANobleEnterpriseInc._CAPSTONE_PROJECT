(function () {
  'use strict';

  // ── Auth guard ──────────────────────────────────────────
  const stored = sessionStorage.getItem('spUser');
  console.log('staff_dashboard.js loaded, spUser in sessionStorage:', !!stored);
  
  if (!stored) { 
    console.log('No spUser in sessionStorage, checking Firebase auth...');
    // Don't redirect immediately - wait for Firebase to initialize
  }
  
  const spUser = stored ? JSON.parse(stored) : {};
  console.log('spUser data:', spUser);

  // ── Back/Forward navigation guard (bfcache) ─────────────
  window.addEventListener('pageshow', function (e) {
    var hasSession = sessionStorage.getItem('spUser') || sessionStorage.getItem('apUser');
    if (!hasSession) {
      window.location.replace('/login.html');
      return;
    }
    if (e.persisted) {
      if (typeof firebase !== 'undefined' && firebase.auth && !firebase.auth().currentUser) {
        sessionStorage.removeItem('spUser');
        window.location.replace('/login.html');
      }
    }
  });

  const db   = firebase.firestore();
  const auth = firebase.auth();

  // ── Init ────────────────────────────────────────────────
  document.addEventListener('DOMContentLoaded', () => {
    console.log('staff_dashboard DOMContentLoaded');
    
    // Check Firebase auth state
    firebase.auth().onAuthStateChanged((user) => {
      console.log('Firebase auth state changed, user:', user?.uid);
      
      if (user) {
        console.log('Firebase user authenticated:', user.uid);
        // Store in sessionStorage if not already there
        if (!sessionStorage.getItem('spUser')) {
          console.log('spUser not in sessionStorage, storing from Firebase...');
          const userData = {
            uid: user.uid,
            email: user.email,
            name: spUser.name || user.displayName || '',
            role: spUser.role || 'staff',
          };
          sessionStorage.setItem('spUser', JSON.stringify(userData));
          console.log('Stored spUser:', userData);
        }
        loadUserInfo();
        loadDashboard();
        loadInventory();
        loadServices();
        loadVehicles();
      } else {
        console.log('No Firebase user, redirecting to login');
        window.location.href = '/login.html';
      }
    });
  });

  // ── User info ────────────────────────────────────────────
  function loadUserInfo() {
    const name = spUser.name || 'Staff Member';
    const initials = name.split(' ').map(p => p[0]).join('').toUpperCase().slice(0, 2) || 'ST';
    document.getElementById('sfAvatar').textContent = initials;
    document.getElementById('sfUserAvatar').textContent = initials;
    document.getElementById('sfUserName').textContent = name;
  }

  // ── Section switching ────────────────────────────────────
  window.sfSwitchSection = function (section, btn) {
    document.querySelectorAll('.sf-section').forEach(s => s.classList.remove('active'));
    document.querySelectorAll('.sf-nav-btn').forEach(b => b.classList.remove('active'));
    const map = { dashboard: 'sfDashboard', inventory: 'sfInventory', maintenance: 'sfMaintenance', vehicles: 'sfVehicles' };
    const el = document.getElementById(map[section]);
    if (el) el.classList.add('active');
    if (btn) btn.classList.add('active');
  };

  // ── Toast ────────────────────────────────────────────────
  function showToast(msg, type = 'error') {
    const t = document.getElementById('sfToast');
    t.textContent = msg;
    t.className = type === 'success' ? 'show success' : 'show';
    clearTimeout(t._timer);
    t._timer = setTimeout(() => { t.className = ''; }, 3500);
  }

  // ── Logout ───────────────────────────────────────────────
  window.sfLogout = function () {
    if (!confirm('Are you sure you want to logout?')) return;
    localStorage.setItem('_loggedOut', Date.now().toString());
    auth.signOut().finally(() => {
      sessionStorage.removeItem('spUser');
      history.replaceState(null, '', '/index.html');
      window.location.replace('/index.html');
    });
  };

  window.sfShowProfile = function () { sfSwitchSection('profile', null); };
  window.sfShowNotifications = function () { /* future */ };

  // ── DASHBOARD ────────────────────────────────────────────
  function loadDashboard() {
    const now = new Date();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const todayStr = `${months[now.getMonth()]} ${now.getDate()}, ${now.getFullYear()}`;

    db.collection('maintenance').orderBy('createdAt', 'desc').onSnapshot(snap => {
      const all = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      const ongoing   = all.filter(s => s.status === 'Ongoing').length;
      const completed = all.filter(s => s.status === 'Completed').length;
      const today     = all.filter(s => s.date === todayStr);

      document.getElementById('sfTotalServices').textContent = all.length;
      document.getElementById('sfOngoing').textContent = ongoing;
      document.getElementById('sfCompleted').textContent = completed;

      renderTodaySchedule(today);
    });

    db.collection('stock_inventory').onSnapshot(snap => {
      const low = snap.docs.filter(d => d.data().status === 'Low').length;
      document.getElementById('sfLowStock').textContent = low;
    });
  }

  function renderTodaySchedule(services) {
    const el = document.getElementById('sfTodaySchedule');
    if (!services.length) {
      el.innerHTML = '<div class="sf-empty">No services scheduled for today.</div>';
      return;
    }
    el.innerHTML = services.slice(0, 8).map(s => {
      const rows = s.svcRows || [];
      const svcName = rows.length ? (rows[0].name || '—') : (s.desc || '—');
      const statusClass = s.status === 'Completed' ? 'completed' : s.status === 'Ongoing' ? 'ongoing' : 'pending';
      return `
        <div class="sf-schedule-row">
          <div class="sf-schedule-icon">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/></svg>
          </div>
          <div style="flex:1;">
            <div class="sf-schedule-plate">${s.plate || '—'}</div>
            <div class="sf-schedule-service">${svcName} · ${s.mechanic || '—'}</div>
          </div>
          <span class="sf-badge ${statusClass}">${s.status || '—'}</span>
        </div>`;
    }).join('');
  }

  // ── INVENTORY ────────────────────────────────────────────
  let _inventory = [];

  function loadInventory() {
    db.collection('stock_inventory').onSnapshot(snap => {
      _inventory = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      sfRenderInventory();
    });
  }

  window.sfRenderInventory = function () {
    const q = (document.getElementById('sfInvSearch')?.value || '').toLowerCase();
    const items = _inventory.filter(i => !q || (i.name || '').toLowerCase().includes(q) || (i.num || '').toLowerCase().includes(q));
    const el = document.getElementById('sfInventoryList');
    if (!items.length) { el.innerHTML = '<div class="sf-empty">No items found.</div>'; return; }
    el.innerHTML = items.map(item => {
      const isLow = item.status === 'Low';
      const iconColor = isLow ? '#ea580c' : '#E8001C';
      const iconBg = isLow ? '#fff7ed' : '#f0f4ff';
      return `
        <div class="sf-inv-row">
          <div class="sf-inv-icon" style="background:${iconBg};color:${iconColor};">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/></svg>
          </div>
          <div style="flex:1;">
            <div style="font-size:13px;font-weight:600;color:#1a202c;">${item.name || '—'}</div>
            <div style="font-size:11px;color:#718096;">${item.num || ''} · ${item.group || ''}</div>
          </div>
          <div style="text-align:right;">
            <div style="font-size:14px;font-weight:700;color:${isLow ? '#ea580c' : '#1a202c'};">${item.stock ?? 0} ${item.uom || ''}</div>
            <span class="sf-badge ${isLow ? 'low' : 'ok'}">${isLow ? 'Low Stock' : 'OK'}</span>
          </div>
        </div>`;
    }).join('');
  };

  // ── SERVICES ─────────────────────────────────────────────
  let _services = [];

  function loadServices() {
    db.collection('maintenance').orderBy('createdAt', 'desc').onSnapshot(snap => {
      _services = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      sfRenderServices();
    });
  }

  window.sfRenderServices = function () {
    const q = (document.getElementById('sfSvcSearch')?.value || '').toLowerCase();
    const items = _services.filter(s => !q || (s.plate || '').toLowerCase().includes(q) || (s.mechanic || '').toLowerCase().includes(q));
    const el = document.getElementById('sfServicesList');
    if (!items.length) { el.innerHTML = '<div class="sf-empty">No services found.</div>'; return; }
    el.innerHTML = `
      <div class="sf-table-wrap">
        <table class="sf-table">
          <thead><tr>
            <th>Date</th><th>Plate</th><th>Description</th><th>Mechanic</th><th>Total Cost</th><th>Status</th>
          </tr></thead>
          <tbody>
            ${items.map(s => {
              const rows = s.svcRows || [];
              const desc = rows.length ? rows.map(r => r.name).filter(Boolean).join(', ') : (s.desc || '—');
              const statusClass = s.status === 'Completed' ? 'completed' : s.status === 'Ongoing' ? 'ongoing' : 'pending';
              return `<tr>
                <td>${s.date || '—'}</td>
                <td><strong>${s.plate || '—'}</strong></td>
                <td>${desc}</td>
                <td>${s.mechanic || '—'}</td>
                <td>₱${parseFloat(s.totalCost || 0).toLocaleString('en-PH', {minimumFractionDigits:2})}</td>
                <td><span class="sf-badge ${statusClass}">${s.status || '—'}</span></td>
              </tr>`;
            }).join('')}
          </tbody>
        </table>
      </div>`;
  };

  // ── VEHICLES ─────────────────────────────────────────────
  let _vehicles = [];

  function loadVehicles() {
    db.collection('vehicles').onSnapshot(snap => {
      _vehicles = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      sfRenderVehicles();
    });
  }

  window.sfRenderVehicles = function () {
    const q = (document.getElementById('sfVehicleSearch')?.value || '').toLowerCase();
    const items = _vehicles.filter(v => !q || (v.plate || '').toLowerCase().includes(q) || (v.desc || '').toLowerCase().includes(q));
    const el = document.getElementById('sfVehiclesList');
    if (!items.length) { el.innerHTML = '<div class="sf-empty">No vehicles found.</div>'; return; }
    el.innerHTML = `
      <div class="sf-table-wrap">
        <table class="sf-table">
          <thead><tr>
            <th>Asset No.</th><th>Plate</th><th>Description</th><th>Owner</th><th>Odometer</th><th>Status</th>
          </tr></thead>
          <tbody>
            ${items.map(v => {
              const statusClass = v.status === 'Good' ? 'ok' : v.status === 'Overdue' ? 'low' : 'ongoing';
              return `<tr>
                <td>${v.assetNum || '—'}</td>
                <td><strong>${v.plate || '—'}</strong></td>
                <td>${v.desc || '—'}</td>
                <td>${v.owner || '—'}</td>
                <td>${v.odometer ? v.odometer.toLocaleString() + ' km' : '—'}</td>
                <td><span class="sf-badge ${statusClass}">${v.status || '—'}</span></td>
              </tr>`;
            }).join('')}
          </tbody>
        </table>
      </div>`;
  };

  // ── RECEIVE ITEMS MODAL ───────────────────────────────────
  let _receiveItem = null;

  window.sfOpenReceiveModal = function () {
    document.getElementById('sfReceiveModal').classList.add('active');
    document.getElementById('sfReceiveSearch').value = '';
    document.getElementById('sfReceiveQty').value = '';
    document.getElementById('sfReceiveInfo').style.display = 'none';
    _receiveItem = null;
  };

  window.sfCloseReceiveModal = function () {
    document.getElementById('sfReceiveModal').classList.remove('active');
  };

  window.sfSearchReceiveItem = async function () {
    const q = document.getElementById('sfReceiveSearch').value.trim().toLowerCase();
    if (!q) { document.getElementById('sfReceiveInfo').style.display = 'none'; return; }
    const snap = await db.collection('stock_inventory').get();
    const found = snap.docs.find(d => {
      const data = d.data();
      return (data.name || '').toLowerCase().includes(q) || (data.num || '').toLowerCase().includes(q);
    });
    const info = document.getElementById('sfReceiveInfo');
    if (found) {
      _receiveItem = { id: found.id, ...found.data() };
      document.getElementById('sfReceiveItemName').textContent = _receiveItem.name || '—';
      document.getElementById('sfReceiveCurrentStock').textContent = `${_receiveItem.stock ?? 0} ${_receiveItem.uom || ''}`;
      info.style.display = 'block';
    } else {
      _receiveItem = null;
      info.style.display = 'none';
    }
  };

  window.sfSubmitReceive = async function () {
    if (!_receiveItem) { showToast('Please search and select an item first.'); return; }
    const qty = parseInt(document.getElementById('sfReceiveQty').value);
    if (!qty || qty < 1) { showToast('Please enter a valid quantity.'); return; }
    try {
      const newStock = (_receiveItem.stock || 0) + qty;
      const min = _receiveItem.min || 0;
      await db.collection('stock_inventory').doc(_receiveItem.id).update({
        stock: newStock,
        status: newStock >= min ? 'OK' : 'Low',
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      await db.collection('transactions').add({
        item: _receiveItem.name || '',
        desc: 'Stock received',
        type: 'IN',
        qty: `+${qty}`,
        date: (function(){ var _d=new Date(),_m=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']; return _m[_d.getMonth()]+' '+_d.getDate()+', '+_d.getFullYear(); })(),
        by: spUser.name || 'Staff',
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      sfCloseReceiveModal();
      showToast(`+${qty} received. New stock: ${newStock}`, 'success');
    } catch (e) {
      showToast('Error: ' + e.message);
    }
  };

  // ── NEW SERVICE MODAL ─────────────────────────────────────
  window.sfOpenNewServiceModal = function () {
    document.getElementById('sfNewServiceModal').classList.add('active');
    document.getElementById('sfSvcPlate').value = '';
    document.getElementById('sfSvcMechanic').value = '';
    document.getElementById('sfSvcDate').value = new Date().toISOString().split('T')[0];
    document.getElementById('sfSvcDesc').value = '';
    document.getElementById('sfSvcStatus').value = 'Ongoing';
    document.getElementById('sfSvcCost').value = '';
  };

  window.sfCloseNewServiceModal = function () {
    document.getElementById('sfNewServiceModal').classList.remove('active');
  };

  window.sfSubmitService = async function () {
    const plate    = document.getElementById('sfSvcPlate').value.trim().toUpperCase();
    const mechanic = document.getElementById('sfSvcMechanic').value.trim();
    const date     = document.getElementById('sfSvcDate').value;
    const desc     = document.getElementById('sfSvcDesc').value.trim();
    const status   = document.getElementById('sfSvcStatus').value;
    const cost     = parseFloat(document.getElementById('sfSvcCost').value) || 0;

    if (!plate || !mechanic || !date) { showToast('Please fill in required fields.'); return; }

    try {
      const dateFormatted = new Date(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });

      // ── Resolve vehicleId + ownerId from the vehicle document ────────────
      // ownerId is authoritative from vehicle — never trust a client value.
      let resolvedVehicleId = '';
      let resolvedOwnerId   = '';
      try {
        let vSnap = await db.collection('vehicles').where('plateNumber', '==', plate).limit(1).get();
        if (vSnap.empty) {
          vSnap = await db.collection('vehicles').where('plate', '==', plate).limit(1).get();
        }
        if (!vSnap.empty) {
          resolvedVehicleId = vSnap.docs[0].id;
          resolvedOwnerId   = vSnap.docs[0].data().ownerId || '';
        }
      } catch (_) { /* non-fatal — migration script fills gaps */ }

      const record = {
        plateNumber: plate,   // canonical
        plate,                // legacy alias
        mechanic,
        date: dateFormatted,
        desc,
        status,
        cost,
        totalCost: cost,
        createdBy: spUser.name || 'Staff',
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      };
      if (resolvedVehicleId) record.vehicleId = resolvedVehicleId;
      if (resolvedOwnerId)   record.ownerId   = resolvedOwnerId;

      await db.collection('maintenance').add(record);
      sfCloseNewServiceModal();
      showToast('Service saved successfully.', 'success');
    } catch (e) {
      showToast('Error: ' + e.message);
    }
  };

  // ── ADD VEHICLE MODAL ─────────────────────────────────────
  window.sfOpenAddVehicleModal = function () {
    document.getElementById('sfAddVehicleModal').classList.add('active');
  };

  window.sfCloseAddVehicleModal = function () {
    document.getElementById('sfAddVehicleModal').classList.remove('active');
  };

  window.sfSubmitAddVehicle = async function () {
    const plate = document.getElementById('sfVPlate').value.trim().toUpperCase();
    const desc  = document.getElementById('sfVDesc').value.trim();
    const owner = document.getElementById('sfVOwner').value.trim();
    const odo   = parseInt(document.getElementById('sfVOdo').value) || 0;

    if (!plate || !desc || !owner) { showToast('Please fill in required fields.'); return; }

    try {
      const snap = await db.collection('vehicles').get();
      const assetNum = `AST-${String(snap.size + 1).padStart(3, '0')}`;

      // Resolve ownerId from owner name so AI can use UID-based lookup
      let ownerId = '';
      try {
        let ownerSnap = await db.collection('users')
          .where('name', '==', owner)
          .where('role', '==', 'customer')
          .limit(1).get();
        if (ownerSnap.empty) {
          ownerSnap = await db.collection('users')
            .where('companyName', '==', owner)
            .where('role', '==', 'customer')
            .limit(1).get();
        }
        if (!ownerSnap.empty) ownerId = ownerSnap.docs[0].id;
      } catch (_) { /* non-fatal */ }

      const vehicleData = {
        assetNum,
        // ── Canonical field names ─────────────────────────────
        plateNumber: plate,
        description: desc,
        owner,
        odometer: odo,
        // ── Legacy aliases (kept for backward compatibility) ──
        plate,
        desc,
        odo: odo ? `${odo} km` : '',
        // ── Status ────────────────────────────────────────────
        status: 'Active',
        createdAt: firebase.firestore.FieldValue.serverTimestamp(),
      };
      if (ownerId) vehicleData.ownerId = ownerId;

      await db.collection('vehicles').add(vehicleData);
      sfCloseAddVehicleModal();
      showToast('Vehicle added successfully.', 'success');
    } catch (e) {
      showToast('Error: ' + e.message);
    }
  };

})();
