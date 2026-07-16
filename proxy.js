// TokenTelemetry reverse-proxy
// Routes API paths to the FastAPI backend, everything else to the Next.js frontend.
// Listens on port 3011 (override with PROXY_PORT env var).

const http = require('http');

const BACKEND  = { host: '127.0.0.1', port: 8010 };
const FRONTEND = { host: '127.0.0.1', port: 3010 };
const PORT = parseInt(process.env.PROXY_PORT || '3011', 10);

// Paths that must hit the backend (FastAPI).
// If you add new backend routes, add them here.
const BACKEND_PATHS = [
  '/api/',
  '/agents',
  '/sessions',
  '/analytics',
  '/version',
  '/health',
  '/remote-access',
  '/openapi.json',
  '/dashboard',
  '/config/',      // ← frontend calls /config/billing, /config/summarizer, etc.
  '/pricing',
];

// Paths that are always frontend static assets.
const FRONTEND_PATHS = [
  '/_next/',
  '/favicon',
  '/icon.svg',
  '/manifest',
  '/__nextjs',
];

function proxy(req, res, target) {
  const opts = {
    ...target,
    path: req.url,
    method: req.method,
    headers: { ...req.headers, host: target.host },
  };
  const upstream = http.request(opts, (upstreamRes) => {
    res.writeHead(upstreamRes.statusCode, upstreamRes.headers);
    upstreamRes.pipe(res);
  });
  upstream.on('error', (e) => {
    res.writeHead(502);
    res.end('' + e);
  });
  req.pipe(upstream);
}

http.createServer((req, res) => {
  const url = req.url;

  // Root → frontend
  if (url === '/') return proxy(req, res, FRONTEND);

  // Known frontend assets → frontend
  if (FRONTEND_PATHS.some((p) => url.startsWith(p))) return proxy(req, res, FRONTEND);

  // HTML navigation requests → frontend (Next.js SSR)
  const accept = (req.headers.accept || '').toLowerCase();
  if (accept.includes('text/html')) return proxy(req, res, FRONTEND);

  // Known backend API paths → backend
  if (BACKEND_PATHS.some((p) => url.startsWith(p))) return proxy(req, res, BACKEND);

  // Everything else → frontend (catch-all)
  proxy(req, res, FRONTEND);
}).listen(PORT, '0.0.0.0', () => {
  console.log(`TT proxy listening on :${PORT} → backend :${BACKEND.port} / frontend :${FRONTEND.port}`);
});
