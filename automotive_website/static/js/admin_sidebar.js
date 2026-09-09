// Page → URL mapping for navigation
const PAGE_URLS = {
    'overview':                 'admin_dashboard.html',
    'item-master':              'admin_inventory_itemaster.html',
    'inventory':                'admin_inventory_stock.html',
    'inventory-transactions':   'admin_transactions.html',
    'assets':                   'admin_vehicle_list.html',
    'asset-servicing':          'admin_vehicle_maintenance.html',
    'issuance':                 'admin_issuances.html',
    'dss':                      'admin_dss.html',
    'dss-pms':                  'admin_dss.html#dss-pms',
    'users':                    'admin_users.html',
    'domains':                  'admin_domain_management.html',
};

// ── Inject mobile-only styles that override inline styles ──────────────
(function injectMobileStyles() {
    var style = document.createElement('style');
    style.id = 'admin-mobile-overrides';
    style.textContent = [
        // ── Header: stack vertically on mobile ──
        '@media (max-width: 900px) {',
        // Force header to stack: title on top, controls below
        '  .admin-header { flex-direction: column !important; align-items: flex-start !important; gap: 0.65rem !important; padding: 0.85rem 1rem !important; }',
        // All direct children except first (title div) go full width, reset margin-left:auto
        '  .admin-header > *:not(:first-child) { width: 100% !important; margin-left: 0 !important; flex-wrap: wrap !important; gap: 0.4rem !important; }',
        // All inputs, selects inside header go full width (overrides inline width:220px etc)
        '  .admin-header input, .admin-header select { width: 100% !important; min-width: 0 !important; box-sizing: border-box !important; }',
        // ── Data table: horizontal scroll on the inner scroll wrapper, NOT the outer container
        // The outer .data-table must stay overflow:visible so action buttons are clickable.
        '  #servicesList, #assetsList, #inventoryList, #issuanceList, #itemMasterList,',
        '  #txnList, #usersList, #domainList, #archiveList, #receivingList {',
        '    overflow-x: auto !important; -webkit-overflow-scrolling: touch !important;',
        '  }',
        '  .data-table { overflow: visible !important; }',
        // Keep table rows at desktop min-width so layout isn't broken
        '  .data-table .table-row { min-width: 560px !important; font-size: 0.82rem !important; }',
        // Action button containers inside table rows
        '  .data-table .table-row > div:last-child { display: flex !important; flex-wrap: nowrap !important; gap: 0.3rem !important; align-items: center !important; }',
        // Equal-width action buttons (overrides inline display:inline-flex)
        '  .data-table .table-row > div:last-child { display: flex !important; flex-wrap: nowrap !important; gap: 0.3rem !important; align-items: center !important; width: 100% !important; }',
        '  .data-table .table-row > div:last-child .btn-small,',
        '  .data-table .table-row > div:last-child button {',
        '    display: flex !important;',       /* inline-flex ignores flex:1 — must be flex */
        '    flex: 1 1 0 !important; width: 0 !important; min-width: 0 !important;',   /* width:0 forces equal growth */
        '    justify-content: center !important; align-items: center !important;',
        '    padding: 0.3rem 0 !important; font-size: 0.75rem !important;',
        '    white-space: nowrap !important; box-sizing: border-box !important;',
        '  }',
        '  .data-table .table-row > div:last-child > div[style] { display: flex !important; gap: 0.3rem !important; width: 100% !important; }',
        '  .data-table .table-row > div:last-child > div[style] .btn-small { flex: 1 1 0 !important; display: flex !important; width: 0 !important; justify-content: center !important; padding: 0.3rem 0 !important; }',
        '}',
        // ── Small phones ──
        '@media (max-width: 480px) {',
        '  .data-table .table-row { font-size: 0.76rem !important; padding: 0.5rem 0.65rem !important; min-width: 480px !important; }',
        '  .data-table .table-row > div:last-child .btn-small,',
        '  .data-table .table-row > div:last-child button { font-size: 0.7rem !important; padding: 0.22rem 0.35rem !important; }',
        '  .admin-header-title { font-size: 1rem !important; }',
        '}',
    ].join('\n');
    document.head.appendChild(style);
})();

function navigateTo(section) {
    const url = PAGE_URLS[section];
    if (!url) return;

    // If we're navigating to a hash on the same page, update data-page and active state in place
    const currentPage = window.location.pathname.split('/').pop();
    const [targetFile, targetHash] = url.split('#');

    if (currentPage === targetFile && targetHash) {
        document.body.setAttribute('data-page', section);
        initSidebarActive();
        window.location.hash = targetHash;
        // Switch the visible section and header controls
        if (typeof switchAdminSection === 'function') switchAdminSection(section);
        if (typeof switchDSSSection === 'function') switchDSSSection(section);
        _closeSidebar();
    } else if (currentPage === targetFile && !targetHash) {
        document.body.setAttribute('data-page', section);
        initSidebarActive();
        history.pushState(null, '', window.location.pathname);
        if (typeof switchAdminSection === 'function') switchAdminSection(section);
        if (typeof switchDSSSection === 'function') switchDSSSection(section);
        _closeSidebar();
    } else {
        window.location.href = url;
    }
}

// Close sidebar + overlay after navigation (mobile)
function _closeSidebar() {
    const sidebar = document.getElementById('adminSidebar');
    const overlay = document.getElementById('adminSidebarOverlay');
    if (sidebar) {
        sidebar.classList.remove('admin-sidebar-open');
        // Also remove asb-exp on mobile so the drawer fully hides after navigation
        if (window.innerWidth <= 900) sidebar.classList.remove('asb-exp');
    }
    if (overlay) overlay.classList.remove('active');
}

function toggleAdminSidebar() {
    const sidebar = document.getElementById('adminSidebar');
    const overlay = document.getElementById('adminSidebarOverlay');
    if (!sidebar) return;
    const isOpen = sidebar.classList.toggle('admin-sidebar-open');
    if (overlay) overlay.classList.toggle('active', isOpen);
}

// ── Expand/collapse sidebar (icon-only ↔ full width) ──
window.toggleSidebarExpand = function() {
    const sidebar = document.getElementById('adminSidebar');
    if (!sidebar) return;

    // On mobile/tablet (≤900px) the sidebar is a fixed drawer —
    // use the drawer classes so the overlay also shows/hides.
    if (window.innerWidth <= 900) {
        const overlay = document.getElementById('adminSidebarOverlay');
        const isOpen  = sidebar.classList.toggle('admin-sidebar-open');
        // Keep asb-exp in sync so CSS is consistent
        sidebar.classList.toggle('asb-exp', isOpen);
        if (overlay) overlay.classList.toggle('active', isOpen);
        return;
    }

    // Desktop: normal expand/collapse (icon-only ↔ full-width)
    const isExpanded = sidebar.classList.toggle('asb-exp');
    document.body.classList.toggle('sidebar-expanded', isExpanded);
    localStorage.setItem('sidebarExpanded', isExpanded ? '1' : '0');
};

function initSidebarActive() {
    const page = document.body.getAttribute('data-page') || 'overview';
    document.querySelectorAll('#adminSidebar .asb-btn[data-section]').forEach(btn => {
        btn.classList.toggle('active', btn.getAttribute('data-section') === page);
    });
}

// Pages that use the expand/collapse (icon ↔ full-width) sidebar pattern.
// All other admin pages use the drawer (hidden ↔ slide-in) pattern.
const EXPAND_COLLAPSE_PAGES = [
    'admin_dashboard.html',
    'admin_inventory_stock.html',
    'admin_inventory_itemaster.html',
    'admin_vehicle_list.html',
    'admin_vehicle_maintenance.html',
    'admin_service_bookings.html',
    'admin_receiving.html',
    'admin_dss.html',
    'admin_users.html',
    'admin_domain_management.html',
    'admin_archive.html',
    'admin_transactions.html',
    'admin_issuances.html',
    'profile.html',
    'change_password.html',
    'notifications.html',
    'help_support.html',
];

function _isExpandCollapsePage() {
    const page = window.location.pathname.split('/').pop();
    return EXPAND_COLLAPSE_PAGES.indexOf(page) !== -1;
}

function bindHeaderControls() {
    // Set page title in topbar
    var _adminPageTitles = {
        'overview':               'Dashboard',
        'item-master':            'Item Master',
        'inventory':              'Stock Inventory',
        'receiving':              'Purchase Orders (PO)',
        'inventory-transactions': 'Inventory Transactions',
        'assets':                 'Vehicle List',
        'asset-servicing':        'Vehicle Maintenance',
        'pms-reschedule':         'Service Bookings',
        'issuance':               'Issuances',
        'dss':                    'Stock Replenishment',
        'dss-pms':                'PMS Scheduling',
        'users':                  'User Management',
        'domains':                'Domain Management',
        'archive':                'Archive',
        'profile':                'My Profile',
        'change_password':        'Change Password',
        'notifications':          'Notifications',
        'help_support':           'Help & Support',
    };
    var titleEl = document.getElementById('adminPageTitle');
    if (titleEl) {
        var page = document.body.getAttribute('data-page') || 'overview';
        titleEl.textContent = _adminPageTitles[page] || '';
    }

    const menuBtn = document.getElementById('adminMenuBtn');
    if (menuBtn) {
        if (_isExpandCollapsePage()) {
            menuBtn.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                toggleSidebarExpand();
            });
        } else {
            // Drawer pages: hamburger opens/closes the sidebar as a slide-in panel
            menuBtn.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                toggleAdminSidebar();
            });
        }
    }

    const overlay = document.getElementById('adminSidebarOverlay');
    if (overlay) overlay.addEventListener('click', function() {
        var sidebar = document.getElementById('adminSidebar');
        // Always close the mobile drawer (both class variants)
        if (sidebar) {
            sidebar.classList.remove('admin-sidebar-open');
            sidebar.classList.remove('asb-exp');
        }
        document.body.classList.remove('sidebar-expanded');
        localStorage.setItem('sidebarExpanded', '0');
        overlay.classList.remove('active');
    });

    // Apply cached notification badge count (set by admin_firebase.js onSnapshot)
    // This handles the case where the snapshot fired before the header was injected
    if (typeof window._adminUnreadCount !== 'undefined') {
        const badge = document.getElementById('adminHeaderNotifBadge');
        if (badge) {
            const unread = window._adminUnreadCount;
            badge.textContent = unread > 99 ? '99+' : unread;
            badge.style.display = unread > 0 ? 'flex' : 'none';
        }
    }

    if (typeof firebase !== 'undefined') {
        firebase.auth().onAuthStateChanged(user => {
            if (user) {
                const avatar   = document.getElementById('adminHeaderAvatar') || document.getElementById('adminAvatar');
                const nameEl   = document.getElementById('adminAvatarName');
                const topbarName = document.getElementById('adminName');

                // Try sessionStorage first (instant)
                const sess = JSON.parse(sessionStorage.getItem('apUser') || '{}');
                const sessName = sess.name || '';
                if (sessName) {
                    const parts = sessName.trim().split(' ').filter(Boolean);
                    const ini = parts.length >= 2
                        ? (parts[0][0] + parts[1][0]).toUpperCase()
                        : parts[0].slice(0, 2).toUpperCase();
                    // Apply photo from sessionStorage immediately if available
                    if (sess.photoUrl && avatar) {
                        avatar.innerHTML = '<img src="' + sess.photoUrl + '" alt="avatar" style="width:100%;height:100%;object-fit:cover;border-radius:50%;">';
                    } else if (avatar) {
                        avatar.textContent = ini;
                    }
                    if (nameEl) nameEl.textContent = sessName;
                    if (topbarName) topbarName.textContent = sessName;

                    // Also apply to sidebar avatar immediately from sessionStorage
                    const sidebarAv = document.getElementById('sidebarAvatar');
                    if (sidebarAv) {
                        if (sess.photoUrl) {
                            sidebarAv.innerHTML = '<img src="' + sess.photoUrl + '" alt="avatar" style="width:100%;height:100%;object-fit:cover;border-radius:50%;">';
                        } else {
                            sidebarAv.textContent = ini;
                        }
                    }
                    const sidebarEmailEl2 = document.getElementById('sidebarEmail');
                    const menuEmailEl2    = document.getElementById('adminAvatarEmail');
                    if (sidebarEmailEl2) sidebarEmailEl2.textContent = sess.email || '';
                    if (menuEmailEl2)    menuEmailEl2.textContent    = sess.email || '';
                }

                // Then update from Firestore
                firebase.firestore().collection('users').doc(user.uid).get().then(doc => {
                    const name     = (doc.exists && doc.data().name)     ? doc.data().name     : sessName || user.email || '';
                    // Prefer Firestore photoUrl, fall back to sessionStorage so photo never disappears
                    const photoUrl = (doc.exists && doc.data().photoUrl) ? doc.data().photoUrl : (sess.photoUrl || '');
                    if (!name) return;
                    const parts    = name.trim().split(' ').filter(Boolean);
                    const initials = parts.length >= 2
                        ? (parts[0][0] + parts[1][0]).toUpperCase()
                        : parts[0].slice(0, 2).toUpperCase();

                    // Helper: set avatar to photo or fallback to initials text
                    function applyAvatar(el, ini, photo) {
                        if (!el) return;
                        if (photo) {
                            el.innerHTML = '<img src="' + photo + '" alt="avatar" '
                                + 'style="width:100%;height:100%;object-fit:cover;border-radius:50%;">';
                        } else {
                            el.textContent = ini;
                        }
                    }

                    applyAvatar(avatar, initials, photoUrl);
                    if (nameEl) nameEl.textContent  = name;
                    if (topbarName) topbarName.textContent = name;

                    // Also update sidebar
                    const sidebarNameEl   = document.getElementById('sidebarName');
                    const sidebarEmailEl  = document.getElementById('sidebarEmail');
                    const sidebarAvatarEl = document.getElementById('sidebarAvatar');
                    const menuEmailEl     = document.getElementById('adminAvatarEmail');
                    if (sidebarNameEl)  sidebarNameEl.textContent  = name;
                    if (sidebarEmailEl) sidebarEmailEl.textContent = (doc.exists && doc.data().email) || sess.email || '';
                    if (menuEmailEl)    menuEmailEl.textContent    = (doc.exists && doc.data().email) || sess.email || '';
                    applyAvatar(sidebarAvatarEl, initials, photoUrl);

                    // Sync photoUrl to sessionStorage
                    var sess2 = JSON.parse(sessionStorage.getItem('apUser') || '{}');
                    if (photoUrl) sess2.photoUrl = photoUrl;
                    sess2.name = name;
                    sessionStorage.setItem('apUser', JSON.stringify(sess2));
                }).catch(() => {});
            }
        });
    }
}

// Load header then sidebar, bind controls after both are ready
(function init() {
    const headerContainer  = document.getElementById('headerContainer');
    const sidebarContainer = document.getElementById('sidebarContainer');

    const headerPromise = headerContainer
        ? fetch('admin_header.html')
            .then(r => r.text())
            .then(html => {
                headerContainer.innerHTML = html;
            })
        : Promise.resolve();

    const sidebarPromise = sidebarContainer
        ? fetch('admin_sidebar.html')
            .then(r => r.text())
            .then(html => {
                sidebarContainer.innerHTML = html;
                initSidebarActive();
                // Restore expanded state from localStorage — only on expand/collapse pages
                if (_isExpandCollapsePage() && localStorage.getItem('sidebarExpanded') === '1') {
                    var sidebar = document.getElementById('adminSidebar');
                    if (sidebar) {
                        sidebar.classList.add('asb-exp');
                        document.body.classList.add('sidebar-expanded');
                    }
                }
                // ── Populate profile instantly from sessionStorage ──
                (function() {
                    var sess = JSON.parse(
                        sessionStorage.getItem('apUser') ||
                        sessionStorage.getItem('spUser') ||
                        sessionStorage.getItem('cpUser') || '{}'
                    );
                    var name  = sess.name  || 'Administrator';
                    var email = sess.email || '';
                    var parts = name.trim().split(' ').filter(Boolean);
                    var ini   = parts.length >= 2
                        ? (parts[0][0] + parts[1][0]).toUpperCase()
                        : (parts[0] ? parts[0].slice(0, 2).toUpperCase() : 'AD');

                    var nameEl    = document.getElementById('sidebarName');
                    var emailEl   = document.getElementById('sidebarEmail');
                    var avatarEl  = document.getElementById('sidebarAvatar');
                    var menuName  = document.getElementById('adminAvatarName');
                    var menuEmail = document.getElementById('adminAvatarEmail');

                    if (nameEl)    nameEl.textContent    = name;
                    if (emailEl)   emailEl.textContent   = email;
                    if (menuName)  menuName.textContent  = name;
                    if (menuEmail) menuEmail.textContent = email;

                    if (sess.photoUrl && avatarEl) {
                        avatarEl.innerHTML = '<img src="' + sess.photoUrl + '" alt="avatar" style="width:100%;height:100%;object-fit:cover;border-radius:50%;">';
                    } else if (avatarEl) {
                        avatarEl.textContent = ini;
                    }
                })();
            })
        : Promise.resolve();

    Promise.all([headerPromise, sidebarPromise])
        .then(() => {
            // Add a small delay to ensure DOM is fully updated
            setTimeout(() => {
                bindHeaderControls();
            }, 100);
        })
        .catch(err => {
            console.error('Error loading header/sidebar:', err);
        });
})();


// ── Avatar dropdown ─────────────────────────────────────────
window.toggleAvatarMenu = function(id) {
    const menu = document.getElementById(id);
    if (!menu) return;
    const isOpen = menu.style.display === 'block';
    document.querySelectorAll('.avatar-menu').forEach(m => m.style.display = 'none');
    document.querySelectorAll('.notif-panel').forEach(p => p.style.display = 'none');
    if (!isOpen) {
        menu.style.display = 'block';
        // Populate name from session
        const sess = JSON.parse(
            sessionStorage.getItem('apUser') ||
            sessionStorage.getItem('spUser') ||
            sessionStorage.getItem('cpUser') || '{}'
        );
        const nameEl = menu.querySelector('.avatar-menu-name');
        if (nameEl && sess.name) nameEl.textContent = sess.name;
    }
};

window.adminAvatarLogout = function() {
    if (!confirm('Are you sure you want to logout?')) return;
    localStorage.setItem('_loggedOut', Date.now().toString());
    // Clear AI chat history for this user
    try {
        var stored = sessionStorage.getItem('apUser') || sessionStorage.getItem('spUser') || sessionStorage.getItem('cpUser');
        if (stored) {
            var u = JSON.parse(stored);
            if (u && u.uid) {
                localStorage.removeItem('rag_chat_' + u.uid);
                localStorage.removeItem('rag_ai_active_' + u.uid);
                localStorage.removeItem('ai_chat_' + u.uid);
                localStorage.removeItem('ai_active_' + u.uid);
                localStorage.removeItem('ai_widget_chat_' + u.uid);
                localStorage.removeItem('ai_widget_active_' + u.uid);
            }
        }
    } catch(e) {}
    sessionStorage.removeItem('apUser');
    sessionStorage.removeItem('spUser');
    sessionStorage.removeItem('cpUser');
    if (typeof firebase !== 'undefined' && firebase.auth) {
        firebase.auth().signOut().finally(() => {
            history.replaceState(null, '', '/index.html');
            window.location.replace('/index.html');
        });
    } else {
        history.replaceState(null, '', '/index.html');
        window.location.replace('/index.html');
    }
};

window.cuAvatarLogout = window.adminAvatarLogout;

// Close avatar menu on outside click
document.addEventListener('click', function(e) {
    const menus   = document.querySelectorAll('.avatar-menu');
    const avatars = document.querySelectorAll('[onclick*="toggleAvatarMenu"]');
    let inside = false;
    menus.forEach(m   => { if (m.contains(e.target))   inside = true; });
    avatars.forEach(a => { if (a.contains(e.target))   inside = true; });
    if (!inside) menus.forEach(m => m.style.display = 'none');
});

// ── Back/Forward navigation guard ───────────────────────────
// If the user presses the browser back button after logout,
// check auth state and redirect to login if no session exists.
window.addEventListener('pageshow', function(e) {
    // When a page is restored from bfcache (back/forward), e.persisted === true.
    // Always re-validate in that case to block back-navigation after logout.
    const hasSession = sessionStorage.getItem('apUser') ||
                       sessionStorage.getItem('spUser') ||
                       sessionStorage.getItem('cpUser');

    if (!hasSession) {
        // No session at all — go to login immediately, no delay
        window.location.replace('/login.html');
        return;
    }

    if (e.persisted) {
        // Page restored from bfcache — force a fresh check with Firebase
        if (typeof firebase !== 'undefined' && firebase.auth) {
            var user = firebase.auth().currentUser;
            if (!user) {
                sessionStorage.removeItem('apUser');
                sessionStorage.removeItem('spUser');
                sessionStorage.removeItem('cpUser');
                window.location.replace('/login.html');
            }
        }
        return;
    }

    // Normal load — verify Firebase auth is still active
    if (typeof firebase !== 'undefined' && firebase.auth) {
        firebase.auth().onAuthStateChanged(function(user) {
            if (!user) {
                // Short delay to allow Firebase to restore session from token
                setTimeout(function() {
                    if (!firebase.auth().currentUser) {
                        sessionStorage.removeItem('apUser');
                        sessionStorage.removeItem('spUser');
                        sessionStorage.removeItem('cpUser');
                        window.location.replace('/login.html');
                    }
                }, 500);
            }
        });
    }
});

// ── Dynamic page title: "Welcome, Full Name" ────────────────
(function _initAdminTitle() {
    function _setTitle(name) {
        if (name) document.title = 'Welcome, ' + name;
    }

    // Immediately try sessionStorage (instant, no flicker)
    var sess = JSON.parse(
        sessionStorage.getItem('apUser') ||
        sessionStorage.getItem('spUser') ||
        sessionStorage.getItem('cpUser') || '{}'
    );
    if (sess.name) { _setTitle(sess.name); return; }

    // Fallback: wait for Firebase and fetch from Firestore
    function _tryFirebase() {
        if (typeof firebase === 'undefined') {
            setTimeout(_tryFirebase, 200); return;
        }
        firebase.auth().onAuthStateChanged(function(user) {
            if (!user) return;
            firebase.firestore().collection('users').doc(user.uid).get()
                .then(function(doc) {
                    var name = doc.exists ? (doc.data().name || '') : '';
                    _setTitle(name);
                }).catch(function() {});
        });
    }
    _tryFirebase();
})();
