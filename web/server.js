/**
 * Database Server Web - Express server
 * Serves landing, admin panel, proxies /auth to auth-microservice,
 * provides /api/stats and /api/health for database statistics.
 */
const express = require('express');
const path = require('path');
const http = require('http');
const { Client } = require('pg');
const { createClient } = require('redis');

const app = express();
const PORT = process.env.PORT || 3390;

const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || 'http://auth-microservice:3370';
const SERVICE_NAME = process.env.SERVICE_NAME || 'database-server-web';

/**
 * Structured log helper for troubleshooting (timestamp, level, message, details).
 */
function log(level, message, details) {
  const entry = {
    ts: new Date().toISOString(),
    service: SERVICE_NAME,
    level,
    message,
    ...(details && { details })
  };
  console.log(JSON.stringify(entry));
}
const DB_HOST = process.env.DB_SERVER_POSTGRES_HOST || 'db-server-postgres';
const DB_PORT = parseInt(process.env.DB_SERVER_PORT || '5432', 10);
const DB_USER = process.env.DB_SERVER_ADMIN_USER || 'dbadmin';
const DB_PASSWORD = process.env.DB_SERVER_ADMIN_PASSWORD || '';
const DB_INIT = process.env.DB_SERVER_INIT_DB || 'postgres';
const REDIS_HOST = process.env.DB_SERVER_REDIS_HOST || 'db-server-redis';
const REDIS_PORT = parseInt(process.env.REDIS_SERVER_PORT || '6379', 10);

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public'), { index: 'index.html' }));

/**
 * Health for frontend container (nginx health check)
 */
app.get('/health', (req, res) => {
  res.status(200).json({ success: true, status: 'ok', service: 'database-server-web' });
});

/**
 * Proxy /auth/* to auth-microservice for login/validate/refresh
 */
app.use('/auth', (req, res) => {
  const url = new URL(req.originalUrl, AUTH_SERVICE_URL);
  const targetUrl = `${url.protocol}//${url.host}${url.pathname}${url.search}`;
  const opts = {
    hostname: url.hostname,
    port: url.port || 80,
    path: url.pathname + url.search,
    method: req.method,
    headers: { ...req.headers, host: url.host }
  };
  delete opts.headers['host'];
  opts.headers['Host'] = url.host;

  const proxyReq = http.request(opts, (proxyRes) => {
    res.status(proxyRes.statusCode);
    Object.keys(proxyRes.headers).forEach(k => res.setHeader(k, proxyRes.headers[k]));
    proxyRes.pipe(res);
  });
  proxyReq.on('error', (err) => {
    const reason = err.code || err.message || 'connection failed';
    log('error', 'Auth proxy request failed', {
      reason,
      code: err.code,
      errno: err.errno,
      targetUrl,
      AUTH_SERVICE_URL,
      path: req.method + ' ' + req.originalUrl,
      message: err.message
    });
    res.status(502).json({
      statusCode: 502,
      message: 'Auth service unavailable',
      reason: `Auth service unreachable: ${reason}. Check that auth-microservice is running and AUTH_SERVICE_URL (${AUTH_SERVICE_URL}) is correct and reachable from this container.`
    });
  });
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    if (req.body && Object.keys(req.body).length > 0) {
      const body = JSON.stringify(req.body);
      proxyReq.setHeader('Content-Type', 'application/json');
      proxyReq.setHeader('Content-Length', Buffer.byteLength(body));
      proxyReq.write(body);
    }
  }
  proxyReq.end();
});

/**
 * Get PostgreSQL databases list with sizes and connections
 */
async function getPostgresStats() {
  if (!DB_PASSWORD) {
    return { healthy: false, error: 'DB_SERVER_ADMIN_PASSWORD not configured', databases: [] };
  }
  const client = new Client({
    host: DB_HOST,
    port: DB_PORT,
    user: DB_USER,
    password: DB_PASSWORD,
    database: DB_INIT,
    connectionTimeoutMillis: 5000
  });
  try {
    await client.connect();
    const res = await client.query(`
      SELECT
        d.datname AS name,
        pg_size_pretty(pg_database_size(d.datname)) AS size,
        (SELECT count(*) FROM pg_stat_activity a WHERE a.datname = d.datname) AS connections
      FROM pg_database d
      WHERE d.datistemplate = false
      ORDER BY pg_database_size(d.datname) DESC
    `);
    return {
      healthy: true,
      databases: res.rows,
      version: (await client.query('SELECT version()')).rows[0]?.version || ''
    };
  } catch (err) {
    return { healthy: false, error: err.message, databases: [] };
  } finally {
    await client.end().catch(() => {});
  }
}

/**
 * Get Redis stats
 */
async function getRedisStats() {
  const client = createClient({ url: `redis://${REDIS_HOST}:${REDIS_PORT}` });
  try {
    await client.connect();
    const info = await client.info('server');
    const memory = await client.info('memory');
    const used = (memory.match(/used_memory_human:([^\r\n]+)/) || [])[1] || 'N/A';
    const version = (info.match(/redis_version:([^\r\n]+)/) || [])[1] || 'N/A';
    return { healthy: true, usedMemory: used, version };
  } catch (err) {
    return { healthy: false, error: err.message };
  } finally {
    await client.quit().catch(() => {});
  }
}

/**
 * API: stats (requires valid JWT - validate via auth-microservice)
 */
app.get('/api/stats', async (req, res) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    log('warn', 'GET /api/stats missing or invalid Authorization header', { hasHeader: !!authHeader });
    return res.status(401).json({ error: 'Unauthorized', message: 'Valid token required' });
  }
  const token = authHeader.slice(7);
  if (!token || token.length < 20) {
    log('warn', 'GET /api/stats token empty or too short (possible jwt malformed at auth)', {
      tokenLength: token ? token.length : 0
    });
    return res.status(401).json({ error: 'Unauthorized', message: 'Invalid or missing token' });
  }
  const validateUrl = `http://127.0.0.1:${PORT}/auth/validate`;
  /* Use self-call via /auth proxy - same path that works for external clients. */
  try {
    const validateRes = await fetch(validateUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token }),
      signal: AbortSignal.timeout(5000)
    });
    const body = await validateRes.text();
    const data = JSON.parse(body || '{}');
    if (!validateRes.ok || !data.valid) {
      log('info', 'GET /api/stats token validation rejected by auth', {
        status: validateRes.status,
        ok: validateRes.ok
      });
      return res.status(401).json({ error: 'Unauthorized', message: 'Invalid token' });
    }
  } catch (err) {
    const reason = err.name === 'AbortError' ? 'timeout after 5s' : (err.cause?.code || err.message);
    log('error', 'GET /api/stats auth validate request failed', {
      reason,
      name: err.name,
      message: err.message,
      validateUrl,
      AUTH_SERVICE_URL,
      code: err.code || err.cause?.code
    });
    return res.status(502).json({
      error: 'Auth service unavailable',
      message: 'Auth service unreachable; cannot validate token.',
      reason: `Auth service unreachable: ${reason}. Check that auth-microservice is running and AUTH_SERVICE_URL (${AUTH_SERVICE_URL}) is correct and reachable from this container.`
    });
  }

  const [postgres, redis] = await Promise.all([getPostgresStats(), getRedisStats()]);
  res.json({
    success: true,
    postgres,
    redis,
    timestamp: new Date().toISOString()
  });
});

/**
 * API: health (public - for quick status checks)
 */
app.get('/api/health', async (req, res) => {
  const [postgres, redis] = await Promise.all([getPostgresStats(), getRedisStats()]);
  const healthy = postgres.healthy && redis.healthy;
  res.status(healthy ? 200 : 503).json({
    success: healthy,
    postgres: { healthy: postgres.healthy, databaseCount: postgres.databases?.length || 0 },
    redis: { healthy: redis.healthy },
    timestamp: new Date().toISOString()
  });
});

app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'admin.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  log('info', 'database-server-web listening', {
    port: PORT,
    AUTH_SERVICE_URL
  });
});
