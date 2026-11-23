import QtQuick

// Popup text: plain, in the bar's font and colour, elided. dim darkens it for
// secondary lines.
Text {
  required property Theme theme
  property real dim: 1

  textFormat: Text.PlainText
  color: dim === 1 ? theme.foreground : Qt.darker(theme.foreground, dim)
  font.family: theme.fontFamily
  font.pixelSize: theme.body
  elide: Text.ElideRight
}
