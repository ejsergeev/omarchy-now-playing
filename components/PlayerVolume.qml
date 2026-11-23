import QtQuick

// The shown player's own volume, through its PipeWire streams, so browsers
// work too: their MPRIS volume is reported but never applied. A player
// without a stream falls back to MPRIS. System volume is left alone.
QtObject {
  id: volume

  required property var player
  required property var streams   // the player's playback streams

  readonly property var stream: streams.length ? streams[0] : null
  readonly property bool available: stream !== null || (!!player && player.volumeSupported && player.canControl)
  readonly property bool canMute: stream !== null
  readonly property real level: stream ? stream.audio.volume : player && player.volumeSupported ? player.volume : 0
  readonly property bool muted: !!stream && stream.audio.muted

  function set(value) {
    var v = Math.max(0, Math.min(1, value))
    if (stream) {
      for (var i = 0; i < streams.length; i++) {
        var audio = streams[i].audio
        if (audio.muted && v > 0) audio.muted = false
        audio.volume = v
      }
    } else if (player && player.volumeSupported) {
      player.volume = v
    }
  }

  function toggleMute() {
    if (!stream) return
    var mute = !stream.audio.muted
    for (var i = 0; i < streams.length; i++) streams[i].audio.muted = mute
  }
}
