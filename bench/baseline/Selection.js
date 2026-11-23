.pragma library
.import "MediaModel.js" as MediaModel

// Version 1.0.0's selection pass, frozen for the P3 baseline: what the QML
// engine re-evaluated in Service.qml and BarWidget.qml whenever a player or a
// PipeWire node changed. The functions are copied as they were, with the
// QML properties they read passed in as `s` (the service's state).

function playbackStreams(nodes) {
  var list = []
  for (var i = 0; i < nodes.length; i++) {
    var n = nodes[i]
    if (n && n.isStream && MediaModel.isPlaybackStream(n) && n.audio) list.push(n)
  }
  return list
}

function playerHasPlaybackStream(s, player) {
  return MediaModel.playerHasPlaybackStream(player, s.playbackStreams)
}

function playerForKey(s, key) {
  if (!key) return null
  for (var i = 0; i < s.players.length; i++) {
    var p = s.players[i]
    if (MediaModel.playerKey(p) === key) return p
  }
  return null
}

function playerOrder(s, player, fallback) {
  var key = MediaModel.playerKey(player)
  var value = key ? s.playerStartedAt[key] : undefined
  return value === undefined ? fallback : value
}

function orderedSourcePlayers(s) {
  var list = []
  for (var i = 0; i < s.players.length; i++) {
    var p = s.players[i]
    if (MediaModel.hasMetadata(p)) list.push(p)
  }
  list.sort(function(a, b) {
    if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
    if (MediaModel.isProxyPlayer(a) !== MediaModel.isProxyPlayer(b)) return MediaModel.isProxyPlayer(a) ? 1 : -1
    if (a.isPlaying && b.isPlaying) {
      var orderDelta = playerOrder(s, a, 1000) - playerOrder(s, b, 1000)
      if (orderDelta !== 0) return orderDelta
    }
    return MediaModel.labelFor(a).localeCompare(MediaModel.labelFor(b))
  })
  return list
}

function orderedCycleSourcePlayers(s) {
  var list = []
  for (var i = 0; i < s.players.length; i++) {
    var p = s.players[i]
    if (MediaModel.canCycleSource(p)) list.push(p)
  }
  list.sort(function(a, b) {
    if (MediaModel.isProxyPlayer(a) !== MediaModel.isProxyPlayer(b)) return MediaModel.isProxyPlayer(a) ? 1 : -1
    return MediaModel.labelFor(a).localeCompare(MediaModel.labelFor(b))
  })
  return list
}

function oldestPlayingPlayer(s, requirePlaybackStream) {
  var oldest = null
  var oldestOrder = 0
  var playingProxy = null
  var proxyOrder = 0
  for (var i = 0; i < s.players.length; i++) {
    var p = s.players[i]
    if (!p) continue
    var proxyPlayer = MediaModel.isProxyPlayer(p)
    if (p.isPlaying) {
      if (requirePlaybackStream && !playerHasPlaybackStream(s, p)) continue
      var order = playerOrder(s, p, i + 1000)
      if (!proxyPlayer && (!oldest || order < oldestOrder)) {
        oldest = p
        oldestOrder = order
      } else if (proxyPlayer && (!playingProxy || order < proxyOrder)) {
        playingProxy = p
        proxyOrder = order
      }
    }
  }
  return oldest || playingProxy || null
}

function selectActivePlayer(s) {
  var preferred = null
  for (var i = 0; i < s.players.length; i++) {
    var p = s.players[i]
    if (p && s.preferredPlayerKey && MediaModel.playerKey(p) === s.preferredPlayerKey && MediaModel.hasMetadata(p)) preferred = p
  }
  var pinnedWithTrack = preferred && MediaModel.playerKey(preferred) === s.pinnedPlayerKey && (preferred.trackTitle || preferred.trackArtist)
  if (preferred && (preferred.isPlaying || pinnedWithTrack)) return preferred
  var last = playerForKey(s, s.lastPlayingKey)
  return oldestPlayingPlayer(s, true) || oldestPlayingPlayer(s, false)
    || (last && (last.trackTitle || last.trackArtist) ? last : null)
    || MediaModel.idlePlayer(s.players, preferred, function(p) { return playerHasPlaybackStream(s, p) })
}

// BarWidget.qml's sourcePlayers and playerStreams.
function widgetSourcePlayers(s, sourcePlayers) {
  var list = sourcePlayers.filter(function(p) { return !!(p && (p.trackTitle || p.trackArtist)) })
  function label(p) { return String(p.identity || MediaModel.playerAppLabel(p) || "").toLowerCase() }
  list.sort(function(a, b) {
    var d = label(a).localeCompare(label(b))
    return d !== 0 ? d : MediaModel.playerKey(a).localeCompare(MediaModel.playerKey(b))
  })
  return list
}

function widgetPlayerStreams(s, activePlayer) {
  if (!activePlayer) return []
  var key = MediaModel.streamLabelKey(MediaModel.playerAppLabel(activePlayer))
  if (!key) return []
  var out = []
  var streams = s.playbackStreams
  for (var i = 0; i < streams.length; i++) {
    var sk = MediaModel.streamLabelKey(MediaModel.rawStreamLabel(streams[i]))
    if (sk && (sk === key || sk.indexOf(key) !== -1 || key.indexOf(sk) !== -1)) out.push(streams[i])
  }
  return out
}

// One full pass: every binding above, as the engine re-evaluated them.
function selectionPass(s) {
  s.playbackStreams = playbackStreams(s.nodes)
  var sourcePlayers = orderedSourcePlayers(s)
  orderedCycleSourcePlayers(s)
  var activePlayer = selectActivePlayer(s)
  var playingPlayer = oldestPlayingPlayer(s, true) || oldestPlayingPlayer(s, false)
  var controlPlayer = playingPlayer || playerForKey(s, s.lastPlayingKey) || activePlayer
  widgetSourcePlayers(s, sourcePlayers)
  widgetPlayerStreams(s, activePlayer)
  return { activePlayer: activePlayer, playingPlayer: playingPlayer, controlPlayer: controlPlayer }
}
