import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BarWidget {
  id: root
  moduleName: "omarchy.media"

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property bool isPlaying: !!activePlayer && !!activePlayer.isPlaying
  readonly property string playIcon: isPlaying ? "󰐊" : "󰏤"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""

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
  readonly property string sourceIcon: {
    if (!activePlayer) return ""
    var entry = activePlayer.desktopEntry || ""
    if (!entry) return ""
    var de = DesktopEntries.heuristicLookup ? DesktopEntries.heuristicLookup(entry) : DesktopEntries.byId(entry)
    return Quickshell.iconPath(de && de.icon ? de.icon : entry, true)
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

  function formatTime(sec) {
    if (!isFinite(sec) || sec < 0) sec = 0
    sec = Math.floor(sec)
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60
    var ss = (s < 10 ? "0" : "") + s
    return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
  }

  function act(action) {
    if (root.mediaService) root.mediaService.runAction(action, false, root.mediaService.playerKey(root.activePlayer))
  }

  onActivePlayerChanged: syncPosition()
  onPopupOpenChanged: syncPosition()

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

  function close() { popupOpen = false }

  visible: hasMedia
  implicitWidth: hasMedia ? button.implicitWidth : 0
  implicitHeight: barSize

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.playIcon
    active: root.popupOpen
    tooltipText: root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : ""
    onPressed: function(b) {
      if (!root.activePlayer) return
      if (b === Qt.RightButton) root.popupOpen = !root.popupOpen
      else root.act("playPause")
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(12)

      // ── Source header ───────────────────────────────────────────
      Item {
        width: parent.width
        height: Math.max(srcIconBox.height, statusText.implicitHeight)

        Item {
          id: srcIconBox
          width: Style.space(18)
          height: Style.space(18)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter

          Image {
            id: srcIconImg
            anchors.fill: parent
            source: root.sourceIcon
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            visible: status === Image.Ready
            smooth: true
          }
          Text {
            anchors.centerIn: parent
            visible: !srcIconImg.visible
            text: "󰎈"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Text {
          anchors.left: srcIconBox.right
          anchors.leftMargin: Style.space(8)
          anchors.right: statusText.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.sourceName + (root.sourceHost ? "  ·  " + root.sourceHost : "")
          color: Qt.darker(root.bar.foreground, 1.25)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          id: statusText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.isPlaying ? "▶ Playing" : "❚❚ Paused"
          color: root.isPlaying ? Commons.Color.accent : Qt.darker(root.bar.foreground, 1.6)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
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
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Commons.Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent)

          SizedImage {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            crop: true
            url: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: url != ""
          }

          Text {
            anchors.centerIn: parent
            visible: !root.activePlayer || !root.activePlayer.trackArtUrl
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
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
            text: root.title || I18n.t("media.nothingPlaying")
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
            text: root.album
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
        visible: root.hasTimeline

        PanelSlider {
          id: seekSlider
          bar: root.bar
          width: parent.width
          minimum: 0
          maximum: root.hasTimeline ? root.activePlayer.length : 1
          step: 1
          value: root.position
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
            text: root.formatTime(seekSlider.dragging ? seekSlider.liveValue : root.position)
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
              : ""
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
            tooltipText: "Shuffle"
            visible: true
            enabled: !!root.activePlayer && root.activePlayer.shuffleSupported
            selected: enabled && root.activePlayer.shuffle
            onClicked: root.activePlayer.shuffle = !root.activePlayer.shuffle
          }

          CtrlButton {
            iconText: "󰒮"
            tooltipText: "Previous"
            enabled: !!root.activePlayer && root.activePlayer.canGoPrevious
            onClicked: root.act("previous")
          }

          CtrlButton {
            iconText: root.isPlaying ? "󰏤" : "󰐊"
            tooltipText: root.isPlaying ? "Pause" : "Play"
            iconSize: Style.font.iconLarge
            bordered: true
            enabled: !!root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
            onClicked: root.act("playPause")
          }

          CtrlButton {
            iconText: "󰒭"
            tooltipText: "Next"
            enabled: !!root.activePlayer && root.activePlayer.canGoNext
            onClicked: root.act("next")
          }

          CtrlButton {
            readonly property int loop: root.activePlayer && root.activePlayer.loopSupported ? root.activePlayer.loopState : MprisLoopState.None
            iconText: loop === MprisLoopState.Track ? "󰑘" : "󰑖"
            tooltipText: loop === MprisLoopState.Track ? "Repeat one" : (loop === MprisLoopState.Playlist ? "Repeat all" : "Repeat off")
            enabled: !!root.activePlayer && root.activePlayer.loopSupported
            selected: enabled && loop !== MprisLoopState.None
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
        height: Math.max(volSlider.implicitHeight, volBtn.height)
        visible: root.hasVolume

        Button {
          id: volBtn
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(32)
          height: Style.space(32)
          horizontalPadding: 0
          verticalPadding: 0
          foreground: root.bar.foreground
          iconSize: Style.font.icon
          iconText: root.playerMuted || root.playerVolume <= 0 ? "" : (root.playerVolume >= 0.67 ? "" : (root.playerVolume >= 0.34 ? "" : ""))
          tooltipText: root.playerMuted ? "Unmute" : "Mute"
          enabled: root.volumeStream !== null
          onClicked: root.togglePlayerMute()
        }

        PanelSlider {
          id: volSlider
          bar: root.bar
          anchors.left: volBtn.right
          anchors.leftMargin: Style.space(8)
          anchors.right: volPct.left
          anchors.rightMargin: Style.space(8)
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
          text: Math.round((volSlider.dragging ? volSlider.liveValue : root.playerVolume) * 100) + "%"
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
            readonly property string sourceTitle: player ? (player.trackTitle || appName || I18n.t("media.mediaSource")) : I18n.t("media.mediaSource")
            readonly property string sourceDetail: {
              if (!player) return ""
              var parts = []
              if (player.trackArtist) parts.push(player.trackArtist)
              if (appName) parts.push(appName)
              return parts.join("  ·  ")
            }

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
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

              Text {
                textFormat: Text.PlainText
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
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

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }
    }
  }
}
