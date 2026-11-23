#!/bin/sh
# Compiles shaders/*.frag to the .qsb files Qt Quick loads (qsb, from the
# qt6-shadertools package; only needed when a shader changes).
#   tools/build-shaders.sh           rebuild every .qsb
#   tools/build-shaders.sh --check   fail if a committed .qsb is out of date
set -u
cd "$(dirname "$0")/.." || exit 1
QSB=${QSB:-/usr/lib/qt6/bin/qsb}
[ -x "$QSB" ] || QSB=$(command -v qsb) || { echo "qsb not found (pacman -S qt6-shadertools)" >&2; exit 2; }
status=0
for src in shaders/*.frag; do
  out="$src.qsb"
  if [ "${1:-}" = "--check" ]; then
    tmp=$(mktemp) || exit 1
    "$QSB" --qt6 -o "$tmp" "$src" >/dev/null || status=1
    if ! cmp -s "$tmp" "$out"; then
      echo "$out is out of date: run tools/build-shaders.sh"
      status=1
    fi
    rm -f "$tmp"
  else
    "$QSB" --qt6 -o "$out" "$src" || status=1
  fi
done
exit $status
