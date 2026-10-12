// The operator dashboard's client.
//
// Three rules this file keeps, because a dashboard that breaks them is worse
// than no dashboard:
//
//   1. TOKEN IN MEMORY, NEVER ON DISK. The bearer token lives in a closure and
//      in `sessionStorage` at most. Nothing is written to `localStorage`, and
//      the sign-in form is cleared on success, so a token outlives neither the
//      tab nor the operator's attention.
//
//   2. EVERY FAILURE SAYS WHY. A rejected request shows the API's own message,
//      not "Something went wrong": an operator who cannot tell an expired token
//      from a rate limit from a network drop will call platform support about
//      a problem they could have solved themselves.
//
//   3. NUMBERS ARE FORMATTED, NEVER STRINGIFIED. `toLocaleString` with the
//      platform's currency, and an empty set shows a dash rather than a zero
//      that reads as "the shop sold nothing" when the truth is "the window has
//      no rows".

(() => {
  'use strict';

  const TOKEN_KEY = 'simplesales-operator-token';
  let token = sessionStorage.getItem(TOKEN_KEY) || '';

  const gate = document.getElementById('gate');
  const views = document.getElementById('views');
  const gateError = document.getElementById('gate-error');

  /** A fetch that carries the token and turns every failure into text. */
  async function api(path, options = {}) {
    const response = await fetch(path, {
      ...options,
      headers: {
        Accept: 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      },
    });
    const text = await response.text();
    let body = null;
    try {
      body = text ? JSON.parse(text) : null;
    } catch {
      body = null;
    }
    if (!response.ok) {
      const message = (body && (body.error || body.message)) || `${response.status} ${text.slice(0, 120)}`;
      const error = new Error(message);
      error.status = response.status;
      throw error;
    }
    return body;
  }

  function money(value) {
    if (value === null || value === undefined || Number.isNaN(Number(value))) return '—';
    return new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 }).format(Number(value));
  }

  function count(value) {
    if (value === null || value === undefined) return '—';
    return new Intl.NumberFormat().format(Number(value));
  }

  function percent(value) {
    if (value === null || value === undefined) return '—';
    return `${Number(value)}%`;
  }

  function when(iso) {
    if (!iso) return '—';
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return iso;
    return date.toLocaleString();
  }

  /** The day an ISO instant falls on, in the reader's own timezone. */
  function day(iso) {
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) return '—';
    return date.toLocaleDateString();
  }

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function tile(label, value, note) {
    const node = el('div', 'tile');
    node.append(el('div', 'label', label), el('div', 'value', value));
    if (note) node.append(el('div', 'note', note));
    return node;
  }

  /** Writes a body of rows, or a single "nothing" row. */
  function fill(table, rows, render) {
    const body = table.querySelector('tbody');
    body.replaceChildren();
    if (!rows || rows.length === 0) {
      const row = document.createElement('tr');
      const cell = el('td', 'empty', 'Nothing in this window');
      cell.colSpan = table.querySelectorAll('thead th').length;
      row.append(cell);
      body.append(row);
      return;
    }
    for (const row of rows) body.append(render(row));
  }

  function pill(text, kind) {
    return el('span', `pill${kind ? ` is-${kind}` : ''}`, text);
  }

  // ---------------------------------------------------------------- views

  async function loadOverview() {
    const from = document.getElementById('from').value;
    const to = document.getElementById('to').value;
    const query = new URLSearchParams();
    if (from) query.set('from', `${from}T00:00:00.000Z`);
    if (to) query.set('to', `${to}T23:59:59.000Z`);

    const [analytics, drilldown] = await Promise.all([
      api(`/api/system/analytics?${query}`),
      api(`/api/system/analytics/drilldown?${query}`),
    ]);

    const tiles = document.getElementById('tiles');
    tiles.replaceChildren(
      tile('Shops', count(analytics.tenants)),
      tile('Active users', count(analytics.activeUsers)),
      tile('Sales', count(analytics.salesCount), `in ${money(analytics.totalSales)} revenue`),
      tile('Profit', money(analytics.totalProfit), `${percent(
        analytics.totalSales ? Math.round((analytics.totalProfit / analytics.totalSales) * 1000) / 10 : 0,
      )} of turnover`),
      tile('Products', count(analytics.activeProducts)),
    );
    if (analytics.window_truncated) {
      tiles.append(
        el('div', 'notice', 'The requested window is wider than the platform serves; the figures cover the last 400 days.'),
      );
    }

    const shops = drilldown.byTenant || [];
    fill(document.getElementById('shops'), shops, (shop) => {
      const row = document.createElement('tr');
      row.append(
        Object.assign(el('td', null, shop.tenantName), { dataset: { tenant: shop.tenantId } }),
        el('td', 'num', count(shop.totals.salesCount)),
        el('td', 'num', money(shop.totals.totalSales)),
        el('td', 'num', money(shop.totals.totalProfit)),
        el('td', 'num', money(shop.totals.averageBasket)),
        el('td', null, (shop.paymentMix[0] && shop.paymentMix[0].method) || '—'),
      );
      return row;
    });
  }

  async function loadUsers() {
    const { users } = await api('/api/system/users?limit=200');
    fill(document.getElementById('users-table'), users, (user) => {
      const row = document.createElement('tr');
      row.append(
        el('td', null, user.name || '—'),
        el('td', null, user.shop || '—'),
        el('td', null, user.role),
        el('td', null, pill(user.email_verified ? 'verified' : 'pending', user.email_verified ? 'ok' : 'warn')),
        el('td', null, when(user.joined_at)),
      );
      return row;
    });
  }

  async function loadHealth() {
    const data = await api('/api/system/observability');
    const tiles = document.getElementById('health-tiles');
    tiles.replaceChildren(
      tile('Shops', count(data.tenants)),
      tile('Active users', count(data.activeUsers)),
      tile('Pending codes', count(data.verification.pending)),
      tile('Codes burnt (24h)', count(data.verification.burnt_last_24h),
        data.verification.burnt_last_24h > 0 ? 'a shop may be failing to verify' : 'none'),
    );
    fill(document.getElementById('verifications'), data.verification.recent, (entry) => {
      const row = document.createElement('tr');
      row.append(
        el('td', null, when(entry.at)),
        el('td', null, entry.email),
        el('td', 'num', count(entry.attempts)),
        el('td', null, pill(entry.used ? 'used' : 'unused', entry.used ? 'ok' : 'warn')),
        el('td', null, pill(entry.expired ? 'expired' : 'live', entry.expired ? 'bad' : 'ok')),
      );
      return row;
    });
  }

  // ---------------------------------------------------------------- shell

  function show(view) {
    for (const button of document.querySelectorAll('.tab')) {
      button.classList.toggle('is-current', button.dataset.view === view);
      button.setAttribute('aria-selected', String(button.dataset.view === view));
    }
    for (const section of document.querySelectorAll('#views > section')) {
      section.hidden = section.id !== `view-${view}`;
    }
    const loaders = { overview: loadOverview, users: loadUsers, health: loadHealth };
    loaders[view]().catch(showError);
  }

  function showError(error) {
    // The API's message, verbatim: an operator must be able to tell an expired
    // token from a rate limit without calling anyone.
    gateError.textContent = error.message;
    gateError.hidden = false;
    if (error.status === 401) {
      // An expired token is the one failure the dashboard can fix for itself.
      gate.hidden = false;
      views.hidden = true;
      sessionStorage.removeItem(TOKEN_KEY);
      gateError.textContent = 'Session expired. Paste a current token to continue.';
    }
  }

  function window30Days() {
    const to = new Date();
    const from = new Date(to.getTime() - 30 * 24 * 60 * 60 * 1000);
    document.getElementById('to').value = to.toISOString().slice(0, 10);
    document.getElementById('from').value = from.toISOString().slice(0, 10);
  }

  function start() {
    if (!token) {
      gate.hidden = false;
      return;
    }
    views.hidden = false;
    window30Days();
    show('overview');
  }

  document.getElementById('signin').addEventListener('submit', (event) => {
    event.preventDefault();
    const field = document.getElementById('token');
    token = field.value.trim();
    sessionStorage.setItem(TOKEN_KEY, token);
    gateError.hidden = true;
    views.hidden = false;
    window30Days();
    show('overview');
  });

  document.getElementById('refresh').addEventListener('click', () => loadOverview().catch(showError));

  for (const button of document.querySelectorAll('.tab')) {
    button.addEventListener('click', () => show(button.dataset.view));
  }

  start();
})();
