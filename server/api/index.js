import http from 'node:http';

const originalListen = http.Server.prototype.listen;
http.Server.prototype.listen = function noopListen(...args) {
  return this;
};

const { app } = await import('../src/index.js');
http.Server.prototype.listen = originalListen;

app.get('/api/health', (req, res) => {
  res.status(200).json({
    ok: true,
    service: 'skyflow-airport-management',
    status: 'healthy',
    timestamp: new Date().toISOString(),
    mode: process.env.VERCEL ? 'serverless' : 'local',
    environment: process.env.NODE_ENV || 'development'
  });
});

app.get('/api/readiness', (req, res) => {
  const isReady = Boolean(process.env.JWT_SECRET) && (process.env.NODE_ENV !== 'production' || Boolean(process.env.CLIENT_ORIGINS || process.env.CORS_ORIGIN));
  res.status(isReady ? 200 : 503).json({
    ok: isReady,
    service: 'skyflow-airport-management',
    status: isReady ? 'ready' : 'degraded',
    timestamp: new Date().toISOString(),
    mode: process.env.VERCEL ? 'serverless' : 'local',
    environment: process.env.NODE_ENV || 'development',
    checks: {
      jwt_secret: Boolean(process.env.JWT_SECRET),
      client_origins: Boolean(process.env.CLIENT_ORIGINS || process.env.CORS_ORIGIN),
      supabase_configured: Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY)
    }
  });
});

app.use((error, req, res, next) => {
  const status = Number(error?.status) || 500;
  const payload = {
    ok: false,
    error: error?.message || 'Internal Server Error'
  };

  if (process.env.NODE_ENV !== 'production') {
    payload.stack = error?.stack;
  }

  res.status(status).json(payload);
});

export default app;
