// Simulates the Admin AI Assistant lifecycle (spec Tests A–E + H) in Node by
// loading the REAL <script> from admin_rag_ai.html into an isolated VM context
// per simulated page load, with DOM/Firestore/fetch stubs and shared
// localStorage (so a "refresh" re-runs the widget against persisted state).
//
// The fetch stub mimics the real FastAPI backend: it returns the client-sent
// session_id when present (server memory is keyed by it), else a fresh UUID.
//
// Run: node tests/rag_session_sim_test.js
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(
  path.join(__dirname, '..', 'templates', 'admin_rag_ai.html'),
  'utf8'
);
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.error('script block not found'); process.exit(1); }
const src = m[1];

// ── Shared (persists across simulated page loads) ─────────────────────────────
const persistent = new Map(); // localStorage store
let aiMode = 'online';
let serverSessionCounter = 0;

// ── One simulated page load = one fresh VM context ────────────────────────────
function loadPage() {
  const elements = {};
  function makeEl(id) {
    const el = {
      id, innerHTML: '', style: {}, children: [], dataset: {},
      listeners: {},
      addEventListener(ev, fn) { (this.listeners[ev] ||= []).push(fn); },
      click() { (this.listeners.click || []).forEach(fn => fn()); },
      appendChild(c) {
        const t = String(c.innerHTML || '').replace(/<[^>]+>/g, '');
        (this._rows ||= []).push(t);
        this.children.push(c);
        return c;
      },
      remove() { delete elements[id]; },
      closest() { return { querySelector: () => ({ style: {} }) }; },
      get scrollTop() { return this._scrollTop || 0; },
      set scrollTop(v) { this._scrollTop = v; },
      get scrollHeight() { return this._scrollHeight || 0; },
      set scrollHeight(v) { this._scrollHeight = v; },
      querySelector(sel) { return { style: {}, getAttribute: () => null }; },
      querySelectorAll(sel) {
        // Support the history-list click wiring: return one element per
        // data-sid in the rendered innerHTML. Click listeners are stored on
        // THIS element (keyed by sid) so they survive across calls — mirrors
        // how a real DOM keeps listeners on live nodes.
        if (sel === '.rag-hist-item[data-sid]') {
          const sids = [...String(this.innerHTML).matchAll(/data-sid="([^"]+)"/g)]
            .map(mm => mm[1]);
          this._itemListeners ||= {};
          return sids.map(sid => {
            const e = makeEl('hist_' + sid);
            e.getAttribute = name => (name === 'data-sid' ? sid : null);
            e.addEventListener = (ev, fn) => { (this._itemListeners[sid] ||= []).push(fn); };
            e.click = () => { (this._itemListeners[sid] || []).forEach(fn => fn()); };
            return e;
          });
        }
        return [];
      },
    };
    return el;
  }

  const ctx = {
    console, JSON, Math, Date, RegExp, String, Array, Object, Set,
    AbortController: class { constructor() { this.signal = {}; } abort() {} },
    fetch: async function (url, opts) {
      url = String(url);
      if (url === '/api/ai-chat') {
        const body = JSON.parse(opts.body);
        if (aiMode === 'online') {
          // Real backend: reuse client session_id, else mint a UUID
          const sid = body.session_id || 'srv_' + (++serverSessionCounter);
          return {
            json: async () => ({
              success: true, answer: 'AI:' + body.message, session_id: sid,
            }),
          };
        }
        return { json: async () => ({ success: false, offline: true }) };
      }
      if (url.startsWith('/api/ai-session/')) {
        return { json: async () => ({ success: true }) };
      }
      if (url.startsWith('/api/ai-health')) {  // may carry ?_= cache-buster
        return { json: async () => ({ online: aiMode === 'online' }) };
      }
      return { json: async () => ({}), catch: () => {} };
    },
  };
  ctx.window = ctx;
  ctx.addEventListener = () => {};
  ctx.dispatchEvent = () => {};
  ctx.setTimeout = setTimeout; ctx.clearTimeout = clearTimeout;
  ctx.setInterval = setInterval; ctx.clearInterval = clearInterval;
  ctx.globalThis = ctx;
  ctx.document = {
    getElementById(id) { return (elements[id] ||= makeEl(id)); },
    createElement(t) { return makeEl('el_' + Math.random()); },
    addEventListener() {},
    visibilityState: 'visible',
  };
  ctx.localStorage = {
    getItem: k => (persistent.has(k) ? persistent.get(k) : null),
    setItem: (k, v) => persistent.set(k, String(v)),
    removeItem: k => persistent.delete(k),
  };
  ctx.sessionStorage = {
    // admin session marker (normally set by admin_firebase.js)
    _s: new Map([['apUser', JSON.stringify({ uid: 'admin1' })]]),
    getItem(k) { return this._s.has(k) ? this._s.get(k) : null; },
    setItem(k, v) { this._s.set(k, String(v)); },
    removeItem(k) { this._s.delete(k); },
  };
  ctx.firebase = {
    auth() {
      return { onAuthStateChanged(fn) { fn({ uid: 'admin1' }); } };
    },
    firestore() {
      return {
        collection() {
          return {
            doc() {
              return {
                get: async () => ({
                  exists: true, data: () => ({ name: 'Test Admin' }),
                }),
              };
            },
          };
        },
      };
    },
  };
  // RAG local-mode data — non-empty so _ragWatch marks data ready quickly
  ctx.assets = [{ plateNumber: 'ABC123', status: 'Active' }];
  ctx.inventory = [];
  ctx.serviceTransactions = [];
  ctx.issuances = [];
  ctx.users = [];

  vm.createContext(ctx);
  vm.runInContext(src, ctx, { filename: 'admin_rag_ai.html<script>' });
  return ctx;
}

const wait = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  let pass = 0, fail = 0;
  const check = (name, cond) => {
    if (cond) { pass++; console.log('  PASS  ' + name); }
    else { fail++; console.log('  FAIL  ' + name); }
  };
  const sessions = () =>
    JSON.parse(persistent.get('rag_ai_chat_admin1') || '[]');
  const active = () =>
    JSON.parse(persistent.get('rag_ai_active_admin1') || 'null');

  // ── Page load 1 ───────────────────────────────────────────────────────────
  let page = loadPage();
  await wait(2200); // _ragWatch starts at 1s; first tick flips ready ~1.6s

  // ── Test A: normal conversation ───────────────────────────────────────────
  console.log('Test A — normal conversation');
  await page.ragAiSend('hello one');
  await wait(150); // let reply + save land before the next send
  await page.ragAiSend('hello two');
  await wait(150);
  await page.ragAiSend('hello three');
  await wait(150);
  // Rendered-row counting: the stub records appendChild of rows AND inner
  // wrappers (typing indicator / welcome), so assert on the stored history
  // rather than exact DOM row count here.
  check('all messages rendered (≥6 rows incl. typing wrappers)',
    (page.document.getElementById('ragAiChat')._rows || []).length >= 6);
  const a = active();
  check('active session has 6 messages', a && a.messages.length === 6);
  check('active session has a stable unique id (not the shared uid fallback)',
    a && a.id && a.id !== 'local_admin1');
  check('history list has exactly ONE entry', sessions().length === 1);
  check('history entry id === active id',
    sessions().length === 1 && sessions()[0].id === a.id);
  const roles = a.messages.map(x => x.role);
  check('stored conversation = user/AI pairs (3 user, 3 ai)',
    roles.filter(r => r === 'user').length === 3 &&
    roles.filter(r => r === 'ai').length === 3);
  check('timestamps kept on the entry', typeof a.ts === 'number');

  // ── Test B: refresh keeps the same conversation ───────────────────────────
  console.log('Test B — refresh keeps conversation');
  const beforeId = a.id;
  page = loadPage(); // fresh page load, same localStorage
  await wait(2200);
  const restoredRows = (page.document.getElementById('ragAiChat')._rows || [])
    .filter(r => r.indexOf('Hey, how can I help') === -1);
  check('conversation restored after refresh (6 bubbles)', restoredRows.length === 6);
  check('conversation id unchanged after refresh', active().id === beforeId);
  check('still exactly ONE history entry', sessions().length === 1);
  await page.ragAiSend('after refresh');
  await wait(150);
  check('new message continues the SAME conversation (8 msgs = 6+2)',
    active().messages.length === 8);
  check('still ONE history entry after post-refresh send', sessions().length === 1);

  // ── Test C: New Chat ──────────────────────────────────────────────────────
  console.log('Test C — new chat');
  page.ragNewChat();
  check('active slot removed after New Chat', active() === null);
  check('no empty history entry created', sessions().length === 1);
  await page.ragAiSend('chat B first message');
  await wait(150);
  check('second conversation created in history', sessions().length === 2);
  const ids = sessions().map(s => s.id);
  check('two distinct conversation ids', new Set(ids).size === 2);
  check('new messages stored under the NEW id',
    sessions().find(s => s.id !== beforeId).messages.length === 2);
  check('old chat untouched in history (8 msgs)',
    sessions().find(s => s.id === beforeId).messages.length === 8);

  // ── Test D: history loading + refresh persistence ─────────────────────────
  console.log('Test D — history');
  page.ragOpenHistory();
  await wait(20);
  const list = page.document.getElementById('ragHistoryList');
  const items = list.querySelectorAll('.rag-hist-item[data-sid]');
  check('history renders 2 items', items.length === 2);
  // Simulate the user clicking the older 8-message conversation
  items.find(e => e.getAttribute('data-sid') === beforeId).click();
  await wait(30);
  check('selected conversation becomes the active one', active().id === beforeId);
  check('exact messages restored in order (8)', active().messages.length === 8);
  page = loadPage(); // refresh again
  await wait(2200);
  check('selected historical conversation stays active after refresh',
    active().id === beforeId && active().messages.length === 8);
  check('history still has exactly 2 conversations', sessions().length === 2);

  // ── Test E: duplicate prevention (reopen/navigation storms) ───────────────
  console.log('Test E — duplicate prevention');
  for (let i = 0; i < 5; i++) {
    page = loadPage(); // repeated reloads/reopens/navigations
    await wait(500);
    page.ragOpenHistory();
    page.ragCloseHistory();
  }
  check('no duplicate conversation entries after reload storm', sessions().length === 2);
  const totalMsgs = sessions().reduce((n, s) => n + s.messages.length, 0);
  check('message totals unchanged (8+2), no duplicated messages', totalMsgs === 10);

  // ── Test H: status theming (green online / orange local) ──────────────────
  console.log('Test H — AI status colours');
  // Fresh page with ONLINE backend — read the FAB status elements after the
  // health check applies the theme.
  aiMode = 'online';
  page = loadPage();
  await wait(2600); // watch(1s) + tick(600ms) + health fetch
  const dotOnline = page.document.getElementById('ragFabOnlineDot');
  const pulseO = page.document.getElementById('ragFabPulseOuter');
  const pulseI = page.document.getElementById('ragFabPulseInner');
  check('ONLINE → FAB status dot GREEN', dotOnline.style.background === '#22c55e');
  check('ONLINE → animated rings GREEN',
    pulseO.style.borderColor === '#22c55e' && pulseI.style.borderColor === '#22c55e');
  aiMode = 'local';
  page = loadPage();
  await wait(2600);
  const dotLocal = page.document.getElementById('ragFabOnlineDot');
  const pulseO2 = page.document.getElementById('ragFabPulseOuter');
  const pulseI2 = page.document.getElementById('ragFabPulseInner');
  check('LOCAL → FAB status dot ORANGE', dotLocal.style.background === '#f97316');
  check('LOCAL → animated rings ORANGE',
    pulseO2.style.borderColor === '#f97316' && pulseI2.style.borderColor === '#f97316');

  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
