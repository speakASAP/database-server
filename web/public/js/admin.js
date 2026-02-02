/**
 * Admin panel: login via /auth (proxied to auth-microservice), then show DB stats.
 */
(function () {
  const STORAGE_ACCESS = 'db_admin_access';
  const STORAGE_REFRESH = 'db_admin_refresh';

  const loginView = document.getElementById('login-view');
  const dashboardView = document.getElementById('dashboard-view');
  const loginForm = document.getElementById('login-form');
  const loginError = document.getElementById('login-error');
  const loginBtn = document.getElementById('login-btn');
  const userEmailEl = document.getElementById('user-email');
  const logoutLink = document.getElementById('logout-link');
  const pgStatusEl = document.getElementById('pg-status');
  const redisStatusEl = document.getElementById('redis-status');
  const dbLoading = document.getElementById('db-loading');
  const dbContent = document.getElementById('db-content');
  const dbEmpty = document.getElementById('db-empty');
  const redisInfoGrid = document.getElementById('redis-info-grid');

  function showError(el, msg) {
    el.textContent = msg || '';
    el.classList.toggle('hidden', !msg);
  }

  function setToken(access, refresh) {
    if (access) sessionStorage.setItem(STORAGE_ACCESS, access);
    if (refresh) sessionStorage.setItem(STORAGE_REFRESH, refresh);
  }

  function clearToken() {
    sessionStorage.removeItem(STORAGE_ACCESS);
    sessionStorage.removeItem(STORAGE_REFRESH);
  }

  function getAccessToken() {
    return sessionStorage.getItem(STORAGE_ACCESS);
  }

  function isLoggedIn() {
    return !!getAccessToken();
  }

  function showView(loggedIn) {
    loginView.classList.toggle('hidden', loggedIn);
    dashboardView.classList.toggle('hidden', !loggedIn);
    if (loggedIn) {
      userEmailEl.textContent = sessionStorage.getItem('db_admin_email') || 'User';
      loadDashboard();
    }
  }

  async function login(email, password) {
    loginBtn.disabled = true;
    showError(loginError, '');
    try {
      const res = await fetch('/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        showError(loginError, data.message || 'Login failed');
        return;
      }
      setToken(data.accessToken, data.refreshToken);
      sessionStorage.setItem('db_admin_email', data.user?.email || email);
      showView(true);
    } catch (e) {
      showError(loginError, 'Network error. Check auth-microservice is reachable.');
    } finally {
      loginBtn.disabled = false;
    }
  }

  function escapeHtml(s) {
    const div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }

  async function loadDashboard() {
    pgStatusEl.textContent = '—';
    pgStatusEl.classList.remove('ok', 'error');
    redisStatusEl.textContent = '—';
    redisStatusEl.classList.remove('ok', 'error');
    dbLoading.classList.remove('hidden');
    dbContent.classList.add('hidden');
    dbEmpty.classList.add('hidden');
    redisInfoGrid.innerHTML = '';

    const token = getAccessToken();
    if (!token) {
      showView(false);
      return;
    }

    try {
      const res = await fetch('/api/stats', {
        headers: { Authorization: 'Bearer ' + token }
      });
      const data = await res.json().catch(() => ({}));
      if (res.status === 401) {
        clearToken();
        sessionStorage.removeItem('db_admin_email');
        showView(false);
        return;
      }
      if (!res.ok) {
        pgStatusEl.textContent = 'Error';
        pgStatusEl.classList.add('error');
        redisStatusEl.textContent = 'Error';
        redisStatusEl.classList.add('error');
        dbLoading.classList.add('hidden');
        dbEmpty.classList.remove('hidden');
        dbEmpty.textContent = data.message || 'Failed to load stats';
        return;
      }

      const pg = data.postgres || {};
      const redis = data.redis || {};
      pgStatusEl.textContent = pg.healthy ? 'OK' : (pg.error || 'Error');
      pgStatusEl.classList.add(pg.healthy ? 'ok' : 'error');
      redisStatusEl.textContent = redis.healthy ? 'OK' : (redis.error || 'Error');
      redisStatusEl.classList.add(redis.healthy ? 'ok' : 'error');

      if (pg.databases && pg.databases.length > 0) {
        const table = document.createElement('table');
        table.innerHTML = '<thead><tr><th>Database</th><th>Size</th><th>Connections</th></tr></thead><tbody></tbody>';
        const tbody = table.querySelector('tbody');
        pg.databases.forEach(function (r) {
          const tr = document.createElement('tr');
          tr.innerHTML =
            '<td>' + escapeHtml(r.name || '—') + '</td>' +
            '<td>' + escapeHtml(r.size || '—') + '</td>' +
            '<td>' + escapeHtml(String(r.connections ?? '—')) + '</td>';
          tbody.appendChild(tr);
        });
        dbContent.innerHTML = '';
        dbContent.appendChild(table);
        dbContent.classList.remove('hidden');
        dbLoading.classList.add('hidden');
      } else {
        dbLoading.classList.add('hidden');
        dbEmpty.classList.remove('hidden');
        dbEmpty.textContent = pg.error || 'No databases found.';
      }

      if (redis.healthy) {
        const cards = [
          { label: 'Memory', value: redis.usedMemory || 'N/A' },
          { label: 'Version', value: redis.version || 'N/A' }
        ];
        cards.forEach(function (c) {
          const card = document.createElement('div');
          card.className = 'stat-card';
          card.innerHTML = '<h4>' + escapeHtml(c.label) + '</h4><div class="value">' + escapeHtml(c.value) + '</div>';
          redisInfoGrid.appendChild(card);
        });
      }
    } catch (e) {
      pgStatusEl.textContent = 'Error';
      pgStatusEl.classList.add('error');
      redisStatusEl.textContent = 'Error';
      redisStatusEl.classList.add('error');
      dbLoading.classList.add('hidden');
      dbEmpty.classList.remove('hidden');
      dbEmpty.textContent = 'Failed to load stats';
    }
  }

  loginForm.addEventListener('submit', function (e) {
    e.preventDefault();
    const email = document.getElementById('email').value.trim();
    const password = document.getElementById('password').value;
    if (email && password) login(email, password);
  });

  logoutLink.addEventListener('click', function (e) {
    e.preventDefault();
    clearToken();
    sessionStorage.removeItem('db_admin_email');
    showView(false);
  });

  if (isLoggedIn()) {
    showView(true);
  } else {
    showView(false);
  }
})();
