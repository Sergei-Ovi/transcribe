#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/share/transcribe"
MODEL_QUANT="Q8_0"
MODEL_NAME="gigaam-v3-e2e-rnnt"
MODEL_URL="https://huggingface.co/handy-computer/${MODEL_NAME}-gguf/resolve/main/${MODEL_NAME}-${MODEL_QUANT}.gguf"
RELEASE_REPO="${TRANSCRIBE_RELEASE_REPO:-Sergei-Ovi/transcribe}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

latest_release() {
  curl -fsSL "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" |
    grep -m1 '"tag_name"' |
    sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

detect_asset() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "transcribe-cli-linux-x86_64" ;;
    *)
      echo "Unsupported arch: $arch (only x86_64 Linux binaries are published)" >&2
      exit 1
      ;;
  esac
}

check_deps() {
  local missing=()
  for cmd in curl arecord ydotool; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "==> Missing dependencies: ${missing[*]}"
    echo "    Arch / CachyOS:"
    echo "      sudo pacman -S --needed curl alsa-utils ydotool"
    echo "    Debian / Ubuntu:"
    echo "      sudo apt install curl alsa-utils ydotool"
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

download_cli() {
  local asset release url cli_path
  asset="$(detect_asset)"
  cli_path="${INSTALL_DIR}/transcribe-cli"

  if [ -x "$cli_path" ]; then
    echo "==> transcribe-cli already installed, skipping download"
    return
  fi

  release="$(latest_release)"
  url="https://github.com/${RELEASE_REPO}/releases/download/${release}/${asset}"

  echo "==> Downloading transcribe-cli ${release} (${asset})..."
  if ! curl -fSL -o "$cli_path" "$url"; then
    echo "error: failed to download ${url}" >&2
    echo "       publish a release first: git tag v1.0.0 && git push origin v1.0.0" >&2
    rm -f "$cli_path"
    exit 1
  fi
  chmod +x "$cli_path"
}

download_model() {
  local model_file="${INSTALL_DIR}/models/${MODEL_NAME}-${MODEL_QUANT}.gguf"
  if [ ! -f "$model_file" ]; then
    echo "==> Downloading ${MODEL_NAME} model (${MODEL_QUANT})..."
    curl -fSL -o "$model_file" "$MODEL_URL"
  fi
}

install_runtime_scripts() {
  if [ ! -f "${SCRIPT_DIR}/transcribe.sh" ]; then
    echo "error: transcribe.sh not found next to install.sh" >&2
    exit 1
  fi
  install -m 755 "${SCRIPT_DIR}/transcribe.sh" "${INSTALL_DIR}/transcribe.sh"
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
  echo "    Releases:    https://github.com/${RELEASE_REPO}/releases"
  echo ""

  check_deps
  mkdir -p "${INSTALL_DIR}/models"

  download_cli
  download_model
  install_runtime_scripts
  configure_hyprland

  echo ""
  echo "==> Done!"
  echo "    CLI:     ${INSTALL_DIR}/transcribe-cli"
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
