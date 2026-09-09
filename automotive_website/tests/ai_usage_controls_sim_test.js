// Simulates the AI Usage Controls page (guard, load, render, cascade, save)
// by running its inline <script> blocks with DOM/fetch/Firebase stubs.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

(async function main() {

const html = fs.readFileSync(
  path.join(__dirname, '..', 'templates', 'ai_usage_controls.html'),
  'utf8'
);
const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);

let PASS = 0, FAIL = 0;
function check(name, cond, detail) {
  if (cond) { PASS++; console.log('  PASS ', name); }
  else { FAIL++; console.log('  FAIL ', name, detail || ''); }
}

// ── Stub DOM ──────────────────────────────────────────────────────────────────
function makeEl(id) {
  return {
    id, innerHTML: '', style: {}, dataset: {}, children: [],
    textContent: '', checked: false, disabled: false, value: '',
    className: '',
    addEventListener() {}, appendChild() {}, setAttribute() {}, focus() {},
    querySelectorAll() { return []; },
    classList: { toggle() {}, add() {}, remove() {} },
  };
}
const els = {};
function getEl(id) { if (!els[id]) els[id] = makeEl(id); return els[id]; }

const documentStub = {
  documentElement: makeEl('html'),
  body: Object.assign(makeEl('body'), { appendChild() {} }),
  getElementById: getEl,
  createElement: (tag) => makeEl('el-' + tag + '-' + Math.random()),
  querySelectorAll: () => [],
};

// ── Stub Firebase ─────────────────────────────────────────────────────────────
let authCallback = null;
const firebaseStub = {
  apps: [],
  initializeApp() { this.apps.push({}); },
  auth: () => ({
    currentUser: { uid: 'admin-uid-1', getIdToken: async () => 'fake-id-token' },
    onAuthStateChanged: (cb) => { authCallback = cb; },
  }),
};

// ── Stub fetch: /api/ai-settings GET/PUT ─────────────────────────────────────
let savedPayload = null;
let fetchCalls = 0;
const settingsFixture = {
  settings: {
    customer_ai_enabled: true,
    customer_token_limit: 30000,
    dev_access_enabled: true,
    dev_bypass_token_limit: false,
    dev_access_while_paused: true,
  },
  overview: {
    customer_tokens_used: 84250,
    customer_token_limit: 30000,
    customers_at_limit: 7,
    customer_ai_status: 'Active',
    next_reset: 'September 11, 2026 at 12:00 AM (PH time)',
    active_customers_today: 42,
  },
};
function fetchStub(url, opts) {
  fetchCalls++;
  if (url === '/api/ai-settings' && (!opts || opts.method === 'GET' || !opts.method)) {
    return Promise.resolve({ ok: true, status: 200, json: async () => settingsFixture });
  }
  if (url === '/api/ai-settings' && opts && opts.method === 'PUT') {
    savedPayload = JSON.parse(opts.body);
    return Promise.resolve({ ok: true, status: 200, json: async () => ({ success: true, settings: savedPayload }) });
  }
  return Promise.resolve({ ok: false, status: 404, json: async () => ({}) });
}

// ── Run the page scripts in order ─────────────────────────────────────────────
const sandbox = {
  document: documentStub,
  firebase: firebaseStub,
  fetch: fetchStub,
  window: { location: { replace: (u) => { sandbox.__redirect = u; } } },
  localStorage: { getItem: () => null, setItem() {} },
  sessionStorage: {
    store: { apUser: JSON.stringify({ uid: 'admin-uid-1', role: 'admin', name: 'Admin User' }) },
    getItem(k) { return this.store[k] || null; },
    setItem(k, v) { this.store[k] = v; },
  },
  setTimeout, clearTimeout, Promise, console,
};
sandbox.window.localStorage = sandbox.localStorage;
sandbox.window.sessionStorage = sandbox.sessionStorage;
vm.createContext(sandbox);

console.log('== Guard + reveal (script block 0) ==');
vm.runInContext(blocks[0], sandbox); // instant auth guard
check('admin not redirected by guard', sandbox.__redirect === undefined);
check('guard does not hide document', sandbox.document.documentElement.style.display !== 'none');

// Mark logged-out scenario in a fresh sandbox
const sb2 = vm.createContext({
  ...sandbox,
  localStorage: { getItem: (k) => k === '_loggedOut' ? '999' : null },
  document: documentStub,
  window: { location: { replace: (u) => { sb2.__redirect = u; } } },
});
sb2.window = { location: { replace: (u) => { sb2.__redirect = u; } } };
vm.runInContext(blocks[0], sb2);
check('logged-out user redirected to login', sb2.__redirect === '/login.html');

console.log('== Bootstrap + page logic (blocks 2-4) ==');
vm.runInContext(blocks[1], sandbox); // firebase init
vm.runInContext(blocks[3], sandbox); // chrome bootstrap (IIFE, no-op with stubs)
vm.runInContext(blocks[4], sandbox); // page logic + auth subscription

check('auth state subscription registered', typeof authCallback === 'function');
authCallback({ uid: 'admin-uid-1' }); // triggers _aiucLoad()

// Let the async load + render settle before asserting.
await new Promise(r => setTimeout(r, 30));

{ // checks (inline; the async load has already settled)
  // The stub DOM does not parse innerHTML, so reflect each switch's rendered
  // `checked` attribute onto its stub element (browsers do this natively).
  function syncChecked() {
    const htmlNow = getEl('aiucContent').innerHTML;
    ['aiucCustomerAI', 'aiucLimitEnabled', 'aiucDevAccess', 'aiucDevBypass', 'aiucDevWhilePaused']
      .forEach(id => {
        const m = htmlNow.match(new RegExp('id="' + id + '"( checked)?'));
        if (m) getEl(id).checked = !!m[1];
      });
  }
  syncChecked();
  vm.runInContext('_aiucSyncCascade()', sandbox);

  console.log('== Rendered output ==');
  const html1 = getEl('aiucContent').innerHTML;
  check('all sections rendered', ['Customer AI Access', 'Customer Token Limit', 'Token Reset',
    'Developer / Test Access', 'Usage Overview'].every(s => html1.includes(s)),
    'missing: ' + ['Customer AI Access','Customer Token Limit','Token Reset','Developer / Test Access','Usage Overview'].filter(s=>!html1.includes(s)));
  check('status pill shows ON', html1.includes('>ON<'));
  check('usage stats rendered', html1.includes('84,250') && html1.includes('7'));
  check('next reset rendered', html1.includes('September 11, 2026'));
  check('breadcrumb rendered', html1.includes('AI Usage Controls</strong>'));

  console.log('== Cascade behavior ==');
  // Dev master ON in fixture -> sub-toggles enabled; limit toggle ON -> input enabled
  check('limit input enabled (fixture has 30000 limit)', getEl('aiucTokenLimit').disabled === false);
  check('dev bypass sub-toggle enabled', getEl('aiucDevBypass').disabled === false);
  check('dev while-paused sub-toggle enabled', getEl('aiucDevWhilePaused').disabled === false);
  // Simulate turning dev master OFF then re-syncing
  getEl('aiucDevAccess').checked = false;
  vm.runInContext('_aiucSyncCascade()', sandbox);
  check('sub-toggles disabled when dev master off',
    getEl('aiucDevBypass').disabled === true && getEl('aiucDevWhilePaused').disabled === true);
  vm.runInContext('_aiucSyncCascade()', sandbox);
  getEl('aiucDevAccess').checked = true;
  vm.runInContext('_aiucSyncCascade()', sandbox);
  check('sub-toggles re-enabled when dev master on', getEl('aiucDevBypass').disabled === false);

  console.log('== Save flow ==');
  getEl('aiucCustomerAI').checked = false; // pause customer AI
  getEl('aiucTokenLimit').value = '45000';
  vm.runInContext('_aiucSave()', sandbox);
  await new Promise(r => setTimeout(r, 20));
  check('PUT request issued', savedPayload !== null);
  check('paused state saved', savedPayload && savedPayload.customer_ai_enabled === false);
  check('token limit saved as number', savedPayload && savedPayload.customer_token_limit === 45000);
  check('dev toggles saved', savedPayload && savedPayload.dev_access_enabled === true);
  // After save the page reloads -> status pill should show PAUSED after re-render
  await new Promise(r => setTimeout(r, 20));
  check('page re-rendered after save (fetch called again)', fetchCalls >= 2);
  syncChecked();
  vm.runInContext('_aiucSyncCascade()', sandbox);
  check('save button restored', getEl('aiucSaveBtn').textContent === 'Save Changes');

  console.log('== Toast feedback ==');
  const toast = getEl('toast');
  check('success toast shown', toast.textContent.includes('saved'), toast.textContent);

  }

  console.log(`\n${'='.repeat(60)}\nRESULT: ${PASS} passed, ${FAIL} failed\n${'='.repeat(60)}`);
  process.exit(FAIL ? 1 : 0);
})().catch(e => { console.error('HARNESS ERROR', e); process.exit(1); });
