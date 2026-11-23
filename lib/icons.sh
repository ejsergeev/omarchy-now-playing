# Shared helpers for the plugin's shell scripts.

# find_icon NAME... — prints the first app icon file found for the names, in
# the user's, XDG, Flatpak and pixmaps icon locations (hicolor, largest first).
find_icon() {
  icon=""
  for name in "$@"; do
    case "$name" in
      /*) [ -f "$name" ] && icon="$name" ;;
      *)
        dirs="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
        old_ifs=$IFS; IFS=:
        for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs:$d/icons"; done
        IFS=$old_ifs
        dirs="$dirs:$HOME/.local/share/flatpak/exports/share/icons:/var/lib/flatpak/exports/share/icons"
        old_ifs=$IFS; IFS=:
        for base in $dirs; do
          IFS=$old_ifs
          for theme in hicolor; do
            for size in 512x512 256x256 192x192 128x128 scalable 96x96 64x64 48x48; do
              for ext in png svg; do
                f="$base/$theme/$size/apps/$name.$ext"
                [ -f "$f" ] && { icon="$f"; break 4; }
              done
            done
          done
        done
        [ -z "$icon" ] && for ext in png svg; do [ -f "/usr/share/pixmaps/$name.$ext" ] && { icon="/usr/share/pixmaps/$name.$ext"; break; }; done
        ;;
    esac
    [ -n "$icon" ] && break
  done
  [ -n "$icon" ] && printf '%s\n' "$icon"
}
