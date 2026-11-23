pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Glyphs.js" as Glyphs
import "../lib/MediaModel.js" as MediaModel

// Every source with a track, in a fixed order, so a row never moves under the
// pointer; ▶/❚❚ and the highlight show the state instead. A click on a row
// shows that source, playback unchanged. Its ▶ plays it and pauses the
// others; its ❚❚ just pauses it.
Column {
  id: list

  required property Theme theme
  required property var strings
  required property var players
  required property string activeKey

  signal showRequested(string key)
  signal toggleRequested(string key)

  spacing: Style.space(4)

  Repeater {
    model: list.players

    BorderSurface {
      id: row

      required property var modelData
      readonly property string key: MediaModel.playerKey(modelData)
      readonly property bool selected: key === list.activeKey
      readonly property bool playing: !!modelData.isPlaying
      readonly property string appName: modelData.identity || MediaModel.playerAppLabel(modelData) || ""

      width: list.width
      height: inner.implicitHeight + Style.space(10)
      radius: Style.cornerRadius
      color: selected ? Style.selectedFillFor(list.theme.foreground, list.theme.accent) : "transparent"
      borderSpec: selected ? Border.controlSpec("normal", list.theme.foreground, list.theme.accent) : Border.none()

      Row {
        id: inner
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: row.borderLeft + Style.space(8)
        anchors.rightMargin: row.borderRight + Style.space(8)
        spacing: Style.space(8)

        Item {
          id: playButton
          width: Style.space(22)
          height: width
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius   // square unless the theme rounds corners
            color: list.theme.foreground
            opacity: mouse.overPlay ? 0.15 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
          }

          Label {
            theme: list.theme
            anchors.centerIn: parent
            text: row.playing ? Glyphs.PAUSE : Glyphs.PLAY
            elide: Text.ElideNone
          }

          PanelToolTip {
            visible: mouse.overPlay
            text: list.strings.t(row.playing ? "media.pause" : "media.play")
          }
        }

        Column {
          width: parent.width - playButton.width - parent.spacing
          spacing: Style.space(1)
          anchors.verticalCenter: parent.verticalCenter

          Label {
            theme: list.theme
            width: parent.width
            text: row.modelData.trackTitle || row.appName || list.strings.t("media.mediaSource")
            font.pixelSize: list.theme.bodySmall
            font.bold: row.selected
          }

          Label {
            theme: list.theme
            width: parent.width
            dim: 1.5
            text: [row.modelData.trackArtist, row.appName].filter(function(part) { return !!part }).join("  ·  ")
            font.pixelSize: list.theme.caption
            visible: text !== ""
          }
        }
      }

      // One area for the whole row, so the play button and the rest share
      // one hover and one cursor.
      MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        readonly property bool overPlay: containsMouse && playButton.contains(mapToItem(playButton, mouseX, mouseY))
        onClicked: function(event) {
          if (playButton.contains(mapToItem(playButton, event.x, event.y))) list.toggleRequested(row.key)
          else list.showRequested(row.key)
        }
      }
    }
  }
}
