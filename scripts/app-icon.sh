#!/bin/sh
# Usage: app-icon.sh COLOR ICON_NAME...
# Prints the path of a normalised, single-colour version of the app's icon:
# trimmed to its content and centred in a square, so every app's icon reads
# at the same size; brightness becomes opacity, so an icon drawn on a dark
# plate (cliamp's equaliser) keeps its artwork and loses the plate; painted
# in COLOR (the theme foreground). Cached per icon file, mtime and colour.
color=$1
shift
# shellcheck source=scripts/icons.sh
. "${0%/*}/icons.sh"
src=$(find_icon "$@") || exit 1
cache=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-now-playing/icons
[ -d "$cache" ] || mkdir -p "$cache" || exit 1
# v4: bump when the pipeline below or the key changes, so old icons are redone.
sum=$(printf 'v4|%s|%s|%s' "$src" "$(stat -c %Y "$src" 2>/dev/null)" "$color" | cksum)
out="$cache/${sum%% *}-${sum##* }.png"
if [ ! -s "$out" ]; then
  tmp="$out.$$.png"
  # brightness x alpha -> opacity (drops dark plates and their borders),
  # painted in COLOR, then trimmed to what is left and centred in a square.
  magick -background none "$src[0]" -resize 256x256 -gravity center -extent 256x256 \
    \( -clone 0 -alpha extract \) \
    \( -clone 0 -background black -alpha remove -colorspace gray -level 30%,92% \) \
    \( -clone 1 -clone 2 -compose multiply -composite -auto-level \) \
    -delete 0-2 \
    \( -size 256x256 xc:"$color" \) +swap -alpha off -compose copyopacity -composite \
    -compose over -trim +repage -resize 120x120 -background none -gravity center -extent 128x128 \
    "$tmp" 2>/dev/null || { rm -f "$tmp"; exit 1; }
  # A dark icon has nothing left after the brightness mask: use its shape
  # (alpha only) instead.
  if [ "$(magick "$tmp" -format '%[fx:maxima.a>0.2]' info: 2>/dev/null)" != "1" ]; then
    magick -background none "$src[0]" -resize 256x256 -gravity center -extent 256x256 \
      \( -clone 0 -alpha extract \) -delete 0 \
      \( -size 256x256 xc:"$color" \) +swap -alpha off -compose copyopacity -composite \
      -compose over -trim +repage -resize 120x120 -background none -gravity center -extent 128x128 \
      "$tmp" 2>/dev/null || { rm -f "$tmp"; exit 1; }
  fi
  mv "$tmp" "$out"
fi
printf '%s\n' "$out"
