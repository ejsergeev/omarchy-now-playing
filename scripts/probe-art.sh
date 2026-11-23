#!/bin/sh
# Usage: probe-art.sh ART_FILE ICON_NAME...
# Prints how far the art is from the player's own app icon, as ImageMagick's
# RMSE distortion (0 is identical); lib/TrackHold.js decides what is close
# enough to be the placeholder Chromium serves as "art" between tracks.
# Prints nothing when it cannot tell: no ImageMagick, no icon, an unreadable
# file.
art=$1
shift
command -v magick >/dev/null 2>&1 || exit 0
# shellcheck source=scripts/icons.sh
. "${0%/*}/icons.sh"
icon=$(find_icon "$@") || exit 0
magick "$art[0]" -background none "$icon[0]" -resize '64x64!' -alpha on \
  -metric RMSE -compare -format '%[distortion]\n' info: 2>/dev/null
exit 0
