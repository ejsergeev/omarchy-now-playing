import QtQuick
import Quickshell
import "../lib/Display.js" as Display

// A player's app icon as a single-colour glyph of a fixed size
// (scripts/app-icon.sh), painted in the theme's bar colour. A result is kept
// per icon and colour, so switching between known sources runs nothing.
// Without ImageMagick, or for an icon only an icon theme has, it falls back
// to the theme's own icon, unprocessed.
QtObject {
  id: appIcon

  required property var names     // icon names to try, best first
  required property color color
  required property string script
  property Metrics metrics: null

  property string source: ""      // file:// URL or theme icon path; "" for none

  readonly property string request: names.length ? JSON.stringify([Display.imColor(color)].concat(names)) : ""
  property var resolved: ({})     // request -> source

  onRequestChanged: Qt.callLater(resolve)
  Component.onCompleted: resolve()

  function resolve() {
    if (request === "") {
      source = ""
    } else if (request in resolved) {
      source = resolved[request]
      if (metrics) metrics.count("iconCacheHits")
    } else {
      runner.run(request, ["sh", script].concat(JSON.parse(request)))
    }
  }

  function themeIcon(names) {
    for (var i = 0; i < names.length; i++) {
      var path = Quickshell.iconPath(names[i], true)
      if (path) return path
    }
    return ""
  }

  readonly property ScriptRunner runner: ScriptRunner {
    metrics: appIcon.metrics
    onFinished: function(tag, ok, output) {
      var found = ok && output ? "file://" + output : appIcon.themeIcon(JSON.parse(tag).slice(1))
      appIcon.resolved[tag] = found
      if (tag === appIcon.request) appIcon.source = found
    }
  }
}
