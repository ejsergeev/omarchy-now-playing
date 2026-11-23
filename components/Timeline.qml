import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Display.js" as Display

// The seek bar with elapsed and remaining time, in the language's numerals.
Column {
  id: timeline

  required property Theme theme
  required property real position   // seconds
  required property real length     // seconds; 0 without a timeline
  required property bool canSeek

  readonly property bool hasTimeline: length > 0
  readonly property alias dragging: slider.dragging
  readonly property real shownPosition: dragging ? slider.liveValue : position

  signal moved(real seconds)
  signal released(real seconds)

  spacing: Style.space(2)
  opacity: hasTimeline ? 1 : 0.35

  function format(seconds) {
    return hasTimeline ? Display.formatTime(seconds, I18n.formatNumber) : "--:--"
  }

  PanelSlider {
    id: slider
    bar: timeline.theme.bar
    // PanelSlider insets its track by half a knob on each side; widen it by
    // that so the track lines up with the cover and the time labels.
    x: -knobSize / 2
    width: parent.width + knobSize
    minimum: 0
    maximum: timeline.hasTimeline ? timeline.length : 1
    step: 1
    value: timeline.hasTimeline ? timeline.position : 0
    enabled: timeline.canSeek
    onMoved: function(v) { timeline.moved(v) }
    onReleased: function(v) { timeline.released(v) }
  }

  Item {
    width: parent.width
    height: elapsed.implicitHeight

    Label {
      id: elapsed
      theme: timeline.theme
      anchors.left: parent.left
      dim: 1.4
      text: timeline.format(timeline.shownPosition)
      font.pixelSize: timeline.theme.caption
      font.features: { "tnum": 1 }
      elide: Text.ElideNone
    }

    Label {
      theme: timeline.theme
      anchors.right: parent.right
      dim: 1.4
      text: timeline.hasTimeline ? "-" + timeline.format(timeline.length - timeline.shownPosition) : timeline.format(0)
      font.pixelSize: timeline.theme.caption
      font.features: { "tnum": 1 }
      elide: Text.ElideNone
    }
  }
}
