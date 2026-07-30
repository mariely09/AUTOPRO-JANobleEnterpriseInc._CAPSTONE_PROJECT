// customer_mobileview.js — Mobile Customer Portal
// Depends on script.js (provides: assets)

(function () {

    // ── Auth guard ──────────────────────────────────────────
    var stored = sessionStorage.getItem('cpUser');
    if (!stored) { window.location.href = 'index.html'; return; }
    var cpUser = JSON.parse(stored);
    window.currentUser = cpUser;

    // ── Init UI ─────────────────────────────────────────────
    document.getElementById('mobCustomerName') && (document.getElementById('mobCustomerName').textContent = cpUser.name);
    document.getElementById('mobAvatar').textContent = cpUser.avatar || cpUser.name.charAt(0).toUpperCase();

    renderMobVehicles();
    renderMobProfile();
    renderMobNotifications();

    // ── Section switching ───────────────────────────────────
    window.mobSwitchSection = function (sectionId, btn) {
        document.querySelectorAll('.mob-section').forEach(function (s) { s.classList.remove('active'); });
        document.querySelectorAll('.mob-nav-btn').forEach(function (b) { b.classList.remove('active'); });
        var sec = document.getElementById(sectionId);
        if (sec) sec.classList.add('active');
        if (btn) btn.classList.add('active');
    };

    // ── Render vehicles ─────────────────────────────────────
    function renderMobVehicles() {
        var ownerName = cpUser.name;
        var companyName = cpUser.companyName || window._cpCompanyName || '';
        var myAssets = assets.filter(function (a) {
            var owner = (a.owner || '').toLowerCase().trim();
            return owner === ownerName.toLowerCase().trim() ||
                   (companyName && owner === companyName.toLowerCase().trim());
        });
        var today = new Date(); today.setHours(0, 0, 0, 0);

        var total = myAssets.length;
        var underMaint = myAssets.filter(function (a) { return a.status === 'maintenance'; }).length;
        var pmsDueSoon = myAssets.filter(function (a) {
            if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
            var diff = Math.ceil((new Date(a.nextPMSDue) - today) / 86400000);
            return diff >= 0 && diff <= 14;
        }).length;
        var pmsOverdue = myAssets.filter(function (a) {
            if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
            var due = new Date(a.nextPMSDue); due.setHours(0, 0, 0, 0);
            return due < today;
        }).length;

        // Stats
        var statsEl = document.getElementById('mobVehicleStats');
        if (statsEl) {
            statsEl.innerHTML = [
                { icon: '🚛', label: 'Total Vehicles', num: total, sub: ownerName + '\u2019s fleet' },
                { icon: '🔧', label: 'Under Maintenance', num: underMaint, sub: 'Being serviced' },
                { icon: '📅', label: 'PMS Due Soon', num: pmsDueSoon, sub: 'Within 14 days' },
                { icon: '⚠️', label: 'PMS Overdue', num: pmsOverdue, sub: 'Needs attention' }
            ].map(function (s) {
                return '<div class="mob-stat-card">'
                    + '<div class="mob-stat-bg-icon">' + s.icon + '</div>'
                    + '<div class="mob-stat-label">' + s.label + '</div>'
                    + '<div class="mob-stat-num">' + s.num + '</div>'
                    + '<div class="mob-stat-sub">' + s.sub + '</div>'
                    + '</div>';
            }).join('');
        }

        // Vehicle cards
        var listEl = document.getElementById('mobVehiclesList');
        if (!listEl) return;

        if (myAssets.length === 0) {
            listEl.innerHTML = '<div class="mob-empty">No vehicles found for this account.</div>';
            return;
        }

        var statusConfig = {
            maintenance: { label: 'Under Maintenance', color: '#3182ce', bg: '#ebf8ff', border: '#bee3f8', dot: '#3182ce' },
            inactive:    { label: 'Inactive',          color: '#718096', bg: '#f7fafc', border: '#e2e8f0', dot: '#a0aec0' }
        };

        function fmtDate(d) {
            return d ? new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '—';
        }

        function getPmsConfig(asset) {
            if (asset.status === 'maintenance') return statusConfig.maintenance;
            if (asset.status === 'inactive')    return statusConfig.inactive;
            if (asset.nextPMSDue) {
                var due = new Date(asset.nextPMSDue); due.setHours(0,0,0,0);
                var diff = Math.ceil((due - today) / 86400000);
                if (diff < 0)   return { label: 'PMS Overdue',  color: '#e53e3e', bg: '#fff5f5', border: '#feb2b2', dot: '#e53e3e', diff: diff };
                if (diff <= 14) return { label: 'PMS Due Soon', color: '#ed8936', bg: '#fffbeb', border: '#fbd38d', dot: '#ed8936', diff: diff };
            }
            return { label: 'Active', color: '#38a169', bg: '#f0fff4', border: '#9ae6b4', dot: '#38a169' };
        }

        listEl.innerHTML = myAssets.map(function (asset) {
            var sc      = getPmsConfig(asset);
            var nextPMS = fmtDate(asset.nextPMSDue);
            var lastSvc = fmtDate(asset.lastServiceDate);
            var odo     = asset.odometer ? asset.odometer.toLocaleString() + ' km' : '—';
            var lastOdoRec = (asset.maintenanceHistory || []).slice().sort(function(a,b){ return new Date(b.date)-new Date(a.date); });
            var lastOdo = lastOdoRec.length && lastOdoRec[0].km ? lastOdoRec[0].km.toLocaleString() + ' km' : '—';

            var pmsNote = '';
            if (typeof sc.diff !== 'undefined') {
                pmsNote = sc.diff < 0
                    ? '<span class="mob-pms-note red">Overdue by ' + Math.abs(sc.diff) + ' day(s)</span>'
                    : '<span class="mob-pms-note orange">Due in ' + sc.diff + ' day(s)</span>';
            }

            return '<div class="mob-veh-card">'
                // Header
                + '<div class="mob-veh-header">'
                + '<div class="mob-veh-icon-wrap" style="background:' + sc.bg + ';border:1px solid ' + sc.border + ';">' + (asset.icon || '🚗') + '</div>'
                + '<div class="mob-veh-header-info">'
                + '<div class="mob-veh-name">' + asset.assetDescription + '</div>'
                + '<div class="mob-veh-sub">' + asset.plateNumber + ' · ' + asset.assetNum + '</div>'
                + '</div>'
                + '<span class="mob-veh-status-badge" style="background:' + sc.bg + ';color:' + sc.color + ';border:1px solid ' + sc.border + ';">'
                + '<span style="width:6px;height:6px;border-radius:50%;background:' + sc.dot + ';display:inline-block;flex-shrink:0;"></span>'
                + sc.label + '</span>'
                + '</div>'
                // Chips
                + '<div class="mob-veh-chips-row">'
                + '<div class="mob-veh-chip"><span class="mob-veh-chip-label">Last Odometer</span><span class="mob-veh-chip-val">' + lastOdo + '</span></div>'
                + '<div class="mob-veh-chip"><span class="mob-veh-chip-label">Current Odometer</span><span class="mob-veh-chip-val">' + odo + '</span></div>'
                + '</div>'
                // PMS row
                + '<div class="mob-veh-pms-row">'
                + '<div class="mob-veh-pms-block"><span class="mob-veh-pms-label">Last Service</span><span class="mob-veh-pms-val">' + lastSvc + '</span></div>'
                + '<div class="mob-veh-pms-arrow">→</div>'
                + '<div class="mob-veh-pms-block"><span class="mob-veh-pms-label">Next PMS</span><span class="mob-veh-pms-val" style="color:' + sc.color + ';">' + nextPMS + '</span></div>'
                + '</div>'
                + (pmsNote ? '<div style="margin-bottom:0.75rem;">' + pmsNote + '</div>' : '')
                // Action
                + '<div class="mob-veh-actions">'
                + '<button class="mob-veh-btn" onclick="mobViewHistory(\'' + asset.plateNumber + '\')">📋 Maintenance History</button>'
                + '</div>'
                + '</div>';
        }).join('');
    }

    // ── Vehicle History Modal ────────────────────────────────
    window.mobViewHistory = function (plateNumber) {
        var asset = assets.find(function (a) { return a.plateNumber === plateNumber; });
        if (!asset) return;

        document.getElementById('mobHistoryIcon').textContent = asset.icon || '🚗';
        document.getElementById('mobHistoryName').textContent = asset.assetDescription;
        document.getElementById('mobHistoryPlate').textContent = plateNumber;

        var history = asset.maintenanceHistory || [];
        document.getElementById('mobHistoryCount').textContent = history.length + ' record' + (history.length !== 1 ? 's' : '');

        var listEl = document.getElementById('mobHistoryList');
        if (history.length === 0) {
            listEl.innerHTML = '<div class="mob-empty" style="padding:2rem 0;">No maintenance history available.</div>';
        } else {
            // Sort newest first
            var sorted = history.slice().sort(function (a, b) { return new Date(b.date) - new Date(a.date); });
            listEl.innerHTML = sorted.map(function (r, i) {
                var fmtDate = new Date(r.date).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' });
                return '<div class="mob-hist-card">'
                    + '<div class="mob-hist-card-header">'
                    + '<div class="mob-hist-index">' + (i + 1) + '</div>'
                    + '<div class="mob-hist-header-info">'
                    + '<div class="mob-hist-service">' + r.service + '</div>'
                    + '<div class="mob-hist-date">📅 ' + fmtDate + '</div>'
                    + '</div>'
                    + '<div class="mob-hist-cost">₱' + r.cost.toLocaleString() + '</div>'
                    + '</div>'
                    + '<div class="mob-hist-chips">'
                    + '<div class="mob-hist-chip"><span class="mob-hist-chip-icon">🔩</span><span class="mob-hist-chip-val">' + (r.parts || '—') + '</span></div>'
                    + '<div class="mob-hist-chip"><span class="mob-hist-chip-icon">📏</span><span class="mob-hist-chip-val">' + (r.km ? r.km.toLocaleString() + ' km' : '—') + '</span></div>'
                    + '</div>'
                    + '</div>';
            }).join('');
        }

        document.getElementById('mobHistoryModal').classList.add('active');
    };

    // ── Smart Chat ──────────────────────────────────────────
    window.mobClearChat = function () {
        var messages = document.getElementById('mobChatMessages');
        if (!messages) return;
        messages.innerHTML = '<div class="mob-welcome-row"><div class="mob-ai-avatar">🤖</div><div class="mob-bubble-ai"><div class="mob-welcome-title">Hello! I\'m your Smart Reports assistant. 👋</div><div class="mob-welcome-sub">Ask me anything about your vehicles — PMS status, maintenance history, and more.</div><div class="mob-chips"><button class="mob-chip" onclick="mobRunQuery(\'Show all my vehicles\')">🚛 All my vehicles</button><button class="mob-chip" onclick="mobRunQuery(\'Which of my assets are under maintenance?\')">🔵 Under maintenance</button><button class="mob-chip" onclick="mobRunQuery(\'Which of my assets have PMS overdue?\')">⚠️ PMS overdue</button><button class="mob-chip" onclick="mobRunQuery(\'Which of my assets have PMS due soon?\')">📅 PMS due soon</button><button class="mob-chip" onclick="mobRunQuery(\'Show maintenance history of my assets\')">📋 Maintenance history</button></div></div></div>';
    };

    window.mobRunQuery = function (queryText) {
        var input = document.getElementById('mobChatInput');
        var query = queryText || (input ? input.value.trim() : '');
        if (!query) return;
        if (input) { input.value = ''; input.style.height = 'auto'; }

        var messages = document.getElementById('mobChatMessages');
        if (!messages) return;

        messages.innerHTML += '<div class="mob-msg-row mob-msg-user"><div class="mob-bubble-user">' + query + '</div><div class="mob-user-avatar-chat">👤</div></div>';

        var typingId = 'mob-typing-' + Date.now();
        messages.innerHTML += '<div class="mob-msg-row" id="' + typingId + '"><div class="mob-ai-avatar">🤖</div><div class="mob-bubble-ai mob-typing"><span></span><span></span><span></span></div></div>';
        messages.scrollTop = messages.scrollHeight;

        setTimeout(function () {
            var typingEl = document.getElementById(typingId);
            if (typingEl) typingEl.remove();
            var response = buildMobSmartResponse(query.toLowerCase(), cpUser.name);
            messages.innerHTML += '<div class="mob-msg-row"><div class="mob-ai-avatar">🤖</div><div class="mob-bubble-ai">' + response + '</div></div>';
            messages.scrollTop = messages.scrollHeight;
        }, 700);
    };

    function buildMobSmartResponse(q, ownerName) {
        var companyName = window._cpCompanyName || '';
        var myAssets = assets.filter(function (a) {
            var owner = (a.owner || '').toLowerCase().trim();
            return owner === ownerName.toLowerCase().trim() ||
                   (companyName && owner === companyName.toLowerCase().trim());
        });
        var today = new Date(); today.setHours(0, 0, 0, 0);

        function fmtDate(d) {
            return d ? new Date(d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : '—';
        }

        function assetRow(a) {
            return '<div style="background:#f8fafc;border-radius:8px;padding:0.7rem 0.85rem;margin-bottom:0.4rem;border-left:3px solid #E31E24;">'
                + '<div style="font-weight:700;color:#1a202c;font-size:0.85rem;">' + a.icon + ' ' + a.assetDescription + '</div>'
                + '<div style="font-size:0.75rem;color:#718096;margin-top:0.15rem;">' + a.plateNumber + ' · ' + a.assetNum + '</div>'
                + '</div>';
        }

        function getPmsDiff(a) {
            if (!a.nextPMSDue) return null;
            var due = new Date(a.nextPMSDue); due.setHours(0, 0, 0, 0);
            return Math.ceil((due - today) / 86400000);
        }

        // ── Intent detection ─────────────────────────────────
        // Each intent has a list of keyword patterns; first match wins.
        var intents = [
            {
                name: 'list_all',
                patterns: [
                    /\b(list|show|display|view|what|how many|count|all|my)\b.*\b(vehicle|truck|car|asset|fleet|unit)\b/,
                    /\b(vehicle|truck|car|asset|fleet|unit)\b.*\b(list|all|do i have|i have|i own|owned)\b/,
                    /how many.*(vehicle|truck|car|asset)/,
                    /^(vehicles?|trucks?|cars?|assets?|fleet)$/
                ]
            },
            {
                name: 'under_maintenance',
                patterns: [
                    /\b(under|being|currently|in|for)\b.*(maintenance|repair|service|servic)/,
                    /\b(maintenance|repair|servic)\b.*(now|current|ongoing|active|status)/,
                    /which.*(being|under|in).*(service|repair|maintenance)/,
                    /\b(fix|fixing|repaired?|shop)\b/
                ]
            },
            {
                name: 'pms_overdue',
                patterns: [
                    /\b(overdue|over due|past due|missed|late|behind|expired)\b/,
                    /pms.*(overdue|missed|late|past|behind)/,
                    /(overdue|missed|late).*(pms|maintenance|service|schedule)/,
                    /\b(haven.t|has not|not yet|no).*(service|maintain|pms)\b/
                ]
            },
            {
                name: 'pms_due_soon',
                patterns: [
                    /\b(due soon|coming up|upcoming|approaching|near|soon|next|schedule)\b.*(pms|maintenance|service)/,
                    /\b(pms|maintenance|service)\b.*(due soon|coming|upcoming|soon|next|schedule|when)/,
                    /when.*(next|due|schedule).*(service|pms|maintenance|oil|check)/,
                    /\b(remind|reminder|alert)\b.*(service|pms|maintenance)/,
                    /\b(oil change|check.?up|tune.?up)\b/
                ]
            },
            {
                name: 'history',
                patterns: [
                    /\b(history|record|log|past|previous|last|done|performed|completed)\b.*(service|maintenance|repair|work)/,
                    /\b(service|maintenance|repair|work)\b.*(history|record|log|past|done|performed|completed)/,
                    /what.*(service|maintenance|repair|work).*(done|performed|completed|had)/,
                    /\b(show|list|view|display)\b.*(history|record|log|past)/
                ]
            },
            {
                name: 'cost',
                patterns: [
                    /\b(cost|spend|spent|expense|total|amount|price|paid|pay|bill)\b/,
                    /how much.*(service|maintenance|repair|spend|cost|paid)/
                ]
            },
            {
                name: 'status',
                patterns: [
                    /\b(status|condition|state|health|ok|fine|good|problem|issue)\b.*(vehicle|truck|car|asset|fleet)/,
                    /\b(vehicle|truck|car|asset)\b.*(status|condition|state|health|ok|fine|good)/,
                    /\b(active|inactive|available|unavailable)\b/
                ]
            },
            {
                name: 'specific_vehicle',
                patterns: [
                    /\b([A-Z]{2,3}[-\s]?\d{3,4})\b/i  // plate number pattern e.g. ABC-1234
                ]
            }
        ];

        function detectIntent(text) {
            for (var i = 0; i < intents.length; i++) {
                for (var j = 0; j < intents[i].patterns.length; j++) {
                    if (intents[i].patterns[j].test(text)) return intents[i].name;
                }
            }
            return null;
        }

        // ── Extract plate number from query ──────────────────
        function extractPlate(text) {
            var m = text.match(/\b([A-Z]{2,3}[-\s]?\d{3,4})\b/i);
            return m ? m[1].toUpperCase().replace(/\s/, '-') : null;
        }

        var intent = detectIntent(q);

        // ── Specific vehicle lookup ──────────────────────────
        var plate = extractPlate(q);
        if (plate) {
            var found = myAssets.find(function (a) { return a.plateNumber.toUpperCase() === plate; });
            if (!found) return '❌ No vehicle with plate <strong>' + plate + '</strong> found in your fleet.';
            var diff = getPmsDiff(found);
            var pmsStatus = diff === null ? 'No PMS data'
                : diff < 0 ? '⚠️ Overdue by ' + Math.abs(diff) + ' day(s)'
                : diff === 0 ? '🔴 Due today'
                : diff <= 14 ? '📅 Due in ' + diff + ' day(s)'
                : '✅ Due ' + fmtDate(found.nextPMSDue);
            var hist = (found.maintenanceHistory || []).slice().sort(function (a, b) { return new Date(b.date) - new Date(a.date); });
            var histRows = hist.length === 0
                ? '<div style="color:#718096;font-size:0.78rem;">No history yet.</div>'
                : hist.slice(0, 5).map(function (r) {
                    return '<div style="font-size:0.78rem;color:#4a5568;padding:0.25rem 0;border-bottom:1px solid #e2e8f0;">'
                        + fmtDate(r.date) + ' — <strong>' + r.service + '</strong> (₱' + r.cost.toLocaleString() + ')</div>';
                }).join('');
            return '<div style="background:#f8fafc;border-radius:8px;padding:0.85rem;border-left:3px solid #E31E24;">'
                + '<div style="font-weight:800;font-size:0.9rem;margin-bottom:0.5rem;">' + (found.icon || '🚗') + ' ' + found.assetDescription + '</div>'
                + '<div style="font-size:0.78rem;color:#718096;margin-bottom:0.6rem;">' + found.plateNumber + ' · ' + found.assetNum + '</div>'
                + '<div style="font-size:0.8rem;margin-bottom:0.25rem;">📍 Status: <strong>' + (found.status || 'active') + '</strong></div>'
                + '<div style="font-size:0.8rem;margin-bottom:0.25rem;">🔧 Odometer: <strong>' + (found.odometer ? found.odometer.toLocaleString() + ' km' : '—') + '</strong></div>'
                + '<div style="font-size:0.8rem;margin-bottom:0.6rem;">📅 Next PMS: <strong>' + pmsStatus + '</strong></div>'
                + '<div style="font-size:0.8rem;font-weight:700;margin-bottom:0.4rem;">Recent Services:</div>'
                + histRows + '</div>';
        }

        // ── Intent-based responses ───────────────────────────
        if (intent === 'list_all') {
            if (myAssets.length === 0) return 'You have no registered vehicles.';
            return '<div style="font-weight:700;margin-bottom:0.6rem;font-size:0.88rem;">You have <span style="color:#E31E24;">' + myAssets.length + '</span> registered vehicle(s):</div>'
                + myAssets.map(assetRow).join('');
        }

        if (intent === 'under_maintenance') {
            var maint = myAssets.filter(function (a) { return a.status === 'maintenance'; });
            if (maint.length === 0) return '✅ None of your vehicles are currently under maintenance.';
            return '<div style="font-weight:700;margin-bottom:0.6rem;font-size:0.88rem;"><span style="color:#3182ce;">' + maint.length + '</span> vehicle(s) under maintenance:</div>'
                + maint.map(assetRow).join('');
        }

        if (intent === 'pms_overdue') {
            var od = myAssets.filter(function (a) {
                var d = getPmsDiff(a);
                return d !== null && d < 0 && a.status !== 'maintenance' && a.status !== 'inactive';
            });
            if (od.length === 0) return '✅ No PMS overdue vehicles. Great job keeping up with maintenance!';
            return '<div style="font-weight:700;margin-bottom:0.6rem;font-size:0.88rem;color:#e53e3e;">⚠️ ' + od.length + ' vehicle(s) with PMS overdue:</div>'
                + od.map(function (a) {
                    var d = getPmsDiff(a);
                    return '<div style="background:#fff5f5;border-radius:8px;padding:0.7rem 0.85rem;margin-bottom:0.4rem;border-left:3px solid #f56565;">'
                        + '<div style="font-weight:700;color:#1a202c;font-size:0.85rem;">' + a.icon + ' ' + a.assetDescription + '</div>'
                        + '<div style="font-size:0.75rem;color:#742a2a;margin-top:0.15rem;">PMS was due: ' + fmtDate(a.nextPMSDue) + ' (overdue by ' + Math.abs(d) + ' day(s))</div>'
                        + '</div>';
                }).join('');
        }

        if (intent === 'pms_due_soon') {
            var ds = myAssets.filter(function (a) {
                var d = getPmsDiff(a);
                return d !== null && d >= 0 && d <= 14 && a.status !== 'maintenance' && a.status !== 'inactive';
            });
            if (ds.length === 0) return '✅ No vehicles with PMS due in the next 14 days.';
            return '<div style="font-weight:700;margin-bottom:0.6rem;font-size:0.88rem;color:#d69e2e;">📅 ' + ds.length + ' vehicle(s) with PMS due soon:</div>'
                + ds.map(function (a) {
                    var d = getPmsDiff(a);
                    return '<div style="background:#fffbeb;border-radius:8px;padding:0.7rem 0.85rem;margin-bottom:0.4rem;border-left:3px solid #ed8936;">'
                        + '<div style="font-weight:700;color:#1a202c;font-size:0.85rem;">' + a.icon + ' ' + a.assetDescription + '</div>'
                        + '<div style="font-size:0.75rem;color:#7c2d12;margin-top:0.15rem;">Due: ' + fmtDate(a.nextPMSDue) + (d === 0 ? ' (today!)' : ' (in ' + d + ' day' + (d !== 1 ? 's' : '') + ')') + '</div>'
                        + '</div>';
                }).join('');
        }

        if (intent === 'history') {
            if (myAssets.length === 0) return 'No vehicles found.';
            return '<div style="font-weight:700;margin-bottom:0.6rem;font-size:0.88rem;">📋 Maintenance history for your vehicles:</div>'
                + myAssets.map(function (a) {
                    var hist = (a.maintenanceHistory || []).slice().sort(function (x, y) { return new Date(y.date) - new Date(x.date); });
                    var rows = hist.length === 0
                        ? '<div style="color:#718096;font-size:0.78rem;padding:0.3rem 0;">No history yet.</div>'
                        : hist.slice(0, 3).map(function (r) {
                            return '<div style="font-size:0.78rem;color:#4a5568;padding:0.25rem 0;border-bottom:1px solid #e2e8f0;">'
                                + fmtDate(r.date) + ' — <strong>' + r.service + '</strong> (₱' + r.cost.toLocaleString() + ')</div>';
                        }).join('');
                    return '<div style="background:#f8fafc;border-radius:8px;padding:0.7rem 0.85rem;margin-bottom:0.6rem;border-left:3px solid #E31E24;">'
                        + '<div style="font-weight:700;color:#1a202c;font-size:0.85rem;margin-bottom:0.4rem;">' + a.icon + ' ' + a.assetDescription + ' — ' + a.plateNumber + '</div>'
                        + rows + '</div>';
                }).join('');
        }

        if (intent === 'cost') {
            if (myAssets.length === 0) return 'No vehicles found.';
            var grandTotal = 0;
            var breakdown = myAssets.map(function (a) {
                var total = (a.maintenanceHistory || []).reduce(function (sum, r) { return sum + (r.cost || 0); }, 0);
                grandTotal += total;
                return '<div style="display:flex;justify-content:space-between;font-size:0.82rem;padding:0.3rem 0;border-bottom:1px solid #e2e8f0;">'
                    + '<span>' + (a.icon || '🚗') + ' ' + a.assetDescription + ' (' + a.plateNumber + ')</span>'
                    + '<strong>₱' + total.toLocaleString() + '</strong></div>';
            }).join('');
            return '<div style="font-weight:700;margin-bottom:0.6rem;font-size:0.88rem;">💰 Total maintenance cost for your fleet:</div>'
                + '<div style="background:#f8fafc;border-radius:8px;padding:0.85rem;border-left:3px solid #E31E24;">'
                + breakdown
                + '<div style="display:flex;justify-content:space-between;font-size:0.88rem;padding:0.5rem 0 0;font-weight:800;color:#E31E24;">'
                + '<span>Grand Total</span><span>₱' + grandTotal.toLocaleString() + '</span></div></div>';
        }

        if (intent === 'status') {
            if (myAssets.length === 0) return 'No vehicles found.';
            return '<div style="font-weight:700;margin-bottom:0.6rem;font-size:0.88rem;">📍 Status of your vehicles:</div>'
                + myAssets.map(function (a) {
                    var d = getPmsDiff(a);
                    var pmsLabel = a.status === 'maintenance' ? '🔵 Under Maintenance'
                        : a.status === 'inactive' ? '⚫ Inactive'
                        : d === null ? '✅ Active'
                        : d < 0 ? '⚠️ PMS Overdue'
                        : d <= 14 ? '📅 PMS Due Soon'
                        : '✅ Active';
                    return '<div style="background:#f8fafc;border-radius:8px;padding:0.7rem 0.85rem;margin-bottom:0.4rem;border-left:3px solid #E31E24;">'
                        + '<div style="font-weight:700;color:#1a202c;font-size:0.85rem;">' + a.icon + ' ' + a.assetDescription + '</div>'
                        + '<div style="font-size:0.75rem;color:#718096;margin-top:0.15rem;">' + a.plateNumber + ' · ' + pmsLabel + '</div>'
                        + '</div>';
                }).join('');
        }

        // ── Fallback: try partial keyword match before giving up ─
        var qWords = q.split(/\s+/);
        var hasVehicleWord = qWords.some(function (w) { return /vehicle|truck|car|asset|fleet|unit|plate/.test(w); });
        var hasPmsWord = qWords.some(function (w) { return /pms|preventive|maintenance|service|oil|check|schedule/.test(w); });

        if (hasVehicleWord && myAssets.length > 0) {
            return '<div style="font-weight:700;margin-bottom:0.6rem;font-size:0.88rem;">Here are your registered vehicles:</div>'
                + myAssets.map(assetRow).join('');
        }

        if (hasPmsWord) {
            // Show a combined PMS summary
            var overdueCnt = myAssets.filter(function (a) { var d = getPmsDiff(a); return d !== null && d < 0 && a.status !== 'maintenance'; }).length;
            var dueSoonCnt = myAssets.filter(function (a) { var d = getPmsDiff(a); return d !== null && d >= 0 && d <= 14 && a.status !== 'maintenance'; }).length;
            return '<div style="font-weight:700;margin-bottom:0.6rem;font-size:0.88rem;">🔧 PMS Summary for your fleet:</div>'
                + '<div style="background:#f8fafc;border-radius:8px;padding:0.85rem;border-left:3px solid #E31E24;">'
                + '<div style="font-size:0.82rem;padding:0.25rem 0;">⚠️ Overdue: <strong style="color:#e53e3e;">' + overdueCnt + '</strong></div>'
                + '<div style="font-size:0.82rem;padding:0.25rem 0;">📅 Due soon (14 days): <strong style="color:#ed8936;">' + dueSoonCnt + '</strong></div>'
                + '<div style="font-size:0.82rem;padding:0.25rem 0;">🚛 Total vehicles: <strong>' + myAssets.length + '</strong></div>'
                + '</div>';
        }

        return 'I can help you with:<br><br>'
            + '• <strong>Show all my vehicles</strong><br>'
            + '• <strong>Which vehicles are under maintenance?</strong><br>'
            + '• <strong>Which vehicles have PMS overdue?</strong><br>'
            + '• <strong>Which vehicles have PMS due soon?</strong><br>'
            + '• <strong>Show maintenance history</strong><br>'
            + '• <strong>How much have I spent on maintenance?</strong><br>'
            + '• <strong>Status of my vehicles</strong><br>'
            + '• Or type a plate number (e.g. <strong>ABC-1234</strong>) for details';
    }

    // ── Notifications ────────────────────────────────────────
    function buildNotifications() {
        var companyName = window._cpCompanyName || '';
        var myAssets = assets.filter(function (a) {
            var owner = (a.owner || '').toLowerCase().trim();
            return owner === cpUser.name.toLowerCase().trim() ||
                   (companyName && owner === companyName.toLowerCase().trim());
        });
        var today = new Date(); today.setHours(0, 0, 0, 0);
        var notifs = [];

        myAssets.forEach(function (a) {
            if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return;
            var due = new Date(a.nextPMSDue); due.setHours(0, 0, 0, 0);
            var diff = Math.ceil((due - today) / 86400000);
            if (diff < 0) {
                notifs.push({ icon: '🔴', title: 'PMS Overdue', msg: a.assetDescription + ' (' + a.plateNumber + ') — PMS was due on ' + due.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }), time: Math.abs(diff) + ' day(s) ago', unread: true });
            } else if (diff <= 14) {
                notifs.push({ icon: '🟡', title: 'PMS Due Soon', msg: a.assetDescription + ' (' + a.plateNumber + ') — PMS due in ' + diff + ' day(s)', time: 'Due ' + due.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }), unread: true });
            }
        });

        var maint = myAssets.filter(function (a) { return a.status === 'maintenance'; });
        maint.forEach(function (a) {
            notifs.push({ icon: '🔵', title: 'Under Maintenance', msg: a.assetDescription + ' (' + a.plateNumber + ') is currently being serviced.', time: 'Ongoing', unread: false });
        });

        return notifs;
    }

    function renderMobNotifications() {
        var notifs = buildNotifications();
        var badge1 = document.getElementById('mobNotifBadge');
        var badge2 = document.getElementById('mobNavNotifBadge');
        var unreadCount = notifs.filter(function (n) { return n.unread; }).length;

        if (badge1) { badge1.textContent = unreadCount; badge1.style.display = unreadCount > 0 ? 'flex' : 'none'; }
        if (badge2) { badge2.textContent = unreadCount; badge2.style.display = unreadCount > 0 ? 'flex' : 'none'; }

        var listEl = document.getElementById('mobNotifList');
        if (!listEl) return;

        if (notifs.length === 0) {
            listEl.innerHTML = '<div class="mob-notif-empty"><div class="mob-notif-empty-icon">🔔</div><div class="mob-notif-empty-text">No notifications</div></div>';
            return;
        }

        listEl.innerHTML = notifs.map(function (n) {
            return '<div class="mob-notif-item' + (n.unread ? ' unread' : '') + '">'
                + '<div class="mob-notif-icon">' + n.icon + '</div>'
                + '<div><div class="mob-notif-title">' + n.title + '</div>'
                + '<div class="mob-notif-msg">' + n.msg + '</div>'
                + '<div class="mob-notif-time">' + n.time + '</div></div>'
                + '</div>';
        }).join('');
    }

    window.mobClearNotifications = function () {
        var listEl = document.getElementById('mobNotifList');
        if (listEl) listEl.innerHTML = '<div class="mob-notif-empty"><div class="mob-notif-empty-icon">🔔</div><div class="mob-notif-empty-text">No notifications</div></div>';
        var badge1 = document.getElementById('mobNotifBadge');
        var badge2 = document.getElementById('mobNavNotifBadge');
        if (badge1) badge1.style.display = 'none';
        if (badge2) badge2.style.display = 'none';
    };

    // ── Profile ─────────────────────────────────────────────
    function renderMobProfile() {
        var ownerName = cpUser.name;
        var companyName = window._cpCompanyName || '';
        var myAssets = assets.filter(function (a) {
            var owner = (a.owner || '').toLowerCase().trim();
            return owner === ownerName.toLowerCase().trim() ||
                   (companyName && owner === companyName.toLowerCase().trim());
        });
        var today = new Date(); today.setHours(0, 0, 0, 0);

        var underMaint = myAssets.filter(function (a) { return a.status === 'maintenance'; }).length;
        var pmsOverdue = myAssets.filter(function (a) {
            if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
            var due = new Date(a.nextPMSDue); due.setHours(0, 0, 0, 0);
            return due < today;
        }).length;
        var pmsDueSoon = myAssets.filter(function (a) {
            if (!a.nextPMSDue || a.status === 'maintenance' || a.status === 'inactive') return false;
            var diff = Math.ceil((new Date(a.nextPMSDue) - today) / 86400000);
            return diff >= 0 && diff <= 14;
        }).length;

        var s = function (id) { return document.getElementById(id); };
        if (s('mobProfileAvatarLg')) s('mobProfileAvatarLg').textContent = cpUser.avatar || cpUser.name.charAt(0).toUpperCase();
        if (s('mobProfileName')) s('mobProfileName').textContent = cpUser.name;
        if (s('mobProfileFullName')) s('mobProfileFullName').textContent = cpUser.name;
        if (s('mobProfileUsername')) s('mobProfileUsername').textContent = cpUser.username || 'customer';
        if (s('mobProfileTotal')) s('mobProfileTotal').textContent = myAssets.length;
        if (s('mobProfileMaint')) s('mobProfileMaint').textContent = underMaint;
        if (s('mobProfileOverdue')) s('mobProfileOverdue').textContent = pmsOverdue;
        if (s('mobProfileDueSoon')) s('mobProfileDueSoon').textContent = pmsDueSoon;

        var logoutBtn = document.getElementById('mobProfileLogoutBtn');
        if (logoutBtn) {
            logoutBtn.addEventListener('click', function () {
                sessionStorage.removeItem('cpUser');
                window.location.href = 'index.html';
            });
        }
    }

})();
