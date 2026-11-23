.pragma library
.import "MediaModel.js" as MediaModel

// What the media actions do: which player an action goes to, what it runs on
// that player, and what the OSD says about it.

function canHandleAction(player, action) {
  if (!player) return false
  if (action === "next") return !!player.canGoNext
  if (action === "previous") return !!player.canGoPrevious
  if (action === "play") return !!(player.canPlay || player.canTogglePlaying)
  if (action === "pause") return !!(player.canPause || player.canTogglePlaying)
  if (action === "playPause") return !!(player.canTogglePlaying || player.canPlay || player.canPause)
  return false
}

// The player a global action goes to. s: { byKey, playing, control, active,
// players, order }. A targeted player first; pausing goes to what plays; then
// the control player, the shown one, and any that can, playing ones first.
function actionPlayer(s, action, targetKey) {
  var targeted = s.byKey[targetKey]
  if (targeted) return targeted
  if ((action === "pause" || action === "playPause") && s.playing) return s.playing
  if (canHandleAction(s.control, action)) return s.control
  if (canHandleAction(s.active, action)) return s.active

  var rows = []
  for (var i = 0; i < s.players.length; i++) {
    var p = s.players[i]
    if (!MediaModel.hasMetadata(p) || !canHandleAction(p, action)) continue
    rows.push({
      player: p,
      playing: p.isPlaying ? 0 : 1,
      proxy: MediaModel.isProxyPlayer(p) ? 1 : 0,
      order: p.isPlaying ? MediaModel.orderOf(s.order, p, 1000) : 0,
      label: MediaModel.labelFor(p),
    })
  }
  rows.sort(function(a, b) { return (a.playing - b.playing) || (a.proxy - b.proxy) || (a.order - b.order) || a.label.localeCompare(b.label) })
  return rows.length ? rows[0].player : s.active
}

var FEEDBACK = {
  next: { label: "media.next", icon: "media-next" },
  previous: { label: "media.previous", icon: "media-previous" },
  play: { label: "media.play", icon: "media-play" },
  pause: { label: "media.pause", icon: "media-pause" },
}

// The OSD label key and icon for an action, decided before it runs.
function actionFeedback(action, player) {
  if (action === "playPause") return FEEDBACK[player && player.isPlaying ? "pause" : "play"]
  return FEEDBACK[action] || { label: "media.playPause", icon: "media" }
}

function invoke(allowed, player, method) {
  if (!allowed) return false
  player[method]()
  return true
}

// Runs an action on a player as far as it allows: a player that cannot play
// or pause on its own is toggled instead. Returns whether anything ran.
function performAction(player, action) {
  if (!player) return false
  var playing = !!player.isPlaying
  if (action === "next") return invoke(player.canGoNext, player, "next")
  if (action === "previous") return invoke(player.canGoPrevious, player, "previous")
  if (action === "play")
    return invoke(player.canPlay, player, "play") || invoke(player.canTogglePlaying && !playing, player, "togglePlaying")
  if (action === "pause")
    return invoke(player.canPause, player, "pause") || invoke(player.canTogglePlaying && playing, player, "togglePlaying")
  if (action === "playPause")
    return invoke(playing && player.canPause, player, "pause")
      || invoke(!playing && player.canPlay, player, "play")
      || invoke(player.canTogglePlaying, player, "togglePlaying")
  return false
}

function osdMessage(player, fallback) {
  if (!player) return fallback
  var label = MediaModel.labelFor(player)
  if (label && player.trackArtist) return label + " - " + player.trackArtist
  return label || fallback
}
