#!/usr/bin/env bash
# TokenTelemetry service manager
# Usage: manage.sh {start|stop|restart|status}

TT_DIR="${TT_DIR:-$HOME/tokentelemetry}"
LOG="$TT_DIR/logs"

kill_service() {
  local port=$1 name=$2
  # Kill by port (normal processes)
  local pids
  pids=$(lsof -ti :"$port" 2>/dev/null) && kill $pids 2>/dev/null
  # Also kill by process name (setsid-ed processes that lsof misses)
  pkill -f "$name" 2>/dev/null
}

case "${1:-help}" in
  start)
    echo "Starting TokenTelemetry..."

    # Backend (FastAPI + uvicorn)
    (cd "$TT_DIR/backend" && setsid -f "$TT_DIR/backend/venv/bin/uvicorn" \
      main:app --host 127.0.0.1 --port 8010) >> "$LOG/backend.log" 2>&1
    sleep 2

    # Frontend (Next.js production)
    # NOTE: NEXT_PUBLIC_API_BASE must be baked into the build via `next build`.
    # Setting it here at runtime has NO effect on production builds.
    (cd "$TT_DIR/frontend" && setsid -f "$TT_DIR/frontend/node_modules/.bin/next" \
      start --port 3010) >> "$LOG/frontend.log" 2>&1
    sleep 2

    # Proxy (routes API → backend, everything else → frontend)
    if [ -f "$TT_DIR/proxy/proxy.js" ]; then
      setsid -f node "$TT_DIR/proxy/proxy.js" >> "$LOG/proxy.log" 2>&1
    elif [ -f "$HOME/docker/tokentelemetry/proxy.js" ]; then
      # Fallback: legacy path on phillias' server
      setsid -f node "$HOME/docker/tokentelemetry/proxy.js" >> "$LOG/proxy.log" 2>&1
    fi
    sleep 1

    echo "Backend:  $(curl -s -o /dev/null -w OK http://127.0.0.1:8010/agents 2>/dev/null || echo DOWN)"
    echo "Frontend: $(curl -s -o /dev/null -w OK http://127.0.0.1:3010 2>/dev/null || echo DOWN)"
    echo "Proxy:    $(curl -s -o /dev/null -w OK http://127.0.0.1:3011/agents 2>/dev/null || echo DOWN)"
    ;;

  stop)
    echo "Stopping TokenTelemetry..."
    kill_service 8010 "uvicorn main:app"
    kill_service 3010 "next-server"
    kill_service 3011 "proxy.js"
    sleep 1
    echo "Stopped"
    ;;

  restart)
    "$0" stop
    sleep 2
    "$0" start
    ;;

  status)
    echo "Backend:  $(curl -s -o /dev/null -w OK http://127.0.0.1:8010/agents 2>/dev/null || echo DOWN)"
    echo "Frontend: $(curl -s -o /dev/null -w OK http://127.0.0.1:3010 2>/dev/null || echo DOWN)"
    echo "Proxy:    $(curl -s -o /dev/null -w OK http://127.0.0.1:3011/agents 2>/dev/null || echo DOWN)"
    ;;

  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
