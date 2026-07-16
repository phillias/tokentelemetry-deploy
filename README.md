# tokentelemetry-deploy

Opinionated deployment wrapper for [TokenTelemetry](https://github.com/VasiHemanth/tokentelemetry) — handles the two gotchas the upstream doesn't document.

## What this does

1. Clones upstream TT into `~/tokentelemetry/`
2. Installs backend (Python venv) + frontend (npm) deps
3. Builds the frontend with `NEXT_PUBLIC_API_BASE=""` — **the critical step the upstream misses**
4. Installs a reverse proxy (`proxy.js`) that routes API paths to the backend and everything else to the frontend
5. Installs `manage.sh` for start/stop/restart/status

## Quick start

```bash
git clone git@github.com:phillias/tokentelemetry-deploy.git
cd tokentelemetry-deploy
chmod +x setup.sh
./setup.sh
```

Then point your reverse proxy at `127.0.0.1:3011`.

## The four gotchas

### 1. NEXT_PUBLIC_API_BASE must be baked in at build time

Next.js compiles `NEXT_PUBLIC_*` env vars into the JS bundles during `next build`. Setting them at runtime with `NEXT_PUBLIC_API_BASE=... next start` has **no effect** on a production build.

Without this, the browser tries to call `https://your-host:8000/agents` directly — port 8000 isn't exposed behind a reverse proxy, so all API calls silently fail and the dashboard shows zeros.

The `setup.sh` handles this. If you rebuild the frontend manually:

```bash
cd ~/tokentelemetry/frontend
NEXT_PUBLIC_API_BASE="" npx next build
```

### 2. Stale next-server processes survive restarts

`setsid` creates process sessions that can hold port bindings after the parent shell exits. `lsof` may not find them. Use this to kill cleanly:

```bash
pkill -f "next-server"
```

The `manage.sh` handles this in its `stop` and `restart` commands.

### 3. Empty NEXT_PUBLIC_API_BASE is treated as unset (upstream bug)

The upstream `api.ts` uses `if (explicit) return explicit` — empty string `""` is falsy in JS, so it falls through to `hostname:8000`. The browser tries to hit port 8000 directly, which fails behind a reverse proxy.

The `setup.sh` patches this to `if (explicit !== undefined && explicit !== null) return explicit` before building. If you rebuild manually:

```bash
cd ~/tokentelemetry/frontend
sed -i 's/if (explicit) return explicit;/if (explicit !== undefined \&\& explicit !== null) return explicit;/' src/lib/api.ts
NEXT_PUBLIC_API_BASE="" npx next build
```

### 4. Backend requires Python 3.9+

The backend uses `asyncio.to_thread` which was added in Python 3.9. On Ubuntu 20.04 (Python 3.8), the sessions scan fails with `AttributeError: module 'asyncio' has no attribute 'to_thread'`.

The `setup.sh` warns if Python < 3.9 is detected. If you hit this, either upgrade Python or patch `main.py`:

```bash
cd ~/tokentelemetry/backend
sed -i 's/data = await _asyncio.to_thread(_scan_sessions_sync)/loop = _asyncio.get_event_loop();\n            data = await loop.run_in_executor(None, _scan_sessions_sync)/' main.py
```

## Ports

| Service    | Port | Bind    | Notes                           |
|------------|------|---------|---------------------------------|
| Backend    | 8010 | 127.0.0.1 | FastAPI (uvicorn) — changed from 8000 to avoid conflicts |
| Frontend   | 3010 | 127.0.0.1 | Next.js production server     |
| Proxy      | 3011 | 0.0.0.0   | Routes API→backend, rest→frontend |

Only port 3011 needs to be reachable by your reverse proxy.

## Reverse proxy examples

### Nginx

```nginx
server {
    listen 443 ssl http2;
    server_name tokentelemetry.yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/tokentelemetry.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tokentelemetry.yourdomain.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3011;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (if needed for live updates)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Long timeout for the ~6s initial session scan
        proxy_read_timeout 30s;
    }
}
```

### Caddy

```
tokentelemetry.yourdomain.com {
    reverse_proxy 127.0.0.1:3011
}
```

### Traefik (Docker labels)

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.tt.rule=Host(`tokentelemetry.yourdomain.com`)"
  - "traefik.http.routers.tt.entrypoints=websecure"
  - "traefik.http.routers.tt.tls.certresolver=letsencrypt"
  - "traefik.http.services.tt.loadbalancer.server.port=3011"
```

### Godoxy (this server's setup)

```yaml
# compose.yml — dummy container with labels
services:
  tokentelemetry-proxy:
    image: alpine:latest
    command: ["tail", "-f", "/dev/null"]
    labels:
      proxy.tokentelemetry.port: "3011"
      proxy.tokentelemetry.alias: tokentelemetry
```

## Updating

```bash
cd ~/tokentelemetry
git pull
cd frontend
NEXT_PUBLIC_API_BASE="" npx next build
cd ../..
./manage.sh restart
```

## Troubleshooting

### Dashboard shows "Loading telemetry..." forever

- Check that `NEXT_PUBLIC_API_BASE=""` was set during `next build` (not at runtime)
- Check that port 3011 is listening: `ss -tlnp | grep 3011`
- Check backend logs: `tail -50 ~/tokentelemetry/logs/backend.log`

### 404 on /config/billing or /config/summarizer

The proxy's backend route list is missing `/config/`. Edit `proxy.js` and add it to `BACKEND_PATHS`:

```javascript
const BACKEND_PATHS = [
  // ...existing paths...
  '/config/',
];
```

Then restart the proxy.

### Backend 500 on /agents (Hermes permission error)

```bash
# Add to manage.sh start, before the uvicorn command:
export HERMES_HOME=/dev/null
```

### First load takes ~6 seconds

Normal — the `/sessions` endpoint scans all agent log files on first request. Subsequent requests within 30 seconds are served from cache. The upstream recently added a sidecar parse cache that should help.
