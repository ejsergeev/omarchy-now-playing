import QtQuick
import qs.Commons
import "../lib/Spectrum.js" as Spectrum

// Shown when a track has no cover: an LED-style spectrum analyser filling the
// box (lib/Spectrum.js), shaped by the track's name and dancing while it
// plays. One Canvas draws the whole grid, once per tick.
Canvas {
  id: spectrum

  required property Theme theme
  required property string title
  required property string artist
  // Playing, popup open: the bars move. Otherwise they rest on their shape.
  required property bool playing

  readonly property bool live: playing && visible && !Style.reduceMotion
  readonly property var meter: Spectrum.create(Spectrum.BARS, Spectrum.ROWS)
  readonly property var colors: ({ foreground: theme.foreground, accent: theme.accent })
  property var geometry: null

  onTitleChanged: restart()
  onArtistChanged: restart()
  onLiveChanged: tick()
  onColorsChanged: requestPaint()
  onWidthChanged: relayout()
  onHeightChanged: relayout()
  Component.onCompleted: restart()

  function restart() {
    Spectrum.reset(meter, title, artist)
    tick()
  }

  function tick() {
    Spectrum.step(meter, live)
    requestPaint()
  }

  function relayout() {
    geometry = null
    requestPaint()
  }

  onPaint: {
    if (width <= 0 || height <= 0) return
    if (!geometry) geometry = Spectrum.geometry(meter, width, height)
    Spectrum.paint(getContext("2d"), meter, geometry, colors, Style.cornerRadius)
  }

  Timer {
    interval: Spectrum.TICK_MS
    repeat: true
    running: spectrum.live
    onTriggered: spectrum.tick()
  }
}
