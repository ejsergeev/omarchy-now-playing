.pragma library
.import "MediaModel.js" as MediaModel

// PipeWire playback streams and the players they belong to. A player's own
// streams carry its volume, and a player with one is actually sounding.

function nodeProps(node) {
  return node && node.ready && node.properties ? node.properties : {}
}

function isPlaybackStream(node) {
  if (!node || !node.isStream) return false
  if (node.isSink === true) return true
  var mediaClass = String(node.type || "")
  return mediaClass.indexOf("Stream/Output/Audio") !== -1
    || mediaClass.indexOf("AudioOutStream") !== -1
    || mediaClass.indexOf("Output") !== -1
}

function playbackStreams(nodes) {
  var list = []
  for (var i = 0; i < nodes.length; i++)
    if (nodes[i] && nodes[i].audio && isPlaybackStream(nodes[i])) list.push(nodes[i])
  return list
}

// A label reduced to what stream and player names share: "PipeWire ALSA
// [Spotify]" and "spotify" both become "spotify".
function streamLabelKey(label) {
  return String(label || "").toLowerCase()
    .replace(/^pipewire alsa \[/, "")
    .replace(/\]$/, "")
    .replace(/^alsa playback \[/, "")
    .replace(/[^a-z0-9]+/g, "")
}

function rawStreamLabel(node) {
  if (!node) return ""
  var p = nodeProps(node)
  return p["application.name"] || node.description || p["media.name"] || p["node.name"] || node.name
}

// Each player's playback streams, by player key; players without one are
// left out. A stream belongs to a player when either label key contains the
// other ("firefox" and "mozillafirefox"). Every label is reduced once, not
// once per player and lookup.
function streamsByPlayer(players, streams) {
  var streamKeys = []
  for (var i = 0; i < streams.length; i++) streamKeys.push(streamLabelKey(rawStreamLabel(streams[i])))

  var map = {}
  for (var j = 0; j < players.length; j++) {
    var key = MediaModel.playerKey(players[j])
    var label = streamLabelKey(MediaModel.playerAppLabel(players[j]))
    if (!key || !label) continue
    var own = []
    for (var k = 0; k < streams.length; k++) {
      var s = streamKeys[k]
      if (s && (s.indexOf(label) !== -1 || label.indexOf(s) !== -1)) own.push(streams[k])
    }
    if (own.length) map[key] = own
  }
  return map
}
