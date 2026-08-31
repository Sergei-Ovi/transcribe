#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/share/transcribe"
MODEL_QUANT="Q8_0"
MODEL_NAME="gigaam-v3-e2e-rnnt"
MODEL_URL="https://huggingface.co/handy-computer/${MODEL_NAME}-gguf/resolve/main/${MODEL_NAME}-${MODEL_QUANT}.gguf"
REPO="handy-computer/transcribe.cpp"
BINARY_BASE="https://github.com/${REPO}/releases/download"
API_LATEST="https://api.github.com/repos/${REPO}/releases/latest"

latest_release() {
  curl -fsSL "$API_LATEST" |
    grep -m1 '"tag_name"' |
    sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      if command -v nvidia-smi &>/dev/null; then
        echo "linux-x86_64-cuda"
      else
        echo "linux-x86_64-cpu-vulkan"
      fi
      ;;
    aarch64|arm64)
      echo "linux-aarch64-cpu-vulkan"
      ;;
    *)
      echo "Unsupported arch: $arch" >&2; exit 1
      ;;
  esac
}

main() {
  mkdir -p "$INSTALL_DIR/models"

  local arch release tarball url
  arch="$(detect_arch)"
  release="$(latest_release)"
  tarball="transcribe-native-${release#v}-${arch}.tar.gz"
  url="${BINARY_BASE}/${release}/${tarball}"

  if [ ! -f "${INSTALL_DIR}/transcribe-cli" ]; then
    echo "==> Downloading transcribe.cpp ${release} (${arch})..."
    curl -fSL "$url" | tar xz -C "$INSTALL_DIR" --strip-components=2 --wildcards '*/bin/*'
    chmod +x "${INSTALL_DIR}/transcribe-cli"
  fi

  local model_file="${INSTALL_DIR}/models/${MODEL_NAME}-${MODEL_QUANT}.gguf"
  if [ ! -f "$model_file" ]; then
    echo "==> Downloading ${MODEL_NAME} model (${MODEL_QUANT})..."
    curl -fSL -o "$model_file" "$MODEL_URL"
  fi

  cat > "${INSTALL_DIR}/transcribe.sh" << 'SCRIPT'
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
  text="$("$CLI" -m "$MODEL" "$WAVFILE" 2>/dev/null | tail -1)"
  rm -f "$WAVFILE"

  if [ -n "$text" ]; then
    xdotool type --delay 0 "$text"
  fi
}

case "${1:-}" in
  start) start ;;
  stop)  stop ;;
  *)     echo "usage: transcribe.sh {start|stop}" >&2; exit 1 ;;
esac
SCRIPT
  chmod +x "${INSTALL_DIR}/transcribe.sh"

  local hyprconf="${HOME}/.config/hypr/hyprland.conf"
  if [ -f "$hyprconf" ]; then
    if ! grep -q 'transcribe.sh start' "$hyprconf"; then
      echo "" >> "$hyprconf"
      echo "# transcribe.cpp hotkey" >> "$hyprconf"
      echo "bind = , F9, keydown, exec, ${INSTALL_DIR}/transcribe.sh start" >> "$hyprconf"
      echo "bind = , F9, keyup,   exec, ${INSTALL_DIR}/transcribe.sh stop" >> "$hyprconf"
      echo "==> Added F9 hold-to-record binding to Hyprland config"
    fi
  fi

  echo "==> Done!"
  echo "    Binary:  ${INSTALL_DIR}/transcribe-cli"
  echo "    Model:   ${model_file}"
  echo "    Script:  ${INSTALL_DIR}/transcribe.sh"
  echo "    F9: hold to record, release to transcribe & type"
}

main "$@"
