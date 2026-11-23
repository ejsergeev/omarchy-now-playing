.pragma library

// What the plugin knows about MPRIS players, as pure functions: which player
// is playing, which one to show, and in what order sources are listed.
// Service.qml binds to these; tests/ runs them in Node. Streams.js matches
// PipeWire streams to players, Actions.js runs actions on them.
//
// A "key" is a player's D-Bus name (playerKey): stable while the player
// lives, unique between players.

var MPRIS_PREFIX = /^org\.mpris\.MediaPlayer2\./

// ── players ────────────────────────────────────────────────────────────────

function isProxyPlayer(player) {
  var dbusName = String(player && player.dbusName || "").toLowerCase()
  var desktopEntry = String(player && player.desktopEntry || "").toLowerCase()
  return dbusName.indexOf("playerctld") !== -1 || desktopEntry === "playerctld"
}

function hasMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.identity || player.desktopEntry))
}

function hasTrackMetadata(player) {
  return !!(player && (player.trackTitle || player.trackArtist || player.trackAlbum || player.trackArtUrl))
}

// What the bar needs before it shows a player at all.
function hasShownTrack(player) {
  return !!(player && (player.trackTitle || player.trackArtist))
}

function playerCanControl(player) {
  return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause || player.canGoNext || player.canGoPrevious))
}

function canCycleSource(player) {
  return !!(player && hasMetadata(player) && (player.isPlaying || player.canPlay))
}

function playerKey(player) {
  return player ? String(player.dbusName || player.desktopEntry || player.identity || "") : ""
}

// The players by key, for constant-time lookups.
function indexByKey(players) {
  var index = {}
  for (var i = 0; i < players.length; i++) {
    var key = playerKey(players[i])
    if (key) index[key] = players[i]
  }
  return index
}

// The app behind a player: its desktop entry, its name, else its D-Bus name
// without the MPRIS prefix and instance suffix.
function playerAppLabel(player) {
  if (!player) return ""
  return player.desktopEntry || player.identity
    || String(player.dbusName || "").replace(MPRIS_PREFIX, "").replace(/\.instance[0-9]+$/, "")
}

function labelFor(player) {
  return player ? player.trackTitle || player.identity || player.desktopEntry || "" : ""
}

// The site a browser player is showing, from its xesam:url.
function sourceHost(player) {
  var url = String(player && player.metadata && player.metadata["xesam:url"] || "")
  var match = url.match(/^https?:\/\/(?:www\.)?([^\/:?#]+)/)
  return match ? match[1] : ""
}

// Names an app's icon may be filed under, best first: the desktop entry's
// icon (desktopIcon, looked up by the caller), the desktop entry, the D-Bus
// name, and the identity as an icon name. Chromium has no desktop entry over
// MPRIS, so the later ones matter.
function iconNames(player, desktopIcon) {
  if (!player) return []
  var names = []
  function add(name) {
    name = String(name || "").trim()
    if (name && names.indexOf(name) === -1) names.push(name)
  }
  if (player.desktopEntry) {
    add(desktopIcon)
    add(player.desktopEntry)
  }
  var bus = String(player.dbusName || "").replace(MPRIS_PREFIX, "").replace(/\.instance[0-9_]+$/, "")
  add(bus)
  add(bus.toLowerCase())
  add(String(player.identity || "").toLowerCase().replace(/\s+/g, "-"))
  return names
}

function trackSignature(player) {
  if (!player) return ""
  return [player.trackTitle || "", player.trackArtist || "", player.trackAlbum || "", player.trackArtUrl || ""].join("\u001f")
}

function trackChanged(previousSignature, player) {
  return trackSignature(player) !== String(previousSignature || "")
}

// ── which player ───────────────────────────────────────────────────────────

// When each playing player started, as a serial: a player keeps its number
// while it plays and loses it when it stops. Returns the new order, the next
// serial, and the keys of every live player.
function playOrder(players, previous, serial) {
  var order = {}
  var alive = {}
  for (var i = 0; i < players.length; i++) {
    var key = playerKey(players[i])
    if (!key) continue
    alive[key] = true
    if (players[i].isPlaying) order[key] = previous[key] !== undefined ? previous[key] : ++serial
  }
  return { order: order, serial: serial, alive: alive }
}

function orderOf(order, player, fallback) {
  var value = order[playerKey(player)]
  return value === undefined ? fallback : value
}

// The player that has played longest: one with a playback stream first (it
// is actually sounding), a real player before a proxy (playerctld), in one
// pass over the players.
function playingPlayer(players, order, streams) {
  var best = [null, null, null, null]   // stream+real, stream+proxy, real, proxy
  var bestOrder = [0, 0, 0, 0]
  for (var i = 0; i < players.length; i++) {
    var p = players[i]
    if (!p || !p.isPlaying) continue
    var rank = orderOf(order, p, i + 1000)
    var proxy = isProxyPlayer(p) ? 1 : 0
    var slots = streams[playerKey(p)] ? [proxy, 2 + proxy] : [2 + proxy]
    for (var s = 0; s < slots.length; s++) {
      if (!best[slots[s]] || rank < bestOrder[slots[s]]) {
        best[slots[s]] = p
        bestOrder[slots[s]] = rank
      }
    }
  }
  return best[0] || best[1] || best[2] || best[3]
}

// A selection slot keeps its first player unless that one would hide the bar
// and this one would not.
function prefersShown(current, candidate) {
  return !current || (!hasShownTrack(current) && hasShownTrack(candidate))
}

// The player to show when nothing is playing. One the bar would hide, like an
// idle browser holding art-only metadata, loses to one it would show, unless
// it is the player the user last chose.
function idlePlayer(players, preferred, hasPlaybackStream) {
  var slots = {}
  for (var i = 0; i < players.length; i++) {
    var p = players[i]
    if (!p) continue
    var bucket = hasPlaybackStream(p) ? "stream"
      : hasTrackMetadata(p) ? "track"
      : playerCanControl(p) ? "controllable"
      : hasMetadata(p) ? "identity"
      : ""
    if (!bucket) continue
    var slot = bucket + (isProxyPlayer(p) ? "Proxy" : "Player")
    if (prefersShown(slots[slot], p)) slots[slot] = p
  }

  var streamPreferred = preferred && hasPlaybackStream(preferred) ? preferred : null
  var candidates = [streamPreferred, slots.streamPlayer, slots.streamProxy, preferred, slots.trackPlayer, slots.trackProxy,
    slots.controllablePlayer, slots.controllableProxy, slots.identityPlayer, slots.identityProxy]
  var fallback = null
  for (var j = 0; j < candidates.length; j++) {
    var candidate = candidates[j]
    if (!candidate) continue
    if (candidate === preferred || hasShownTrack(candidate)) return candidate
    if (!fallback) fallback = candidate
  }
  return fallback
}

// The player the popup shows. s: { players, byKey, streams, playing,
// preferredKey, pinnedKey, lastPlayingKey, held }. The user's pick wins while it
// plays, or while pinned with a track; then what plays; then what played
// last; then the best idle player.
function activePlayer(s) {
  // A source between tracks (s.held, by key) still counts as having one: a
  // skip on YouTube Music reports Stopped with no metadata for a moment, and
  // the popup must not wander off to another source meanwhile.
  function hasTrack(player, key) { return hasShownTrack(player) || !!(s.held && s.held[key]) }

  var preferred = s.byKey[s.preferredKey] || null
  if (preferred && !hasMetadata(preferred)) preferred = null
  if (preferred && (preferred.isPlaying || (s.held && s.held[s.preferredKey])
      || (s.preferredKey === s.pinnedKey && hasShownTrack(preferred)))) return preferred
  if (s.playing) return s.playing
  var last = s.byKey[s.lastPlayingKey]
  if (last && hasTrack(last, s.lastPlayingKey)) return last
  return idlePlayer(s.players, preferred, function(p) { return !!s.streams[playerKey(p)] })
}

// Rows of the popup's source list: players with a track, or between tracks
// (held: their keys), in a fixed order (by app, then key) so a row never
// moves under the pointer when its source starts, stops or skips.
function sourceRows(players, held) {
  var rows = []
  for (var i = 0; i < players.length; i++) {
    var p = players[i]
    if (hasShownTrack(p) || (held && held[playerKey(p)]))
      rows.push({ player: p, label: String(p.identity || playerAppLabel(p) || "").toLowerCase(), key: playerKey(p) })
  }
  rows.sort(function(a, b) { return a.label.localeCompare(b.label) || a.key.localeCompare(b.key) })
  return rows.map(function(row) { return row.player })
}

// What the source keys cycle through: real players before proxies, by label.
function cycleOrder(players) {
  var rows = []
  for (var i = 0; i < players.length; i++)
    if (canCycleSource(players[i])) rows.push({ player: players[i], proxy: isProxyPlayer(players[i]), label: labelFor(players[i]) })
  rows.sort(function(a, b) { return (a.proxy - b.proxy) || a.label.localeCompare(b.label) })
  return rows.map(function(row) { return row.player })
}

// The player at offset delta from current in list, wrapping around.
function cycle(list, current, delta) {
  if (!list.length) return null
  var key = playerKey(current)
  var index = 0
  for (var i = 0; i < list.length; i++) {
    if (playerKey(list[i]) === key) {
      index = i
      break
    }
  }
  return list[(index + delta + list.length) % list.length]
}
