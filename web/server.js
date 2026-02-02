/**
 * Database Server Web - Express server
 * Serves landing, admin panel, proxies /auth to auth-microservice,
 * provides /api/stats and /api/health for database statistics.
 */
const express = require('express');
const path = require('path');
const http = require('http');
const https = require('https');
const { Client } = require('pg');
const { createClient } = require('redis');

const app = express();
const PORT = process.env.PORT || 3390;

const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || 'http://auth-microservice:3370';
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
  proxyReq.on('error', () => {
    res.status(502).json({ statusCode: 502, message: 'Auth service unreachable' });
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
    return res.status(401).json({ error: 'Unauthorized', message: 'Valid token required' });
  }
  const token = authHeader.slice(7);
  const validateUrl = `${AUTH_SERVICE_URL}/auth/validate`;
  const httpModule = validateUrl.startsWith('https') ? https : http;
  try {
    const validateRes = await new Promise((resolve, reject) => {
      const urlObj = new URL(validateUrl);
      const reqOpt = httpModule.request({
        hostname: urlObj.hostname,
        port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
        path: urlObj.pathname + urlObj.search,
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        timeout: 5000
      }, (r) => {
        let body = '';
        r.on('data', c => (body += c));
        r.on('end', () => resolve({ status: r.statusCode, body }));
      });
      reqOpt.on('error', reject);
      reqOpt.on('timeout', () => { reqOpt.destroy(); reject(new Error('Timeout')); });
      reqOpt.write(JSON.stringify({ token }));
      reqOpt.end();
    });
    const data = JSON.parse(validateRes.body || '{}');
    if (validateRes.status !== 200 || !data.valid) {
      return res.status(401).json({ error: 'Unauthorized', message: 'Invalid token' });
    }
  } catch (err) {
    return res.status(502).json({ error: 'Auth service unreachable', message: err.message });
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
  console.log(`database-server-web listening on port ${PORT}`);
});
