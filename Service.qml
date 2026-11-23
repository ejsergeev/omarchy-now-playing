pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Commons
import "components"
import "lib/Display.js" as Display
import "lib/Actions.js" as Actions
import "lib/CoverStyle.js" as CoverStyle
import "lib/MediaModel.js" as MediaModel
import "lib/Streams.js" as Streams

// The plugin's state, one per shell and shared by the bar on every monitor:
// which player plays and which one the popup shows (lib/MediaModel.js), the
// track held steady for display with its cover and app icon, the shown
// player's volume, and the `media` IPC target the media keys reach.
Item {
  id: root

  property var shell: null   // set by the host

  readonly property Translations strings: Translations { directory: Qt.resolvedUrl("i18n") }
  readonly property Metrics metrics: Metrics {}
  readonly property Preferences preferences: Preferences {}

  // ── players and streams ─────────────────────────────────────────────────

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var playersByKey: MediaModel.indexByKey(players)
  readonly property var playbackStreams: Streams.playbackStreams(Pipewire.nodes ? Pipewire.nodes.values : [])
  readonly property var streamsByPlayer: Streams.streamsByPlayer(players, playbackStreams)

  PwObjectTracker { objects: root.playbackStreams }

  // ── which player ────────────────────────────────────────────────────────

  // The player picked last: in the source list, by Tab, or by acting on it.
  property string preferredPlayerKey: ""
  // A player picked in the popup stays shown while paused, until it closes.
  property string pinnedPlayerKey: ""
  // The source that played last, for the bar and the keys when nothing plays.
  property string lastPlayingKey: ""
  property var playOrder: ({})
  property int playSerial: 0

  // What is actually sounding. The bar button follows it, so looking at a
  // paused source in the popup never changes the button.
  readonly property var playingPlayer: MediaModel.playingPlayer(players, playOrder, streamsByPlayer)
  // What the popup shows.
  readonly property var activePlayer: MediaModel.activePlayer({
    players: players, byKey: playersByKey, streams: streamsByPlayer, playing: playingPlayer,
    preferredKey: preferredPlayerKey, pinnedKey: pinnedPlayerKey, lastPlayingKey: lastPlayingKey, held: heldSources,
  })
  readonly property string activeKey: MediaModel.playerKey(activePlayer)
  // What the bar button and the global keys act on: what plays, else what
  // played last, never a source only looked at in the popup.
  readonly property var controlPlayer: playingPlayer || playersByKey[lastPlayingKey] || activePlayer
  // The popup's source list, in a fixed order. Sources between tracks keep
  // their row under the track they showed last: key -> { title, artist }.
  property var heldSources: ({})
  readonly property var sourcePlayers: MediaModel.sourceRows(players, heldSources)

  onPlayingPlayerChanged: if (playingPlayer && !MediaModel.isProxyPlayer(playingPlayer)) lastPlayingKey = MediaModel.playerKey(playingPlayer)
  onPlayersChanged: syncPlayOrder()
  Component.onCompleted: syncPlayOrder()

  function syncPlayOrder() {
    var next = MediaModel.playOrder(players, playOrder, playSerial)
    if (preferredPlayerKey && !next.alive[preferredPlayerKey]) preferredPlayerKey = ""
    if (pinnedPlayerKey && !next.alive[pinnedPlayerKey]) pinnedPlayerKey = ""
    playSerial = next.serial
    playOrder = next.order
  }

  Instantiator {
    model: root.players
    delegate: SourceWatch {
      id: watch
      onPlayingChanged: root.playStateChanged(watch.modelData)
      onHeld: function(key, track) { root.holdSource(key, track) }
      onReleased: function(key) { root.releaseSource(key) }
    }
  }

  function holdSource(key, track) {
    var next = Object.assign({}, heldSources)
    next[key] = track
    heldSources = next
  }

  function releaseSource(key) {
    if (!(key in heldSources)) return
    var next = Object.assign({}, heldSources)
    delete next[key]
    heldSources = next
  }

  function playStateChanged(player) {
    syncPlayOrder()
    // A skip on a paused source started it: the others pause, as with play.
    if (skipWatch.running && player.isPlaying && MediaModel.playerKey(player) === skipWatch.key) pauseOthers(skipWatch.key)
  }

  // ── what the popup shows ────────────────────────────────────────────────

  readonly property var iconNames: MediaModel.iconNames(activePlayer, desktopIcon(activePlayer))
  readonly property string sourceName: Display.capitalize(activePlayer ? activePlayer.identity || MediaModel.playerAppLabel(activePlayer) : "")
  readonly property string sourceHost: MediaModel.sourceHost(activePlayer)
  readonly property color iconColor: Color.bar.text

  readonly property TrackDisplay display: TrackDisplay {
    player: root.activePlayer
    playersByKey: root.playersByKey
    iconNames: root.iconNames
    probeScript: root.scriptPath("probe-art.sh")
    metrics: root.metrics
  }

  readonly property AppIcon appIcon: AppIcon {
    names: root.iconNames
    color: root.iconColor
    script: root.scriptPath("app-icon.sh")
    metrics: root.metrics
  }

  function desktopIcon(player) {
    var entry = player ? player.desktopEntry : ""
    if (!entry) return ""
    var found = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(entry) : DesktopEntries.byId(entry)
    return found ? found.icon : ""
  }

  function scriptPath(name) {
    return Display.localPath(Qt.resolvedUrl("scripts/" + name))
  }

  // ── volume of the shown player ──────────────────────────────────────────

  readonly property PlayerVolume volume: PlayerVolume {
    player: root.activePlayer
    streams: root.streamsByPlayer[root.activeKey] || []
  }

  // ── popup actions ───────────────────────────────────────────────────────

  // The popup closed: next time it opens on what is playing.
  function clearPin() {
    pinnedPlayerKey = ""
  }

  // Shows a player in the popup, playback unchanged.
  function selectPlayer(key) {
    if (!MediaModel.hasShownTrack(playersByKey[key])) return false
    preferredPlayerKey = key
    pinnedPlayerKey = key
    return true
  }

  // An explicit pick shows at once, without the hold for player switches.
  function showSource(key) {
    display.explicit = true
    if (selectPlayer(key)) display.refresh()
    else display.explicit = false
  }

  function cycleSource(direction) {
    if (sourcePlayers.length > 1) showSource(MediaModel.playerKey(MediaModel.cycle(sourcePlayers, activePlayer, direction)))
  }

  // ▶ plays a source and pauses every other one, so only one sounds at a
  // time; ❚❚ just pauses it.
  function toggleSource(key) {
    var player = playersByKey[key]
    if (!player) return
    if (player.isPlaying) {
      runAction("pause", false, key)
      return
    }
    display.explicit = true
    if (!playExclusive(key)) display.explicit = false
  }

  function playExclusive(key) {
    var player = playersByKey[key]
    if (!player || !(player.isPlaying || Actions.performAction(player, "play"))) return false
    pauseOthers(key)
    selectPlayer(key)
    return true
  }

  function pauseOthers(key) {
    for (var i = 0; i < players.length; i++) {
      var other = players[i]
      // A proxy (playerctld) forwards to real players: pausing it could pause
      // the source just started.
      if (other && other.isPlaying && MediaModel.playerKey(other) !== key && !MediaModel.isProxyPlayer(other))
        Actions.performAction(other, "pause")
    }
  }

  // Previous or next on the shown source. Many players start playing when
  // the track changes; if this one does soon, the other sources pause, as
  // with play. A proxy forwards to a real player the "others" would include,
  // so skips on it never pause anything.
  function skipTrack(action) {
    if (!activePlayer) return
    if (activePlayer.isPlaying || MediaModel.isProxyPlayer(activePlayer)) {
      skipWatch.stop()
    } else {
      skipWatch.key = activeKey
      skipWatch.restart()
    }
    runAction(action, false, activeKey)
  }

  Timer {
    id: skipWatch
    property string key: ""
    interval: 2500
  }

  // A click on the cover: the next way to show covers, kept for all sources.
  function cycleCoverStyle() {
    preferences.setCoverStyle(CoverStyle.next(preferences.coverStyle))
  }

  function toggleShuffle() {
    if (activePlayer && activePlayer.shuffleSupported) activePlayer.shuffle = !activePlayer.shuffle
  }

  function cycleRepeat() {
    if (activePlayer && activePlayer.loopSupported)
      activePlayer.loopState = Display.nextLoopState(activePlayer.loopState, MprisLoopState.None, MprisLoopState.Playlist, MprisLoopState.Track)
  }

  // Brings the shown source's window forward: MPRIS Raise when the player
  // can, else raise-player.sh finds its Hyprland window.
  function raisePlayer() {
    if (!activePlayer) return
    if (activePlayer.canRaise) activePlayer.raise()
    else raiser.run(null, ["sh", scriptPath("raise-player.sh"), String(activePlayer.dbusName || ""), String(activePlayer.trackTitle || ""), sourceHost])
  }

  readonly property ScriptRunner raiser: ScriptRunner { metrics: root.metrics }

  // ── global actions ──────────────────────────────────────────────────────

  function runAction(action, showFeedback, targetKey) {
    var player = Actions.actionPlayer({
      players: players, byKey: playersByKey, playing: playingPlayer, control: controlPlayer, active: activePlayer, order: playOrder,
    }, action, targetKey)
    var key = MediaModel.playerKey(player)
    var feedback = Actions.actionFeedback(action, player)
    var before = MediaModel.trackSignature(player)
    var handled = Actions.performAction(player, action)
    // An action on another source (a row, the bar button) doesn't move the
    // popup off a source the user picked.
    if (handled && key && (!pinnedPlayerKey || pinnedPlayerKey === key)) preferredPlayerKey = key
    if (showFeedback && handled && (action === "next" || action === "previous"))
      osd.showAfterTrackChange(strings.t(feedback.label), feedback.icon, player, before)
    else if (showFeedback)
      osd.showSoon(strings.t(feedback.label), feedback.icon, player)
    return handled
  }

  // The source keys: the next or previous source by name. transferPlayback
  // also moves playback to it.
  function switchSource(delta, transferPlayback) {
    var list = MediaModel.cycleOrder(players)
    if (!list.length) return false
    var next = MediaModel.cycle(list, activePlayer, delta)
    var nextKey = MediaModel.playerKey(next)
    var current = transferPlayback && playingPlayer ? playingPlayer : activePlayer
    var moving = transferPlayback && current && current.isPlaying && MediaModel.playerKey(current) !== nextKey

    preferredPlayerKey = nextKey
    // With the popup closed there is no pin: the next play, next or previous
    // key goes to this source instead.
    if (!next.isPlaying) lastPlayingKey = nextKey
    if (moving && (next.isPlaying || Actions.performAction(next, "play"))) Actions.performAction(current, "pause")

    osd.showSoon(strings.t("media.source"), "media-source", next)
    return true
  }

  readonly property MediaOsd osd: MediaOsd {
    shell: root.shell
    playersByKey: root.playersByKey
    fallbackPlayer: root.activePlayer
  }

  // ── IPC ─────────────────────────────────────────────────────────────────

  // Asks the bar widgets to add what they count with addWidgetMetrics(). A
  // signal argument would reach them as a copy, so they report back instead.
  signal metricsRequested()
  property var widgetMetrics: []

  function addWidgetMetrics(entry) {
    widgetMetrics.push(entry)
  }

  function statusJson() {
    var p = controlPlayer
    return JSON.stringify({
      hasPlayer: p !== null,
      hasMedia: MediaModel.hasShownTrack(p),
      playing: !!(p && p.isPlaying),
      identity: p ? p.identity || "" : "",
      desktopEntry: p ? p.desktopEntry || "" : "",
      title: p ? p.trackTitle || "" : "",
      artist: p ? p.trackArtist || "" : "",
      album: p ? p.trackAlbum || "" : "",
      artUrl: p ? p.trackArtUrl || "" : "",
      canGoNext: !!(p && p.canGoNext),
      canGoPrevious: !!(p && p.canGoPrevious),
      canTogglePlaying: !!(p && p.canTogglePlaying),
    })
  }

  function metricsJson() {
    widgetMetrics = []
    metricsRequested()
    return metrics.report({ players: players.length, playbackStreams: playbackStreams.length, coverStyle: preferences.coverStyle,
      shown: { key: display.shownKey, title: display.title, hasMedia: display.hasMedia }, widgets: widgetMetrics })
  }

  ShellIpc {
    target: "media"

    function status(): string { return root.statusJson() }
    function playPause(): string { return root.runAction("playPause", true, "") ? "ok" : "unhandled" }
    function next(): string { return root.runAction("next", true, "") ? "ok" : "unhandled" }
    function previous(): string { return root.runAction("previous", true, "") ? "ok" : "unhandled" }
    function play(): string { return root.runAction("play", true, "") ? "ok" : "unhandled" }
    function pause(): string { return root.runAction("pause", true, "") ? "ok" : "unhandled" }
    function sourceNext(): string { return root.switchSource(1, false) ? "ok" : "unhandled" }
    function sourcePrevious(): string { return root.switchSource(-1, false) ? "ok" : "unhandled" }
    function sourceSwitch(): string { return root.switchSource(1, true) ? "ok" : "unhandled" }
    function sourceSwitchPrevious(): string { return root.switchSource(-1, true) ? "ok" : "unhandled" }
    function ping(): string { return "ok" }
    // Development: docs/METRICS.md.
    function metrics(): string { return root.metricsJson() }
  }
}
