pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../lib/CoverStyle.js" as CoverStyle
import "../lib/Display.js" as Display

// The shown track: its cover beside the title, artist and album. A click on
// the cover steps through the ways to show it (lib/CoverStyle.js): as it is,
// as a duotone in the theme's colours, or as the ASCII spectrum, which is
// also what a track without a cover gets.
Item {
  id: card

  required property Theme theme
  required property var display        // Service's TrackDisplay
  required property bool playing       // the spectrum dances
  required property string placeholder // title when nothing plays
  required property string coverStyle  // lib/CoverStyle.js

  signal styleCycleRequested()

  readonly property string shown: CoverStyle.shown(coverStyle, cover.showing)

  implicitHeight: art.height

  BorderSurface {
    id: art
    width: Style.space(84)
    height: width
    anchors.left: parent.left
    anchors.top: parent.top
    radius: Style.cornerRadius
    color: Style.normalFillFor(card.theme.foreground, card.theme.accent)
    borderSpec: Border.controlSpec("normal", card.theme.foreground, card.theme.accent)

    // Hidden, not unloaded, under the spectrum, so switching back is
    // instant. The duotone layer exists only while it shows.
    ArtView {
      id: cover
      anchors.fill: parent
      anchors.margins: Style.space(2)
      url: card.display.artUrl
      opacity: card.shown === "spectrum" ? 0 : 1
      onFailed: function(url) { card.display.artFailed(url) }
      layer.enabled: card.shown === "duotone"
      layer.effect: ShaderEffect {
        readonly property color dark: card.theme.background
        readonly property color light: card.theme.foreground
        fragmentShader: Qt.resolvedUrl("../shaders/duotone.frag.qsb")
      }
    }

    Connections {
      target: card.display
      function onReloadArt(url) { cover.reload(url) }
    }

    AsciiSpectrum {
      anchors.fill: parent
      anchors.margins: Style.space(7)
      visible: card.shown === "spectrum"
      theme: card.theme
      title: card.display.title
      artist: card.display.artist
      playing: card.playing
    }

    // No cursorShape: the pointer stays as it is over the cover.
    MouseArea {
      anchors.fill: parent
      enabled: cover.showing
      onClicked: card.styleCycleRequested()
    }
  }

  Column {
    anchors.left: art.right
    anchors.leftMargin: Style.space(12)
    anchors.right: parent.right
    anchors.verticalCenter: art.verticalCenter
    spacing: Style.space(4)

    Label {
      theme: card.theme
      width: parent.width
      text: card.display.title || card.placeholder
      font.pixelSize: card.theme.subtitle
      font.bold: true
      wrapMode: Text.Wrap
      maximumLineCount: 2
    }

    Label {
      theme: card.theme
      width: parent.width
      dim: 1.25
      text: card.display.artist
      font.pixelSize: card.theme.bodySmall
      visible: text !== ""
    }

    Label {
      theme: card.theme
      width: parent.width
      dim: 1.6
      text: Display.albumText(card.display.album)
      font.pixelSize: card.theme.caption
      visible: text !== ""
    }
  }
}
