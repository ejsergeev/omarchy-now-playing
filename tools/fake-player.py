#!/usr/bin/env python3
"""A silent MPRIS player for repeatable measurements.

Usage: fake-player.py [--name NAME] [--art always|never|alternate] [--tracks N]
                      [--paused] [--skip-gap MS]

Owns org.mpris.MediaPlayer2.<NAME> on the session bus and plays a list of
synthetic tracks without making a sound. Next/Previous change the track at
once, so the bench scenarios can drive track changes without touching the
user's real players. Art, when a track has it, is a small PNG generated with
ImageMagick into $XDG_RUNTIME_DIR, so the plugin probes it like a browser's.
With --skip-gap, a skip first reports Stopped with no metadata for that long,
as YouTube Music in Chromium does. Stop ends the session the way closing a
browser tab does: Stopped, with no metadata, for good.
"""

import argparse
import os
import subprocess
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/><method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/><method name="Previous"/>
    <method name="Pause"/><method name="PlayPause"/>
    <method name="Stop"/><method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/>
      <arg direction="in" name="Position" type="x"/>
    </method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"
PATH = "/org/mpris/MediaPlayer2"
TRACK_US = 180 * 1_000_000


class FakePlayer:
    def __init__(self, args):
        self.name = args.name
        self.art_mode = args.art
        self.count = args.tracks
        self.skip_gap_ms = args.skip_gap
        self.blank = False
        self.index = 0
        self.playing = not args.paused
        self.offset_us = 0              # position when playback last (re)started
        self.started = time.monotonic()
        self.art_dir = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "np-bench-art")
        os.makedirs(self.art_dir, exist_ok=True)
        self.conn = None

    # -- tracks -------------------------------------------------------------

    def has_art(self, i):
        return self.art_mode == "always" or (self.art_mode == "alternate" and i % 2 == 0)

    def art_url(self, i):
        path = os.path.join(self.art_dir, f"{self.name}-{i}.png")
        if not os.path.exists(path):
            hue = (i * 47) % 360
            subprocess.run(["magick", "-size", "256x256", f"xc:hsl({hue},60%,45%)", path], check=False)
        return "file://" + path

    def metadata(self):
        if self.blank:
            return {"mpris:trackid": GLib.Variant("o", "/org/mpris/MediaPlayer2/TrackList/NoTrack")}
        i = self.index
        md = {
            "mpris:trackid": GLib.Variant("o", f"/np/bench/track/{i}"),
            "mpris:length": GLib.Variant("x", TRACK_US),
            "xesam:title": GLib.Variant("s", f"Bench track {i + 1}"),
            "xesam:artist": GLib.Variant("as", ["Bench Artist"]),
            "xesam:album": GLib.Variant("s", "Bench Album"),
        }
        if self.has_art(i):
            md["mpris:artUrl"] = GLib.Variant("s", self.art_url(i))
        return md

    def position_us(self):
        if not self.playing:
            return self.offset_us
        return min(TRACK_US, self.offset_us + int((time.monotonic() - self.started) * 1_000_000))

    # -- D-Bus --------------------------------------------------------------

    def props(self, iface):
        if iface == ROOT:
            return {
                "CanQuit": GLib.Variant("b", True),
                "CanRaise": GLib.Variant("b", False),
                "HasTrackList": GLib.Variant("b", False),
                "Identity": GLib.Variant("s", f"NP Bench {self.name}"),
                "DesktopEntry": GLib.Variant("s", ""),
                "SupportedUriSchemes": GLib.Variant("as", []),
                "SupportedMimeTypes": GLib.Variant("as", []),
            }
        return {
            "PlaybackStatus": GLib.Variant("s", "Stopped" if self.blank else "Playing" if self.playing else "Paused"),
            "Rate": GLib.Variant("d", 1.0),
            "Metadata": GLib.Variant("a{sv}", self.metadata()),
            "Volume": GLib.Variant("d", 1.0),
            "Position": GLib.Variant("x", self.position_us()),
            "MinimumRate": GLib.Variant("d", 1.0),
            "MaximumRate": GLib.Variant("d", 1.0),
            "CanGoNext": GLib.Variant("b", True),
            "CanGoPrevious": GLib.Variant("b", True),
            "CanPlay": GLib.Variant("b", True),
            "CanPause": GLib.Variant("b", True),
            "CanSeek": GLib.Variant("b", True),
            "CanControl": GLib.Variant("b", True),
        }

    def changed(self, *names):
        values = self.props(PLAYER)
        self.conn.emit_signal(
            None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", (PLAYER, {n: values[n] for n in names}, [])))

    def set_playing(self, playing):
        if playing == self.playing:
            return
        self.offset_us = self.position_us()
        self.started = time.monotonic()
        self.playing = playing
        self.changed("PlaybackStatus")

    def skip(self, delta):
        self.index = (self.index + delta) % self.count
        self.offset_us = 0
        self.started = time.monotonic()
        if self.skip_gap_ms:
            self.blank = True
            self.changed("Metadata", "PlaybackStatus")
            GLib.timeout_add(self.skip_gap_ms, self.end_gap)
        else:
            self.changed("Metadata")

    def end_gap(self):
        self.blank = False
        self.changed("Metadata", "PlaybackStatus")
        return False

    def on_call(self, conn, sender, path, iface, method, params, invocation):
        if method == "Next":
            self.skip(1)
        elif method == "Previous":
            self.skip(-1)
        elif method == "Play":
            self.set_playing(True)
        elif method == "Pause":
            self.set_playing(False)
        elif method == "Stop":
            self.playing = False
            self.blank = True
            self.changed("Metadata", "PlaybackStatus")
        elif method == "PlayPause":
            self.set_playing(not self.playing)
        elif method in ("Seek", "SetPosition"):
            value = params.unpack()[-1]
            target = self.position_us() + value if method == "Seek" else value
            self.offset_us = max(0, min(TRACK_US, target))
            self.started = time.monotonic()
            conn.emit_signal(None, PATH, PLAYER, "Seeked", GLib.Variant("(x)", (self.offset_us,)))
        elif method == "Quit":
            GLib.idle_add(self.loop.quit)
        invocation.return_value(None)

    def on_get(self, conn, sender, path, iface, prop):
        return self.props(iface)[prop]

    def run(self):
        info = Gio.DBusNodeInfo.new_for_xml(XML)
        self.loop = GLib.MainLoop()

        def acquired(conn, _name):
            self.conn = conn
            for iface in info.interfaces:
                conn.register_object(PATH, iface, self.on_call, self.on_get, None)

        Gio.bus_own_name(Gio.BusType.SESSION, f"{ROOT}.{self.name}", Gio.BusNameOwnerFlags.NONE,
                         acquired, None, lambda *_: self.loop.quit())
        self.loop.run()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--name", default="npbench")
    parser.add_argument("--art", choices=["always", "never", "alternate"], default="alternate")
    parser.add_argument("--tracks", type=int, default=50)
    parser.add_argument("--paused", action="store_true")
    parser.add_argument("--skip-gap", type=int, default=0, metavar="MS")
    FakePlayer(parser.parse_args()).run()


if __name__ == "__main__":
    main()
