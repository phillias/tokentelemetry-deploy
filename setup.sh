#!/usr/bin/env bash
# TokenTelemetry Deploy — one-shot setup for a new server
# Clones upstream TT, installs deps, builds frontend with correct env, creates manage.sh
set -euo pipefail

TT_DIR="${TT_DIR:-$HOME/tokentelemetry}"
UPSTREAM="https://github.com/VasiHemanth/tokentelemetry.git"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== TokenTelemetry Deploy ==="
echo "Target: $TT_DIR"

# 0. Check Python version (asyncio.to_thread requires 3.9+)
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
PY_MINOR=$(echo "$PY_VER" | cut -d. -f2)
if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 9 ]; }; then
  echo "⚠ Python $PY_VER detected. Backend requires 3.9+ (asyncio.to_thread)."
  echo "  Install Python 3.9+ and recreate the venv, or patch main.py."
  echo "  Continuing — the venv will use $(python3 --version)."
fi

# 1. Clone or pull upstream
if [ -d "$TT_DIR/.git" ]; then
  echo "→ Updating existing clone..."
  git -C "$TT_DIR" pull --ff-only
else
  echo "→ Cloning upstream..."
  git clone "$UPSTREAM" "$TT_DIR"
fi

# 2. Patch api.ts: fix empty-string NEXT_PUBLIC_API_BASE treated as unset
#    Upstream treats "" as falsy, falling through to hostname:8000 which
#    breaks behind a reverse proxy. We patch to treat "" as valid.
API_TS="$TT_DIR/frontend/src/lib/api.ts"
if [ -f "$API_TS" ] && grep -q 'if (explicit) return explicit' "$API_TS"; then
  echo "→ Patching api.ts (empty-string API_BASE fix)..."
  sed -i 's/if (explicit) return explicit;/if (explicit !== undefined \&\& explicit !== null) return explicit;/' "$API_TS"
fi

# 3. Backend deps
echo "→ Installing backend dependencies..."
cd "$TT_DIR/backend"
if [ ! -d venv ]; then
  python3 -m venv venv
fi
./venv/bin/pip install -q -r requirements.txt

# 4. Frontend deps + build
echo "→ Installing frontend dependencies..."
cd "$TT_DIR/frontend"
npm install --silent

echo "→ Building frontend (NEXT_PUBLIC_API_BASE=\"\")..."
# CRITICAL: NEXT_PUBLIC_API_BASE must be set at BUILD time, not runtime.
# Empty string = same-origin relative URLs, so the browser calls /agents etc.
# through whatever reverse proxy is in front. Without this, the browser
# tries :8000 directly which fails behind a reverse proxy.
NEXT_PUBLIC_API_BASE="" npx next build

# 5. Install proxy
echo "→ Installing proxy..."
mkdir -p "$TT_DIR/proxy"
cp "$SCRIPT_DIR/proxy.js" "$TT_DIR/proxy/proxy.js"

# 6. Install manage.sh
echo "→ Installing manage.sh..."
cp "$SCRIPT_DIR/manage.sh" "$TT_DIR/manage.sh"
chmod +x "$TT_DIR/manage.sh"

# 7. Create logs dir
mkdir -p "$TT_DIR/logs"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Start:  $TT_DIR/manage.sh start"
echo "Stop:   $TT_DIR/manage.sh stop"
echo "Status: $TT_DIR/manage.sh status"
echo ""
echo "Proxy listens on port 3011."
echo "Backend listens on port 8010 (avoids conflict with other services on 8000)."
echo "Route your reverse proxy to 127.0.0.1:3011."
echo ""
echo "See README.md for reverse proxy configs and gotchas."
