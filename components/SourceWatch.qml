import QtQuick
import Quickshell.Services.Mpris
import "../lib/MediaModel.js" as MediaModel
import "../lib/TrackHold.js" as TrackHold

// Watches one player for the service: when it starts or stops (playing), and the gaps
// between tracks in which it reports no title or artist. Through such a gap
// the source keeps its row in the popup's list, under the track it showed
// last, for as long as the shown track itself is held (lib/TrackHold.js).
QtObject {
  id: watch

  required property var modelData

  signal held(string key, var track)   // a gap began: { title, artist }
  signal released(string key)          // the track is back, or the gap lasted

  readonly property string key: MediaModel.playerKey(modelData)
  readonly property bool playing: !!modelData && modelData.isPlaying
  readonly property bool shown: MediaModel.hasShownTrack(modelData)
  readonly property string title: modelData ? modelData.trackTitle || "" : ""
  readonly property string artist: modelData ? modelData.trackArtist || "" : ""
  property var lastTrack: null

  // A player's metadata arrives one property at a time; remembering at the
  // end of the turn sees the whole track, never half of the next one.
  onTitleChanged: Qt.callLater(remember)
  onArtistChanged: Qt.callLater(remember)
  onShownChanged: shown ? release() : hold()
  Component.onCompleted: remember()
  Component.onDestruction: if (gap.running) released(key)

  function remember() {
    if (shown) lastTrack = { title: title, artist: artist }
  }

  function hold() {
    if (!lastTrack) return
    gap.interval = TrackHold.blankHoldMs(modelData.playbackState === MprisPlaybackState.Stopped)
    gap.restart()
    held(key, lastTrack)
  }

  function release() {
    if (!gap.running) return
    gap.stop()
    released(key)
  }

  readonly property Timer gap: Timer {
    onTriggered: watch.released(watch.key)
  }
}
