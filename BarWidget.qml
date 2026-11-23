import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BarWidget {
  id: root
  // The plugin's own strings (i18n/<lang>.json), following Setup > Language live.
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // This plugin's id (manifest.json); its own Service.qml is looked up by it.
  readonly property string pluginId: "io.github.ejsergeev.now-playing"
  moduleName: pluginId

  // This plugin's own service (Service.qml), looked up by its own id.
  readonly property var mediaService: bar?.shell?.serviceFor(pluginId) ?? null
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  // The popup's source list keeps a fixed order (by app, then player id) so a
  // row never moves under the pointer when its source starts or stops; the
  // ▶/❚❚ icon and the highlight show the state instead.
  readonly property var sourcePlayers: {
    if (!mediaService) return []
    // Only sources with a track: browsers keep an empty, Stopped session
    // around after a video ends or its tab closes.
    var list = (mediaService.sourcePlayers || []).filter(function(p) {
      return !!(p && (p.trackTitle || p.trackArtist))
    })
    var svc = mediaService
    function label(p) { return String(p.identity || svc.playerAppLabel(p) || "").toLowerCase() }
    list.sort(function(a, b) {
      var d = label(a).localeCompare(label(b))
      return d !== 0 ? d : svc.playerKey(a).localeCompare(svc.playerKey(b))
    })
    return list
  }

  readonly property bool isPlaying: !!activePlayer && !!activePlayer.isPlaying
  // Shows the current state: playing, or paused.
  readonly property string playIcon: isPlaying ? "󰐊" : "󰏤"

  // The bar button reflects and controls what is really playing; the popup
  // shows and controls the selected source (activePlayer).
  // When nothing plays, it falls back to the source that played last, so a
  // second right-click resumes what the first one paused.
  readonly property var barPlayer: mediaService ? mediaService.controlPlayer : null
  readonly property bool barPlaying: !!barPlayer && !!barPlayer.isPlaying
  readonly property string barIcon: barPlaying ? "󰐊" : "󰏤"
  function actOnBar(action) {
    if (mediaService && barPlayer) mediaService.runAction(action, false, mediaService.playerKey(barPlayer))
  }

  // Displayed metadata is held, not bound. Players blank their metadata for a
  // moment between tracks; showing that would hide the button, drop the art
  // and resize the popup. Blanks only apply once they persist.
  readonly property bool liveMedia: activePlayer !== null && !!(activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string liveArtUrl: activePlayer && activePlayer.trackArtUrl ? String(activePlayer.trackArtUrl) : ""
  readonly property string metaSig: activePlayer
    ? [activePlayer.trackTitle || "", activePlayer.trackArtist || "", activePlayer.trackAlbum || "", liveArtUrl].join("\u001f")
    : ""
  property bool hasMedia: false
  property string title: ""
  property string artist: ""
  property string album: ""
  property string artUrl: ""         // art currently shown
  property string rejectedArtUrl: "" // a placeholder the player served instead of art

  property string artPlayerKey: ""   // player the shown art came from
  property string lastTrackSig: ""

  function applyMeta() {
    var p = activePlayer
    var key = p && mediaService ? mediaService.playerKey(p) : ""
    var trackSig = key + "\u001f" + (p ? (p.trackTitle || "") + "\u001f" + (p.trackArtist || "") : "")
    if (trackSig !== lastTrackSig) { lastTrackSig = trackSig; rejectedArtUrl = ""; artFailures = ({}) }
    // Another app's cover never stays on this app's track.
    if (artUrl !== "" && key !== artPlayerKey) clearArt()
    title = p ? (p.trackTitle || "") : ""
    artist = p ? (p.trackArtist || "") : ""
    album = p && p.trackAlbum ? p.trackAlbum : ""
    hasMedia = liveMedia
    if (liveArtUrl !== "") {
      if (liveArtUrl !== artUrl && liveArtUrl !== rejectedArtUrl) artProbe.check(liveArtUrl)
    } else if (!liveMedia) {
      clearArt()
    } else {
      artClearTimer.restart()
    }
  }

  property string metaPlayerKey: ""

  // Set just before the user picks a source (row, Tab): no debounce for it.
  property bool explicitSwitch: false
  function showSource(key) {
    if (!mediaService) return
    explicitSwitch = true
    if (!mediaService.selectPlayer(key)) explicitSwitch = false
    else refreshMeta()
  }

  function refreshMeta() {
    var key = activePlayer && mediaService ? mediaService.playerKey(activePlayer) : ""
    // The shown player quit (its D-Bus name is gone): nothing to wait for.
    var shownGone = metaPlayerKey !== "" && !(mediaService && mediaService.playerForKey(metaPlayerKey))
    // A switch to another player must last a moment before it shows: players
    // briefly report Stopped between tracks, and the service then flips to
    // another player and back. No player at all, or the shown one quitting,
    // applies right away.
    if (activePlayer && key !== metaPlayerKey && !shownGone && !explicitSwitch) { blankTimer.stop(); playerSwitchTimer.restart(); return }
    explicitSwitch = false
    playerSwitchTimer.stop()
    metaPlayerKey = key
    // Blank metadata from a Stopped player is a closed tab or a finished
    // video, not a skip: apply it at once. A Playing/Paused player going
    // blank is between tracks: wait that out.
    var stopped = !!activePlayer && activePlayer.playbackState === MprisPlaybackState.Stopped
    if (liveMedia || !activePlayer || shownGone || stopped) {
      blankTimer.stop()
      applyMeta()
    } else {
      blankTimer.restart()
    }
  }

  onMetaSigChanged: refreshMeta()
  readonly property int playerCount: mediaService && mediaService.players ? mediaService.players.length : 0
  onPlayerCountChanged: refreshMeta()
  onLiveMediaChanged: refreshMeta()
  Component.onCompleted: applyMeta()

  Timer { id: blankTimer; interval: 2500; onTriggered: root.applyMeta() }
  Timer {
    id: playerSwitchTimer
    interval: 400
    onTriggered: {
      root.metaPlayerKey = root.activePlayer && root.mediaService ? root.mediaService.playerKey(root.activePlayer) : ""
      blankTimer.stop()
      root.applyMeta()
    }
  }
  // A track that really has no art clears the previous one, after a grace period.
  Timer {
    id: artClearTimer
    interval: 2500
    onTriggered: if (root.liveArtUrl === "" || root.liveArtUrl === root.rejectedArtUrl) root.clearArt()
  }

  function clearArt() {
    artClearTimer.stop()
    artUrl = ""
    artSwap.show("")
  }

  function artProbed(url, isArt) {
    if (url !== liveArtUrl) return   // superseded while probing
    if (isArt) {
      artClearTimer.stop()
      rejectedArtUrl = ""
      artUrl = url
      artPlayerKey = activePlayer && mediaService ? mediaService.playerKey(activePlayer) : ""
      artSwap.show(url)
    } else {
      rejectedArtUrl = url
      artClearTimer.restart()
    }
  }

  // Called when the accepted art fails to load: show the placeholder rather
  // than the previous track's cover.
  // Browsers may announce an art file before it is fully written, so a
  // failed load is retried twice, a second apart, before it is given up on.
  property var artFailures: ({})
  function artFailed(url) {
    if (url !== artUrl) return
    var n = (artFailures[url] || 0) + 1
    artFailures[url] = n
    if (n <= 2) { artRetry.url = url; artRetry.restart(); return }
    rejectedArtUrl = url   // don't retry it on every metadata tweak; reset on track change
    artUrl = ""
    artSwap.show("")
  }

  Timer {
    id: artRetry
    property string url: ""
    interval: 1000
    onTriggered: if (url === root.artUrl && url === root.liveArtUrl) artSwap.reload(url)
  }

  // Some players (Chromium-based browsers) fill the gap between tracks with
  // their own app icon as "art". Local art files are compared with the
  // player's app icon by ImageMagick; a near-identical image is that
  // placeholder and is dropped, so the previous cover stays until the real
  // one arrives. Real art of any kind, transparent or not, is kept. Anything
  // uncertain (no ImageMagick, no icon found, unreadable file) is shown.
  readonly property var playerIconNames: {
    if (!activePlayer) return []
    var names = []
    function add(n) { n = String(n || "").trim(); if (n && names.indexOf(n) === -1) names.push(n) }
    var entry = activePlayer.desktopEntry || ""
    if (entry) {
      var de = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(entry) : DesktopEntries.byId(entry)
      if (de && de.icon) add(de.icon)
      add(entry)
    }
    var bus = String(activePlayer.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "").replace(/\.instance[0-9_]+$/, "")
    add(bus)
    add(bus.toLowerCase())
    add(String(activePlayer.identity || "").toLowerCase().replace(/\s+/g, "-"))
    return names
  }

  // probe-art.sh (next to this file) finds the player's icon and compares.
  readonly property string probeScript: {
    var u = String(Qt.resolvedUrl("probe-art.sh"))
    return u.indexOf("file://") === 0 ? decodeURIComponent(u.slice(7)) : u
  }

  property int magickState: 0   // 0 unknown, 1 available, -1 missing

  Process {
    running: true
    command: ["sh", "-c", "command -v magick >/dev/null"]
    onExited: function(code) {
      root.magickState = code === 0 ? 1 : -1
      if (artProbe.waiting !== "") { var w = artProbe.waiting; artProbe.waiting = ""; artProbe.check(w) }
    }
  }

  function localPath(u) {
    var m = String(u).match(/^file:\/\/(?:localhost)?(\/.*)$/)
    if (!m) return ""
    try { return decodeURIComponent(m[1]) } catch (e) { return "" }
  }

  QtObject {
    id: artProbe
    property string probing: ""
    property string queued: ""
    property string waiting: ""   // art seen before ImageMagick detection finished

    function check(url) {
      var u = String(url)
      if (root.magickState === 0 && root.localPath(u) !== "") { waiting = u; return }
      var path = root.magickState === 1 && root.playerIconNames.length ? root.localPath(u) : ""
      if (path === "") { root.artProbed(u, true); return }
      if (u === probing || u === queued) return
      if (probeProc.running || probing !== "" || probeProc.killing) { queued = u; return }
      probing = u
      probeProc.output = ""
      probeProc.exitCode = -1
      probeProc.outDone = false
      probeProc.gen++
      probeProc.runGen = probeProc.gen
      probeProc.command = ["sh", root.probeScript, path].concat(root.playerIconNames)
      probeProc.running = true
      probeWatchdog.restart()
    }

    function finish(exitCode, out) {
      var u = probing
      if (u === "") return
      probing = ""
      probeWatchdog.stop()
      // Only a definite "this is the app icon" answer rejects; failures show the art.
      root.artProbed(u, !(exitCode === 0 && out === "placeholder"))
      if (queued !== "") { var q = queued; queued = ""; check(q) }
    }
  }

  Process {
    id: probeProc
    property string output: ""
    property int exitCode: -1
    property bool outDone: false
    property int gen: 0      // id of the newest probe
    property int runGen: 0   // id of the probe the result belongs to
    property bool killing: false   // a timed-out probe is still exiting
    function maybeFinish() {
      if (exitCode < 0 || !outDone) return
      if (runGen !== gen) return   // a killed probe reporting late
      artProbe.finish(exitCode, String(output).trim())
    }
    property int outGen: -1   // probe generation the collected stdout belongs to
    onStarted: outGen = runGen
    stdout: StdioCollector {
      onStreamFinished: {
        if (probeProc.outGen !== probeProc.runGen) return   // a previous probe's output
        probeProc.output = text
        probeProc.outDone = true
        probeProc.maybeFinish()
      }
    }
    onExited: function(code) {
      if (killing) {
        // The killed probe is gone; the next one may start on this Process.
        killing = false
        exitCode = -1
        outDone = false
        if (artProbe.probing === "" && artProbe.queued !== "") { var q = artProbe.queued; artProbe.queued = ""; artProbe.check(q) }
        return
      }
      exitCode = code
      maybeFinish()
    }
  }

  // A probe that never reports back (failed to start, hung) shows the art.
  Timer {
    id: probeWatchdog
    interval: 5000   // a cold first ImageMagick run can take a couple of seconds
    onTriggered: {
      probeProc.gen++   // whatever the killed probe reports later is ignored
      if (probeProc.running) probeProc.killing = true
      probeProc.running = false
      artProbe.finish(-1, "")
    }
  }

  // Source details: the player app and, for browsers, the site.
  readonly property string sourceName: {
    if (!activePlayer) return ""
    var n = activePlayer.identity || (mediaService ? mediaService.playerAppLabel(activePlayer) : "") || ""
    return n.length ? n.charAt(0).toUpperCase() + n.slice(1) : ""
  }
  readonly property string sourceHost: {
    if (!activePlayer || !activePlayer.metadata) return ""
    var url = String(activePlayer.metadata["xesam:url"] || "")
    var m = url.match(/^https?:\/\/(?:www\.)?([^\/:?#]+)/)
    return m ? m[1] : ""
  }
  // The player's app icon: tries the desktop entry's icon, then names taken
  // from the D-Bus name and identity (Chromium has no desktop entry over MPRIS).
  // app-icon.sh turns it into a single-colour glyph in the theme foreground,
  // trimmed to a square, so every app's icon matches in style and size.
  property string sourceIcon: ""
  readonly property string iconRequest: playerIconNames.length && bar
    ? JSON.stringify([imColor(bar.foreground)].concat(playerIconNames)) : ""
  // ImageMagick reads #RRGGBBAA, Qt writes #AARRGGBB; pass rgba() instead.
  function imColor(c) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(3) + ")"
  }
  onIconRequestChanged: Qt.callLater(refreshSourceIcon)
  function refreshSourceIcon() {
    if (iconRequest === "") { sourceIcon = ""; return }
    if (iconProc.running) { iconProc.pending = true; return }
    iconProc.request = iconRequest
    iconProc.gen++
    iconProc.command = ["sh", appIconScript].concat(JSON.parse(iconRequest))
    iconProc.running = true
  }
  function themeIcon() {
    for (var i = 0; i < playerIconNames.length; i++) {
      var p = Quickshell.iconPath(playerIconNames[i], true)
      if (p) return p
    }
    return ""
  }
  readonly property string appIconScript: {
    var u = String(Qt.resolvedUrl("app-icon.sh"))
    return u.indexOf("file://") === 0 ? decodeURIComponent(u.slice(7)) : u
  }
  Process {
    id: iconProc
    property string request: ""
    property bool pending: false
    property int gen: 0      // newest run
    property int outGen: -1  // run whose output is being collected
    onStarted: outGen = gen
    stdout: StdioCollector {
      onStreamFinished: {
        var path = text.trim()
        if (iconProc.outGen !== iconProc.gen || iconProc.request !== root.iconRequest) return
        // No normalised icon (no ImageMagick, or the icon is only in an icon
        // theme): fall back to the theme's own icon, unprocessed.
        root.sourceIcon = path ? "file://" + path : root.themeIcon()
      }
    }
    onExited: if (pending) { pending = false; Qt.callLater(root.refreshSourceIcon) }
  }

  // Per-app volume: the player's PipeWire playback streams. Browsers expose an
  // MPRIS Volume they ignore, so the stream volume is the reliable control.
  readonly property var playerStreams: {
    if (!activePlayer || !mediaService) return []
    var key = mediaService.streamLabelKey(mediaService.playerAppLabel(activePlayer))
    if (!key) return []
    var out = []
    var streams = mediaService.playbackStreams || []
    for (var i = 0; i < streams.length; i++) {
      var sk = mediaService.streamLabelKey(mediaService.rawStreamLabel(streams[i]))
      if (sk && (sk === key || sk.indexOf(key) !== -1 || key.indexOf(sk) !== -1)) out.push(streams[i])
    }
    return out
  }
  readonly property var volumeStream: {
    for (var i = 0; i < playerStreams.length; i++)
      if (playerStreams[i] && playerStreams[i].audio) return playerStreams[i]
    return null
  }
  readonly property bool hasVolume: volumeStream !== null || (!!activePlayer && activePlayer.volumeSupported && activePlayer.canControl)
  readonly property real playerVolume: volumeStream ? volumeStream.audio.volume
    : (activePlayer && activePlayer.volumeSupported ? activePlayer.volume : 0)
  readonly property bool playerMuted: !!volumeStream && volumeStream.audio.muted

  function setPlayerVolume(v) {
    v = Math.max(0, Math.min(1, v))
    if (volumeStream) {
      for (var i = 0; i < playerStreams.length; i++) {
        var a = playerStreams[i] && playerStreams[i].audio
        if (!a) continue
        if (a.muted && v > 0) a.muted = false
        a.volume = v
      }
    } else if (activePlayer && activePlayer.volumeSupported) {
      activePlayer.volume = v
    }
  }

  function togglePlayerMute() {
    if (!volumeStream) return
    var m = !volumeStream.audio.muted
    for (var i = 0; i < playerStreams.length; i++)
      if (playerStreams[i] && playerStreams[i].audio) playerStreams[i].audio.muted = m
  }

  PwObjectTracker { objects: root.playerStreams }

  onActivePlayerChanged: {
    syncPosition()
    refreshMeta()
  }

  // Playback position. MPRIS does not push position updates, so poll while visible.
  readonly property bool hasTimeline: !!activePlayer && activePlayer.lengthSupported && activePlayer.length > 0
  readonly property bool canSeek: hasTimeline && activePlayer.canSeek && activePlayer.positionSupported
  property real position: 0
  property bool seeking: false

  function syncPosition() {
    if (!activePlayer || seeking) return
    activePlayer.positionChanged()
    position = activePlayer.positionSupported ? activePlayer.position : 0
  }

  // A playful name for where playback is, in the spirit of the audio panel's
  // volume ladder ("Steady groove", "Concert hall").
  readonly property string moodName: {
    if (!activePlayer) return strings.t("media.mood.silence")
    if (playerMuted) return strings.t("media.mood.silentDisco")
    if (!isPlaying) return strings.t("media.mood.intermission")
    if (!hasTimeline) return strings.t("media.mood.onAir")
    var len = activePlayer.length
    if (position < 10) return strings.t("media.mood.needleDrop")
    if (len - position < 15) return strings.t("media.mood.encore")
    var p = position / len
    if (p < 0.4) return strings.t("media.mood.warmingUp")
    if (p < 0.75) return strings.t("media.mood.inTheGroove")
    return strings.t("media.mood.finalChorus")
  }

  function formatTime(sec) {
    if (!isFinite(sec) || sec < 0) sec = 0
    sec = Math.floor(sec)
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60
    // Digits in the language's own numerals (Arabic, Persian, Bengali, ...).
    function n(v) { return Commons.I18n.formatNumber(v) }
    function n2(v) { return (v < 10 ? n(0) : "") + n(v) }
    return h > 0 ? n(h) + ":" + n2(m) + ":" + n2(s) : n(m) + ":" + n2(s)
  }

  function seekBy(seconds) {
    if (!canSeek) return
    var p = Math.max(0, Math.min(activePlayer.length - 1, position + seconds))
    activePlayer.position = p
    position = p
  }

  function cycleSource(direction) {
    var list = sourcePlayers
    if (!mediaService || !list || list.length < 2) return
    var cur = mediaService.playerKey(activePlayer), idx = 0
    for (var i = 0; i < list.length; i++) if (mediaService.playerKey(list[i]) === cur) idx = i
    var next = list[(idx + direction + list.length) % list.length]
    showSource(mediaService.playerKey(next))
  }

  // Letter shortcuts in the popup. Russian layout letters on the same keys
  // are accepted too.
  function handleKey(text) {
    var t = String(text).toLowerCase()
    var p = activePlayer
    if (t === "р") skipTrack("previous")                 // h
    else if (t === "д") skipTrack("next")                // l
    else if (t === "о" && hasVolume) setPlayerVolume(playerVolume - 0.05)   // j
    else if (t === "л" && hasVolume) setPlayerVolume(playerVolume + 0.05)   // k
    else if (t === "," || t === "б") seekBy(-10)
    else if (t === "." || t === "ю") seekBy(10)
    else if (t === "m" || t === "ь") togglePlayerMute()
    else if ((t === "s" || t === "ы") && p && p.shuffleSupported) p.shuffle = !p.shuffle
    else if ((t === "r" || t === "к") && p && p.loopSupported)
      p.loopState = p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
        : (p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None)
  }

  // Brings the source app's window forward: MPRIS Raise when the player
  // supports it, else raise-player.sh finds and focuses its Hyprland window.
  readonly property string raiseScript: {
    var u = String(Qt.resolvedUrl("raise-player.sh"))
    return u.indexOf("file://") === 0 ? decodeURIComponent(u.slice(7)) : u
  }

  function raisePlayer() {
    var p = activePlayer
    if (!p) return
    if (p.canRaise) p.raise()
    else {
      raiseProc.command = ["sh", raiseScript, String(p.dbusName || ""), String(p.trackTitle || ""), sourceHost]
      raiseProc.running = true
    }
    close()
  }

  Process { id: raiseProc }

  // The popup's play/pause: pausing pauses the shown source; starting it
  // pauses whatever else is playing, so only one source sounds at a time.
  function togglePlayback() {
    var p = activePlayer
    if (!p || !mediaService) return
    var key = mediaService.playerKey(p)
    if (p.isPlaying) mediaService.runAction("pause", false, key)
    else { explicitSwitch = true; if (!mediaService.playExclusive(key)) explicitSwitch = false }
  }

  // Previous / next on the shown source. Many players start playing when
  // their track changes; if this one does within a couple of seconds, the
  // other sources are paused, as with play.
  property string skipKey: ""
  function skipTrack(action) {
    if (!activePlayer || !mediaService) return
    skipKey = mediaService.playerKey(activePlayer)
    if (activePlayer.isPlaying) skipWatch.stop()   // already playing: nothing starts
    else skipWatch.restart()
    // A proxy (playerctld) forwards to a real player; "others" would include
    // the one it controls, so skips on it never pause anything.
    if (mediaService.isProxyPlayer(activePlayer)) { skipWatch.stop(); act(action); return }
    act(action)   // skipWatch pauses the others only if this skip starts playback
  }
  Timer { id: skipWatch; interval: 2500 }
  Connections {
    target: root.activePlayer
    ignoreUnknownSignals: true
    function onIsPlayingChanged() {
      if (!skipWatch.running || !root.activePlayer || !root.activePlayer.isPlaying || !root.mediaService) return
      if (root.mediaService.playerKey(root.activePlayer) === root.skipKey) root.mediaService.pauseOthers(root.skipKey)
    }
  }

  function act(action) {
    if (root.mediaService) root.mediaService.runAction(action, false, root.mediaService.playerKey(root.activePlayer))
  }

  onPopupOpenChanged: {
    syncPosition()
    // Closed: the next opening shows what is playing, not the last pick.
    if (!popupOpen && mediaService) mediaService.clearPin()
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen && root.isPlaying
    triggeredOnStart: true
    onTriggered: root.syncPosition()
  }

  Connections {
    target: root.activePlayer
    ignoreUnknownSignals: true
    function onPostTrackChanged() { root.syncPosition() }
    function onSeeked() { root.syncPosition() }
    function onIsPlayingChanged() { root.syncPosition() }
  }

  property bool popupOpen: false



  // Bar panel contract: lets `omarchy-shell shell toggle io.github.ejsergeev.now-playing`, a
  // { panel = "io.github.ejsergeev.now-playing" } keybinding and SUPER+CTRL+<n> open it.
  readonly property bool opened: popupOpen
  function open() { if (hasMedia) popupOpen = true }
  function close() { popupOpen = false }
  onHasMediaChanged: if (!hasMedia) close()

  visible: hasMedia
  implicitWidth: hasMedia ? button.implicitWidth : 0
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    tooltipText: root.barPlayer && (root.barPlayer.trackTitle || root.barPlayer.trackArtist)
      ? (String(root.barPlayer.trackTitle || "") + (root.barPlayer.trackArtist ? " — " + root.barPlayer.trackArtist : ""))
      : ""
    onPressed: function(b) {
      if (!root.activePlayer) return
      if (b === Qt.RightButton) root.actOnBar("playPause")
      else if (b === Qt.MiddleButton) root.actOnBar("next")
      else root.popupOpen = !root.popupOpen
    }
  }

  // KeyboardPanel (not PopupCard) takes keyboard focus when it opens, so
  // Escape closes it like the other bar panels.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      // Space / Enter: play-pause · ←/→ (h/l): previous / next track
      // ↑/↓ (k/j): player volume · , / . : seek -10 s / +10 s
      // m: mute · s: shuffle · r: repeat · Tab / Shift+Tab: next / previous source
      onActivateRequested: root.togglePlayback()
      onMoveRequested: function(dx, dy) {
        // The transport row is never mirrored, so undo PanelKeyCatcher's
        // right-to-left swap: ← is always previous, → next.
        var d = Commons.I18n.rightToLeft ? -dx : dx
        if (d !== 0) root.skipTrack(d > 0 ? "next" : "previous")
        else if (dy !== 0 && root.hasVolume) root.setPlayerVolume(root.playerVolume - dy * 0.05)
      }
      onTabRequested: function(direction) { root.cycleSource(direction) }
      onTextKey: function(text, modifiers) { root.handleKey(text) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        // ── Hero: source icon · title / status (as in the audio panel) ──
        Item {
          id: heroItem
          width: parent.width
          implicitHeight: Math.max(heroIconBox.height, heroLabels.implicitHeight)

          Item {
            id: heroIconBox
            // Sized to the glyph itself, as the audio panel's hero icon is, so
            // the labels sit the same 14px from it.
            width: heroGlyph.implicitWidth
            height: heroGlyph.implicitHeight
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Text {
              id: heroGlyph
              anchors.fill: parent
              textFormat: Text.PlainText
              text: root.playIcon   // the selected source's state
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          // The source app's icon on the trailing edge, where the audio panel
          // keeps its switch. Hover names the app and site.
          Item {
            id: sourceIconBox
            width: Style.space(28)
            height: width
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.sourceIcon !== "" || root.sourceName !== ""
            // Secondary to the title, like the subtitle's dimmed text; full on hover.
            opacity: sourceIconMouse.containsMouse ? 1.0 : 0.55
            Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }

            Image {
              id: sourceAppIcon
              anchors.fill: parent
              source: root.sourceIcon
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectFit
              visible: status === Image.Ready
              smooth: true
            }
            // No icon found: the app's initial in a tinted square.
            Rectangle {
              anchors.fill: parent
              visible: !sourceAppIcon.visible
              radius: Style.cornerRadius
              color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.15)
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.sourceName.charAt(0).toUpperCase()
                color: Commons.Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            MouseArea {
              id: sourceIconMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.raisePlayer()
            }
            PanelToolTip {
              visible: sourceIconMouse.containsMouse && text !== ""
              text: strings.t("media.open").arg([root.sourceName, root.sourceHost].filter(function(x) { return x !== "" }).join("  ·  "))
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIconBox.right
            anchors.leftMargin: Style.space(14)
            anchors.right: sourceIconBox.visible ? sourceIconBox.left : parent.right
            anchors.rightMargin: sourceIconBox.visible ? Style.space(12) : 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: strings.t("media.title")
              textFormat: Text.PlainText
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.moodName.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        // ── Artwork + track info ────────────────────────────────────
        Item {
          width: parent.width
          height: art.height

          BorderSurface {
            id: art
            width: Style.space(84)
            height: Style.space(84)
            anchors.left: parent.left
            anchors.top: parent.top
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.bar.foreground, Commons.Color.accent)
            borderSpec: Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent)

            // Two layers: the next cover decodes in the back one and fades in
            // over the current cover once ready, so the art never blinks.
            Item {
              id: artSwap
              anchors.fill: parent
              anchors.margins: Style.space(2)
              property bool aFront: true
              property string wanted: ""

              function setLayer(img, url) { img.key = url; img.url = url }

            // Loads url again into the back layer (after a failed load).
            function reload(url) {
              var back = aFront ? artB : artA
              var front = aFront ? artA : artB
              fade.stop()
              wanted = url
              if (front.key === url) setLayer(front, "")
              setLayer(back, "")
              back.opacity = 0
              setLayer(back, url)
              if (back.status === Image.Ready) promote()
            }

              function show(url) {
                wanted = url
                fade.stop()
                var front = aFront ? artA : artB
                var back = aFront ? artB : artA
                if (url === "") {
                  front.opacity = 0; setLayer(front, "")
                  back.opacity = 0; setLayer(back, "")
                  return
                }
                if (front.key === url) {
                  front.opacity = 1
                  back.opacity = 0; setLayer(back, "")
                  return
                }
                back.opacity = 0
                setLayer(back, url)
                if (back.status === Image.Ready) promote()
              }

              function promote() {
                var back = aFront ? artB : artA
                if (back.key !== wanted || fade.running) return
                fade.target = back
                fade.start()
              }

              // SizedImage retries some failed decodes once; give it time first.
              function failed(img) {
                if (img.key !== wanted || wanted === "") return
                failCheck.img = img
                failCheck.restart()
              }

              Timer {
                id: failCheck
                property var img: null
                interval: 500
                onTriggered: if (img && img.status === Image.Error && img.key === artSwap.wanted) root.artFailed(artSwap.wanted)
              }

              NumberAnimation {
                id: fade
                property: "opacity"
                from: 0; to: 1
                duration: Style.duration(160)
              easing.type: Easing.OutCubic
                onFinished: {
                  if (!fade.target || fade.target.key !== artSwap.wanted) return
                  var front = artSwap.aFront ? artA : artB
                  if (front === fade.target) return
                  front.opacity = 0
                  artSwap.setLayer(front, "")
                  artSwap.aFront = !artSwap.aFront
                }
              }

              SizedImage {
                id: artA
                property string key: ""   // the url as given; Qt decodes url on read
                anchors.fill: parent
                crop: true
                opacity: 0
                onStatusChanged: {
                  if (status === Image.Ready && !artSwap.aFront) artSwap.promote()
                  else if (status === Image.Error) artSwap.failed(artA)
                }
              }
              SizedImage {
                id: artB
                property string key: ""
                anchors.fill: parent
                crop: true
                opacity: 0
                onStatusChanged: {
                  if (status === Image.Ready && artSwap.aFront) artSwap.promote()
                  else if (status === Image.Error) artSwap.failed(artB)
                }
              }
            }

            // No cover: an ASCII spectrum analyser filling the box. Its shape
            // comes from the track's name, so each track gets its own; while
            // playing (and the popup is open) the bars dance with falling peak
            // caps. Shown whenever no cover layer is visible.
            Item {
              id: asciiArt
              anchors.fill: parent
              anchors.margins: Style.space(7)
              visible: artA.opacity < 0.01 && artB.opacity < 0.01
              clip: true

              // An LED-meter grid: bars of stacked cells, empty cells shown as
              // dots, sized to fill the box exactly.
              readonly property int bars: 8
              readonly property int rows: 8
              readonly property real gap: Math.max(1, Math.round(width / 40))
              readonly property real barW: (width - gap * (bars - 1)) / bars
              readonly property real cellH: (height - gap * (rows - 1)) / rows
              readonly property bool live: root.isPlaying && root.popupOpen && visible && !Style.reduceMotion
              property var levels: []   // per bar, in cells (0..rows)
              property var peaks: []
              property int tick: 0

              // Deterministic noise from the track and a step counter.
              function noise(i, t) {
                var seed = String(root.title) + "|" + String(root.artist)
                var h = 2166136261
                for (var k = 0; k < seed.length; k++) { h ^= seed.charCodeAt(k); h = Math.imul(h, 16777619) >>> 0 }
                h ^= Math.imul(i + 1, 0x9e3779b1) >>> 0
                h ^= Math.imul(t + 7, 0x85ebca6b) >>> 0
                h ^= h >>> 15; h = Math.imul(h, 0x2c1b3c6d) >>> 0; h ^= h >>> 12
                return (h >>> 0) / 4294967295
              }

              // The track's resting shape: a gentle curve plus per-bar character.
              function base(i) {
                var x = bars > 1 ? i / (bars - 1) : 0
                var curve = 0.55 + 0.35 * Math.sin(x * Math.PI * (1.2 + noise(99, 0)) + noise(98, 0) * 6)
                return Math.min(1, Math.max(0.25, curve * (0.75 + 0.45 * noise(i, 0))))
              }

              function step() {
                var next = [], nextPeaks = []
                for (var i = 0; i < bars; i++) {
                  var target = base(i) * rows
                  if (live) target *= 0.5 + 0.8 * noise(i, tick)
                  var cur = levels[i] !== undefined ? levels[i] : target
                  var v = live ? cur * 0.45 + target * 0.55 : target
                  v = Math.max(0.6, Math.min(rows, v))
                  next.push(v)
                  // Paused or closed: caps rest on the bars instead of floating.
                  var pk = live && peaks[i] !== undefined ? peaks[i] - 0.25 : v
                  nextPeaks.push(Math.max(v, pk))
                }
                levels = next
                peaks = nextPeaks
                tick++
              }

              onLiveChanged: step()
              Component.onCompleted: step()
              Connections {
                target: root
                function onTitleChanged() { asciiArt.levels = []; asciiArt.peaks = []; asciiArt.step() }
              }

              Timer {
                interval: 110
                repeat: true
                running: asciiArt.live
                onTriggered: asciiArt.step()
              }

              Repeater {
                model: asciiArt.bars
                Item {
                  id: barItem
                  required property int index
                  readonly property real level: asciiArt.levels[index] || 0
                  readonly property real peak: asciiArt.peaks[index] || 0
                  x: index * (asciiArt.barW + asciiArt.gap)
                  width: asciiArt.barW
                  height: asciiArt.height

                  Repeater {
                    model: asciiArt.rows
                    Item {
                      required property int index           // 0 = bottom row
                      readonly property real fill: Math.max(0, Math.min(1, barItem.level - index))
                      width: barItem.width
                      height: asciiArt.cellH
                      y: asciiArt.height - (index + 1) * asciiArt.cellH - index * asciiArt.gap

                      // Lit part of the cell, growing from its bottom.
                      Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.round(parent.height * parent.fill)
                        visible: parent.fill > 0.12
                        color: root.bar.foreground
                        opacity: 0.45 + 0.4 * (index / Math.max(1, asciiArt.rows - 1))
                        radius: Math.min(1, Style.cornerRadius)
                      }
                      // Unlit cell: a dot, the "·" of the ASCII version.
                      Rectangle {
                        anchors.centerIn: parent
                        width: Math.max(1, Math.round(asciiArt.gap * 1.2))
                        height: width
                        radius: Math.min(width / 2, Style.cornerRadius)
                        visible: parent.fill <= 0.12
                        color: root.bar.foreground
                        opacity: 0.25
                      }
                    }
                  }

                  // Peak cap in the accent colour, falling slowly.
                  Rectangle {
                    readonly property int cell: Math.min(asciiArt.rows, Math.ceil(barItem.peak)) - 1
                    visible: barItem.peak > Math.ceil(barItem.level) - 0.01 && cell >= Math.ceil(barItem.level)
                    width: parent.width
                    height: Math.max(2, Math.round(asciiArt.cellH * 0.3))
                    y: asciiArt.height - (cell + 1) * asciiArt.cellH - cell * asciiArt.gap
                    color: Commons.Color.accent
                    radius: Math.min(1, Style.cornerRadius)
                  }
                }
              }
            }
          }

          Column {
            anchors.left: art.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.verticalCenter: art.verticalCenter
            spacing: Style.space(4)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.title || strings.t("media.nothingPlaying")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              wrapMode: Text.Wrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.artist
              color: Qt.darker(root.bar.foreground, 1.25)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              visible: text !== ""
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: /[^\s\-–—_.·]/.test(root.album) ? root.album : ""   // players send "-" for none
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              visible: text !== ""
            }
          }
        }

        // ── Timeline ────────────────────────────────────────────────
        Column {
          width: parent.width
          spacing: Style.space(2)
          opacity: root.hasTimeline ? 1 : 0.35

          PanelSlider {
            id: seekSlider
            bar: root.bar
            // PanelSlider insets its track by half a knob on each side; widen it
            // by that so the track lines up with the cover and the time labels.
            x: -knobSize / 2
            width: parent.width + knobSize
            minimum: 0
            maximum: root.hasTimeline ? root.activePlayer.length : 1
            step: 1
            value: root.hasTimeline ? root.position : 0
            enabled: root.canSeek
            onDraggingChanged: root.seeking = dragging
            onMoved: function(v) { root.position = v }
            onReleased: function(v) {
              if (root.canSeek) root.activePlayer.position = v
              root.position = v
              root.seeking = false
            }
          }

          Item {
            width: parent.width
            height: elapsed.implicitHeight

            Text {
              id: elapsed
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: root.hasTimeline ? root.formatTime(seekSlider.dragging ? seekSlider.liveValue : root.position) : "--:--"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.features: { "tnum": 1 }
            }
            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.hasTimeline
                ? "-" + root.formatTime(root.activePlayer.length - (seekSlider.dragging ? seekSlider.liveValue : root.position))
                : "--:--"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.features: { "tnum": 1 }
            }
          }
        }

        // ── Transport controls ──────────────────────────────────────
        Item {
          id: transport
          width: parent.width
          height: Style.space(44)
          LayoutMirroring.enabled: false
          LayoutMirroring.childrenInherit: true

          readonly property real slot: Style.space(44)
          // Spaced for five buttons even when shuffle/repeat are hidden, so
          // previous / play / next keep their places.
          readonly property real gap: Math.max(Style.space(4), (width - slot * 5) / 4)

          component CtrlButton: Button {
            width: transport.slot
            height: transport.slot
            horizontalPadding: 0
            verticalPadding: 0
            foreground: root.bar.foreground
            iconSize: Style.font.icon
            opacity: enabled ? 1.0 : 0.35
          }

          Row {
            anchors.centerIn: parent
            spacing: transport.gap

            CtrlButton {
              iconText: "󰒝"
              tooltipText: strings.t("media.shuffle")
              // Hidden, not dimmed, when the player has no shuffle at all
              // (Chromium), as Omarchy's panels do for unsupported actions.
              visible: !!root.activePlayer && root.activePlayer.shuffleSupported
              selected: visible && root.activePlayer.shuffle
              onClicked: root.activePlayer.shuffle = !root.activePlayer.shuffle
            }

            CtrlButton {
              iconText: "󰒮"
              tooltipText: strings.t("media.previous")
              enabled: !!root.activePlayer && root.activePlayer.canGoPrevious
              onClicked: root.skipTrack("previous")
            }

            CtrlButton {
              iconText: root.isPlaying ? "󰏤" : "󰐊"
              tooltipText: root.isPlaying ? strings.t("media.pause") : strings.t("media.play")
              iconSize: Style.font.iconLarge
              bordered: true
              enabled: !!root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
              onClicked: root.togglePlayback()
            }

            CtrlButton {
              iconText: "󰒭"
              tooltipText: strings.t("media.next")
              enabled: !!root.activePlayer && root.activePlayer.canGoNext
              onClicked: root.skipTrack("next")
            }

            CtrlButton {
              readonly property int loop: root.activePlayer && root.activePlayer.loopSupported ? root.activePlayer.loopState : MprisLoopState.None
              iconText: loop === MprisLoopState.Track ? "󰑘" : "󰑖"
              tooltipText: loop === MprisLoopState.Track ? strings.t("media.repeatOne") : (loop === MprisLoopState.Playlist ? strings.t("media.repeatAll") : strings.t("media.repeatOff"))
              visible: !!root.activePlayer && root.activePlayer.loopSupported
              selected: visible && loop !== MprisLoopState.None
              onClicked: {
                root.activePlayer.loopState = loop === MprisLoopState.None ? MprisLoopState.Playlist
                  : (loop === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None)
              }
            }
          }
        }

        // ── Player volume (per-app PipeWire stream) ─────────────────
        Item {
          width: parent.width
          height: Math.max(volSlider.implicitHeight, volBtn.implicitHeight)
          enabled: root.hasVolume
          opacity: root.hasVolume ? 1 : 0.35

          // The speaker glyph sits flush with the cover's left edge; click mutes.
          Text {
            id: volBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.playerMuted || root.playerVolume <= 0 ? "\ueee8" : (root.playerVolume >= 0.67 ? "\uf028" : (root.playerVolume >= 0.34 ? "\uf027" : "\uf026"))
            color: root.bar.foreground
            opacity: volMouse.containsMouse ? 1.0 : 0.75
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.icon
            width: Style.space(20)

            MouseArea {
              id: volMouse
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              enabled: root.volumeStream !== null
              cursorShape: Qt.PointingHandCursor
              onClicked: root.togglePlayerMute()
            }
            PanelToolTip {
              visible: volMouse.containsMouse
              text: root.playerMuted ? strings.t("media.unmute") : strings.t("media.mute")
            }
          }

          PanelSlider {
            id: volSlider
            bar: root.bar
            anchors.left: volBtn.right
            anchors.leftMargin: Style.space(8) - knobSize / 2
            anchors.right: volPct.left
            anchors.rightMargin: Style.space(8) - knobSize / 2
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0
            maximum: 1
            step: 0.05
            value: root.playerVolume
            opacity: root.playerMuted ? 0.5 : 1.0
            onMoved: function(v) { root.setPlayerVolume(v) }
            onRightClicked: root.togglePlayerMute()
          }

          Text {
            id: volPct
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(34)
            horizontalAlignment: Text.AlignRight
            textFormat: Text.PlainText
            text: Commons.I18n.formatNumber(Math.round((volSlider.dragging ? volSlider.liveValue : root.playerVolume) * 100)) + "%"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.features: { "tnum": 1 }
          }
        }

        // ── Other sources ───────────────────────────────────────────
        PanelSeparator {
          visible: root.sourcePlayers.length > 1
          foreground: root.bar.foreground
        }

        Column {
          id: sourceList
          visible: root.sourcePlayers.length > 1
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.sourcePlayers

            BorderSurface {
              id: sourceRow
              required property var modelData

              readonly property var player: modelData
              readonly property bool selected: root.activePlayer && player
                && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
              readonly property string appName: player ? (player.identity || root.mediaService.playerAppLabel(player) || "") : ""
              readonly property string sourceTitle: player ? (player.trackTitle || appName || strings.t("media.mediaSource")) : strings.t("media.mediaSource")
              readonly property string sourceDetail: {
                if (!player) return ""
                var parts = []
                if (player.trackArtist) parts.push(player.trackArtist)
                if (appName) parts.push(appName)
                return parts.join("  ·  ")
              }

              width: sourceList.width
              height: sourceInner.implicitHeight + Style.space(10)
              radius: Style.cornerRadius
              color: selected ? Style.selectedFillFor(root.bar.foreground, Commons.Color.accent) : "transparent"
              borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent) : Border.none()

              Row {
                id: sourceInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
                anchors.rightMargin: sourceRow.borderRight + Style.space(8)
                spacing: Style.space(8)

                // ▶ plays this source (pausing the others) and shows it; ❚❚
                // pauses it and leaves the popup where it is.
                Item {
                  id: rowPlay
                  width: Style.space(22)
                  height: width
                  anchors.verticalCenter: parent.verticalCenter

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius   // square unless the theme rounds corners
                    color: root.bar.foreground
                    opacity: rowMouse.overPlay ? 0.15 : 0
                    Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
                  }
                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  PanelToolTip {
                    visible: rowMouse.overPlay
                    text: sourceRow.player && sourceRow.player.isPlaying ? strings.t("media.pause") : strings.t("media.play")
                  }
                }

                Column {
                  width: parent.width - Style.space(30)
                  spacing: Style.space(1)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    textFormat: Text.PlainText
                    text: sourceRow.sourceTitle
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: sourceRow.selected
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: sourceRow.sourceDetail
                    color: Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== ""
                  }
                }
              }

              // One area for the row. Over the play button: ▶ plays this source
              // and pauses the others, ❚❚ just pauses it. Anywhere else: show
              // the source in the popup, playback unchanged.
              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                readonly property bool overPlay: containsMouse && rowPlay.contains(mapToItem(rowPlay, mouseX, mouseY))
                onClicked: function(mouse) {
                  if (!root.mediaService || !sourceRow.player) return
                  var key = root.mediaService.playerKey(sourceRow.player)
                  if (!rowPlay.contains(mapToItem(rowPlay, mouse.x, mouse.y))) root.showSource(key)
                  else if (sourceRow.player.isPlaying) root.mediaService.runAction("pause", false, key)
                  else { root.explicitSwitch = true; if (!root.mediaService.playExclusive(key)) root.explicitSwitch = false }   // play this, pause the rest
                }
              }
            }
          }
        }
      }
    }
  }
}
