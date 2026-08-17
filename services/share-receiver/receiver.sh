#!/bin/sh
# Start/stop the OpenMinis share receiver on the host.
# Lives under /root/services/share-receiver (stable, outside the volatile
# /var/minis sandbox workspace) so the service stays usable across isolation.
# Usage: ./receiver.sh start | stop | status
set -e
# Self-locate: this script's directory regardless of CWD.
DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="$DIR/receiver.pid"
LOGFILE="$DIR/receiver.log"
PORT="${PORT:-8741}"

case "$1" in
  start)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "already running (pid $(cat "$PIDFILE"))"; exit 0
    fi
    mkdir -p "$DIR/data"
    # 'env -u' clears any leaked SHARE_OUTPUT/SHARE_CURSOR override so the
    # receiver always writes to $DIR/data/incoming-share.txt (stable path).
    nohup env -u SHARE_OUTPUT -u SHARE_CURSOR \
      python3 "$DIR/share_receiver.py" "$PORT" \
      >> "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    echo "started pid $(cat "$PIDFILE") on :$PORT"
    sleep 1
    "$0" status
    ;;
  stop)
    if [ -f "$PIDFILE" ]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null && echo "stopped" || echo "not running"
      rm -f "$PIDFILE"
    else
      echo "not running"
    fi
    ;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo "running (pid $(cat "$PIDFILE")): $(curl -s http://127.0.0.1:$PORT/health)"
    else
      echo "not running"
    fi
    ;;
  *)
    echo "usage: $0 start|stop|status"; exit 1;;
esac
