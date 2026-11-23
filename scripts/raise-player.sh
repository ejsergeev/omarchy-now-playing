#!/bin/sh
# Usage: raise-player.sh BUS_NAME [TRACK_TITLE] [SITE_HOST]
# Focuses the window of an MPRIS player that cannot raise itself (Chromium,
# terminal players such as cliamp). The player's windows are those of its
# process or, when it has none, of the nearest ancestor that has some: a
# terminal player's window belongs to the terminal it runs in. Among them it
# prefers the one whose title contains the track title, then one whose class
# names the site (web apps such as chrome-music.youtube.com__-Default), then
# any of them.
bus=$1
title=${2:-}
host=${3:-}
# "u 1234": the reply's type and the process id.
reply=$(busctl --user call org.freedesktop.DBus / org.freedesktop.DBus \
  GetConnectionUnixProcessID s "$bus" 2>/dev/null)
pid=${reply#* }

# The player's process and its ancestors, nearest first, as a JSON array.
# The parent is the second field after the command name, which may itself
# hold spaces and parentheses, so the split starts after its last ")".
chain=""
p=$pid
while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ -r "/proc/$p/stat" ]; do
  chain="$chain${chain:+,}$p"
  read -r stat < "/proc/$p/stat"
  # shellcheck disable=SC2086 # split the fields on purpose
  set -- ${stat##*) }
  p=$2
done

clients=$(hyprctl clients -j 2>/dev/null) || exit 1
addr=$(printf '%s' "$clients" | jq -r --argjson chain "[$chain]" --arg title "$title" --arg host "$host" '
  . as $clients
  | ([ $chain[] as $p | [ $clients[] | select(.pid == $p) ] | select(length > 0) ] | first // []) as $own
  | if ($own | length) > 0 then $own else . end as $pool
  | ( [ $pool[] | select(($own | length) > 0 and $title != "" and (.title | contains($title))) ]
    + [ $pool[] | select($host != "" and ((.class + " " + .initialClass) | contains($host))) ]
    + (if ($own | length) > 0 then $own else [] end) )
  | first | .address // empty')
[ -n "$addr" ] || exit 1
# Lua-config Hyprland first (as Omarchy's own scripts do), classic syntax as fallback.
hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null 2>&1 || \
  hyprctl dispatch focuswindow "address:$addr" >/dev/null
