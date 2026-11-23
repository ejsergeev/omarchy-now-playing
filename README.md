# Now Playing — Omarchy bar plugin

A macOS-style "Now Playing" button for the Omarchy shell bar, cloned from the
stock `omarchy.media` plugin.

- Single icon in the bar: ▶ while playing, ❚❚ while paused
- Left click: play / pause
- Right click: details popup
  - source app and site (e.g. `Chromium · youtube.com`)
  - artwork, title, artist, album
  - seek bar with elapsed / remaining time
  - shuffle, previous, play/pause, next, repeat
  - per-app volume (PipeWire stream) with mute
  - list of other MPRIS sources

## Install

```bash
git clone <this repo> ~/Work/personal/omarchy-media-plugin
ln -s ~/Work/personal/omarchy-media-plugin ~/.config/omarchy/plugins/evgenii.media
omarchy bar put evgenii.media --before omarchy.audio
omarchy restart shell
```

Disable the stock widget if it is on the bar: remove `omarchy.media` from the
bar layout in `~/.config/omarchy/shell.json`.
