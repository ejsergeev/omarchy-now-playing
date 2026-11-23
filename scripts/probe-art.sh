#!/bin/sh
# Usage: probe-art.sh ART_FILE ICON_NAME...
# Finds the first icon for the given names in the usual icon locations and
# prints "placeholder" when the art is (nearly) that icon, else "art".
art="$1"; shift
. "$(dirname "$0")/icons.sh"
icon=$(find_icon "$@")
[ -z "$icon" ] && { echo art; exit 0; }
d=$(magick "$art[0]" -background none "$icon[0]" -resize 64x64! -alpha on -metric RMSE -compare -format "%[distortion]" info: 2>/dev/null)
case "$d" in
  ""|*[!0-9.e-]*) echo art ;;
  *) awk -v d="$d" "BEGIN { print (d < 0.08) ? \"placeholder\" : \"art\" }" ;;
esac
