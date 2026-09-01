#!/usr/bin/env bash
set -uo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
CLI="${DIR}/transcribe-cli"
MODEL="${DIR}/models/gigaam-v3-e2e-rnnt-Q8_0.gguf"
PIDFILE="/tmp/transcribe.pid"
WAVFILE="/tmp/transcribe-rec.wav"

start() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
  fi
  rm -f "$WAVFILE"
  arecord -f S16_LE -r 16000 -c 1 -q "$WAVFILE" &
  echo $! > "$PIDFILE"
}

stop() {
  [ -f "$PIDFILE" ] || exit 0
  local pid
  pid="$(cat "$PIDFILE")"
  rm -f "$PIDFILE"

  if kill -0 "$pid" 2>/dev/null; then
    kill -INT "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi

  if [ ! -s "$WAVFILE" ] || [ "$(stat -c%s "$WAVFILE" 2>/dev/null || echo 0)" -lt 32000 ]; then
    rm -f "$WAVFILE"
    exit 0
  fi

  local text
  text="$("$CLI" -m "$MODEL" "$WAVFILE" 2>/dev/null | sed -n 's/^text: //p' | head -1)"
  rm -f "$WAVFILE"

  if [ -n "$text" ] && [ "$text" != "(empty)" ]; then
    if command -v ydotool &>/dev/null; then
      ydotool type --key-delay 0 -- "$text"
    else
      echo "ydotool not found" >&2
      exit 1
    fi
  fi
}

case "${1:-}" in
  start) start ;;
  stop)  stop ;;
  *)     echo "usage: transcribe.sh {start|stop}" >&2; exit 1 ;;
esac
