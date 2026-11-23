import QtQuick
import qs.Commons
import qs.Ui
import "../lib/Display.js" as Display
import "../lib/KeyMap.js" as KeyMap

// The popup, built the first time it opens and kept after. What it shows
// comes from the service; it adds the playback position, read once a second
// while open and playing (MPRIS does not push it), and the keys:
//   Space / Enter      play / pause (starting pauses other sources)
//   ← / → (h / l)      previous / next track
//   ↑ / ↓ (k / j)      player volume
//   , / .              seek -10 s / +10 s
//   m · s · r          mute · shuffle · repeat
//   Tab / Shift+Tab    next / previous source
PanelKeyCatcher {
  id: popup

  required property var service
  required property var bar
  required property bool open

  readonly property Item focusTarget: letterKeys
  readonly property Theme theme: Theme { bar: popup.bar }
  readonly property var strings: service.strings
  readonly property var player: service.activePlayer
  readonly property bool playing: !!player && player.isPlaying
  readonly property real length: player && player.lengthSupported && player.length > 0 ? player.length : 0
  readonly property bool canSeek: length > 0 && player.canSeek && player.positionSupported
  property real position: 0

  readonly property int positionPollMs: 1000
  readonly property real volumeStep: 0.05
  readonly property real seekStep: 10

  implicitHeight: column.implicitHeight

  onPlayerChanged: syncPosition()
  onOpenChanged: syncPosition()

  function syncPosition() {
    if (!player || timeline.dragging) return
    position = player.positionSupported ? player.position : 0
  }

  function seekTo(seconds) {
    if (!canSeek) return
    position = Math.max(0, Math.min(length - 1, seconds))
    player.position = position
  }

  function changeVolume(delta) {
    if (service.volume.available) service.volume.set(service.volume.level + delta)
  }

  readonly property var keyActions: ({
    previous: function() { popup.service.skipTrack("previous") },
    next: function() { popup.service.skipTrack("next") },
    volumeDown: function() { popup.changeVolume(-popup.volumeStep) },
    volumeUp: function() { popup.changeVolume(popup.volumeStep) },
    seekBack: function() { popup.seekTo(popup.position - popup.seekStep) },
    seekForward: function() { popup.seekTo(popup.position + popup.seekStep) },
    mute: function() { popup.service.volume.toggleMute() },
    shuffle: function() { popup.service.toggleShuffle() },
    repeat: function() { popup.service.cycleRepeat() },
  })

  onActivateRequested: service.toggleSource(service.activeKey)
  onTabRequested: function(direction) { service.cycleSource(direction) }
  onMoveRequested: function(dx, dy) {
    // The transport row is never mirrored, so PanelKeyCatcher's right-to-left
    // swap is undone: ← is always previous.
    var d = I18n.rightToLeft ? -dx : dx
    if (d !== 0) service.skipTrack(d > 0 ? "next" : "previous")
    else if (dy !== 0) changeVolume(-dy * volumeStep)
  }

  // Letter keys get the first look (lib/KeyMap.js), by letter or, on a
  // non-Latin layout, by position. Everything else goes on to the
  // PanelKeyCatcher.
  Item {
    id: letterKeys
    focus: true
    Keys.onPressed: function(event) {
      var action = KeyMap.action(event.text, event.nativeScanCode, event.modifiers)
      if (!action) return
      popup.keyActions[action]()
      event.accepted = true
    }
  }

  Timer {
    interval: popup.positionPollMs
    repeat: true
    running: popup.open && popup.playing
    triggeredOnStart: true
    onTriggered: popup.syncPosition()
  }

  Connections {
    target: popup.player
    ignoreUnknownSignals: true
    function onPostTrackChanged() { popup.syncPosition() }
    function onSeeked() { popup.syncPosition() }
    function onIsPlayingChanged() { popup.syncPosition() }
  }

  Column {
    id: column
    anchors.fill: parent
    spacing: Style.space(12)

    HeroHeader {
      width: parent.width
      theme: popup.theme
      playing: popup.playing
      title: popup.strings.t("media.title")
      status: popup.strings.t(Display.moodKey({
        hasPlayer: !!popup.player, muted: popup.service.volume.muted, playing: popup.playing,
        hasTimeline: popup.length > 0, position: popup.position, length: popup.length,
      }))
      iconSource: popup.service.appIcon.source
      sourceName: popup.service.sourceName
      openHint: popup.strings.t("media.open").arg([popup.service.sourceName, popup.service.sourceHost]
        .filter(function(part) { return part !== "" }).join("  ·  "))
      onRaiseRequested: {
        popup.service.raisePlayer()
        popup.closeRequested()
      }
    }

    PanelSeparator { foreground: popup.theme.foreground }

    TrackCard {
      width: parent.width
      theme: popup.theme
      display: popup.service.display
      playing: popup.playing && popup.open
      placeholder: popup.strings.t("media.nothingPlaying")
      coverStyle: popup.service.preferences.coverStyle
      onStyleCycleRequested: popup.service.cycleCoverStyle()
    }

    Timeline {
      id: timeline
      width: parent.width
      theme: popup.theme
      position: popup.position
      length: popup.length
      canSeek: popup.canSeek
      onMoved: function(seconds) { popup.position = seconds }
      onReleased: function(seconds) { popup.seekTo(seconds) }
    }

    Transport {
      width: parent.width
      theme: popup.theme
      strings: popup.strings
      player: popup.player
      playing: popup.playing
      onPrevious: popup.service.skipTrack("previous")
      onNext: popup.service.skipTrack("next")
      onTogglePlayback: popup.service.toggleSource(popup.service.activeKey)
      onToggleShuffle: popup.service.toggleShuffle()
      onCycleRepeat: popup.service.cycleRepeat()
    }

    VolumeRow {
      width: parent.width
      theme: popup.theme
      strings: popup.strings
      enabled: popup.service.volume.available
      volume: popup.service.volume.level
      muted: popup.service.volume.muted
      canMute: popup.service.volume.canMute
      onVolumeMoved: function(value) { popup.service.volume.set(value) }
      onToggleMute: popup.service.volume.toggleMute()
    }

    PanelSeparator {
      visible: sources.visible
      foreground: popup.theme.foreground
    }

    SourceList {
      id: sources
      width: parent.width
      visible: popup.service.sourcePlayers.length > 1
      theme: popup.theme
      strings: popup.strings
      players: popup.service.sourcePlayers
      held: popup.service.heldSources
      activeKey: popup.service.activeKey
      onShowRequested: function(key) { popup.service.showSource(key) }
      onToggleRequested: function(key) { popup.service.toggleSource(key) }
    }
  }
}
