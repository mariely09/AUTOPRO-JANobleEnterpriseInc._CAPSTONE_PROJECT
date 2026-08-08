// customer_shared.js — runs as a proper <script src> on all customer pages.
// Handles: avatar dropdown, notification panel, active tab highlight.

(function () {
    'use strict';

    // ── Wait for DOM ────────────────────────────────────────
    function ready(fn) {
        if (document.readyState !== 'loading') fn();
        else document.addEventListener('DOMContentLoaded', fn);
    }

    // ── Active tab highlight ────────────────────────────────
    // Runs immediately and again after header is injected
    function setActiveTab() {
        const page = document.body.getAttribute('data-page');
        if (!page) return;
        document.querySelectorAll('.cu-tab[data-page]').forEach(function (tab) {
            tab.classList.toggle('active', tab.getAttribute('data-page') === page);
        });
    }
    ready(setActiveTab);
    window.setActiveTab = setActiveTab; // expose for pages that inject header dynamically

    // ── Avatar dropdown ─────────────────────────────────────
    window.toggleAvatarMenu = function (id) {
        const menu = document.getElementById(id);
        if (!menu) return;
        const isOpen = menu.style.display === 'block';
        // Close everything else first
        document.querySelectorAll('.avatar-menu').forEach(function (m) { m.style.display = 'none'; });
        document.querySelectorAll('.notif-panel').forEach(function (p) { p.style.display = 'none'; });
        if (!isOpen) {
            menu.style.display = 'block';
            // Populate name from session
            var sess = JSON.parse(
                sessionStorage.getItem('cpUser') ||
                sessionStorage.getItem('spUser') || '{}'
            );
            var nameEl = menu.querySelector('.avatar-menu-name');
            if (nameEl && sess.name) nameEl.textContent = sess.name;
        }
    };

    window.cuAvatarLogout = function () {
        if (!confirm('Are you sure you want to logout?')) return;
        localStorage.setItem('_loggedOut', Date.now().toString());
        // Clear AI chat history for this user
        try {
            var stored = sessionStorage.getItem('cpUser');
            if (stored) {
                var cpUser = JSON.parse(stored);
                if (cpUser && cpUser.uid) {
                    localStorage.removeItem('ai_chat_' + cpUser.uid);
                    localStorage.removeItem('ai_widget_chat_' + cpUser.uid);
                    localStorage.removeItem('rag_chat_' + cpUser.uid);
                }
            }
        } catch(e) {}
        sessionStorage.removeItem('cpUser');
        sessionStorage.removeItem('spUser');
        if (typeof firebase !== 'undefined' && firebase.auth) {
            firebase.auth().signOut().finally(function () {
                history.replaceState(null, '', '/index.html');
                window.location.replace('/index.html');
            });
        } else {
            history.replaceState(null, '', '/index.html');
            window.location.replace('/index.html');
        }
    };

    // ── Back/Forward navigation guard ──────────────────────
    window.addEventListener('pageshow', function (e) {
        var hasSession = sessionStorage.getItem('cpUser') || sessionStorage.getItem('spUser') || sessionStorage.getItem('apUser');
        if (!hasSession) {
            window.location.replace('/login.html');
            return;
        }
        // bfcache restore — check Firebase synchronously
        if (e.persisted) {
            if (typeof firebase !== 'undefined' && firebase.auth) {
                if (!firebase.auth().currentUser) {
                    sessionStorage.removeItem('cpUser');
                    sessionStorage.removeItem('spUser');
                    window.location.replace('/login.html');
                }
            }
            return;
        }
        if (typeof firebase !== 'undefined' && firebase.auth) {
            firebase.auth().onAuthStateChanged(function (user) {
                if (!user) {
                    setTimeout(function () {
                        if (!firebase.auth().currentUser) {
                            var stillHasSession = sessionStorage.getItem('cpUser') || sessionStorage.getItem('spUser') || sessionStorage.getItem('apUser');
                            if (!stillHasSession) {
                                sessionStorage.removeItem('cpUser');
                                sessionStorage.removeItem('spUser');
                                window.location.replace('/login.html');
                            }
                        }
                    }, 500);
                }
            });
        }
    });

    // ── Notification panel toggle ───────────────────────────
    window.toggleCuNotifPanel = function () {
        var panel = document.getElementById('cuNotifPanel');
        if (!panel) return;
        var isOpen = panel.style.display === 'block';
        // Close avatar menus first
        document.querySelectorAll('.avatar-menu').forEach(function (m) { m.style.display = 'none'; });
        panel.style.display = isOpen ? 'none' : 'block';
    };

    // ── Outside-click: close avatar menus + notif panel ────
    document.addEventListener('click', function (e) {
        // Avatar menus
        var menus   = document.querySelectorAll('.avatar-menu');
        var avatars = document.querySelectorAll('[onclick*="toggleAvatarMenu"]');
        var insideAvatar = false;
        menus.forEach(function (m)   { if (m.contains(e.target))   insideAvatar = true; });
        avatars.forEach(function (a) { if (a.contains(e.target))   insideAvatar = true; });
        if (!insideAvatar) menus.forEach(function (m) { m.style.display = 'none'; });

        // Notification panel
        var panel = document.getElementById('cuNotifPanel');
        var btn   = document.getElementById('cuHeaderNotifBtn');
        if (panel && btn && !panel.contains(e.target) && !btn.contains(e.target)) {
            panel.style.display = 'none';
        }
    });

    // ── Customer notification panel — Firebase-powered ──────
    var _cuNotifs   = [];
    var _cuUid      = null;
    var _roleDocs   = [];
    var _personalDocs = [];

    function _timeAgo(ts) {
        if (!ts || !ts.toMillis) return '';
        var diff = Date.now() - ts.toMillis();
        var mins = Math.floor(diff / 60000);
        if (mins < 1)  return 'Just now';
        if (mins < 60) return mins + ' min ago';
        var hrs = Math.floor(mins / 60);
        if (hrs < 24)  return hrs + ' hr ago';
        var days = Math.floor(hrs / 24);
        return days === 1 ? 'Yesterday' : days + ' days ago';
    }

    function _typeIcon(type) {
        return '<span style="display:flex;align-items:center;justify-content:center;width:32px;height:32px;background:rgba(232,0,28,0.1);border-radius:8px;flex-shrink:0;">'
            + '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#E8001C" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>'
            + '</span>';
    }

    function _renderNotifPanel() {
        var listEl  = document.getElementById('cuNotifList');
        var countEl = document.getElementById('cuNotifPanelCount');
        var badge   = document.getElementById('cuNotifBadge');
        if (!listEl) return;

        var unread = _cuNotifs.filter(function (n) { return !n.read; }).length;
        if (badge) {
            badge.textContent = unread > 99 ? '99+' : String(unread);
            badge.style.display = unread > 0 ? 'flex' : 'none';
        }
        if (countEl) {
            countEl.textContent = _cuNotifs.length + ' notification' + (_cuNotifs.length !== 1 ? 's' : '');
        }

        if (_cuNotifs.length === 0) {
            listEl.innerHTML = '<div class="admin-notif-empty">'
                + '<div class="admin-notif-empty-icon">🔔</div>'
                + '<div class="admin-notif-empty-text">No notifications</div>'
                + '</div>';
            return;
        }

        listEl.innerHTML = _cuNotifs.map(function (n, i) {
            return '<div class="admin-notif-item' + (!n.read ? ' unread' : '') + '" '
                + 'style="position:relative;padding-right:2rem;" '
                + 'onclick="_cuMarkRead(\'' + n.id + '\',' + i + ')">'
                + '<div class="admin-notif-icon">' + _typeIcon(n.type) + '</div>'
                + '<div style="flex:1;min-width:0;">'
                +   '<div class="admin-notif-title">' + (n.title || '') + '</div>'
                +   '<div class="admin-notif-msg">' + (n.message || '') + '</div>'
                +   '<div class="admin-notif-time">' + _timeAgo(n.createdAt) + '</div>'
                + '</div>'
                + (!n.read ? '<div style="width:8px;height:8px;border-radius:50%;background:#E8001C;flex-shrink:0;margin-top:4px;"></div>' : '')
                + '<button onclick="event.stopPropagation();_cuDeleteNotif(\'' + n.id + '\')" title="Delete" '
                + 'style="position:absolute;top:0.5rem;right:0.4rem;background:none;border:none;cursor:pointer;color:#a0aec0;font-size:1rem;line-height:1;padding:2px 4px;border-radius:4px;" '
                + 'onmouseover="this.style.color=\'#e53e3e\'" onmouseout="this.style.color=\'#a0aec0\'">&times;</button>'
                + '</div>';
        }).join('');
    }

    window._cuMarkRead = function (docId, idx) {
        if (!_cuUid || !docId) return;
        firebase.firestore().collection('notifications').doc(docId)
            .update((_a = {}, _a['readBy.' + _cuUid] = true, _a))
            .catch(function () {});
        if (_cuNotifs[idx]) _cuNotifs[idx].read = true;
        _renderNotifPanel();
        var _a;
    };

    window._cuDeleteNotif = function (docId) {
        firebase.firestore().collection('notifications').doc(docId).delete().catch(function () {});
        _cuNotifs = _cuNotifs.filter(function (n) { return n.id !== docId; });
        _renderNotifPanel();
        _showCuNotifToast('Notification deleted');
    };

    window.markAllCuNotifsRead = function () {
        if (!_cuUid) return;
        var unread = _cuNotifs.filter(function (n) { return !n.read; });
        if (unread.length === 0) { _showCuNotifToast('All notifications already read'); return; }
        var db    = firebase.firestore();
        var batch = db.batch();
        var _a;
        unread.forEach(function (n) {
            batch.update(db.collection('notifications').doc(n.id),
                (_a = {}, _a['readBy.' + _cuUid] = true, _a));
            n.read = true; // update local cache immediately
        });
        batch.commit().catch(function () {});
        _renderNotifPanel();
        _showCuNotifToast('All notifications marked as read');
    };

    window.clearCuNotifications = function () {
        var db = firebase.firestore();
        var batch = db.batch();
        var count = _cuNotifs.length;
        _cuNotifs.forEach(function (n) {
            batch.delete(db.collection('notifications').doc(n.id));
        });
        batch.commit().catch(function () {});
        _cuNotifs = [];
        _renderNotifPanel();
        _showCuNotifToast(count + ' notification' + (count !== 1 ? 's' : '') + ' deleted');
    };

    function _showCuNotifToast(msg) {
        var toast = document.getElementById('cuNotifToast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'cuNotifToast';
            toast.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%) translateY(80px);background:#1a202c;color:white;padding:12px 24px;border-radius:12px;font-size:13px;font-weight:600;z-index:99999;opacity:0;transition:all .3s cubic-bezier(0.4,0,0.2,1);pointer-events:none;box-shadow:0 4px 16px rgba(0,0,0,0.2);display:flex;align-items:center;gap:8px;';
            document.body.appendChild(toast);
        }
        toast.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#4ade80" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>' + msg;
        toast.style.opacity = '1';
        toast.style.transform = 'translateX(-50%) translateY(0)';
        clearTimeout(window._cuNotifToastTimer);
        window._cuNotifToastTimer = setTimeout(function() {
            toast.style.opacity = '0';
            toast.style.transform = 'translateX(-50%) translateY(80px)';
        }, 3000);
    }

    function _mergeNotifs(roleDocs, personalDocs) {
        var map = {};
        roleDocs.concat(personalDocs).forEach(function (d) {
            var data   = d.data();
            var readBy = data.readBy || {};
            map[d.id] = {
                id:        d.id,
                title:     data.title   || '',
                message:   data.message || '',
                type:      data.type    || 'info',
                createdAt: data.createdAt || null,
                read:      readBy[_cuUid] === true,
            };
        });
        _cuNotifs = Object.values(map).sort(function (a, b) {
            if (!a.createdAt || !b.createdAt) return 0;
            return b.createdAt.toMillis() - a.createdAt.toMillis();
        });
        _renderNotifPanel();
    }

    function _initCuNotifs(uid) {
        _cuUid = uid;
        var db = firebase.firestore();

        // Also update avatar initials from Firebase Auth
        firebase.auth().currentUser && db.collection('users').doc(uid).get().then(function (doc) {
            var name = (doc.exists && doc.data().name) || '';
            if (name) {
                var parts = name.trim().split(' ').filter(Boolean);
                var ini   = parts.length >= 2
                    ? (parts[0][0] + parts[1][0]).toUpperCase()
                    : parts[0][0].toUpperCase();
                var avatarEl = document.getElementById('cuAvatar');
                if (avatarEl) avatarEl.textContent = ini;
                // Pre-fill avatar menu name
                var nameEl = document.getElementById('cuAvatarName');
                if (nameEl) nameEl.textContent = name;
                // Update page title
                if (window._cuUpdateTitleWithName) window._cuUpdateTitleWithName(name);
            }
        }).catch(function () {});

        var roleQuery = db.collection('notifications')
            .where('targetRole', '==', 'customer')
            .limit(30);
        var personalQuery = db.collection('notifications')
            .where('targetUid', '==', uid)
            .limit(20);

        roleQuery.onSnapshot(function (snap) {
            _roleDocs = snap.docs;
            _mergeNotifs(_roleDocs, _personalDocs);
        });
        personalQuery.onSnapshot(function (snap) {
            _personalDocs = snap.docs;
            _mergeNotifs(_roleDocs, _personalDocs);
        });
    }

    // Start when Firebase Auth is ready
    ready(function () {
        if (typeof firebase === 'undefined') return;
        firebase.auth().onAuthStateChanged(function (user) {
            if (user) _initCuNotifs(user.uid);
        });
    });

    // Re-run active tab after header is injected (MutationObserver)
    ready(function () {
        var headerEl = document.getElementById('customerHeader');
        if (!headerEl) return;
        var obs = new MutationObserver(function () { setActiveTab(); });
        obs.observe(headerEl, { childList: true, subtree: true });
    });

    // ── Dynamic page title: "Welcome, Full Name" ────────────
    function _updateTitle() {
        var sess = JSON.parse(
            sessionStorage.getItem('cpUser') ||
            sessionStorage.getItem('spUser') ||
            sessionStorage.getItem('apUser') || '{}'
        );
        var name = (sess.name || '').trim();
        if (name) document.title = 'Welcome, ' + name;
    }
    ready(_updateTitle);
    // Also update once Firebase loads the name (may arrive after page load)
    window._cuUpdateTitleWithName = function(name) {
        if (name) document.title = 'Welcome, ' + name;
    };

})();
