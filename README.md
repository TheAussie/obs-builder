# OBS Builder

Automated build system for OBS Studio with:

- linux-vkcapture plugin
- PipeWire application audio capture
- Distrobox container environment
- Wayland + NVIDIA support
- optional X11 Twitch docks launcher

## Usage

```bash
Usage: obs-build-engine.sh [options]

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

