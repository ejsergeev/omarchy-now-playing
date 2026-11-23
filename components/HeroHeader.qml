import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Glyphs.js" as Glyphs

// The popup's head, as in the audio panel: the shown source's state, the
// title and a playful status, and the source app's icon on the trailing edge,
// which names the app and site on hover and brings its window forward on
// click.
Item {
  id: hero

  required property Theme theme
  required property bool playing
  required property string title
  required property string status
  required property string iconSource
  required property string sourceName
  required property string openHint   // tooltip over the app icon

  signal raiseRequested()

  implicitHeight: Math.max(glyph.implicitHeight, labels.implicitHeight)

  Label {
    id: glyph
    theme: hero.theme
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: hero.playing ? Glyphs.PLAY : Glyphs.PAUSE
    font.pixelSize: hero.theme.display
    elide: Text.ElideNone
  }

  // Secondary to the title, like the dimmed status line; full on hover.
  Item {
    id: appIcon
    width: Style.space(28)
    height: width
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: hero.iconSource !== "" || hero.sourceName !== ""
    opacity: iconMouse.containsMouse ? 1.0 : 0.55
    Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

    Image {
      id: iconImage
      anchors.fill: parent
      source: hero.iconSource
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      fillMode: Image.PreserveAspectFit
      visible: status === Image.Ready
    }

    // No icon: the app's initial in a tinted square.
    Rectangle {
      anchors.fill: parent
      visible: !iconImage.visible
      radius: Style.cornerRadius
      color: Qt.rgba(hero.theme.accent.r, hero.theme.accent.g, hero.theme.accent.b, 0.15)

      Label {
        theme: hero.theme
        anchors.centerIn: parent
        text: hero.sourceName.charAt(0).toUpperCase()
        color: hero.theme.accent
        font.bold: true
      }
    }

    MouseArea {
      id: iconMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: hero.raiseRequested()
    }

    PanelToolTip {
      visible: iconMouse.containsMouse && text !== ""
      text: hero.openHint
    }
  }

  Column {
    id: labels
    anchors.left: glyph.right
    anchors.leftMargin: Style.space(14)
    anchors.right: appIcon.visible ? appIcon.left : parent.right
    anchors.rightMargin: appIcon.visible ? Style.space(12) : 0
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Label {
      theme: hero.theme
      width: parent.width
      text: hero.title
      font.pixelSize: hero.theme.title
      font.bold: true
    }

    Label {
      theme: hero.theme
      width: parent.width
      dim: 1.4
      text: hero.status.toUpperCase()
      font.pixelSize: hero.theme.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
  }
}
