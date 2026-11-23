pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../lib/Glyphs.js" as Glyphs

// Shuffle, previous, play/pause, next and repeat. Spaced for five buttons
// even when shuffle and repeat are hidden, so the middle three keep their
// places. Never mirrored: ← is always previous.
Item {
  id: transport

  required property Theme theme
  required property var strings
  required property var player   // the shown player, or null
  required property bool playing

  signal previous()
  signal next()
  signal togglePlayback()
  signal toggleShuffle()
  signal cycleRepeat()

  readonly property real slot: Style.space(44)
  readonly property real gap: Math.max(Style.space(4), (width - slot * 5) / 4)
  readonly property int loop: player && player.loopSupported ? player.loopState : MprisLoopState.None

  height: slot
  LayoutMirroring.enabled: false
  LayoutMirroring.childrenInherit: true

  component ControlButton: Button {
    width: transport.slot
    height: transport.slot
    horizontalPadding: 0
    verticalPadding: 0
    foreground: transport.theme.foreground
    iconSize: transport.theme.icon
    opacity: enabled ? 1.0 : 0.35
  }

  Row {
    anchors.centerIn: parent
    spacing: transport.gap

    // Hidden, not dimmed, when the player has no shuffle at all (Chromium),
    // as Omarchy's panels do for unsupported actions.
    ControlButton {
      iconText: Glyphs.SHUFFLE
      tooltipText: transport.strings.t("media.shuffle")
      visible: !!transport.player && transport.player.shuffleSupported
      selected: visible && transport.player.shuffle
      onClicked: transport.toggleShuffle()
    }

    ControlButton {
      iconText: Glyphs.PREVIOUS
      tooltipText: transport.strings.t("media.previous")
      enabled: !!transport.player && transport.player.canGoPrevious
      onClicked: transport.previous()
    }

    ControlButton {
      iconText: transport.playing ? Glyphs.PAUSE : Glyphs.PLAY
      tooltipText: transport.strings.t(transport.playing ? "media.pause" : "media.play")
      iconSize: transport.theme.iconLarge
      bordered: true
      enabled: !!transport.player && (transport.player.canTogglePlaying || transport.player.canPlay || transport.player.canPause)
      onClicked: transport.togglePlayback()
    }

    ControlButton {
      iconText: Glyphs.NEXT
      tooltipText: transport.strings.t("media.next")
      enabled: !!transport.player && transport.player.canGoNext
      onClicked: transport.next()
    }

    ControlButton {
      iconText: transport.loop === MprisLoopState.Track ? Glyphs.REPEAT_ONE : Glyphs.REPEAT
      tooltipText: transport.strings.t(transport.loop === MprisLoopState.Track ? "media.repeatOne"
        : transport.loop === MprisLoopState.Playlist ? "media.repeatAll" : "media.repeatOff")
      visible: !!transport.player && transport.player.loopSupported
      selected: visible && transport.loop !== MprisLoopState.None
      onClicked: transport.cycleRepeat()
    }
  }
}
