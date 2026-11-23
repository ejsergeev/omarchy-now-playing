pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "components"
import "lib/Glyphs.js" as Glyphs
import "lib/MediaModel.js" as MediaModel

// The bar button: ▶ while something plays, ❚❚ when nothing does, following
// the source that is actually sounding. Left click opens the popup, right
// click plays or pauses, middle click skips. Everything it shows lives in
// Service.qml, shared by the bar on every monitor; the popup is built the
// first time it opens.
BarWidget {
  id: root

  readonly property string pluginId: "io.github.ejsergeev.now-playing"
  moduleName: pluginId

  // The host types `bar` as a plain QtObject; its API has shell.
  readonly property var service: bar?.shell?.serviceFor(pluginId) ?? null // qmllint disable missing-property
  readonly property var barPlayer: service ? service.controlPlayer : null
  readonly property bool hasMedia: !!service && service.display.hasMedia

  // Bar panel contract: `omarchy-shell shell toggle <id>`, a
  // { panel = "<id>" } keybinding and Super+Ctrl+<n> open it.
  property bool popupOpen: false
  readonly property bool opened: popupOpen
  function open() { if (hasMedia) popupOpen = true }
  function close() { popupOpen = false }

  property double openedAt: 0   // when the popup was asked for, for metrics

  onHasMediaChanged: if (!hasMedia) close()
  onPopupOpenChanged: {
    if (popupOpen) openedAt = Date.now()
    // Closed: the next opening shows what is playing, not the last pick.
    else if (service) service.clearPin()
  }

  // The bar acts on what plays, else what played last, so a second right
  // click resumes what the first one paused.
  function act(action) {
    if (service && barPlayer) service.runAction(action, false, MediaModel.playerKey(barPlayer))
  }

  visible: hasMedia
  implicitWidth: hasMedia ? button.implicitWidth : 0
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barPlayer && root.barPlayer.isPlaying ? Glyphs.PLAY : Glyphs.PAUSE
    tooltipText: MediaModel.hasShownTrack(root.barPlayer)
      ? [root.barPlayer.trackTitle, root.barPlayer.trackArtist].filter(function(part) { return !!part }).join(" — ")
      : ""
    onPressed: function(mouseButton) {
      if (!root.service || !root.service.activePlayer) return
      if (mouseButton === Qt.RightButton) root.act("playPause")
      else if (mouseButton === Qt.MiddleButton) root.act("next")
      else root.popupOpen = !root.popupOpen
    }
  }

  // KeyboardPanel (not PopupCard) takes keyboard focus when it opens, so
  // Escape closes it like the other bar panels.
  KeyboardPanel {
    id: panel
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: (panel.loadedContent as NowPlayingPopup)?.focusTarget ?? null
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)
    onLoadedContentChanged: if (panel.loadedContent && root.service) root.service.metrics.record("popupBuildMs", Date.now() - root.openedAt)

    content: NowPlayingPopup {
      service: root.service
      bar: root.bar
      open: root.popupOpen
      onCloseRequested: root.close()
    }
  }

  Connections {
    target: root.service
    function onMetricsRequested() {
      root.service.addWidgetMetrics({
        open: root.popupOpen,
        objects: root.service.metrics.objectCount(root, [panel]),
        popupObjects: root.service.metrics.objectCount(panel.loadedContent, []),
      })
    }
  }
}
