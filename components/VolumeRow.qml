import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Display.js" as Display

// The shown player's own volume: the speaker glyph (click mutes), a slider
// and the percentage.
Item {
  id: row

  required property Theme theme
  required property var strings
  required property real volume   // 0..1
  required property bool muted
  required property bool canMute

  signal volumeMoved(real value)
  signal toggleMute()

  height: Math.max(slider.implicitHeight, speaker.implicitHeight)
  opacity: enabled ? 1 : 0.35

  // Flush with the cover's left edge.
  Label {
    id: speaker
    theme: row.theme
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(20)
    text: Display.volumeGlyph(row.volume, row.muted)
    opacity: speakerMouse.containsMouse ? 1.0 : 0.75
    font.pixelSize: row.theme.icon
    elide: Text.ElideNone

    MouseArea {
      id: speakerMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      enabled: row.canMute
      cursorShape: Qt.PointingHandCursor
      onClicked: row.toggleMute()
    }

    PanelToolTip {
      visible: speakerMouse.containsMouse
      text: row.strings.t(row.muted ? "media.unmute" : "media.mute")
    }
  }

  PanelSlider {
    id: slider
    bar: row.theme.bar
    anchors.left: speaker.right
    anchors.leftMargin: Style.space(8) - knobSize / 2
    anchors.right: percent.left
    anchors.rightMargin: Style.space(8) - knobSize / 2
    anchors.verticalCenter: parent.verticalCenter
    minimum: 0
    maximum: 1
    step: 0.05
    value: row.volume
    opacity: row.muted ? 0.5 : 1.0
    onMoved: function(v) { row.volumeMoved(v) }
    onRightClicked: row.toggleMute()
  }

  Label {
    id: percent
    theme: row.theme
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(34)
    horizontalAlignment: Text.AlignRight
    dim: 1.4
    text: I18n.formatNumber(Math.round((slider.dragging ? slider.liveValue : row.volume) * 100)) + "%"
    font.pixelSize: row.theme.caption
    font.features: { "tnum": 1 }
    elide: Text.ElideNone
  }
}
