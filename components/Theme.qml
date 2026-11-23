import QtQuick
import qs.Commons

// The host's look for the popup: the bar's colour and font, and the shell's
// type scale. The host hands these over as untyped objects (the bar API,
// Style.font); this is the one place that reads them, and the views get
// typed properties.
QtObject {
  required property var bar
  readonly property var scale: Style.font

  readonly property color foreground: bar.foreground
  readonly property color background: bar.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar.fontFamily
  readonly property real display: scale.display
  readonly property real title: scale.title
  readonly property real subtitle: scale.subtitle
  readonly property real body: scale.body
  readonly property real bodySmall: scale.bodySmall
  readonly property real caption: scale.caption
  readonly property real icon: scale.icon
  readonly property real iconLarge: scale.iconLarge
}
