import QtQuick
import Quickshell.Services.Mpris
import "../lib/Display.js" as Display
import "../lib/MediaModel.js" as MediaModel
import "../lib/TrackHold.js" as TrackHold

// The track the bar and the popup show, held steady through what players do
// between tracks (lib/TrackHold.js), and its cover. A new local cover is
// compared with the player's app icon first (scripts/probe-art.sh): Chromium
// fills the gap between tracks with its icon as "art", and that is dropped so
// the previous cover stays until the real one arrives. Anything uncertain
// (remote art, no icon, a failed probe) is shown.
QtObject {
  id: display

  required property var player           // the active player
  required property var playersByKey
  required property var iconNames         // the player's icon names, for the probe
  required property string probeScript
  property Metrics metrics: null

  // What is shown.
  property bool hasMedia: false
  property string title: ""
  property string artist: ""
  property string album: ""
  property string artUrl: ""

  // The shown cover failed to load and is worth another try.
  signal reloadArt(string url)

  // Set just before the user picks a player: it shows without a hold.
  property bool explicit: false

  property string shownKey: ""        // player whose metadata is shown
  property string artPlayerKey: ""    // player the shown cover came from
  property string trackId: ""
  property string rejectedArtUrl: ""  // a placeholder served instead of art
  property var artFailures: ({})      // url -> failed loads, this track
  property var verdicts: ({})         // probe key -> is art
  property int verdictCount: 0
  property string probing: ""         // probe key in flight
  property string retryUrl: ""        // cover to load again

  readonly property int maxVerdicts: 256
  readonly property string playerKey: MediaModel.playerKey(player)
  readonly property bool liveMedia: MediaModel.hasShownTrack(player)
  readonly property string liveArtUrl: player && player.trackArtUrl ? String(player.trackArtUrl) : ""
  readonly property string signature: MediaModel.trackSignature(player)

  onSignatureChanged: refresh()
  onPlayerChanged: refresh()
  onPlayersByKeyChanged: refresh()
  Component.onCompleted: apply()

  function refresh() {
    var action = TrackHold.refreshAction({
      hasPlayer: !!player, key: playerKey, shownKey: shownKey,
      shownGone: shownKey !== "" && !playersByKey[shownKey],
      explicit: explicit, liveMedia: liveMedia,
      stopped: !!player && player.playbackState === MprisPlaybackState.Stopped,
    })
    if (action === "waitSwitch") {
      blankHold.stop()
      switchHold.restart()
      return
    }
    explicit = false
    switchHold.stop()
    shownKey = playerKey
    if (action === "apply") {
      blankHold.stop()
      apply()
    } else {
      blankHold.restart()
    }
  }

  function apply() {
    var id = TrackHold.trackIdentity(playerKey, player)
    if (id !== trackId) {
      trackId = id
      rejectedArtUrl = ""
      artFailures = {}
    }
    // Another app's cover never stays on this app's track.
    if (artUrl !== "" && playerKey !== artPlayerKey) clearArt()
    title = player ? player.trackTitle || "" : ""
    artist = player ? player.trackArtist || "" : ""
    album = player ? player.trackAlbum || "" : ""
    hasMedia = liveMedia

    var action = TrackHold.artAction({ liveArtUrl: liveArtUrl, artUrl: artUrl, rejectedArtUrl: rejectedArtUrl, liveMedia: liveMedia })
    if (action === "probe") probe(liveArtUrl)
    else if (action === "clear") clearArt()
    else if (action === "clearLater") artClear.restart()
  }

  function probe(url) {
    var path = iconNames.length ? Display.localPath(url) : ""
    if (path === "") {
      accept(url, true)
      return
    }
    var key = TrackHold.probeKey(url, trackId)
    if (key in verdicts) {
      if (metrics) metrics.count("probeCacheHits")
      accept(url, verdicts[key])
    } else if (key !== probing) {
      probing = key
      runner.run({ url: url, key: key }, ["sh", probeScript, path].concat(iconNames))
    }
  }

  function remember(key, isArt) {
    if (verdictCount >= maxVerdicts) {
      verdicts = {}
      verdictCount = 0
    }
    verdicts[key] = isArt
    verdictCount++
  }

  function accept(url, isArt) {
    if (url !== liveArtUrl) return   // superseded while probing
    if (isArt) {
      artClear.stop()
      rejectedArtUrl = ""
      artUrl = url
      artPlayerKey = playerKey
    } else {
      rejectedArtUrl = url
      artClear.restart()
    }
  }

  function clearArt() {
    artClear.stop()
    artUrl = ""
  }

  // The view could not load the shown cover: retry, then give up on it for
  // this track rather than show the previous track's cover.
  function artFailed(url) {
    if (url !== artUrl) return
    var failures = (artFailures[url] || 0) + 1
    artFailures[url] = failures
    if (TrackHold.retryArt(failures)) {
      retryUrl = url
      artRetry.restart()
    } else {
      rejectedArtUrl = url
      artUrl = ""
    }
  }

  readonly property ScriptRunner runner: ScriptRunner {
    timeout: TrackHold.PROBE_TIMEOUT_MS
    metrics: display.metrics
    onFinished: function(tag, ok, output) {
      // A finished probe is final for this file on this track, even "cannot
      // tell" (no icon to compare with); a failed or hung one is not.
      var isArt = !(ok && TrackHold.isPlaceholder(output))
      if (ok) display.remember(tag.key, isArt)
      if (display.probing === tag.key) display.probing = ""
      display.accept(tag.url, isArt)
    }
  }

  readonly property Timer switchHold: Timer {
    interval: TrackHold.SWITCH_HOLD_MS
    onTriggered: {
      display.shownKey = display.playerKey
      display.blankHold.stop()
      display.apply()
    }
  }

  readonly property Timer blankHold: Timer {
    interval: TrackHold.BLANK_HOLD_MS
    onTriggered: display.apply()
  }

  readonly property Timer artClear: Timer {
    interval: TrackHold.ART_CLEAR_MS
    onTriggered: if (display.liveArtUrl === "" || display.liveArtUrl === display.rejectedArtUrl) display.clearArt()
  }

  readonly property Timer artRetry: Timer {
    interval: TrackHold.ART_RETRY_MS
    onTriggered: if (display.retryUrl === display.artUrl && display.retryUrl === display.liveArtUrl) display.reloadArt(display.retryUrl)
  }
}
