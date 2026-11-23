import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Display.js" as Display

// The shown track: its cover (or the ASCII spectrum when it has none) beside
// the title, artist and album.
Item {
  id: card

  required property Theme theme
  required property var display        // Service's TrackDisplay
  required property bool playing       // the spectrum dances
  required property string placeholder // title when nothing plays

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

    ArtView {
      id: cover
      anchors.fill: parent
      anchors.margins: Style.space(2)
      url: card.display.artUrl
      onFailed: function(url) { card.display.artFailed(url) }
    }

    Connections {
      target: card.display
      function onReloadArt(url) { cover.reload(url) }
    }

    AsciiSpectrum {
      anchors.fill: parent
      anchors.margins: Style.space(7)
      visible: !cover.showing
      theme: card.theme
      title: card.display.title
      artist: card.display.artist
      playing: card.playing
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
