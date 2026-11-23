#!/bin/sh
# Usage: raise-player.sh BUS_NAME [TRACK_TITLE] [SITE_HOST]
# Focuses the window of an MPRIS player that cannot raise itself (Chromium).
# Among the player process's windows it prefers the one whose title contains
# the track title, then one whose class names the site (web apps such as
# chrome-music.youtube.com__-Default), then any of them.
bus="$1"; title="$2"; host="$3"
pid=$(busctl --user call org.freedesktop.DBus / org.freedesktop.DBus \
  GetConnectionUnixProcessID s "$bus" 2>/dev/null | awk '{print $2}')
clients=$(hyprctl clients -j 2>/dev/null) || exit 1
addr=$(printf '%s' "$clients" | jq -r --arg pid "$pid" --arg title "$title" --arg host "$host" '
  [ .[] | select($pid != "" and (.pid | tostring) == $pid) ] as $own
  | if ($own | length) > 0 then $own else . end as $pool
  | ( [ $pool[] | select(($own | length) > 0 and $title != "" and (.title | contains($title))) ]
    + [ $pool[] | select($host != "" and ((.class + " " + .initialClass) | contains($host))) ]
    + (if ($own | length) > 0 then $own else [] end) )
  | first | .address // empty')
[ -n "$addr" ] || exit 1
# Lua-config Hyprland first (as Omarchy's own scripts do), classic syntax as fallback.
hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null 2>&1 || \
  hyprctl dispatch focuswindow "address:$addr" >/dev/null
