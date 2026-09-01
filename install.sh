#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/share/transcribe"
MODEL_QUANT="Q8_0"
MODEL_NAME="gigaam-v3-e2e-rnnt"
MODEL_URL="https://huggingface.co/handy-computer/${MODEL_NAME}-gguf/resolve/main/${MODEL_NAME}-${MODEL_QUANT}.gguf"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

check_deps() {
  local missing=()
  for cmd in curl python3 arecord ydotool; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done

  if [ "${#missing[@]}" -gt 0 ]; then
  echo "==> Missing dependencies: ${missing[*]}"
  echo "    Arch / CachyOS:"
  echo "      sudo pacman -S --needed curl python python-pip alsa-utils ydotool"
  echo "    Debian / Ubuntu:"
  echo "      sudo apt install curl python3 python3-pip python3-venv alsa-utils ydotool"
  echo ""
  echo "    ydotool also needs the user daemon:"
  echo "      systemctl --user enable --now ydotoold"
  exit 1
  fi

  if ! pgrep -x ydotoold &>/dev/null; then
    echo "==> Warning: ydotoold is not running."
    echo "    Start it with: systemctl --user enable --now ydotoold"
    echo ""
  fi
}

install_python() {
  if [ ! -d "${INSTALL_DIR}/venv" ]; then
    echo "==> Creating Python venv and installing transcribe-cpp..."
    python3 -m venv "${INSTALL_DIR}/venv"
    "${INSTALL_DIR}/venv/bin/pip" install --upgrade pip
    "${INSTALL_DIR}/venv/bin/pip" install transcribe-cpp
  else
    echo "==> Python venv already exists, skipping transcribe-cpp install"
  fi

  if [ -f "${SCRIPT_DIR}/transcribe.py" ]; then
    install -m 644 "${SCRIPT_DIR}/transcribe.py" "${INSTALL_DIR}/transcribe.py"
  else
    echo "error: transcribe.py not found next to install.sh" >&2
    exit 1
  fi
}

download_model() {
  local model_file="${INSTALL_DIR}/models/${MODEL_NAME}-${MODEL_QUANT}.gguf"
  if [ ! -f "$model_file" ]; then
    echo "==> Downloading ${MODEL_NAME} model (${MODEL_QUANT})..."
    curl -fSL -o "$model_file" "$MODEL_URL"
  fi
}

write_transcribe_sh() {
  cat > "${INSTALL_DIR}/transcribe.sh" << 'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
PYTHON="${DIR}/venv/bin/python"
TRANSCRIBE="${DIR}/transcribe.py"
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
  text="$("$PYTHON" "$TRANSCRIBE" "$MODEL" "$WAVFILE" 2>/dev/null || true)"
  rm -f "$WAVFILE"

  if [ -n "$text" ]; then
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
SCRIPT
  chmod +x "${INSTALL_DIR}/transcribe.sh"
}

configure_hyprland() {
  local hyprconf="${HOME}/.config/hypr/hyprland.conf"
  if [ -f "$hyprconf" ] && ! grep -q 'transcribe.sh start' "$hyprconf"; then
    echo "" >> "$hyprconf"
    echo "# transcribe.cpp hotkey" >> "$hyprconf"
    echo "bind = , F9, keydown, exec, ${INSTALL_DIR}/transcribe.sh start" >> "$hyprconf"
    echo "bind = , F9, keyup,   exec, ${INSTALL_DIR}/transcribe.sh stop" >> "$hyprconf"
    echo "==> Added F9 hold-to-record binding to Hyprland config"
  fi
}

main() {
  echo "==> transcribe installer (Linux)"
  echo "    Install dir: ${INSTALL_DIR}"
  echo ""

  check_deps
  mkdir -p "${INSTALL_DIR}/models"

  install_python
  download_model
  write_transcribe_sh
  configure_hyprland

  echo ""
  echo "==> Done!"
  echo "    Python:  ${INSTALL_DIR}/venv/bin/python"
  echo "    Model:   ${INSTALL_DIR}/models/${MODEL_NAME}-${MODEL_QUANT}.gguf"
  echo "    Script:  ${INSTALL_DIR}/transcribe.sh"
  echo "    F9: hold to record, release to transcribe and type"
  echo ""
  if [ ! -f "${HOME}/.config/hypr/hyprland.conf" ]; then
    echo "    KDE Plasma: bind F9 in System Settings -> Custom Shortcuts:"
    echo "      ${INSTALL_DIR}/transcribe.sh start   (trigger: on press)"
    echo "      ${INSTALL_DIR}/transcribe.sh stop    (trigger: on release)"
  fi
}

main "$@"
