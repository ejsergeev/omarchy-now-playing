# Shared by the plugin's scripts; sourced, not run.

# find_icon NAME... prints the first icon file found for the names: a
# hicolor app icon in the user's, XDG and Flatpak data directories (largest
# size first), else a pixmap. An absolute path is taken as it is. Fails when
# there is none. Only shell builtins: it runs on every probe.
find_icon() {
  data_dirs="${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  data_dirs="$data_dirs:$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share"
  for name in "$@"; do
    case $name in
      /*)
        if [ -f "$name" ]; then printf '%s\n' "$name"; return 0; fi
        continue
        ;;
    esac
    old_ifs=$IFS
    IFS=:
    for dir in $data_dirs; do
      IFS=$old_ifs
      for size in 512x512 256x256 192x192 128x128 scalable 96x96 64x64 48x48; do
        for ext in png svg; do
          file="$dir/icons/hicolor/$size/apps/$name.$ext"
          if [ -f "$file" ]; then printf '%s\n' "$file"; return 0; fi
        done
      done
    done
    IFS=$old_ifs
    for ext in png svg; do
      file="/usr/share/pixmaps/$name.$ext"
      if [ -f "$file" ]; then printf '%s\n' "$file"; return 0; fi
    done
  done
  return 1
}
