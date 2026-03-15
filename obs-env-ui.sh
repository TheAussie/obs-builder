#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$SCRIPT_DIR/obs-env-core.sh"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/obs-env"
CONFIG_FILE="$CONFIG_DIR/config.sh"
STATUS_FILE="${XDG_RUNTIME_DIR:-/tmp}/obs-env-status.log"
RUN_LOG="${XDG_RUNTIME_DIR:-/tmp}/obs-env-run.log"
RUN_PID_FILE="${XDG_RUNTIME_DIR:-/tmp}/obs-env-run.pid"
mkdir -p "$CONFIG_DIR"

ACTION=""
PROFILE="custom"
BUILD_OBS=1
ENABLE_VKCAPTURE=0
ENABLE_APP_AUDIO=0
ENABLE_TWITCH_API=0
INSTALL_OSU=0
INSTALL_OTD=0
INSTALL_FLATPAK_OBS=0
VERBOSE=0
QUIET=0

cleanup_runner() {
  if [[ -f "$RUN_PID_FILE" ]]; then
    local run_pid
    run_pid="$(cat "$RUN_PID_FILE" 2>/dev/null || true)"
    if [[ -n "${run_pid:-}" ]]; then
      kill "$run_pid" 2>/dev/null || true
      wait "$run_pid" 2>/dev/null || true
    fi
    rm -f "$RUN_PID_FILE"
  fi
}
trap cleanup_runner INT TERM

load_saved_config() { [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || true; }

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

show_help() {
cat <<'EOF'
obs-env-ui.sh - OBS / Streaming Environment Setup Utility
EOF
}

profile_apply() {
  case "$PROFILE" in
    minimal) BUILD_OBS=1; ENABLE_VKCAPTURE=0; ENABLE_APP_AUDIO=0; ENABLE_TWITCH_API=0; INSTALL_OSU=0; INSTALL_OTD=0; INSTALL_FLATPAK_OBS=0 ;;
    streamer) BUILD_OBS=1; ENABLE_VKCAPTURE=1; ENABLE_APP_AUDIO=1; ENABLE_TWITCH_API=0; INSTALL_OSU=1; INSTALL_OTD=1; INSTALL_FLATPAK_OBS=0 ;;
    fallback) BUILD_OBS=0; ENABLE_VKCAPTURE=0; ENABLE_APP_AUDIO=0; ENABLE_TWITCH_API=0; INSTALL_OSU=0; INSTALL_OTD=1; INSTALL_FLATPAK_OBS=1 ;;
    custom|"") ;;
    *) echo "Unknown profile: $PROFILE" >&2; exit 1 ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build) ACTION="build" ;;
      --verify) ACTION="verify" ;;
      --remove) ACTION="remove" ;;
      --purge) ACTION="purge" ;;
      --diagnostics) ACTION="diagnostics" ;;
      --profile) PROFILE="${2:-}"; shift ;;
      --vkcapture) ENABLE_VKCAPTURE=1 ;;
      --app-audio) ENABLE_APP_AUDIO=1 ;;
      --twitch-api) ENABLE_TWITCH_API=1 ;;
      --osu) INSTALL_OSU=1 ;;
      --tablet) INSTALL_OTD=1 ;;
      --flatpak-obs) INSTALL_FLATPAK_OBS=1; BUILD_OBS=0 ;;
      -v|--verbose) VERBOSE=1 ;;
      -q|--quiet) QUIET=1 ;;
      -h|--help) show_help; exit 0 ;;
      *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
    esac
    shift
  done
}

summary_text() {
cat <<EOF
You are about to:

 • Build custom OBS:         $BUILD_OBS
 • Enable linux-vkcapture:   $ENABLE_VKCAPTURE
 • Enable app audio:         $ENABLE_APP_AUDIO
 • Enable Twitch OAuth:      $ENABLE_TWITCH_API
 • Install osu-winello:      $INSTALL_OSU
 • Install OpenTabletDriver: $INSTALL_OTD
 • Install OBS Flatpak:      $INSTALL_FLATPAK_OBS
 • Verbose output:           $VERBOSE
EOF
}

core_env_cmd() {
  env ACTION="${ACTION:-build}" PROFILE="$PROFILE" BUILD_OBS="$BUILD_OBS" ENABLE_VKCAPTURE="$ENABLE_VKCAPTURE" ENABLE_APP_AUDIO="$ENABLE_APP_AUDIO" ENABLE_TWITCH_API="$ENABLE_TWITCH_API" INSTALL_OSU="$INSTALL_OSU" INSTALL_OTD="$INSTALL_OTD" INSTALL_FLATPAK_OBS="$INSTALL_FLATPAK_OBS" VERBOSE="$VERBOSE" QUIET="$QUIET" bash "$CORE"
}

show_text_file_msgbox() {
  local file="$1"
  local title="$2"
  [[ -f "$file" ]] || printf 'No output available.
' > "$file"
  whiptail --title "$title" --textbox "$file" 24 100
}

progress_from_status() {
  local status_line="${1:-}"
  case "$status_line" in
    *"[1/4]"*) echo 25 ;;
    *"[2/4]"*) echo 50 ;;
    *"[3/4]"*) echo 75 ;;
    *"[4/4]"*) echo 90 ;;
    *"Completed."*) echo 100 ;;
    *"Removing custom OBS"*) echo 35 ;;
    *"Purging everything"*) echo 35 ;;
    *"Verifying installation"*) echo 80 ;;
    *"Environment diagnostics"*) echo 80 ;;
    *) echo 10 ;;
  esac
}

spinner_frame() {
  local n="${1:-0}"
  case $(( n % 4 )) in
    0) printf '|' ;;
    1) printf '/' ;;
    2) printf '-' ;;
    3) printf '\\' ;;
  esac
}

elapsed_hms() {
  local start_ts="$1"
  local now_ts elapsed
  now_ts="$(date +%s)"
  elapsed=$(( now_ts - start_ts ))
  printf '%02d:%02d' $(( elapsed / 60 )) $(( elapsed % 60 ))
}

current_status_line() {
  if [[ -s "$STATUS_FILE" ]]; then
    tail -n 1 "$STATUS_FILE"
  else
    case "$ACTION" in
      build) echo "Preparing build..." ;;
      remove) echo "Removing custom OBS..." ;;
      purge) echo "Purging everything..." ;;
      verify) echo "Verifying installation..." ;;
      diagnostics) echo "Running diagnostics..." ;;
      *) echo "Working..." ;;
    esac
  fi
}

start_run() {
  save_config
  : > "$RUN_LOG"
  : > "$STATUS_FILE"
  core_env_cmd >"$RUN_LOG" 2>&1 &
  echo $! > "$RUN_PID_FILE"
}

wait_for_run() {
  local run_pid
  run_pid="$(cat "$RUN_PID_FILE")"
  wait "$run_pid" || true
  rm -f "$RUN_PID_FILE"
}

run_verbose_in_ui() {
  start_run
  local start_ts frame=0 run_pid tmp status_line spin elapsed
  start_ts="$(date +%s)"
  run_pid="$(cat "$RUN_PID_FILE")"
  while kill -0 "$run_pid" 2>/dev/null; do
    status_line="$(current_status_line)"
    spin="$(spinner_frame "$frame")"
    elapsed="$(elapsed_hms "$start_ts")"
    tmp="${RUN_LOG}.tail"
    {
      echo "Action: $status_line"
      echo "Activity: $spin   Elapsed: $elapsed"
      echo
      echo "Recent log output:"
      echo "------------------"
      tail -n 40 "$RUN_LOG" 2>/dev/null || true
      echo
      echo "Press OK to refresh."
    } > "$tmp"
    whiptail --title "Live log" --textbox "$tmp" 24 100
    frame=$(( frame + 1 ))
  done
  wait_for_run
  show_text_file_msgbox "$RUN_LOG" "Final log output"
}

run_nonverbose_in_ui() {
  start_run
  local fifo="${RUN_LOG}.gauge.fifo"
  local run_pid start_ts
  rm -f "$fifo"
  mkfifo "$fifo"
  run_pid="$(cat "$RUN_PID_FILE")"
  start_ts="$(date +%s)"
  (
    local frame=0 status_line pct spin elapsed
    while kill -0 "$run_pid" 2>/dev/null; do
      status_line="$(current_status_line)"
      pct="$(progress_from_status "$status_line")"
      spin="$(spinner_frame "$frame")"
      elapsed="$(elapsed_hms "$start_ts")"
      printf '%s
XXX
%s
%s   Elapsed: %s
This step can take several minutes.
XXX
' "$pct" "$status_line" "$spin" "$elapsed"
      frame=$(( frame + 1 ))
      sleep 0.3
    done
    status_line="$(current_status_line)"
    printf '100
XXX
%s
Done. Preparing final log view.
XXX
' "$status_line"
  ) > "$fifo" &
  local feed_pid=$!
  whiptail --title "Running setup" --gauge "Starting..." 12 78 0 < "$fifo" || true
  wait "$feed_pid" 2>/dev/null || true
  wait_for_run
  rm -f "$fifo"
  show_text_file_msgbox "$RUN_LOG" "Run output"
}

run_live_action() {
  if [[ "$VERBOSE" == "1" ]]; then
    run_verbose_in_ui
  else
    run_nonverbose_in_ui
  fi
}

run_simple_action_and_show_output() {
  save_config
  : > "$RUN_LOG"
  : > "$STATUS_FILE"
  core_env_cmd >"$RUN_LOG" 2>&1 || true
  show_text_file_msgbox "$RUN_LOG" "$1"
}

show_explanations() {
  ACTION="explain"
  run_simple_action_and_show_output "Feature explanations"
}

maybe_whiptail() {
  command -v whiptail >/dev/null 2>&1 || return 1
  while true; do
    local detected="Detected environment:\n"
    [[ -f /usr/bin/ujust ]] && detected+=" • Bazzite/ublue helper: yes\n" || detected+=" • Bazzite helper: no\n"
    [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && detected+=" • Session: Wayland\n" || detected+=" • Session: ${XDG_SESSION_TYPE:-unknown}\n"
    [[ -d /dev/dri ]] && detected+=" • GPU device nodes: present\n" || detected+=" • GPU device nodes: missing\n"
    whiptail --title "Welcome" --msgbox "$detected\nRecommended profile for your setup is usually:\nStreamer" 14 72
    local action_choice
    action_choice=$(whiptail --title "OBS / Streaming Environment Setup" --menu "Choose an action" 18 78 8 "build" "Install / Update environment" "verify" "Verify installation" "remove" "Remove custom OBS" "purge" "Purge everything" "diagnostics" "Run diagnostics" "explain" "Feature explanations" "quit" "Quit" 3>&1 1>&2 2>&3) || continue
    case "$action_choice" in
      quit) return 0 ;;
      explain) show_explanations; continue ;;
      verify) ACTION="verify"; run_simple_action_and_show_output "Verification output"; continue ;;
      diagnostics) ACTION="diagnostics"; run_simple_action_and_show_output "Diagnostics output"; continue ;;
      remove) ACTION="remove"; whiptail --yesno "Proceed with remove?" 8 50 || continue; run_live_action; continue ;;
      purge) ACTION="purge"; whiptail --yesno "Proceed with purge?" 8 50 || continue; run_live_action; continue ;;
      build) ACTION="build" ;;
    esac
    local profile_choice
    profile_choice=$(whiptail --title "Select Profile" --menu "Choose a profile" 16 78 6 "minimal" "Custom OBS only" "streamer" "OBS + vkcapture + app audio + osu + tablet" "fallback" "OBS Flatpak + tablet" "custom" "Choose components manually" 3>&1 1>&2 2>&3) || continue
    PROFILE="$profile_choice"
    profile_apply
    if [[ "$PROFILE" == "custom" ]]; then
      local selected
      selected=$(whiptail --title "Components" --checklist "Space to toggle, Enter to continue" 22 92 10 "build" "Build custom OBS" $([[ "$BUILD_OBS" == "1" ]] && echo ON || echo OFF) "vkcapture" "linux-vkcapture" $([[ "$ENABLE_VKCAPTURE" == "1" ]] && echo ON || echo OFF) "appaudio" "App audio plugin" $([[ "$ENABLE_APP_AUDIO" == "1" ]] && echo ON || echo OFF) "twitch" "Twitch OAuth" $([[ "$ENABLE_TWITCH_API" == "1" ]] && echo ON || echo OFF) "osu" "osu-winello" $([[ "$INSTALL_OSU" == "1" ]] && echo ON || echo OFF) "tablet" "OpenTabletDriver" $([[ "$INSTALL_OTD" == "1" ]] && echo ON || echo OFF) "flatpak" "OBS Flatpak fallback" $([[ "$INSTALL_FLATPAK_OBS" == "1" ]] && echo ON || echo OFF) "verbose" "Verbose output" $([[ "$VERBOSE" == "1" ]] && echo ON || echo OFF) 3>&1 1>&2 2>&3) || continue
      BUILD_OBS=0; ENABLE_VKCAPTURE=0; ENABLE_APP_AUDIO=0; ENABLE_TWITCH_API=0; INSTALL_OSU=0; INSTALL_OTD=0; INSTALL_FLATPAK_OBS=0; VERBOSE=0
      for s in $selected; do
        s="${s//\"/}"
        case "$s" in
          build) BUILD_OBS=1 ;;
          vkcapture) ENABLE_VKCAPTURE=1 ;;
          appaudio) ENABLE_APP_AUDIO=1 ;;
          twitch) ENABLE_TWITCH_API=1 ;;
          osu) INSTALL_OSU=1 ;;
          tablet) INSTALL_OTD=1 ;;
          flatpak) INSTALL_FLATPAK_OBS=1 ;;
          verbose) VERBOSE=1 ;;
        esac
      done
    fi
    whiptail --title "Summary" --yesno "$(summary_text)\n\nProceed?" 18 72 || continue
    run_live_action
  done
}

menu_plain() {
  echo "Plain-text fallback not updated in this build."
  exit 1
}

main() {
  load_saved_config
  parse_args "$@"
  [[ -n "$PROFILE" && "$PROFILE" != "custom" ]] && profile_apply
  if [[ -n "$ACTION" ]]; then
    core_env_cmd
  else
    maybe_whiptail || menu_plain
  fi
}

main "$@"
