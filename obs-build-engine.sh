#!/usr/bin/env bash
# ==============================================================
# OBS build script (distrobox + user-local OBS install)
# v9.4.0 – user-local dependency prefix for x264/x265/FFmpeg, no sudo installs,
#          distrobox host-managed deps, GPU handoff, HTML reporting,
#          dual launchers and dual desktop entries for Wayland-native and X11 compatibility
#          optional plugin auto-install support for linux-vkcapture and PipeWire application audio
# ==============================================================

set -u
set -o pipefail

############################
# Step 0: Argument parsing #
############################
VERBOSE=0
FORCE=0
PROGRESS=1
REBUILD=0
UNINSTALL_MODE=""
INTERACTIVE=0

# Feature defaults: auto means detect/sane default
ENABLE_BROWSER="auto"
ENABLE_PIPEWIRE="auto"
ENABLE_WEBSOCKET="auto"
ENABLE_V4L2="auto"
ENABLE_NVENC="auto"
ENABLE_QSV11="auto"
ENABLE_WEBRTC="off"
ENABLE_VLC="off"
ENABLE_AJA="off"
ENABLE_NEW_MPEGTS_OUTPUT="off"
ENABLE_SCRIPTING="auto"
ENABLE_TWITCH_API="off"
ENABLE_VKCAPTURE_PLUGIN="off"
ENABLE_APP_AUDIO_PLUGIN="off"

ORIGINAL_ARGS=("$@")

parse_args() {
  local argv=("$@")
  local i arg
  for ((i=0; i<${#argv[@]}; i++)); do
    arg="${argv[$i]}"
    case "$arg" in
      --verbose|-v) VERBOSE=1; PROGRESS=0 ;;&
      --progress) VERBOSE=0; PROGRESS=1 ;;&
      --force|-f) FORCE=1 ;;&
      --rebuild) REBUILD=1; FORCE=1 ;;&
      --interactive) INTERACTIVE=1 ;;&
      --uninstall-obs|--uninstall-libs|--uninstall-build-dirs|--uninstall-container|--uninstall-all)
        UNINSTALL_MODE="$arg"
        ;;&
      --enable-browser) ENABLE_BROWSER="on" ;;&
      --disable-browser) ENABLE_BROWSER="off" ;;&
      --enable-pipewire) ENABLE_PIPEWIRE="on" ;;&
      --disable-pipewire) ENABLE_PIPEWIRE="off" ;;&
      --enable-websocket) ENABLE_WEBSOCKET="on" ;;&
      --disable-websocket) ENABLE_WEBSOCKET="off" ;;&
      --enable-v4l2) ENABLE_V4L2="on" ;;&
      --disable-v4l2) ENABLE_V4L2="off" ;;&
      --enable-nvenc) ENABLE_NVENC="on" ;;&
      --disable-nvenc) ENABLE_NVENC="off" ;;&
      --enable-qsv11) ENABLE_QSV11="on" ;;&
      --disable-qsv11) ENABLE_QSV11="off" ;;&
      --enable-webrtc) ENABLE_WEBRTC="on" ;;&
      --disable-webrtc) ENABLE_WEBRTC="off" ;;&
      --enable-vlc) ENABLE_VLC="on" ;;&
      --disable-vlc) ENABLE_VLC="off" ;;&
      --enable-aja) ENABLE_AJA="on" ;;&
      --disable-aja) ENABLE_AJA="off" ;;&
      --enable-new-mpegts) ENABLE_NEW_MPEGTS_OUTPUT="on" ;;&
      --disable-new-mpegts) ENABLE_NEW_MPEGTS_OUTPUT="off" ;;&
      --enable-scripting) ENABLE_SCRIPTING="on" ;;&
      --disable-scripting) ENABLE_SCRIPTING="off" ;;&
      --enable-twitch-api) ENABLE_TWITCH_API="on" ;;&
      --disable-twitch-api) ENABLE_TWITCH_API="off" ;;&
      --enable-vkcapture-plugin) ENABLE_VKCAPTURE_PLUGIN="on" ;;&
      --disable-vkcapture-plugin) ENABLE_VKCAPTURE_PLUGIN="off" ;;&
      --enable-app-audio-plugin) ENABLE_APP_AUDIO_PLUGIN="on" ;;&
      --disable-app-audio-plugin) ENABLE_APP_AUDIO_PLUGIN="off" ;;&
    esac
  done
}

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build options:
  --verbose, -v                 Show full command output
  --progress                    Spinner/progress output (default)
  --force, -f                   Rebuild even if components are already installed
  --rebuild                     Clean previous outputs/container and rebuild from scratch
  --interactive                 Prompt for feature toggles

Uninstall options:
  --uninstall-obs               Remove OBS user-local install, wrapper, desktop file, icons
  --uninstall-libs              Remove custom x264/x265/FFmpeg libs from inside distrobox container
  --uninstall-build-dirs        Remove ~/OBSBuild
  --uninstall-container         Remove distrobox container
  --uninstall-all               Remove all of the above

Plugin/feature toggles:
  --enable-browser | --disable-browser
  --enable-pipewire | --disable-pipewire
  --enable-websocket | --disable-websocket
  --enable-v4l2 | --disable-v4l2
  --enable-nvenc | --disable-nvenc
  --enable-qsv11 | --disable-qsv11
  --enable-webrtc | --disable-webrtc
  --enable-vlc | --disable-vlc
  --enable-aja | --disable-aja
  --enable-new-mpegts | --disable-new-mpegts
  --enable-scripting | --disable-scripting
  --enable-twitch-api | --disable-twitch-api
  --enable-vkcapture-plugin | --disable-vkcapture-plugin
  --enable-app-audio-plugin | --disable-app-audio-plugin
  --help, -h                    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose|-v) VERBOSE=1; PROGRESS=0 ;;
    --progress) VERBOSE=0; PROGRESS=1 ;;
    --force|-f) FORCE=1 ;;
    --rebuild) REBUILD=1; FORCE=1 ;;
    --interactive) INTERACTIVE=1 ;;
    --uninstall-obs|--uninstall-libs|--uninstall-build-dirs|--uninstall-container|--uninstall-all)
      UNINSTALL_MODE="$1"
      ;;
    --enable-browser) ENABLE_BROWSER="on" ;;
    --disable-browser) ENABLE_BROWSER="off" ;;
    --enable-pipewire) ENABLE_PIPEWIRE="on" ;;
    --disable-pipewire) ENABLE_PIPEWIRE="off" ;;
    --enable-websocket) ENABLE_WEBSOCKET="on" ;;
    --disable-websocket) ENABLE_WEBSOCKET="off" ;;
    --enable-v4l2) ENABLE_V4L2="on" ;;
    --disable-v4l2) ENABLE_V4L2="off" ;;
    --enable-nvenc) ENABLE_NVENC="on" ;;
    --disable-nvenc) ENABLE_NVENC="off" ;;
    --enable-qsv11) ENABLE_QSV11="on" ;;
    --disable-qsv11) ENABLE_QSV11="off" ;;
    --enable-webrtc) ENABLE_WEBRTC="on" ;;
    --disable-webrtc) ENABLE_WEBRTC="off" ;;
    --enable-vlc) ENABLE_VLC="on" ;;
    --disable-vlc) ENABLE_VLC="off" ;;
    --enable-aja) ENABLE_AJA="on" ;;
    --disable-aja) ENABLE_AJA="off" ;;
    --enable-new-mpegts) ENABLE_NEW_MPEGTS_OUTPUT="on" ;;
    --disable-new-mpegts) ENABLE_NEW_MPEGTS_OUTPUT="off" ;;
    --enable-scripting) ENABLE_SCRIPTING="on" ;;
    --disable-scripting) ENABLE_SCRIPTING="off" ;;
    --enable-twitch-api) ENABLE_TWITCH_API="on" ;;
    --disable-twitch-api) ENABLE_TWITCH_API="off" ;;
    --enable-vkcapture-plugin) ENABLE_VKCAPTURE_PLUGIN="on" ;;
    --disable-vkcapture-plugin) ENABLE_VKCAPTURE_PLUGIN="off" ;;
    --enable-app-audio-plugin) ENABLE_APP_AUDIO_PLUGIN="on" ;;
    --disable-app-audio-plugin) ENABLE_APP_AUDIO_PLUGIN="off" ;;
    --help|-h) print_usage; exit 0 ;;
    *) echo "Unknown argument: $1"; print_usage; exit 1 ;;
  esac
  shift
done

#######################
# Step 0.5: Variables #
#######################
BUILD_STAMP="${BUILD_STAMP:-$(date +%Y%m%d-%H%M)}"
HANDED_OFF=0
ROOT_DIR="$HOME/OBSBuild"
BUILD_DIR="$ROOT_DIR/Builds/obs-build-$BUILD_STAMP"
REPO_DIR="$ROOT_DIR/Repos"
LOG_DIR="$ROOT_DIR/Logs"
FAILED_DIR="$LOG_DIR/Failed"

MASTER_LOG="$LOG_DIR/obs-master-build-$BUILD_STAMP.log"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/obs-build}"
GENERAL_CONFIG_FILE="${GENERAL_CONFIG_FILE:-$CONFIG_DIR/config.sh}"
OAUTH_CONFIG_FILE="${OAUTH_CONFIG_FILE:-$CONFIG_DIR/oauth.conf}"
if [[ -f "$GENERAL_CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$GENERAL_CONFIG_FILE"
fi

if [[ -f "$OAUTH_CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$OAUTH_CONFIG_FILE"
fi

# Re-apply CLI arguments after loading config so command-line flags take precedence
parse_args "$@"

OAUTH_BASE_URL="${OAUTH_BASE_URL:-https://obs-oauth-cf.obs-oauth-cf.workers.dev/}"
TWITCH_CLIENTID="${TWITCH_CLIENTID:-}"
TWITCH_HASH="${TWITCH_HASH:-0}"
HTML_REPORT="$LOG_DIR/obs-build-report-$BUILD_STAMP.html"
FAIL_HTML="$LOG_DIR/obs-build-fail-$BUILD_STAMP.html"
VERIFY_LOG="$LOG_DIR/obs-verify-$BUILD_STAMP.log"

X264_LOG="$LOG_DIR/x264-build-$BUILD_STAMP.log"
X265_LOG="$LOG_DIR/x265-build-$BUILD_STAMP.log"
FFMPEG_LOG="$LOG_DIR/ffmpeg-build-$BUILD_STAMP.log"
OBS_LOG="$LOG_DIR/obs-build-$BUILD_STAMP.log"
VKCAPTURE_LOG="$LOG_DIR/obs-vkcapture-$BUILD_STAMP.log"
VKCAPTURE_BUILD_LOG="$LOG_DIR/obs-vkcapture-build-$BUILD_STAMP.log"
APP_AUDIO_LOG="$LOG_DIR/obs-pipewire-audio-capture-$BUILD_STAMP.log"
APP_AUDIO_BUILD_LOG="$LOG_DIR/obs-pipewire-audio-capture-build-$BUILD_STAMP.log"

mkdir -p "$ROOT_DIR" "$ROOT_DIR/Builds" "$REPO_DIR" "$LOG_DIR" "$FAILED_DIR"

if [[ "$FORCE" -eq 1 && -d "$BUILD_DIR" ]]; then
  rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"

DEPS_PREFIX="$HOME/.local/obs-deps"
OBS_PREFIX="$HOME/.local"

X264_SRC="$REPO_DIR/x264"
X265_SRC="$REPO_DIR/x265"
FFMPEG_SRC="$REPO_DIR/ffmpeg"
OBS_SRC="$REPO_DIR/obs-studio"

X264_BUILD="$BUILD_DIR/x264-build"
X265_BUILD="$BUILD_DIR/x265-build"
FFMPEG_BUILD="$BUILD_DIR/ffmpeg-build"
OBS_BUILD="$BUILD_DIR/obs-studio-build"

mkdir -p "$X264_BUILD" "$X265_BUILD" "$FFMPEG_BUILD" "$OBS_BUILD"

FFMPEG_REF="n7.1.1"

DISTROBOX_NAME="${DISTROBOX_NAME:-obs-build-fedora}"
ENABLE_BROWSER_BUILD="${ENABLE_BROWSER_BUILD:-1}"
CEF_URL="${CEF_URL:-https://cdn-fastly.obsproject.com/downloads/cef_binary_6533_linux_x86_64_v6.tar.xz}"
CEF_ARCHIVE_NAME="$(basename "$CEF_URL")"
CEF_ARCHIVE_PATH="$REPO_DIR/$CEF_ARCHIVE_NAME"
CEF_ROOT_DIR_DEFAULT="${CEF_ARCHIVE_NAME%.tar.xz}"
CEF_ROOT_DIR="${CEF_ROOT_DIR:-$REPO_DIR/$CEF_ROOT_DIR_DEFAULT}"
DESKTOP_FILE="$HOME/.local/share/applications/obs-distrobox-native.desktop"
DESKTOP_FILE_X11="$HOME/.local/share/applications/obs-distrobox-x11.desktop"
DESKTOP_ICON_FILE=""
DESKTOP_ICON_FILE_X11=""
VKCAPTURE_SRC="$REPO_DIR/obs-vkcapture"
VKCAPTURE_BUILD="$BUILD_DIR/obs-vkcapture-build"
VKCAPTURE_BUILD32="$BUILD_DIR/obs-vkcapture-build32"
APP_AUDIO_SRC="$REPO_DIR/obs-pipewire-audio-capture"
APP_AUDIO_BUILD="$BUILD_DIR/obs-pipewire-audio-capture-build"

#######################
# Step 0.6: Colors    #
#######################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_line() {
  local level="$1"
  local color="$2"
  local message="$3"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local plain="$ts | $level: $message"
  mkdir -p "$(dirname "$MASTER_LOG")"
  printf '%s\n' "$plain" >> "$MASTER_LOG"
  printf "%b%s%b\n" "$color" "$plain" "$NC"
}

info()  { log_line "INFO" "$BLUE" "$1"; }
warn()  { log_line "WARNING" "$YELLOW" "$1"; }
error() { log_line "ERROR" "$RED" "$1"; }
ok()    { log_line "SUCCESS" "$GREEN" "$1"; }

################################
# Step 0.7: Status tracking    #
################################
declare -A STATUS
declare -A SUMMARY
declare -A LOGFILE

for comp in x264 x265 ffmpeg obs-studio; do
  STATUS[$comp]="PENDING"
  SUMMARY[$comp]="Not run yet"
done

LOGFILE[x264]="$X264_LOG"
LOGFILE[x265]="$X265_LOG"
LOGFILE[ffmpeg]="$FFMPEG_LOG"
LOGFILE[obs-studio]="$OBS_LOG"
LOGFILE[obs-vkcapture]="$VKCAPTURE_LOG"
LOGFILE[obs-pipewire-audio-capture]="$APP_AUDIO_LOG"

BUILD_FAILED=0

################################
# Step 0.8: Utility functions  #
################################
spinner_wait() {
  local pid="$1"
  local label="$2"
  local marks='|/-\'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r%b%s [%c]%b" "$BLUE" "$label" "${marks:$i:1}" "$NC"
    i=$(( (i + 1) % 4 ))
    sleep 0.15
  done
  printf "\r%-90s\r" ""
}

run_cmd() {
  local label="$1"
  local logfile="$2"
  shift 2

  {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$label"
    printf 'Command: '
    printf '%q ' "$@"
    printf '\n\n'
  } >> "$logfile"

  if [[ "$VERBOSE" -eq 1 ]]; then
    "$@" 2>&1 | tee -a "$logfile"
    return "${PIPESTATUS[0]}"
  fi

  "$@" >> "$logfile" 2>&1 &
  local pid=$!
  spinner_wait "$pid" "$label"
  wait "$pid"
}

run_in_dir() {
  local dir="$1"
  shift
  ( cd "$dir" && "$@" )
}

escape_html_file() {
  local file="$1"
  python3 - "$file" <<'PY'
import html, pathlib, sys
p = pathlib.Path(sys.argv[1])
if p.exists():
    print(html.escape(p.read_text(errors="replace")))
PY
}

write_fail_stub() {
  local comp="$1"
  local fail_log="$FAILED_DIR/${comp}-build-fail-$BUILD_STAMP.log"
  cp -f "${LOGFILE[$comp]}" "$fail_log" 2>/dev/null || true
}

mark_failed() {
  local comp="$1"
  local summary="$2"
  STATUS[$comp]="FAILED"
  SUMMARY[$comp]="$summary"
  BUILD_FAILED=1
  write_fail_stub "$comp"
  warn "$comp failed: $summary"
}

mark_success() {
  local comp="$1"
  local summary="$2"
  STATUS[$comp]="SUCCESS"
  SUMMARY[$comp]="$summary"
  ok "$comp succeeded: $summary"
}

mark_skipped() {
  local comp="$1"
  local summary="$2"
  STATUS[$comp]="SKIPPED"
  SUMMARY[$comp]="$summary"
  info "$comp skipped: $summary"
}

generate_html_report() {
  local target="$1"

  {
    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>OBS Build Report</title>
<style>
body{font-family:Arial,sans-serif;background:#1e1e1e;color:#eee;padding:24px;}
h1,h2{color:#7cc7ff;}
table{width:100%;border-collapse:collapse;margin-bottom:24px;}
th,td{border:1px solid #444;padding:10px;text-align:left;vertical-align:top;}
th{background:#2a2a2a;}
.success{color:#6ee07a;font-weight:bold;}
.failed{color:#ff6b6b;font-weight:bold;}
.pending{color:#ffd166;font-weight:bold;}
.skipped{color:#9ecbff;font-weight:bold;}
details{margin-top:6px;}
summary{cursor:pointer;color:#9ad1ff;}
pre{background:#111;padding:12px;border:1px solid #333;overflow:auto;white-space:pre-wrap;}
.muted{color:#aaa;}
</style>
</head>
<body>
<h1>OBS Build Report (distrobox + user-local install)</h1>
<p class="muted">Build stamp: $BUILD_STAMP</p>
<p class="muted">Build dir: $BUILD_DIR</p>
<p class="muted">Repo dir: $REPO_DIR</p>
<p class="muted">Config dir: $CONFIG_DIR</p>
<p class="muted">Master log: $MASTER_LOG</p>
<p class="muted">Verification log: $VERIFY_LOG</p>
<table>
<tr><th>Component</th><th>Status</th><th>Summary</th><th>Log</th></tr>
EOF
    local comp cls
    for comp in x264 x265 ffmpeg obs-studio; do
      case "${STATUS[$comp]}" in
        SUCCESS) cls="success" ;;
        FAILED) cls="failed" ;;
        SKIPPED) cls="skipped" ;;
        *) cls="pending" ;;
      esac
      printf '<tr><td>%s</td><td class="%s">%s</td><td>%s</td><td><details><summary>%s</summary><pre>
'         "$comp" "$cls" "${STATUS[$comp]}" "${SUMMARY[$comp]}" "${LOGFILE[$comp]}"
      escape_html_file "${LOGFILE[$comp]}"
      printf '</pre></details></td></tr>
'
    done
    cat <<EOF
</table>
<h2>Plugin Build Logs</h2>
<details><summary>View linux-vkcapture build log</summary><pre>
EOF
    escape_html_file "$VKCAPTURE_BUILD_LOG"
    cat <<EOF
</pre></details>
<details><summary>View PipeWire application audio build log</summary><pre>
EOF
    escape_html_file "$APP_AUDIO_BUILD_LOG"
    cat <<EOF
</pre></details>
<h2>Verification Log</h2>
<details><summary>View verification</summary><pre>
EOF
    escape_html_file "$VERIFY_LOG"
    cat <<EOF
</pre></details>
<h2>Master Log</h2>
<details><summary>View master log</summary><pre>
EOF
    escape_html_file "$MASTER_LOG"
    cat <<EOF
</pre></details>
</body>
</html>
EOF
  } > "$target"
}

cleanup_on_exit() {
  local exit_code=$?

  # When the host script hands off execution into distrobox, the container run
  # should own report generation. Skipping host-side report generation avoids
  # duplicate reports with mismatched timestamps/status.
  if [[ "$HANDED_OFF" -eq 1 && ! inside_container ]]; then
    return
  fi

  if [[ "$BUILD_FAILED" -eq 1 ]]; then
    generate_html_report "$FAIL_HTML"
    warn "Failure report generated: $FAIL_HTML"
    if [[ -d "$BUILD_DIR" ]]; then
      warn "Keeping failed build directory for debugging: $BUILD_DIR"
    fi
  else
    generate_html_report "$HTML_REPORT"
    info "HTML report generated: $HTML_REPORT"
  fi

  if [[ $exit_code -ne 0 && "$BUILD_FAILED" -eq 0 ]]; then
    generate_html_report "$FAIL_HTML"
    warn "Unexpected error report generated: $FAIL_HTML"
  fi
}
trap cleanup_on_exit EXIT

################################
# Step 1: Distro detection     #
################################
DISTRO="unknown"
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO="$ID"
fi
info "Detected distro: $DISTRO"

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"


feature_to_bool() {
  case "$1" in
    1|on|ON|true|TRUE|yes|YES|auto) return 0 ;;
    *) return 1 ;;
  esac
}

detect_gpu_vendor() {
  if [[ -n "${OBS_GPU_VENDOR:-}" ]]; then
    GPU_VENDOR="$OBS_GPU_VENDOR"
    return 0
  fi

  local info_blob=""
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    GPU_VENDOR="nvidia"
    return 0
  fi
  if [[ -e /usr/lib64/libnvidia-encode.so.1 || -e /usr/lib/libnvidia-encode.so.1 ]]; then
    GPU_VENDOR="nvidia"
    return 0
  fi
  if command -v lspci >/dev/null 2>&1; then
    info_blob="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
  fi
  if echo "$info_blob" | grep -qi 'nvidia'; then
    GPU_VENDOR="nvidia"
  elif echo "$info_blob" | grep -qiE 'amd|advanced micro devices|ati'; then
    GPU_VENDOR="amd"
  elif echo "$info_blob" | grep -qi 'intel'; then
    GPU_VENDOR="intel"
  else
    GPU_VENDOR="unknown"
  fi
}

prompt_toggle() {
  local var_name="$1"
  local prompt="$2"
  local default="$3"
  local answer
  read -r -p "$prompt [$default]: " answer
  answer="${answer:-$default}"
  case "$answer" in
    y|Y|yes|YES) printf -v "$var_name" '%s' 'on' ;;
    n|N|no|NO) printf -v "$var_name" '%s' 'off' ;;
  esac
}

resolve_feature_defaults() {
  detect_gpu_vendor

  [[ "$ENABLE_BROWSER" == "auto" ]] && ENABLE_BROWSER="on"
  [[ "$ENABLE_PIPEWIRE" == "auto" ]] && ENABLE_PIPEWIRE="on"
  [[ "$ENABLE_WEBSOCKET" == "auto" ]] && ENABLE_WEBSOCKET="on"
  [[ "$ENABLE_V4L2" == "auto" ]] && ENABLE_V4L2="on"
  [[ "$ENABLE_SCRIPTING" == "auto" ]] && ENABLE_SCRIPTING="on"

  if [[ "$ENABLE_NVENC" == "auto" ]]; then
    [[ "$GPU_VENDOR" == "nvidia" ]] && ENABLE_NVENC="on" || ENABLE_NVENC="off"
  fi
  if [[ "$ENABLE_QSV11" == "auto" ]]; then
    [[ "$GPU_VENDOR" == "intel" ]] && ENABLE_QSV11="on" || ENABLE_QSV11="off"
  fi

  if [[ "$INTERACTIVE" -eq 1 ]]; then
    prompt_toggle ENABLE_BROWSER "Enable browser source/docks" Y
    prompt_toggle ENABLE_WEBSOCKET "Enable obs-websocket" Y
    prompt_toggle ENABLE_V4L2 "Enable V4L2 webcam support" Y
    prompt_toggle ENABLE_SCRIPTING "Enable OBS scripting (LuaJIT)" Y
    [[ "$GPU_VENDOR" == "nvidia" ]] && prompt_toggle ENABLE_NVENC "Enable NVENC" Y
    [[ "$GPU_VENDOR" == "intel" ]] && prompt_toggle ENABLE_QSV11 "Enable Intel QSV" N
    prompt_toggle ENABLE_WEBRTC "Enable WebRTC output" N
    prompt_toggle ENABLE_VLC "Enable VLC source" N
    prompt_toggle ENABLE_NEW_MPEGTS_OUTPUT "Enable new MPEGTS output (RIST/SRT)" N
    prompt_toggle ENABLE_AJA "Enable AJA plugin" N
  fi

  info "GPU vendor detected: $GPU_VENDOR"
  info "Feature selection: browser=$ENABLE_BROWSER websocket=$ENABLE_WEBSOCKET v4l2=$ENABLE_V4L2 nvenc=$ENABLE_NVENC qsv11=$ENABLE_QSV11 webrtc=$ENABLE_WEBRTC vlc=$ENABLE_VLC aja=$ENABLE_AJA new_mpegts=$ENABLE_NEW_MPEGTS_OUTPUT scripting=$ENABLE_SCRIPTING pipewire=$ENABLE_PIPEWIRE twitch_api=$ENABLE_TWITCH_API vkcapture_plugin=$ENABLE_VKCAPTURE_PLUGIN app_audio_plugin=$ENABLE_APP_AUDIO_PLUGIN"
}


get_desktop_dir() {
  local desktop_dir=""
  if command -v xdg-user-dir >/dev/null 2>&1; then
    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
  fi
  if [[ -z "$desktop_dir" || "$desktop_dir" == "$HOME" ]]; then
    desktop_dir="$HOME/Desktop"
  fi
  printf '%s' "$desktop_dir"
}

install_desktop_icons() {
  local desktop_dir
  desktop_dir="$(get_desktop_dir)"
  [[ -z "$desktop_dir" ]] && return 0

  mkdir -p "$desktop_dir"
  DESKTOP_ICON_FILE="$desktop_dir/OBS Studio (Wayland-NVIDIA).desktop"
  DESKTOP_ICON_FILE_X11="$desktop_dir/OBS Studio (X11-Twitch Docks).desktop"

  cp -f "$DESKTOP_FILE" "$DESKTOP_ICON_FILE"
  cp -f "$DESKTOP_FILE_X11" "$DESKTOP_ICON_FILE_X11"
  chmod +x "$DESKTOP_ICON_FILE" "$DESKTOP_ICON_FILE_X11"
}

create_desktop_entry() {
  mkdir -p "$(dirname "$DESKTOP_FILE")"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=OBS Studio (Wayland/NVIDIA)
Comment=Launch OBS Studio from distrobox using the Wayland-native NVIDIA path
Exec=$HOME/.local/bin/obs-distrobox-native
Icon=com.obsproject.Studio
Terminal=false
Type=Application
Categories=AudioVideo;Recorder;Video;
StartupNotify=true
EOF

  cat > "$DESKTOP_FILE_X11" <<EOF
[Desktop Entry]
Name=OBS Studio (X11/Twitch Docks)
Comment=Launch OBS Studio from distrobox using the X11 compatibility path for Twitch and browser docks
Exec=$HOME/.local/bin/obs-distrobox-x11
Icon=com.obsproject.Studio
Terminal=false
Type=Application
Categories=AudioVideo;Recorder;Video;
StartupNotify=true
EOF

  install_desktop_icons
}

uninstall_obs_files() {
  info "Removing OBS user-local install and launchers..."

  rm -f \
    "$HOME/.local/bin/obs" \
    "$HOME/.local/bin/obs-distrobox-native" \
    "$HOME/.local/bin/obs-distrobox-x11" \
    "$HOME/.local/bin/obs-gamecapture" \
    "$HOME/.local/bin/obs-gamecapture-run" \
    "$HOME/.local/bin/obs-gamecapture.old" \
    "$HOME/.local/bin/obs-vkcapture" \
    "$HOME/.local/bin/obs-vkcapture.old" \
    "$HOME/.local/bin/obs-glcapture" \
    "$HOME/.local/bin/osu-wine-capture"

  rm -f \
    "$HOME/.local/share/vulkan/implicit_layer.d/obs_vkcapture_32.json" \
    "$HOME/.local/share/vulkan/implicit_layer.d/obs_vkcapture_64.json"

  rm -f \
    "$DESKTOP_FILE" \
    "$DESKTOP_FILE_X11" \
    "$(get_desktop_dir)/OBS Studio (Wayland-NVIDIA).desktop" \
    "$(get_desktop_dir)/OBS Studio (X11-Twitch Docks).desktop"

  rm -rf \
    "$HOME/.local/share/obs/obs-plugins/linux-vkcapture" \
    "$HOME/.local/share/obs/obs-plugins/linux-pipewire-audio" \
    "$HOME/.local/lib64/obs-plugins/linux-vkcapture.so" \
    "$HOME/.local/lib64/obs-plugins/linux-pipewire-audio.so" \
    "$HOME/.local/lib/obs_glcapture" \
    "$HOME/.local/lib64/obs_glcapture"
}

uninstall_build_dirs() {
  info "Removing build directories under $ROOT_DIR..."
  rm -rf "$ROOT_DIR"
}

uninstall_container() {
  if command -v distrobox >/dev/null 2>&1; then
    info "Removing distrobox container $DISTROBOX_NAME..."
    distrobox rm "$DISTROBOX_NAME" -f || true
  fi
}

uninstall_custom_libs() {
  if ! command -v distrobox >/dev/null 2>&1; then
    warn "distrobox not available; skipping library uninstall."
    return 0
  fi

  if [[ "$REBUILD" -eq 1 ]]; then
    info "Rebuild requested; removing existing container if present..."
    distrobox rm "$DISTROBOX_NAME" -f >/dev/null 2>&1 || true
  fi

  if ! distrobox list --no-color 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$DISTROBOX_NAME"; then
    warn "Container $DISTROBOX_NAME not found; skipping library uninstall."
  else
    info "Removing custom multimedia libs from $DEPS_PREFIX in $DISTROBOX_NAME..."
    distrobox enter "$DISTROBOX_NAME" -- bash -lc '
      DEPS_PREFIX="$HOME/.local/obs-deps"

      rm -f "$DEPS_PREFIX/bin/ffmpeg" "$DEPS_PREFIX/bin/ffprobe" "$DEPS_PREFIX/bin/ffplay"

      rm -f \
        "$DEPS_PREFIX/lib"/libx264* \
        "$DEPS_PREFIX/lib"/libx265* \
        "$DEPS_PREFIX/lib"/libavcodec* \
        "$DEPS_PREFIX/lib"/libavdevice* \
        "$DEPS_PREFIX/lib"/libavfilter* \
        "$DEPS_PREFIX/lib"/libavformat* \
        "$DEPS_PREFIX/lib"/libavutil* \
        "$DEPS_PREFIX/lib"/libpostproc* \
        "$DEPS_PREFIX/lib"/libswresample* \
        "$DEPS_PREFIX/lib"/libswscale*

      rm -f \
        "$DEPS_PREFIX/lib/pkgconfig"/x264.pc \
        "$DEPS_PREFIX/lib/pkgconfig"/libavcodec.pc \
        "$DEPS_PREFIX/lib/pkgconfig"/libavdevice.pc \
        "$DEPS_PREFIX/lib/pkgconfig"/libavfilter.pc \
        "$DEPS_PREFIX/lib/pkgconfig"/libavformat.pc \
        "$DEPS_PREFIX/lib/pkgconfig"/libavutil.pc \
        "$DEPS_PREFIX/lib/pkgconfig"/libswresample.pc \
        "$DEPS_PREFIX/lib/pkgconfig"/libswscale.pc

      rm -rf \
        "$DEPS_PREFIX/include/libavcodec" \
        "$DEPS_PREFIX/include/libavdevice" \
        "$DEPS_PREFIX/include/libavfilter" \
        "$DEPS_PREFIX/include/libavformat" \
        "$DEPS_PREFIX/include/libavutil" \
        "$DEPS_PREFIX/include/libpostproc" \
        "$DEPS_PREFIX/include/libswresample" \
        "$DEPS_PREFIX/include/libswscale"

      rm -f "$DEPS_PREFIX/include/x264.h" "$DEPS_PREFIX/include/x265.h"

      rmdir \
        "$DEPS_PREFIX/bin" \
        "$DEPS_PREFIX/lib/pkgconfig" \
        "$DEPS_PREFIX/lib64" \
        "$DEPS_PREFIX/lib" \
        "$DEPS_PREFIX/include" \
        "$DEPS_PREFIX" \
        2>/dev/null || true
    ' || true
  fi

  info "Removing host-side custom library payloads..."
  rm -f \
    "$HOME/.local/lib/libVkLayer_obs_vkcapture.so" \
    "$HOME/.local/lib64/libVkLayer_obs_vkcapture.so" \
    "$HOME/.local/lib64/obs-plugins/linux-vkcapture.so" \
    "$HOME/.local/lib64/obs-plugins/linux-pipewire-audio.so"

  rm -rf \
    "$HOME/.local/lib/obs_glcapture" \
    "$HOME/.local/lib64/obs_glcapture"
}

handle_uninstall_mode() {
  case "$UNINSTALL_MODE" in
    --uninstall-obs) uninstall_obs_files; exit 0 ;;
    --uninstall-libs) uninstall_custom_libs; exit 0 ;;
    --uninstall-build-dirs) uninstall_build_dirs; exit 0 ;;
    --uninstall-container) uninstall_container; exit 0 ;;
    --uninstall-all) uninstall_obs_files; uninstall_custom_libs; uninstall_build_dirs; uninstall_container; exit 0 ;;
    "") return 0 ;;
  esac
}

inside_container() {
  [[ -n "${DISTROBOX_ENTER_PATH:-}" || -n "${CONTAINER_ID:-}" || -f /run/.containerenv ]]
}

make_shell_quoted_args() {
  local out=""
  local arg
  for arg in "${ORIGINAL_ARGS[@]}"; do
    out+=" $(printf '%q' "$arg")"
  done
  printf '%s' "$out"
}

create_host_obs_launcher() {
  mkdir -p "$HOME/.local/bin"

  cat > "$HOME/.local/bin/obs-distrobox-native" <<EOF
#!/usr/bin/env bash
mkdir -p "$HOME/.config/obs-studio/basic/scenes" "$HOME/.config/obs-studio/plugin_config"
exec distrobox enter $(printf '%q' "$DISTROBOX_NAME") -- env \
LD_LIBRARY_PATH="\$HOME/.local/lib:\$HOME/.local/lib64:\$HOME/.local/obs-deps/lib:\$HOME/.local/obs-deps/lib64:/usr/local/lib:/usr/local/lib64:\$LD_LIBRARY_PATH" \
"\$HOME/.local/bin/obs" "\$@"
EOF

  cat > "$HOME/.local/bin/obs-distrobox-x11" <<EOF
#!/usr/bin/env bash
mkdir -p "$HOME/.config/obs-studio/basic/scenes" "$HOME/.config/obs-studio/plugin_config"
exec distrobox enter $(printf '%q' "$DISTROBOX_NAME") -- env \
QT_QPA_PLATFORM=xcb \
QT_XCB_GL_INTEGRATION=xcb_glx \
WAYLAND_DISPLAY= \
DISPLAY="\${DISPLAY}" \
__GLX_VENDOR_LIBRARY_NAME=nvidia \
__NV_PRIME_RENDER_OFFLOAD=1 \
LD_LIBRARY_PATH="\$HOME/.local/lib:\$HOME/.local/lib64:\$HOME/.local/obs-deps/lib:\$HOME/.local/obs-deps/lib64:/usr/local/lib:/usr/local/lib64:\$LD_LIBRARY_PATH" \
"\$HOME/.local/bin/obs" "\$@"
EOF

  chmod +x "$HOME/.local/bin/obs-distrobox-native" "$HOME/.local/bin/obs-distrobox-x11"
  create_desktop_entry
}

ensure_container_running() {
  if ! command -v podman >/dev/null 2>&1; then
    error "podman is required on the host to manage the distrobox container"
    return 1
  fi

  if ! podman container exists "$DISTROBOX_NAME" 2>/dev/null; then
    error "Container $DISTROBOX_NAME does not exist"
    return 1
  fi

  local state
  state="$(podman inspect -f '{{.State.Status}}' "$DISTROBOX_NAME" 2>/dev/null || true)"
  if [[ "$state" != "running" ]]; then
    info "Starting container $DISTROBOX_NAME for host-side package installation..."
    if ! run_cmd "Starting container $DISTROBOX_NAME" "$MASTER_LOG" podman start "$DISTROBOX_NAME"; then
      error "Failed to start container $DISTROBOX_NAME"
      return 1
    fi
  fi

  return 0
}

install_container_packages_from_host() {
  local pkgs=("$@")
  if [[ ${#pkgs[@]} -eq 0 ]]; then
    return 0
  fi

  if ! command -v podman >/dev/null 2>&1; then
    error "podman is required on the host to install packages into the distrobox container"
    return 1
  fi

  ensure_container_running || return 1

  info "Installing missing required packages into $DISTROBOX_NAME from the host..."
  info "${pkgs[*]}"
  if ! run_cmd "Installing required packages in $DISTROBOX_NAME" "$MASTER_LOG" \
    podman exec --user 0 "$DISTROBOX_NAME" dnf install -y "${pkgs[@]}"; then
    error "Host-side package installation into $DISTROBOX_NAME failed"
    return 1
  fi
}

bootstrap_into_distrobox_if_needed() {
  if [[ "$DISTRO" != "bazzite" ]] || inside_container; then
    return 0
  fi

  if ! command -v distrobox >/dev/null 2>&1; then
    error "distrobox is not installed on the host. Install distrobox first, then rerun this script."
    return 1
  fi

  local fedora_ver="${VERSION_ID:-43}"
  local image_ref="fedora:${fedora_ver}"
  local quoted_args
  quoted_args="$(make_shell_quoted_args)"

  info "Bazzite host detected; switching to distrobox build mode."
  info "Container name: $DISTROBOX_NAME"
  info "Container image: $image_ref"

  if [[ "$REBUILD" -eq 1 ]]; then
    info "Rebuild requested; removing existing container if present..."
    distrobox rm "$DISTROBOX_NAME" -f >/dev/null 2>&1 || true
  fi

  if ! distrobox list --no-color 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$DISTROBOX_NAME"; then
    info "Creating distrobox container $DISTROBOX_NAME..."
    if ! run_cmd "Creating distrobox container $DISTROBOX_NAME" "$MASTER_LOG" \
      distrobox create --yes --name "$DISTROBOX_NAME" --image "$image_ref" --nvidia; then
      error "Failed to create distrobox container"
      return 1
    fi
  else
    info "Using existing distrobox container: $DISTROBOX_NAME"
  fi

  # Prime the container so distrobox finishes its initial setup before host-side execs.
  run_cmd "Priming distrobox container $DISTROBOX_NAME" "$MASTER_LOG" \
    distrobox enter "$DISTROBOX_NAME" -- true || true

  if [[ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]]; then
    warn "Optional OBS packages are not preinstalled by default: ${OPTIONAL_PACKAGES[*]}"
    warn "Build may still succeed without them."
  fi

  info "Installing full required OBS dependency set into distrobox image..."
  install_container_packages_from_host "${REQUIRED_PACKAGES[@]}" || return 1

  info "Re-running build script inside distrobox..."
  HANDED_OFF=1
  run_cmd "Handing off build into distrobox $DISTROBOX_NAME" "$MASTER_LOG" \
    distrobox enter "$DISTROBOX_NAME" -- env BUILD_STAMP="$BUILD_STAMP" OBS_GPU_VENDOR="$GPU_VENDOR" HOST_MANAGED_CONTAINER_DEPS=1 bash -lc "$(printf 'chmod +x %q && %q%s' "$SCRIPT_PATH" "$SCRIPT_PATH" "$quoted_args")"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    error "Distrobox build failed with exit code $rc"
    return $rc
  fi

  create_host_obs_launcher
  ok "Build completed inside distrobox."
  info "Wayland/NVIDIA launcher: obs-distrobox-native"
  info "X11/Twitch docks launcher: obs-distrobox-x11"
  info "Desktop entries created: OBS Studio (Wayland/NVIDIA), OBS Studio (X11/Twitch Docks)"
  info "Application menu entries: $DESKTOP_FILE and $DESKTOP_FILE_X11"
  info "Desktop icons: $(get_desktop_dir)/OBS Studio (Wayland-NVIDIA).desktop and $(get_desktop_dir)/OBS Studio (X11-Twitch Docks).desktop"
  feature_to_bool "$ENABLE_APP_AUDIO_PLUGIN" && info "PipeWire application audio plugin install requested."
  exit 0
}

ensure_browser_cef() {
  mkdir -p "$REPO_DIR"

  if [[ -d "$CEF_ROOT_DIR" ]]; then
    info "CEF already present: $CEF_ROOT_DIR"
    return 0
  fi

  info "Browser build enabled; downloading CEF wrapper..."
  if ! run_cmd "Downloading CEF" "$OBS_LOG" curl -L --fail --output "$CEF_ARCHIVE_PATH" "$CEF_URL"; then
    error "CEF download failed"
    return 1
  fi

  if ! run_cmd "Extracting CEF" "$OBS_LOG" tar -C "$REPO_DIR" -xf "$CEF_ARCHIVE_PATH"; then
    error "CEF extraction failed"
    return 1
  fi

  # First try the expected folder name
  if [[ -d "$CEF_ROOT_DIR" ]]; then
    info "CEF ready at: $CEF_ROOT_DIR"
    return 0
  fi

  # Fallback: detect the actual extracted top-level directory
  local detected_cef_dir
  detected_cef_dir="$(tar -tf "$CEF_ARCHIVE_PATH" 2>/dev/null | head -n1 | cut -d/ -f1)"

  if [[ -n "$detected_cef_dir" && -d "$REPO_DIR/$detected_cef_dir" ]]; then
    CEF_ROOT_DIR="$REPO_DIR/$detected_cef_dir"
    info "Detected extracted CEF directory: $CEF_ROOT_DIR"
    return 0
  fi

  # Second fallback: find any matching extracted cef directory
  detected_cef_dir="$(find "$REPO_DIR" -maxdepth 1 -type d -name 'cef_binary_*' | head -n1)"

  if [[ -n "$detected_cef_dir" && -d "$detected_cef_dir" ]]; then
    CEF_ROOT_DIR="$detected_cef_dir"
    info "Detected extracted CEF directory: $CEF_ROOT_DIR"
    return 0
  fi

  error "CEF extracted, but no usable directory was found under: $REPO_DIR"
  return 1
}

########################################
# Step 2: Package checks/installation  #
########################################

# Core packages required for a modern OBS build on Fedora/Bazzite.
BASE_REQUIRED_PACKAGES=(
  cmake
  ninja-build
  gcc
  gcc-c++
  git
  pkgconf-pkg-config
  python3
  python3-devel
  swig
  nasm
  yasm
  curl

  qt6-qtbase-devel
  qt6-qtbase-private-devel
  qt6-qtsvg-devel
  qt6-qtwayland-devel
  extra-cmake-modules

  libX11-devel
  libXcomposite-devel
  libXinerama-devel
  libXrandr-devel
  libXrender-devel
  libXfixes-devel
  libXi-devel
  libXcursor-devel
  libXdamage-devel
  libXext-devel
  libxcb-devel
  xcb-util-devel
  xcb-util-image-devel
  xcb-util-keysyms-devel
  xcb-util-renderutil-devel
  xcb-util-wm-devel
  libxkbcommon-devel
  wayland-devel

  alsa-lib-devel
  pulseaudio-libs-devel
  speexdsp-devel
  rnnoise-devel
  freetype-devel
  fontconfig-devel

  jansson-devel
  libcurl-devel
  mbedtls-devel
  libglvnd-devel
  libdrm-devel
  libva-devel
  uthash-devel
  simde-devel
  libuuid-devel
  pciutils-devel
)

REQUIRED_PACKAGES=()
OPTIONAL_PACKAGES=()

build_package_sets() {
  REQUIRED_PACKAGES=("${BASE_REQUIRED_PACKAGES[@]}")
  OPTIONAL_PACKAGES=()

  feature_to_bool "$ENABLE_PIPEWIRE" && REQUIRED_PACKAGES+=(pipewire-devel pipewire-jack-audio-connection-kit-devel)
  feature_to_bool "$ENABLE_V4L2" && REQUIRED_PACKAGES+=(libv4l-devel)
  feature_to_bool "$ENABLE_WEBSOCKET" && REQUIRED_PACKAGES+=(json-devel libqrcodegencpp-devel websocketpp-devel asio-devel)
  feature_to_bool "$ENABLE_SCRIPTING" && REQUIRED_PACKAGES+=(luajit-devel)
  feature_to_bool "$ENABLE_NVENC" && REQUIRED_PACKAGES+=(nv-codec-headers)
  feature_to_bool "$ENABLE_QSV11" && REQUIRED_PACKAGES+=(libvpl-devel)
  feature_to_bool "$ENABLE_WEBRTC" && REQUIRED_PACKAGES+=(libdatachannel-devel)
  feature_to_bool "$ENABLE_NEW_MPEGTS_OUTPUT" && REQUIRED_PACKAGES+=(librist-devel srt-devel)
  feature_to_bool "$ENABLE_VLC" && REQUIRED_PACKAGES+=(vlc-devel)
  feature_to_bool "$ENABLE_VKCAPTURE_PLUGIN" && REQUIRED_PACKAGES+=(vulkan-loader-devel)

  OPTIONAL_PACKAGES+=(x264-devel libvpx-devel)
}

resolve_pkg_name() {
  local pkg="$1"
  case "$pkg" in
    pkgconfig) echo "pkgconf-pkg-config" ;;
    curl-devel) echo "libcurl-devel" ;;
    uuid-devel) echo "libuuid-devel" ;;
    pci-devel) echo "pciutils-devel" ;;
    asio) echo "asio-devel" ;;
    v4l-utils-devel|libv4l2-devel) echo "libv4l-devel" ;;
    websocket++-devel) echo "websocketpp-devel" ;;
    nlohmann-json-devel|nlohmann_json-devel) echo "json-devel" ;;
    qrcodegencpp-devel|libqrcodegen-cpp-devel) echo "libqrcodegencpp-devel" ;;
    lua-jit-devel) echo "luajit-devel" ;;
    qt5-qtbase-devel) echo "qt6-qtbase-devel" ;;
    qt5-qtsvg-devel) echo "qt6-qtsvg-devel" ;;
    qt5-qtmultimedia-devel|qt5-qtwebsockets-devel) echo "" ;;
    *) echo "$pkg" ;;
  esac
}

pkg_present_fedora_family() {
  local pkg="$1"
  [[ -z "$pkg" ]] && return 0

  if rpm -q "$pkg" >/dev/null 2>&1; then
    return 0
  fi

  if rpm -q --whatprovides "$pkg" >/dev/null 2>&1; then
    return 0
  fi

  case "$pkg" in
    pkgconf-pkg-config)
      command -v pkg-config >/dev/null 2>&1 && return 0
      ;;
    cmake|git|python3|swig|nasm|yasm|ninja-build)
      command -v "${pkg%%-*}" >/dev/null 2>&1 && return 0
      ;;
  esac

  return 1
}

bazzite_pkg_present() {
  local pkg="$1"
  [[ -z "$pkg" ]] && return 0

  if pkg_present_fedora_family "$pkg"; then
    return 0
  fi

  if rpm-ostree status 2>/dev/null | grep -qw "$pkg"; then
    return 0
  fi

  return 1
}

collect_missing_packages() {
  local mode="$1"  # required|optional
  local raw_pkg resolved checker
  local -n out_ref="$2"

  out_ref=()

  if [[ "$DISTRO" == "bazzite" ]]; then
    checker="bazzite_pkg_present"
  else
    checker="pkg_present_fedora_family"
  fi

  local pkg_list=()
  if [[ "$mode" == "required" ]]; then
    pkg_list=("${REQUIRED_PACKAGES[@]}")
  else
    pkg_list=("${OPTIONAL_PACKAGES[@]}")
  fi

  for raw_pkg in "${pkg_list[@]}"; do
    resolved="$(resolve_pkg_name "$raw_pkg")"
    [[ -z "$resolved" ]] && continue

    if ! "$checker" "$resolved"; then
      out_ref+=("$resolved")
    fi
  done

  local deduped=()
  local seen=""
  local p
  for p in "${out_ref[@]}"; do
    if [[ " $seen " != *" $p "* ]]; then
      deduped+=("$p")
      seen+=" $p"
    fi
  done
  out_ref=("${deduped[@]}")
}

install_required_packages() {
  info "STEP 1: Checking required packages..."

  local missing_required=()
  local missing_optional=()

  collect_missing_packages required missing_required
  collect_missing_packages optional missing_optional

  if [[ ${#missing_optional[@]} -gt 0 ]]; then
    warn "Optional OBS packages missing: ${missing_optional[*]}"
    warn "Build may still succeed without them."
  else
    info "All optional OBS packages already installed."
  fi

  case "$DISTRO" in
    bazzite)
      warn "Bazzite host detected outside a container."
      warn "Run will be redirected into distrobox before dependency installation."
      return 1
      ;;
    fedora)
      if inside_container; then
        if [[ ${#missing_required[@]} -gt 0 ]]; then
          error "Missing required packages inside distrobox after host-managed dependency install: ${missing_required[*]}"
          error "Rerun from the host so the script can preinstall them before handoff."
          return 1
        fi
        info "All required packages already installed inside distrobox."
      else
        if [[ ${#missing_required[@]} -gt 0 ]]; then
          info "Installing missing required packages via dnf:"
          info "${missing_required[*]}"
          if ! run_cmd "Installing required Fedora packages" "$MASTER_LOG" sudo dnf install -y "${missing_required[@]}"; then
            error "dnf dependency installation failed"
            return 1
          fi
        else
          info "All required packages already installed."
        fi
      fi
      ;;
    *)
      warn "Automatic package installation is not implemented for distro: $DISTRO"
      if [[ ${#missing_required[@]} -gt 0 ]]; then
        warn "Missing required packages: ${missing_required[*]}"
        return 1
      fi
      ;;
  esac

  return 0
}

######################################
# Step 3: Prepare repo/build folders #
######################################
prepare_directories() {
  info "STEP 2: Preparing folders..."
  mkdir -p "$BUILD_DIR" "$REPO_DIR" "$LOG_DIR" "$FAILED_DIR"
  mkdir -p "$X264_BUILD" "$X265_BUILD" "$FFMPEG_BUILD" "$OBS_BUILD"
  mkdir -p "$DEPS_PREFIX"
  info "Build dir: $BUILD_DIR"
  info "Repo dir:  $REPO_DIR"
  info "Log dir:   $LOG_DIR"
}

################################
# Step 4: Clone/update repos   #
################################
declare -A REPOS=(
  [x264]="https://code.videolan.org/videolan/x264.git"
  [x265]="https://github.com/videolan/x265.git"
  [ffmpeg]="https://github.com/FFmpeg/FFmpeg.git"
  [obs-studio]="https://github.com/obsproject/obs-studio.git"
)

clone_or_update_repo() {
  local name="$1"
  local url="$2"
  local target="$REPO_DIR/$name"
  local logfile="${LOGFILE[$name]:-$LOG_DIR/${name}-build-$BUILD_STAMP.log}"

  : > "$logfile"

  if [[ -d "$target/.git" ]]; then
    info "$name repo exists, updating..."
    run_cmd "Fetching $name" "$logfile" git -C "$target" fetch --all --tags --progress || return 1
    run_cmd "Updating $name submodules" "$logfile" git -C "$target" submodule update --init --recursive --progress || return 1
    if [[ "$name" == "ffmpeg" ]]; then
      info "Using FFmpeg release: $FFMPEG_REF"
      if [[ "$VERBOSE" -eq 1 ]]; then
        run_cmd "Checking out FFmpeg ref $FFMPEG_REF" "$logfile" git -C "$target" checkout "$FFMPEG_REF" || return 1
      else
        run_cmd "Checking out FFmpeg ref $FFMPEG_REF" "$logfile" git -C "$target" -c advice.detachedHead=false checkout "$FFMPEG_REF" || return 1
      fi
    else
      run_cmd "Fast-forwarding $name" "$logfile" git -C "$target" pull --progress --rebase --recurse-submodules || warn "$name pull failed, continuing with current checkout."
    fi
  else
    info "Cloning $name..."
    run_cmd "Cloning $name" "$logfile" git clone --progress --recursive "$url" "$target" || return 1
    if [[ "$name" == "ffmpeg" ]]; then
      info "Using FFmpeg release: $FFMPEG_REF"
      if [[ "$VERBOSE" -eq 1 ]]; then
        run_cmd "Checking out FFmpeg ref $FFMPEG_REF" "$logfile" git -C "$target" checkout "$FFMPEG_REF" || return 1
      else
        run_cmd "Checking out FFmpeg ref $FFMPEG_REF" "$logfile" git -C "$target" -c advice.detachedHead=false checkout "$FFMPEG_REF" || return 1
      fi
    fi
  fi
}

#############################################
# Step 5: Install detection / skip helpers  #
#############################################
check_x264() {
  [[ -f "$DEPS_PREFIX/lib/libx264.so" || -f "$DEPS_PREFIX/lib/libx264.a" ]] &&
  [[ -f "$DEPS_PREFIX/include/x264.h" ]] &&
  [[ -f "$DEPS_PREFIX/lib/pkgconfig/x264.pc" ]]
}

check_x265() {
  [[ -f "$DEPS_PREFIX/lib/libx265.so" || -f "$DEPS_PREFIX/lib/libx265.a" ]] &&
  [[ -f "$DEPS_PREFIX/include/x265.h" ]]
}

check_ffmpeg() {
  command -v "$DEPS_PREFIX/bin/ffmpeg" >/dev/null 2>&1 &&
  [[ -f "$DEPS_PREFIX/lib/pkgconfig/libavcodec.pc" ]] &&
  PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig" pkg-config --exists libavcodec libavformat
}

check_obs() {
  command -v "$HOME/.local/bin/obs" >/dev/null 2>&1
}

should_skip() {
  local comp="$1"
  [[ "$FORCE" -eq 0 ]] || return 1
  case "$comp" in
    x264) check_x264 ;;
    x265) check_x265 ;;
    ffmpeg) check_ffmpeg ;;
    obs-studio) check_obs ;;
    *) return 1 ;;
  esac
}

verify_ffmpeg_pkgconfig() {
  local log="$1"
  run_cmd "Checking FFmpeg pkg-config visibility" "$log" env \
    PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}" \
    pkg-config --exists libavcodec libavformat libavutil libswscale libswresample
}

ensure_local_install_writable() {
  local paths=(
    "$HOME/.local"
    "$HOME/.local/bin"
    "$HOME/.local/lib"
    "$HOME/.local/lib64"
    "$HOME/.local/share"
    "$HOME/.local/share/obs"
    "$HOME/.local/share/applications"
    "$HOME/.local/share/icons"
  )
  local p
  for p in "${paths[@]}"; do
    mkdir -p "$p"
  done

  local unwritable=()
  for p in "${paths[@]}"; do
    if [[ ! -w "$p" ]]; then
      unwritable+=("$p")
    fi
  done

  if [[ ${#unwritable[@]} -gt 0 ]]; then
    warn "User-local install paths are not writable: ${unwritable[*]}"
    warn "Attempting to restore ownership with sudo chown..."
    if ! run_cmd "Fixing ownership of ~/.local OBS install paths" "$OBS_LOG" sudo chown -R "$USER:$USER" "$HOME/.local"; then
      error "Failed to restore ownership of $HOME/.local"
      return 1
    fi
  fi

  return 0
}

# Temporary Debug Function
dump_obs_debug_artifacts() {
  local latest_build=""
  local debug_dir="$LOG_DIR/debug"

  mkdir -p "$debug_dir"

  latest_build="$(ls -dt "$ROOT_DIR"/Builds/obs-build-*/obs-studio-build 2>/dev/null | head -n1)"

  if [[ -z "$latest_build" ]]; then
    warn "No obs-studio-build directory found for debug artifact dump."
    return 1
  fi

  info "Dumping OBS debug artifacts from: $latest_build"

  printf '%s\n' "$latest_build" > "$debug_dir/latest_build.txt"

  if [[ -f "$latest_build/libobs/CMakeFiles/libobs.dir/link.txt" ]]; then
    cp -f "$latest_build/libobs/CMakeFiles/libobs.dir/link.txt" "$debug_dir/link.txt"
  else
    warn "link.txt not found in $latest_build"
  fi

  if [[ -f "$latest_build/CMakeCache.txt" ]]; then
    grep -nE 'X11|libX11|xcb|xkbcommon' "$latest_build/CMakeCache.txt" > "$debug_dir/CMakeCache.txt" || true
  else
    warn "CMakeCache.txt not found in $latest_build"
  fi
}

#######################################
# Step 6: Component build functions   #
#######################################
build_x264() {
  local log="$X264_LOG"
  : > "$log"
  STATUS[x264]="RUNNING"
  SUMMARY[x264]="Configuring and compiling"

  if [[ "$FORCE" -eq 1 ]]; then
    run_in_dir "$X264_SRC" make distclean >> "$log" 2>&1 || true
    rm -rf "$X264_BUILD"/*
  fi

  run_in_dir "$X264_BUILD" run_cmd "Configuring x264" "$log" "$X264_SRC/configure" --prefix="$DEPS_PREFIX" --enable-shared --enable-pic || { mark_failed x264 "configure failed"; return 1; }
  run_in_dir "$X264_BUILD" run_cmd "Building x264" "$log" make -j"$(nproc)" || { mark_failed x264 "build failed"; return 1; }
  run_in_dir "$X264_BUILD" run_cmd "Installing x264" "$log" make install || { mark_failed x264 "install failed"; return 1; }

  mark_success x264 "Installed to $DEPS_PREFIX"
}

build_x265() {
  local log="$X265_LOG"
  : > "$log"
  STATUS[x265]="RUNNING"
  SUMMARY[x265]="Configuring and compiling"

  [[ "$FORCE" -eq 1 ]] && rm -rf "$X265_BUILD"/*

  run_in_dir "$X265_BUILD" run_cmd "Configuring x265" "$log" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" -DENABLE_SHARED=ON "$X265_SRC/source" || { mark_failed x265 "configure failed"; return 1; }
  run_in_dir "$X265_BUILD" run_cmd "Building x265" "$log" make -j"$(nproc)" || { mark_failed x265 "build failed"; return 1; }
  run_in_dir "$X265_BUILD" run_cmd "Installing x265" "$log" make install || { mark_failed x265 "install failed"; return 1; }

  mark_success x265 "Installed to $DEPS_PREFIX"
}

build_ffmpeg() {
  local log="$FFMPEG_LOG"
  : > "$log"
  STATUS[ffmpeg]="RUNNING"
  SUMMARY[ffmpeg]="Configuring and compiling"

  [[ "$FORCE" -eq 1 ]] && rm -rf "$FFMPEG_BUILD"/*

  run_in_dir "$FFMPEG_BUILD" run_cmd "Configuring FFmpeg ($FFMPEG_REF)" "$log" env \
    PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    LD_LIBRARY_PATH="$DEPS_PREFIX/lib:${LD_LIBRARY_PATH:-}" \
    "$FFMPEG_SRC/configure" \
      --prefix="$DEPS_PREFIX" \
      --pkg-config-flags=--static \
      --extra-cflags="-I$DEPS_PREFIX/include" \
      --extra-ldflags="-L$DEPS_PREFIX/lib" \
      --extra-libs="-lpthread -lm" \
      --enable-gpl \
      --enable-libx264 \
      --enable-libx265 \
      --enable-shared \
      --enable-pic || { mark_failed ffmpeg "configure failed"; return 1; }

  run_in_dir "$FFMPEG_BUILD" run_cmd "Building FFmpeg" "$log" make -j"$(nproc)" || { mark_failed ffmpeg "build failed"; return 1; }
  run_in_dir "$FFMPEG_BUILD" run_cmd "Installing FFmpeg" "$log" make install || { mark_failed ffmpeg "install failed"; return 1; }

  mark_success ffmpeg "Installed to $DEPS_PREFIX"
}

sanitize_obs_pkgconfig() {
  local pc="$HOME/.local/lib64/pkgconfig/libobs.pc"
  [[ -f "$pc" ]] || return 0
  sed -i 's/[[:space:]]-Werror//g' "$pc"
}

build_obs() {
  local log="$OBS_LOG"
  : > "$log"
  STATUS[obs-studio]="RUNNING"
  SUMMARY[obs-studio]="Configuring and compiling"

  rm -rf "$OBS_BUILD"/*

  verify_ffmpeg_pkgconfig "$log" || { mark_failed obs-studio "FFmpeg pkg-config check failed"; return 1; }
  ensure_local_install_writable || { mark_failed obs-studio "local install path is not writable"; return 1; }
  if feature_to_bool "$ENABLE_BROWSER"; then
    ensure_browser_cef || { mark_failed obs-studio "CEF setup failed"; return 1; }
  fi

  local cmake_flags=(
    -DCMAKE_INSTALL_PREFIX="$HOME/.local"
    -DCMAKE_INSTALL_RPATH="$HOME/.local/lib;$HOME/.local/lib64;$DEPS_PREFIX/lib"
    -DCMAKE_PREFIX_PATH="$DEPS_PREFIX"
    -DCMAKE_LIBRARY_PATH="$DEPS_PREFIX/lib;/usr/lib64;/usr/local/lib64"
    -DCMAKE_INCLUDE_PATH="$DEPS_PREFIX/include;/usr/include"
    -DFFmpeg_INCLUDE_DIRS="$DEPS_PREFIX/include"
    -DFFmpeg_LIBRARY_DIR="$DEPS_PREFIX/lib"
    -Djansson_INCLUDE_DIR="/usr/include"
    -Djansson_LIBRARY="/usr/lib64/libjansson.so"
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-rpath,$DEPS_PREFIX/lib -Wl,-rpath-link,$DEPS_PREFIX/lib"
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-rpath,$DEPS_PREFIX/lib -Wl,-rpath-link,$DEPS_PREFIX/lib"
    -DCMAKE_FIND_DEBUG_MODE=ON # Temporary Flag
    -DX11_X11_LIB=/usr/lib64/libX11.so
    -DX11_X11_xcb_LIB=/usr/lib64/libX11-xcb.so
    -DX11_XCB_LIBRARY=/usr/lib64/libX11-xcb.so
    -DX11_xcb_LIB=/usr/lib64/libxcb.so
    -DX11_Xcomposite_LIB=/usr/lib64/libXcomposite.so
    -DX11_Xcursor_LIB=/usr/lib64/libXcursor.so
    -DX11_Xdamage_LIB=/usr/lib64/libXdamage.so
    -DX11_Xext_LIB=/usr/lib64/libXext.so
    -DX11_Xfixes_LIB=/usr/lib64/libXfixes.so
    -DX11_Xi_LIB=/usr/lib64/libXi.so
    -DX11_Xinerama_LIB=/usr/lib64/libXinerama.so
    -DX11_Xrandr_LIB=/usr/lib64/libXrandr.so
    -DX11_Xrender_LIB=/usr/lib64/libXrender.so
    -DX11_xcb_xinput_LIB=/usr/lib64/libxcb-xinput.so
    -DX11_xkbcommon_LIB=/usr/lib64/libxkbcommon.so
)

  local cmake_env=(
    LD_LIBRARY_PATH="$DEPS_PREFIX/lib"
    LIBRARY_PATH="$DEPS_PREFIX/lib:/usr/lib64:/usr/local/lib64"
    CMAKE_PREFIX_PATH="/usr/local"
    CMAKE_LIBRARY_PATH="/usr/lib64:/usr/local/lib64"
    CMAKE_INCLUDE_PATH="/usr/local/include:/usr/include"
    PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_LIBDIR="/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    PKG_CONFIG_SYSTEM_LIBRARY_PATH="/usr/lib64"
)

  feature_to_bool "$ENABLE_PIPEWIRE" && cmake_flags+=(-DENABLE_PIPEWIRE=ON) || cmake_flags+=(-DENABLE_PIPEWIRE=OFF)
  feature_to_bool "$ENABLE_BROWSER" && cmake_flags+=(-DENABLE_BROWSER=ON -DCEF_ROOT_DIR="$CEF_ROOT_DIR") || cmake_flags+=(-DENABLE_BROWSER=OFF)
  feature_to_bool "$ENABLE_AJA" && cmake_flags+=(-DENABLE_AJA=ON) || cmake_flags+=(-DENABLE_AJA=OFF)
  feature_to_bool "$ENABLE_NEW_MPEGTS_OUTPUT" && cmake_flags+=(-DENABLE_NEW_MPEGTS_OUTPUT=ON) || cmake_flags+=(-DENABLE_NEW_MPEGTS_OUTPUT=OFF)
  feature_to_bool "$ENABLE_QSV11" && cmake_flags+=(-DENABLE_QSV11=ON) || cmake_flags+=(-DENABLE_QSV11=OFF)
  feature_to_bool "$ENABLE_WEBRTC" && cmake_flags+=(-DENABLE_WEBRTC=ON) || cmake_flags+=(-DENABLE_WEBRTC=OFF)
  feature_to_bool "$ENABLE_VLC" && cmake_flags+=(-DENABLE_VLC=ON) || cmake_flags+=(-DENABLE_VLC=OFF)
  feature_to_bool "$ENABLE_NVENC" && cmake_flags+=(-DENABLE_NVENC=ON) || cmake_flags+=(-DENABLE_NVENC=OFF)
  feature_to_bool "$ENABLE_SCRIPTING" || cmake_flags+=(-DENABLE_SCRIPTING=OFF)
  feature_to_bool "$ENABLE_WEBSOCKET" || cmake_flags+=(-DENABLE_WEBSOCKET=OFF)

  if feature_to_bool "$ENABLE_TWITCH_API"; then
    if [[ -n "$TWITCH_CLIENTID" ]]; then
      cmake_flags+=(
        -DOAUTH_BASE_URL="$OAUTH_BASE_URL"
        -DTWITCH_CLIENTID="$TWITCH_CLIENTID"
        -DTWITCH_HASH="$TWITCH_HASH"
      )
      info "Twitch API integration enabled with custom OAuth base URL."
    else
      warn "Twitch API integration requested, but TWITCH_CLIENTID is not set. Building without Twitch API integration."
    fi
  fi

#   run_cmd "Configuring OBS Studio" "$log" \
#   env "${cmake_env[@]}" \
#   cmake -S "$OBS_SRC" -B "$OBS_BUILD" "${cmake_flags[@]}" \
#   || { mark_failed obs-studio "cmake configure failed"; return 1; }

  # Temporary Debug Dump During config if fail.
  run_cmd "Configuring OBS Studio" "$log" \
  env "${cmake_env[@]}" \
  cmake -S "$OBS_SRC" -B "$OBS_BUILD" "${cmake_flags[@]}" \
    || { dump_obs_debug_artifacts; mark_failed obs-studio "cmake configure failed"; return 1; }

#   run_cmd "Building OBS Studio" "$log" \
#   env "${cmake_env[@]}" \
#   cmake --build "$OBS_BUILD" -j"$(nproc)" \
#   || { mark_failed obs-studio "build failed"; return 1; }
   # Same thing as the previous.
  run_cmd "Building OBS Studio" "$log" \
  env "${cmake_env[@]}" \
  cmake --build "$OBS_BUILD" -j"$(nproc)" \
    || { dump_obs_debug_artifacts; mark_failed obs-studio "build failed"; return 1; }


  run_cmd "Installing OBS Studio" "$log" \
  cmake --install "$OBS_BUILD" \
    || { mark_failed obs-studio "install failed"; return 1; }


  sanitize_obs_pkgconfig



  mark_success obs-studio "Installed to $HOME/.local"
#   mark_success obs-studio "OBS compiled successfully (install step disabled for debugging)"
}

##########
ensure_obs_local_lib_symlinks() {
  mkdir -p /usr/local/lib64 /usr/local/lib
  local lib
  for lib in libobs.so libobs-frontend-api.so; do
    if [[ -e "$HOME/.local/lib64/$lib" ]]; then
      ln -sfn "$HOME/.local/lib64/$lib" "/usr/local/lib64/$lib"
    elif [[ -e "$HOME/.local/lib/$lib" ]]; then
      ln -sfn "$HOME/.local/lib/$lib" "/usr/local/lib/$lib"
    fi
  done
  ldconfig >/dev/null 2>&1 || true
}

verify_plugin_file() {
  local path="$1"
  [[ -f "$path" ]]
}

verify_plugin_deps() {
  local path="$1"
  if ! [[ -f "$path" ]]; then
    return 1
  fi
  local plugin_lib_path="$HOME/.local/lib:$HOME/.local/lib64:$HOME/.local/lib64/obs-plugins:$HOME/.local/obs-deps/lib:$HOME/.local/obs-deps/lib64:/usr/local/lib:/usr/local/lib64:${LD_LIBRARY_PATH:-}"
  ! LD_LIBRARY_PATH="$plugin_lib_path" ldd "$path" 2>/dev/null | grep -q 'not found'
}

install_plugin_payload() {
  local so_name="$1"
  local data_dir_name="$2"
  local src_lib_dir="$3"
  local src_share_dir="$4"

  mkdir -p "$HOME/.local/lib64/obs-plugins" "$HOME/.local/share/obs/obs-plugins"
  if [[ -f "$src_lib_dir/$so_name" ]]; then
    cp -av "$src_lib_dir/$so_name" "$HOME/.local/lib64/obs-plugins/" >> "$MASTER_LOG" 2>&1
  fi
  if [[ -n "$data_dir_name" && -d "$src_share_dir/$data_dir_name" ]]; then
    rm -rf "$HOME/.local/share/obs/obs-plugins/$data_dir_name"
    cp -av "$src_share_dir/$data_dir_name" "$HOME/.local/share/obs/obs-plugins/" >> "$MASTER_LOG" 2>&1
  fi
}

install_vkcapture_multilib_deps() {
  feature_to_bool "$ENABLE_VKCAPTURE_PLUGIN" || return 0
  local log="$VKCAPTURE_BUILD_LOG"

  info "Installing 32-bit linux-vkcapture build dependencies..."


  local multilib_packages=(
    vulkan-loader-devel.i686
    glibc-devel.i686
    libgcc.i686
    libstdc++-devel.i686
    libX11-devel.i686
    libXcomposite-devel.i686
    libXinerama-devel.i686
    libXrandr-devel.i686
    libXrender-devel.i686
    libXfixes-devel.i686
    libXi-devel.i686
    libXcursor-devel.i686
    libXdamage-devel.i686
    libXext-devel.i686
    libxcb-devel.i686
    xcb-util-devel.i686
    xcb-util-image-devel.i686
    xcb-util-keysyms-devel.i686
    xcb-util-renderutil-devel.i686
    xcb-util-wm-devel.i686
    libxkbcommon-devel.i686
    libglvnd-devel.i686
    libdrm-devel.i686
  )

  if inside_container; then
    run_cmd "Installing linux-vkcapture multilib deps" "$log" \
      distrobox-host-exec podman exec --user 0 "$DISTROBOX_NAME" \
      dnf install -y "${multilib_packages[@]}" \
      || { warn "linux-vkcapture multilib dependency install failed (see $log)"; return 1; }
  else
    warn "Attempted multilib dependency install outside container — falling back to host install."
    install_container_packages_from_host "${multilib_packages[@]}" >>"$log" 2>&1 \
      || { warn "linux-vkcapture multilib dependency install failed (see $log)"; return 1; }
  fi
#     run_cmd "Installing linux-vkcapture multilib deps" "$log" dnf install -y \
#     vulkan-loader-devel.i686 \
#     glibc-devel.i686 \
#     libgcc.i686 \
#     libstdc++-devel.i686 \
#     libX11-devel.i686 \
#     libXcomposite-devel.i686 \
#     libXinerama-devel.i686 \
#     libXrandr-devel.i686 \
#     libXrender-devel.i686 \
#     libXfixes-devel.i686 \
#     libXi-devel.i686 \
#     libXcursor-devel.i686 \
#     libXdamage-devel.i686 \
#     libXext-devel.i686 \
#     libxcb-devel.i686 \
#     xcb-util-devel.i686 \
#     xcb-util-image-devel.i686 \
#     xcb-util-keysyms-devel.i686 \
#     xcb-util-renderutil-devel.i686 \
#     xcb-util-wm-devel.i686 \
#     libxkbcommon-devel.i686 \
#     libglvnd-devel.i686 \
#     libdrm-devel.i686 \

}


build_linux_vkcapture_plugin() {
  feature_to_bool "$ENABLE_VKCAPTURE_PLUGIN" || return 0

  local log="$VKCAPTURE_BUILD_LOG"
  : > "$log"

  info "STEP 7a: Building linux-vkcapture plugin..."

  clone_or_update_repo obs-vkcapture https://github.com/nowrep/obs-vkcapture.git \
    || { warn "obs-vkcapture repo update failed"; return 1; }

  rm -rf "$VKCAPTURE_BUILD" "$VKCAPTURE_BUILD32" "$BUILD_DIR/vkcapture-stage"
  mkdir -p "$VKCAPTURE_BUILD" "$VKCAPTURE_BUILD32"

  local vkcapture_stage_prefix="$BUILD_DIR/vkcapture-stage$HOME/.local"

  ################################################
  # Build 64-bit first (safe for OBS environment)
  ################################################

  run_in_dir "$VKCAPTURE_BUILD" run_cmd \
    "Configuring linux-vkcapture (64-bit)" "$log" \
    cmake "$VKCAPTURE_SRC" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
      -DCMAKE_INSTALL_LIBDIR=lib64 \
      || { warn "linux-vkcapture 64-bit configure failed"; return 1; }

  run_in_dir "$VKCAPTURE_BUILD" run_cmd \
    "Building linux-vkcapture (64-bit)" "$log" \
    cmake --build . -j"$(nproc)" \
    || { warn "linux-vkcapture 64-bit build failed"; return 1; }

  run_in_dir "$VKCAPTURE_BUILD" run_cmd \
    "Installing linux-vkcapture (64-bit)" "$log" \
    env DESTDIR="$BUILD_DIR/vkcapture-stage" cmake --install . \
    || { warn "linux-vkcapture 64-bit install failed"; return 1; }

  ################################################
  # Install multilib dependencies ONLY now
  ################################################

  install_vkcapture_multilib_deps || return 1

  ################################################
  # Build 32-bit version
  ################################################


  local vkcapture32_env=(
    PKG_CONFIG_PATH="$HOME/.local/lib64/pkgconfig:$HOME/.local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
    CFLAGS="-m32 -I$HOME/.local/include -I$HOME/.local/include/obs -Wno-error"
    CXXFLAGS="-m32 -I$HOME/.local/include -I$HOME/.local/include/obs -Wno-error"
    LDFLAGS="-m32"
  )

  local vkcapture32_cmake_flags=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="$HOME/.local"
    -DCMAKE_INSTALL_LIBDIR=lib
  )

  run_in_dir "$VKCAPTURE_BUILD32" run_cmd \
    "Configuring linux-vkcapture (32-bit)" "$log" \
    env "${vkcapture32_env[@]}" \
    cmake "$VKCAPTURE_SRC" "${vkcapture32_cmake_flags[@]}" \
      || { warn "linux-vkcapture 32-bit configure failed"; return 1; }

#   run_in_dir "$VKCAPTURE_BUILD32" run_cmd \
#     "Building linux-vkcapture (32-bit)" "$log" \
#     cmake --build . -j"$(nproc)" \
#       || { warn "linux-vkcapture 32-bit build failed"; return 1; }

  run_in_dir "$VKCAPTURE_BUILD32" run_cmd \
  "Building linux-vkcapture helper targets (32-bit)" "$log" \
  cmake --build . -j"$(nproc)" --target obs_glcapture VkLayer_obs_vkcapture \
    || { warn "linux-vkcapture 32-bit helper build failed"; return 1; }


  info "Installing linux-vkcapture helper artifacts (32-bit)"

  mkdir -p \
    "$BUILD_DIR/vkcapture-stage/usr/local/lib" \
    "$BUILD_DIR/vkcapture-stage/usr/local/lib32"

  cp -av "$VKCAPTURE_BUILD32/libobs_glcapture.so" \
    "$BUILD_DIR/vkcapture-stage/usr/local/lib/" >> "$log" 2>&1 || true

  cp -av "$VKCAPTURE_BUILD32/libVkLayer_obs_vkcapture.so" \
    "$BUILD_DIR/vkcapture-stage/usr/local/lib/" >> "$log" 2>&1 || true

#   run_in_dir "$VKCAPTURE_BUILD32" run_cmd \
#     "Installing linux-vkcapture helper artifacts (32-bit)" "$log" \
#     env DESTDIR="$BUILD_DIR/vkcapture-stage" cmake --install . \
#       || { warn "linux-vkcapture 32-bit install failed"; return 1; }

# Old Export Code

#   mkdir -p \
#     "$HOME/.local/bin" \
#     "$HOME/.local/lib" \
#     "$HOME/.local/lib64" \
#     "$HOME/.local/share/vulkan/implicit_layer.d"
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/bin/obs-gamecapture" \
#     "$HOME/.local/bin/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/bin/obs-vkcapture" \
#     "$HOME/.local/bin/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/bin/obs-glcapture" \
#     "$HOME/.local/bin/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/lib64/libVkLayer_obs_vkcapture.so" \
#     "$HOME/.local/lib64/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/lib/libVkLayer_obs_vkcapture.so" \
#     "$HOME/.local/lib/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/share/vulkan/implicit_layer.d/"*.json \
#     "$HOME/.local/share/vulkan/implicit_layer.d/" >> "$log" 2>&1 || true
#
#   ok "linux-vkcapture plugin installed into $HOME/.local"


  ################################################
  # Export both architectures
  ################################################

  mkdir -p \
    "$HOME/.local/bin" \
    "$HOME/.local/lib" \
    "$HOME/.local/lib64" \
    "$HOME/.local/lib/obs_glcapture" \
    "$HOME/.local/lib64/obs_glcapture" \
    "$HOME/.local/lib64/obs-plugins" \
    "$HOME/.local/share/vulkan/implicit_layer.d"

  cp -av "$vkcapture_stage_prefix/bin/obs-gamecapture" \
    "$HOME/.local/bin/" >> "$log" 2>&1 || { warn "Failed to install obs-gamecapture"; return 1; }

  cp -av "$vkcapture_stage_prefix/bin/obs-vkcapture" \
    "$HOME/.local/bin/" >> "$log" 2>&1 || { warn "Failed to install obs-vkcapture"; return 1; }

  cp -av "$vkcapture_stage_prefix/bin/obs-glcapture" \
    "$HOME/.local/bin/" >> "$log" 2>&1 || { warn "Failed to install obs-glcapture"; return 1; }

  cp -av "$vkcapture_stage_prefix/lib64/obs-plugins/linux-vkcapture.so" \
    "$HOME/.local/lib64/obs-plugins/" >> "$log" 2>&1 || { warn "Failed to install linux-vkcapture.so"; return 1; }

  cp -av "$vkcapture_stage_prefix/lib64/libVkLayer_obs_vkcapture.so" \
    "$HOME/.local/lib64/" >> "$log" 2>&1 || { warn "Failed to install 64-bit libVkLayer_obs_vkcapture.so"; return 1; }

  cp -av "$BUILD_DIR/vkcapture-stage/usr/local/lib/libVkLayer_obs_vkcapture.so" \
    "$HOME/.local/lib/" >> "$log" 2>&1 || { warn "Failed to install 32-bit libVkLayer_obs_vkcapture.so"; return 1; }

  cp -av "$vkcapture_stage_prefix/lib64/obs_glcapture/libobs_glcapture.so" \
    "$HOME/.local/lib64/obs_glcapture/" >> "$log" 2>&1 || { warn "Failed to install 64-bit libobs_glcapture.so"; return 1; }

  cp -av "$BUILD_DIR/vkcapture-stage/usr/local/lib/libobs_glcapture.so" \
    "$HOME/.local/lib/obs_glcapture/" >> "$log" 2>&1 || { warn "Failed to install 32-bit libobs_glcapture.so"; return 1; }

  cp -av "$vkcapture_stage_prefix/share/vulkan/implicit_layer.d/"*.json \
    "$HOME/.local/share/vulkan/implicit_layer.d/" >> "$log" 2>&1 || { warn "Failed to install Vulkan implicit layer JSON files"; return 1; }

  ok "linux-vkcapture plugin installed into $HOME/.local"


}


# build_linux_vkcapture_plugin() {
#   feature_to_bool "$ENABLE_VKCAPTURE_PLUGIN" || return 0
#
#   local log="$VKCAPTURE_BUILD_LOG"
#   : > "$log"
#
#   info "STEP 7a: Building linux-vkcapture plugin..."
#
#   clone_or_update_repo obs-vkcapture https://github.com/nowrep/obs-vkcapture.git \
#     || { warn "obs-vkcapture repo update failed"; return 1; }
#
#   rm -rf "$VKCAPTURE_BUILD" "$VKCAPTURE_BUILD32" "$BUILD_DIR/vkcapture-stage"
#   mkdir -p "$VKCAPTURE_BUILD" "$VKCAPTURE_BUILD32"
#
#   ################################################
#   # Build 64-bit first (safe for OBS environment)
#   ################################################
#
#   run_in_dir "$VKCAPTURE_BUILD" run_cmd \
#     "Configuring linux-vkcapture (64-bit)" "$log" \
#     cmake "$VKCAPTURE_SRC" \
#       -DCMAKE_BUILD_TYPE=Release \
#       -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
#       -DCMAKE_INSTALL_LIBDIR=lib64 \
#       || { warn "linux-vkcapture 64-bit configure failed"; return 1; }
#
#   run_in_dir "$VKCAPTURE_BUILD" run_cmd \
#     "Building linux-vkcapture (64-bit)" "$log" \
#     cmake --build . -j"$(nproc)" \
#     || { warn "linux-vkcapture 64-bit build failed"; return 1; }
#
#   run_in_dir "$VKCAPTURE_BUILD" run_cmd \
#     "Installing linux-vkcapture (64-bit)" "$log" \
#     env DESTDIR="$BUILD_DIR/vkcapture-stage" cmake --install . \
#     || { warn "linux-vkcapture 64-bit install failed"; return 1; }
#
#   ################################################
#   # Install multilib dependencies ONLY now
#   ################################################
#
#   install_vkcapture_multilib_deps || return 1
#
#   ################################################
#   # Build 32-bit version
#   ################################################
#
#
#   local vkcapture32_env=(
#     PKG_CONFIG_PATH="$HOME/.local/lib64/pkgconfig:$HOME/.local/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig"
#     CFLAGS="-m32 -I$HOME/.local/include -I$HOME/.local/include/obs -Wno-error"
#     CXXFLAGS="-m32 -I$HOME/.local/include -I$HOME/.local/include/obs -Wno-error"
#     LDFLAGS="-m32"
#   )
#
#   local vkcapture32_cmake_flags=(
#     -DCMAKE_BUILD_TYPE=Release
#     -DCMAKE_INSTALL_PREFIX="$HOME/.local"
#     -DCMAKE_INSTALL_LIBDIR=lib
#   )
#
#   run_in_dir "$VKCAPTURE_BUILD32" run_cmd \
#     "Configuring linux-vkcapture (32-bit)" "$log" \
#     env "${vkcapture32_env[@]}" \
#     cmake "$VKCAPTURE_SRC" "${vkcapture32_cmake_flags[@]}" \
#       || { warn "linux-vkcapture 32-bit configure failed"; return 1; }
#
# #   run_in_dir "$VKCAPTURE_BUILD32" run_cmd \
# #     "Building linux-vkcapture (32-bit)" "$log" \
# #     cmake --build . -j"$(nproc)" \
# #       || { warn "linux-vkcapture 32-bit build failed"; return 1; }
#
#   run_in_dir "$VKCAPTURE_BUILD32" run_cmd \
#   "Building linux-vkcapture helper targets (32-bit)" "$log" \
#   cmake --build . -j"$(nproc)" --target obs_glcapture VkLayer_obs_vkcapture \
#     || { warn "linux-vkcapture 32-bit helper build failed"; return 1; }
#
#
#   info "Installing linux-vkcapture helper artifacts (32-bit)"
#
#   mkdir -p \
#     "$BUILD_DIR/vkcapture-stage/usr/local/lib" \
#     "$BUILD_DIR/vkcapture-stage/usr/local/lib32"
#
#   cp -av "$VKCAPTURE_BUILD32/libobs_glcapture.so" \
#     "$BUILD_DIR/vkcapture-stage/usr/local/lib/" >> "$log" 2>&1 || true
#
#   cp -av "$VKCAPTURE_BUILD32/libVkLayer_obs_vkcapture.so" \
#     "$BUILD_DIR/vkcapture-stage/usr/local/lib/" >> "$log" 2>&1 || true
#
# #   run_in_dir "$VKCAPTURE_BUILD32" run_cmd \
# #     "Installing linux-vkcapture helper artifacts (32-bit)" "$log" \
# #     env DESTDIR="$BUILD_DIR/vkcapture-stage" cmake --install . \
# #       || { warn "linux-vkcapture 32-bit install failed"; return 1; }
#
#   ################################################
#   # Export both architectures
#   ################################################
#
#   mkdir -p \
#     "$HOME/.local/bin" \
#     "$HOME/.local/lib" \
#     "$HOME/.local/lib64" \
#     "$HOME/.local/share/vulkan/implicit_layer.d"
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/bin/obs-gamecapture" \
#     "$HOME/.local/bin/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/bin/obs-vkcapture" \
#     "$HOME/.local/bin/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/bin/obs-glcapture" \
#     "$HOME/.local/bin/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/lib64/libVkLayer_obs_vkcapture.so" \
#     "$HOME/.local/lib64/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/lib/libVkLayer_obs_vkcapture.so" \
#     "$HOME/.local/lib/" >> "$log" 2>&1 || true
#
#   cp -av "$BUILD_DIR/vkcapture-stage/usr/local/share/vulkan/implicit_layer.d/"*.json \
#     "$HOME/.local/share/vulkan/implicit_layer.d/" >> "$log" 2>&1 || true
#
#   ok "linux-vkcapture plugin installed into $HOME/.local"
# }


build_app_audio_capture_plugin() {
  feature_to_bool "$ENABLE_APP_AUDIO_PLUGIN" || return 0
  local log="$APP_AUDIO_BUILD_LOG"
  : > "$log"
  info "STEP 7b: Building PipeWire application-audio plugin..."
  clone_or_update_repo obs-pipewire-audio-capture https://github.com/dimtpap/obs-pipewire-audio-capture.git || { warn "obs-pipewire-audio-capture repo update failed"; return 1; }
  rm -rf "$APP_AUDIO_BUILD"
  mkdir -p "$APP_AUDIO_BUILD"
  run_in_dir "$APP_AUDIO_BUILD" run_cmd "Configuring obs-pipewire-audio-capture" "$log"     env PKG_CONFIG_PATH="$HOME/.local/lib/pkgconfig:$HOME/.local/lib64/pkgconfig:$DEPS_PREFIX/lib/pkgconfig:/usr/local/lib64/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib64/pkgconfig:/usr/share/pkgconfig:${PKG_CONFIG_PATH:-}"     cmake "$APP_AUDIO_SRC"       -DCMAKE_BUILD_TYPE=Release       -DCMAKE_INSTALL_PREFIX=/usr/local       -DCMAKE_PREFIX_PATH="$HOME/.local;$DEPS_PREFIX;/usr/local;/usr"       -DCMAKE_LIBRARY_PATH="$HOME/.local/lib;$HOME/.local/lib64;$DEPS_PREFIX/lib;/usr/local/lib64;/usr/local/lib;/usr/lib64"       -DCMAKE_INCLUDE_PATH="$HOME/.local/include;$DEPS_PREFIX/include;/usr/local/include;/usr/include" || { warn "obs-pipewire-audio-capture configure failed"; return 1; }
  run_in_dir "$APP_AUDIO_BUILD" run_cmd "Building obs-pipewire-audio-capture" "$log" cmake --build . -j"$(nproc)" || { warn "obs-pipewire-audio-capture build failed"; return 1; }
  run_in_dir "$APP_AUDIO_BUILD" run_cmd "Installing obs-pipewire-audio-capture" "$log" env DESTDIR="$BUILD_DIR/app-audio-stage" cmake --install . || { warn "obs-pipewire-audio-capture install failed"; return 1; }
  local so_name
  so_name="$(find "$BUILD_DIR/app-audio-stage/usr/local/lib64/obs-plugins" -maxdepth 1 -name '*.so' -printf '%f
' | head -n1)"
  local data_name
  data_name="$(find "$BUILD_DIR/app-audio-stage/usr/local/share/obs/obs-plugins" -mindepth 1 -maxdepth 1 -type d -printf '%f
' | head -n1)"
  if [[ -z "$so_name" ]]; then
    warn "obs-pipewire-audio-capture built, but no plugin .so was found"
    return 1
  fi
  install_plugin_payload "$so_name" "$data_name" "$BUILD_DIR/app-audio-stage/usr/local/lib64/obs-plugins" "$BUILD_DIR/app-audio-stage/usr/local/share/obs/obs-plugins"
  if verify_plugin_file "$HOME/.local/lib64/obs-plugins/$so_name" && verify_plugin_deps "$HOME/.local/lib64/obs-plugins/$so_name"; then
    ok "obs-pipewire-audio-capture plugin installed into $HOME/.local"
  else
    warn "obs-pipewire-audio-capture installed, but verification failed; see $log"
    return 1
  fi
}

create_capture_wrappers() {
  mkdir -p "$HOME/.local/bin"

  if [[ -x /usr/bin/obs-gamecapture || -x /usr/bin/obs-vkcapture || -x /usr/bin/obs-glcapture ]]; then
    warn "Host-installed obs-vkcapture helpers detected in /usr/bin; OBSBuilder will use ~/.local/bin versions."
  fi

  cat > "$HOME/.local/bin/obs-gamecapture-run" <<'EOF'
#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"
exec "$HOME/.local/bin/obs-gamecapture" "$@"
EOF
  chmod +x "$HOME/.local/bin/obs-gamecapture-run"

  if [[ -x "$HOME/.local/bin/osu-wine" ]]; then
    cat > "$HOME/.local/bin/osu-wine-capture" <<'EOF'
#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"
exec "$HOME/.local/bin/obs-gamecapture" "$HOME/.local/bin/osu-wine" "$@"
EOF
    chmod +x "$HOME/.local/bin/osu-wine-capture"
  fi
}

#############################
# Step 7: Post-install verification   #
#######################################
verify_install() {
  : > "$VERIFY_LOG"
  {
    echo "Verification timestamp: $(date)"
    echo
    echo "=== Binary checks ==="
    command -v "$HOME/.local/bin/obs" || true
    command -v "$DEPS_PREFIX/bin/ffmpeg" || true
    command -v "$HOME/.local/bin/obs-gamecapture" || true
    command -v "$HOME/.local/bin/obs-gamecapture-run" || true
    command -v "$HOME/.local/bin/osu-wine-capture" || true
    echo
    echo "=== Version checks ==="
    "$DEPS_PREFIX/bin/ffmpeg" -version 2>/dev/null | head -n 1 || true
    PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig" pkg-config --modversion libavcodec 2>/dev/null || true
    PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig" pkg-config --modversion libavformat 2>/dev/null || true
    echo
    echo "=== Header checks ==="
    ls "$DEPS_PREFIX/include/libavcodec/avcodec.h" 2>/dev/null || true
    ls "$DEPS_PREFIX/include/libavformat/avformat.h" 2>/dev/null || true
    ls /usr/include/jansson.h 2>/dev/null || true
    echo
    echo "=== OBS runtime checks ==="
    ls "$HOME/.local/bin/obs" 2>/dev/null || true
    ls "$HOME/.local/lib"/libobs*.so* 2>/dev/null || ls "$HOME/.local/lib64"/libobs*.so* 2>/dev/null || true
    echo
    echo "=== Plugin checks ==="
    ls "$HOME/.local/lib64/obs-plugins" 2>/dev/null || true
    ls "$HOME/.local/share/obs/obs-plugins" 2>/dev/null || true
    for plugin in "$HOME/.local/lib64/obs-plugins/linux-vkcapture.so" "$HOME/.local/lib64/obs-plugins/linux-pipewire-audio.so"; do
      if [[ -f "$plugin" ]]; then
        echo "--- ldd for $plugin ---"
        ldd "$plugin" 2>/dev/null || true
      fi
    done
  } >> "$VERIFY_LOG" 2>&1
  info "Verification written to: $VERIFY_LOG"
}

#############################
# Step 8: Execute the build #
#############################
main() {
  info "OBS Build Script v10.0.1"
  handle_uninstall_mode
  resolve_feature_defaults
  build_package_sets
  if [[ "$REBUILD" -eq 1 ]]; then
    info "Rebuild requested; removing previous local install and build directories..."
    uninstall_obs_files
    uninstall_build_dirs
  fi
  bootstrap_into_distrobox_if_needed || return 1
  prepare_directories
  install_required_packages || return 1

  info "STEP 3: Cloning or updating repositories..."
  info "[1/4] Syncing x264 repository..."
  clone_or_update_repo x264 "${REPOS[x264]}" || mark_failed x264 "repo update failed"
  info "[2/4] Syncing x265 repository..."
  clone_or_update_repo x265 "${REPOS[x265]}" || mark_failed x265 "repo update failed"
  info "[3/4] Syncing FFmpeg repository..."
  clone_or_update_repo ffmpeg "${REPOS[ffmpeg]}" || mark_failed ffmpeg "repo update failed"
  info "[4/4] Syncing OBS Studio repository..."
  clone_or_update_repo obs-studio "${REPOS[obs-studio]}" || mark_failed obs-studio "repo update failed"

  info "STEP 4: Building x264..."
  if [[ "${STATUS[x264]}" == "FAILED" ]]; then
    warn "Skipping x264 build due to earlier repo failure."
  elif should_skip x264; then
    mark_skipped x264 "Already installed in $DEPS_PREFIX"
  else
    build_x264 || true
  fi

  info "STEP 5: Building x265..."
  if [[ "${STATUS[x265]}" == "FAILED" ]]; then
    warn "Skipping x265 build due to earlier repo failure."
  elif should_skip x265; then
    mark_skipped x265 "Already installed in $DEPS_PREFIX"
  else
    build_x265 || true
  fi

  info "STEP 6: Building FFmpeg..."
  if [[ "${STATUS[x264]}" == "FAILED" || "${STATUS[x265]}" == "FAILED" || "${STATUS[ffmpeg]}" == "FAILED" ]]; then
    mark_failed ffmpeg "dependency or repo failure"
  elif should_skip ffmpeg; then
    mark_skipped ffmpeg "Already installed in $DEPS_PREFIX"
  else
    build_ffmpeg || true
  fi

  info "STEP 7: Building OBS Studio..."
  if [[ "${STATUS[ffmpeg]}" == "FAILED" || "${STATUS[obs-studio]}" == "FAILED" ]]; then
    mark_failed obs-studio "dependency or repo failure"
  elif should_skip obs-studio; then
    mark_skipped obs-studio "Already installed in $HOME/.local"
  else
    build_obs || true
  fi

  if [[ "$BUILD_FAILED" -eq 1 ]]; then
    warn "One or more builds failed."
    return 1
  fi

  info "OBS built successfully."
  ensure_obs_local_lib_symlinks


  info "OBS frontend API library detected:"
  ls -l "$HOME/.local/lib64/libobs-frontend-api.so" 2>/dev/null || true
  ls -l /usr/local/lib64/libobs-frontend-api.so 2>/dev/null || true

  build_linux_vkcapture_plugin || true
  build_app_audio_capture_plugin || true
  create_capture_wrappers

  info "STEP 8: Build completed successfully."
  if inside_container; then
    info "Refreshing linker cache inside container..."
    run_cmd "Refreshing linker cache (ldconfig)" "$MASTER_LOG" ldconfig || warn "ldconfig returned a non-zero status."
  else
    info "Running sudo ldconfig..."
    run_cmd "Refreshing linker cache (sudo ldconfig)" "$MASTER_LOG" sudo ldconfig || warn "ldconfig returned a non-zero status."
  fi

  info "STEP 9: Verifying installed binaries and libraries..."
  verify_install

  ok "OBS may now be available as: $HOME/.local/bin/obs"
  return 0
}

main
