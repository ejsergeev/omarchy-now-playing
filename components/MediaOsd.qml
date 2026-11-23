import QtQuick
import "../lib/Actions.js" as Actions
import "../lib/MediaModel.js" as MediaModel

// Feedback for media actions on the shell's OSD. After a skip it waits a
// moment for the new track, so it names that track and not the old one.
QtObject {
  id: osd

  required property var shell
  required property var playersByKey
  required property var fallbackPlayer   // named when an action had no player

  readonly property int waitMs: 1200
  property var pending: null   // { label, icon, key, player, before }

  function show(label, icon, player) {
    if (shell) shell.summon("omarchy.osd", JSON.stringify({ icon: icon, message: Actions.osdMessage(player || fallbackPlayer, label) }))
  }

  function showSoon(label, icon, player) {
    Qt.callLater(function() { osd.show(label, icon, player) })
  }

  // trackBefore: the player's track signature before the skip.
  function showAfterTrackChange(label, icon, player, trackBefore) {
    pending = { label: label, icon: icon, key: MediaModel.playerKey(player), player: player, before: trackBefore }
    timeout.restart()
  }

  function flush(force) {
    var p = pending
    if (!p) return
    var player = playersByKey[p.key] || p.player
    if (!force && !MediaModel.trackChanged(p.before, player)) return
    pending = null
    timeout.stop()
    show(p.label, p.icon, player)
  }

  readonly property Timer timeout: Timer {
    interval: osd.waitMs
    onTriggered: osd.flush(true)
  }

  readonly property Connections trackWatch: Connections {
    target: osd.pending ? osd.playersByKey[osd.pending.key] || null : null
    ignoreUnknownSignals: true
    function onPostTrackChanged() { osd.flush(false) }
  }
}
