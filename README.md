# OBS Builder

Automated build system for OBS Studio with:

- linux-vkcapture plugin
- PipeWire application audio capture
- Distrobox container environment
- Wayland + NVIDIA support
- optional X11 Twitch docks launcher

## Usage

```bash
./obs-build-engine-v10.0.2.sh \
  --rebuild \
  --enable-vkcapture-plugin \
  --enable-app-audio-plugin \
  --verbose
