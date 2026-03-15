#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/obs-build-engine-v10.0.2.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/obs-env"
CONFIG_FILE="$CONFIG_DIR/config.sh"
STATUS_FILE="${XDG_RUNTIME_DIR:-/tmp}/obs-env-status.log"
mkdir -p "$CONFIG_DIR"

ACTION="${ACTION:-build}"
PROFILE="${PROFILE:-custom}"
VERBOSE="${VERBOSE:-0}"
QUIET="${QUIET:-0}"

BUILD_OBS="${BUILD_OBS:-1}"
ENABLE_VKCAPTURE="${ENABLE_VKCAPTURE:-0}"
ENABLE_APP_AUDIO="${ENABLE_APP_AUDIO:-0}"
ENABLE_TWITCH_API="${ENABLE_TWITCH_API:-0}"
INSTALL_OSU="${INSTALL_OSU:-0}"
INSTALL_OTD="${INSTALL_OTD:-0}"
INSTALL_FLATPAK_OBS="${INSTALL_FLATPAK_OBS:-0}"

status() { echo "$*" | tee -a "$STATUS_FILE"; }

load_config() { [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || true; }

save_config() {
  cat > "$CONFIG_FILE" <<EOF
PROFILE=$PROFILE
BUILD_OBS=$BUILD_OBS
ENABLE_VKCAPTURE=$ENABLE_VKCAPTURE
ENABLE_APP_AUDIO=$ENABLE_APP_AUDIO
ENABLE_TWITCH_API=$ENABLE_TWITCH_API
INSTALL_OSU=$INSTALL_OSU
INSTALL_OTD=$INSTALL_OTD
INSTALL_FLATPAK_OBS=$INSTALL_FLATPAK_OBS
VERBOSE=$VERBOSE
QUIET=$QUIET
EOF
}

run_profile() {
  case "$PROFILE" in
    minimal) BUILD_OBS=1; ENABLE_VKCAPTURE=0; ENABLE_APP_AUDIO=0; ENABLE_TWITCH_API=0; INSTALL_OSU=0; INSTALL_OTD=0; INSTALL_FLATPAK_OBS=0 ;;
    streamer) BUILD_OBS=1; ENABLE_VKCAPTURE=1; ENABLE_APP_AUDIO=1; ENABLE_TWITCH_API=0; INSTALL_OSU=1; INSTALL_OTD=1; INSTALL_FLATPAK_OBS=0 ;;
    fallback) BUILD_OBS=0; ENABLE_VKCAPTURE=0; ENABLE_APP_AUDIO=0; ENABLE_TWITCH_API=0; INSTALL_OSU=0; INSTALL_OTD=1; INSTALL_FLATPAK_OBS=1 ;;
    custom|"") ;;
    *) echo "Unknown profile: $PROFILE" >&2; exit 1 ;;
  esac
}

run_engine() {
  local args=()
  [[ "$ENABLE_VKCAPTURE" == "1" ]] && args+=(--enable-vkcapture-plugin)
  [[ "$ENABLE_APP_AUDIO" == "1" ]] && args+=(--enable-app-audio-plugin)
  [[ "$ENABLE_TWITCH_API" == "1" ]] && args+=(--enable-twitch-api)
  [[ "$VERBOSE" == "1" ]] && args+=(--verbose)
  [[ "$QUIET" == "1" ]] && args+=(--quiet)
  status "[1/4] Building custom OBS environment..."
  bash "$ENGINE" "${args[@]}"
}

install_osu() {
  status "[2/4] Installing/updating osu-winello..."
  local repo="$HOME/osu-winello"
  if [[ -d "$repo/.git" ]]; then git -C "$repo" pull --ff-only; else git clone https://github.com/NelloKudo/osu-winello "$repo"; fi
  status "osu-winello repository is at: $repo"
}

install_otd() {
  status "[3/4] Installing OpenTabletDriver via ujust..."
  if command -v ujust >/dev/null 2>&1; then ujust install-opentabletdriver; else echo "ujust not found. This option is intended for Bazzite."; return 1; fi
}

install_flatpak_obs() {
  status "[4/4] Installing OBS Flatpak fallback..."
  flatpak install -y flathub com.obsproject.Studio
}

verify_install() {
  echo "Verifying installation..."
  [[ -x "$HOME/.local/bin/obs" ]] && echo "OBS binary: OK" || echo "OBS binary: missing"
  for so in linux-vkcapture.so linux-pipewire-audio.so; do
    if [[ -f "$HOME/.local/lib64/obs-plugins/$so" ]]; then
      echo "Plugin: OK ($so)"
      ldd "$HOME/.local/lib64/obs-plugins/$so" | grep -q 'not found' && echo "  dependency issue detected in $so" || true
    else
      echo "Plugin: missing ($so)"
    fi
  done
  for helper in obs-distrobox-native obs-distrobox-x11 obs-gamecapture obs-vkcapture obs-glcapture; do
    [[ -x "$HOME/.local/bin/$helper" ]] && echo "Helper: OK ($helper)"
  done
}

remove_custom_obs() { status "Removing custom OBS..."; bash "$ENGINE" --uninstall-obs; }
purge_all() { status "Purging everything..."; bash "$ENGINE" --uninstall-all; }

diagnostics() {
  echo "Environment diagnostics"
  command -v distrobox >/dev/null 2>&1 && echo "✔ distrobox installed" || echo "✖ distrobox missing"
  command -v podman >/dev/null 2>&1 && echo "✔ podman installed" || echo "✖ podman missing"
  command -v flatpak >/dev/null 2>&1 && echo "✔ flatpak installed" || echo "✖ flatpak missing"
  command -v ujust >/dev/null 2>&1 && echo "✔ ujust available" || echo "✖ ujust missing"
  command -v whiptail >/dev/null 2>&1 && echo "✔ whiptail available" || echo "✖ whiptail missing (install package: newt)"
  [[ -d /dev/dri ]] && echo "✔ /dev/dri present" || echo "✖ /dev/dri missing"
  pgrep -x pipewire >/dev/null 2>&1 && echo "✔ PipeWire running" || echo "✖ PipeWire not detected"
  [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && echo "✔ Wayland session" || echo "• Session: ${XDG_SESSION_TYPE:-unknown}"
}

explain() {
cat <<'EOF'
Feature explanations

Build custom OBS
  Builds your distrobox-based custom OBS install.

linux-vkcapture
  Low-latency capture for Vulkan/OpenGL apps. Best for Wine/DXVK games.

App audio plugin
  Adds per-application PipeWire audio capture.

Twitch OAuth
  Enables your custom Twitch OAuth build integration if configured.

osu-winello
  Installs or updates the osu!stable Wine wrapper on the host.

OpenTabletDriver
  Runs: ujust install-opentabletdriver

OBS Flatpak fallback
  Installs Flatpak OBS as a fallback option for portal capture and browser docks.
EOF
}

main() {
  : > "$STATUS_FILE"
  load_config
  [[ -n "$PROFILE" ]] && run_profile
  save_config

  case "$ACTION" in
    explain) explain ;;
    diagnostics) diagnostics ;;
    verify) verify_install ;;
    remove) remove_custom_obs ;;
    purge) purge_all ;;
    build)
      [[ "$BUILD_OBS" == "1" ]] && run_engine
      [[ "$INSTALL_OSU" == "1" ]] && install_osu
      [[ "$INSTALL_OTD" == "1" ]] && install_otd
      [[ "$INSTALL_FLATPAK_OBS" == "1" ]] && install_flatpak_obs
      status "Completed."
      ;;
    *) echo "Unknown action: $ACTION" >&2; exit 1 ;;
  esac
}
main
