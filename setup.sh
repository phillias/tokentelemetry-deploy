#!/usr/bin/env bash
# TokenTelemetry Deploy — one-shot setup for a new server
# Clones upstream TT, installs deps, builds frontend with correct env, creates manage.sh
set -euo pipefail

TT_DIR="${TT_DIR:-$HOME/tokentelemetry}"
UPSTREAM="https://github.com/VasiHemanth/tokentelemetry.git"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== TokenTelemetry Deploy ==="
echo "Target: $TT_DIR"

# 1. Clone or pull upstream
if [ -d "$TT_DIR/.git" ]; then
  echo "→ Updating existing clone..."
  git -C "$TT_DIR" pull --ff-only
else
  echo "→ Cloning upstream..."
  git clone "$UPSTREAM" "$TT_DIR"
fi

# 2. Backend deps
echo "→ Installing backend dependencies..."
cd "$TT_DIR/backend"
if [ ! -d venv ]; then
  python3 -m venv venv
fi
./venv/bin/pip install -q -r requirements.txt

# 3. Frontend deps + build
echo "→ Installing frontend dependencies..."
cd "$TT_DIR/frontend"
npm install --silent

echo "→ Building frontend (NEXT_PUBLIC_API_BASE=\"\")..."
# CRITICAL: NEXT_PUBLIC_API_BASE must be set at BUILD time, not runtime.
# Empty string = same-origin relative URLs, so the browser calls /agents etc.
# through whatever reverse proxy is in front. Without this, the browser
# tries :8000 directly which fails behind a reverse proxy.
NEXT_PUBLIC_API_BASE="" npx next build

# 4. Install proxy
echo "→ Installing proxy..."
mkdir -p "$TT_DIR/proxy"
cp "$SCRIPT_DIR/proxy.js" "$TT_DIR/proxy/proxy.js"

# 5. Install manage.sh
echo "→ Installing manage.sh..."
cp "$SCRIPT_DIR/manage.sh" "$TT_DIR/manage.sh"
chmod +x "$TT_DIR/manage.sh"

# 6. Create logs dir
mkdir -p "$TT_DIR/logs"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Start:  $TT_DIR/manage.sh start"
echo "Stop:   $TT_DIR/manage.sh stop"
echo "Status: $TT_DIR/manage.sh status"
echo ""
echo "Proxy listens on port 3011."
echo "Route your reverse proxy to 127.0.0.1:3011."
echo ""
echo "See README.md for reverse proxy configs and gotchas."
