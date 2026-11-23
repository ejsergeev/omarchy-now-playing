#!/usr/bin/env python3
"""Measures the Now Playing plugin inside the running Omarchy shell.

Usage: measure.py SCENARIO [--seconds N] [--runs N] [--label TEXT]

Scenarios (see docs/METRICS.md):
  idle           nothing plays, popup closed
  play           a fake player plays, popup closed
  open-art       a fake player plays a track with art, popup open
  open-spectrum  a fake player plays a track without art, popup open
  churn          20 track changes on a fake player (art on every other one)
  switch         20 source switches between two fake players
  startup        restarts the shell and watches its first seconds

For each run it prints one JSON line with:
  cpu_ms        CPU time of the quickshell process during the window
  child_cpu_ms  CPU time of the processes it spawned and reaped (scripts)
  pss_kb        quickshell's proportional set size at the end
  spawns        processes quickshell started for this plugin
  processes     all processes in those spawns' trees (sh, magick, ...)
  metrics       the plugin's own counters, when it exposes `media metrics`
  valid         open-* only: the popup was still open at the end (a run
                where it closed early is repeated)

The plugin's cost is the difference between a run with the plugin enabled and
one with it disabled; run both. Scenarios that need a fake player refuse to
start while another player is playing, unless --pause-others is given, which
pauses those players for the run and resumes them afterwards.
"""

import argparse
import json
import os
import statistics
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN_DIR = os.path.dirname(HERE)
PLUGIN_ID = "io.github.ejsergeev.now-playing"
SHELL_PATH = "/usr/share/omarchy/shell"
TICK_MS = 1000 / os.sysconf("SC_CLK_TCK")
MPRIS = "org.mpris.MediaPlayer2"


# ── process helpers ────────────────────────────────────────────────────────

def shell_pid():
    out = subprocess.run(["pgrep", "-f", f"quickshell .*-p {SHELL_PATH}$"],
                         capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return b""


def cpu_ticks(pid):
    """(own, reaped children) CPU ticks of pid."""
    raw = read(f"/proc/{pid}/stat").decode()
    fields = raw[raw.rfind(")") + 2:].split()
    utime, stime, cutime, cstime = (int(x) for x in fields[11:15])
    return utime + stime, cutime + cstime


def pss_kb(pid):
    for line in read(f"/proc/{pid}/smaps_rollup").decode().splitlines():
        if line.startswith("Pss:"):
            return int(line.split()[1])
    return 0


def children(pid):
    kids = []
    for task in os.listdir(f"/proc/{pid}/task") if os.path.isdir(f"/proc/{pid}/task") else []:
        kids += [int(x) for x in read(f"/proc/{pid}/task/{task}/children").split()]
    return kids


def cmdline(pid):
    return read(f"/proc/{pid}/cmdline").replace(b"\0", b" ").decode(errors="replace").strip()


class SpawnSniffer(threading.Thread):
    """Polls the shell's children every 0.2 ms and records the ones that
    belong to this plugin: a script from its directory, or ImageMagick.
    QProcess forks from the main thread, so only its children list is read;
    a whole-process scan takes long enough to miss a 2 ms script."""

    def __init__(self):
        super().__init__(daemon=True)
        self.stop_flag = threading.Event()
        self.seen = {}        # pid -> cmdline, every process in a plugin tree
        self.roots = set()    # pids the shell itself started

    def ours(self, cmd):
        return PLUGIN_DIR in cmd or "now-playing" in cmd or "command -v magick" in cmd

    def visit(self, pid, depth):
        if pid in self.seen:
            return
        cmd = cmdline(pid)
        if not cmd:
            return
        if depth == 0 and not self.ours(cmd):
            return
        self.seen[pid] = cmd
        if depth == 0:
            self.roots.add(pid)
        for kid in children(pid):
            self.visit(kid, depth + 1)

    def run(self):
        pid = shell_pid()
        resolved = time.monotonic()
        while not self.stop_flag.is_set():
            if not pid or time.monotonic() - resolved > 0.5:   # the shell may restart
                pid, resolved = shell_pid(), time.monotonic()
            if pid:
                for kid in read(f"/proc/{pid}/task/{pid}/children").split():
                    self.visit(int(kid), 0)
                for known in list(self.seen):
                    for kid in read(f"/proc/{known}/task/{known}/children").split():
                        self.visit(int(kid), 1)
            time.sleep(0.0002)

    def stop(self):
        self.stop_flag.set()
        self.join()


# ── shell and players ──────────────────────────────────────────────────────

def ipc(target, method, *args):
    out = subprocess.run(["qs", "-p", SHELL_PATH, "ipc", "call", target, method, *args],
                         capture_output=True, text=True, timeout=10)
    return out.stdout.strip() if out.returncode == 0 else None


def plugin_metrics():
    raw = ipc("media", "metrics")
    try:
        return json.loads(raw) if raw else None
    except ValueError:
        return None


def mpris_names():
    out = subprocess.run(["busctl", "--user", "list", "--no-legend"], capture_output=True, text=True).stdout
    return [line.split()[0] for line in out.splitlines() if line.startswith(MPRIS + ".")]


def mpris(name, method):
    subprocess.run(["gdbus", "call", "--session", "-d", name, "-o", "/org/mpris/MediaPlayer2",
                    "-m", f"{MPRIS}.Player.{method}"], capture_output=True)


def playing(name):
    out = subprocess.run(["busctl", "--user", "get-property", name, "/org/mpris/MediaPlayer2",
                          f"{MPRIS}.Player", "PlaybackStatus"], capture_output=True, text=True).stdout
    return '"Playing"' in out


class FakePlayers:
    def __init__(self):
        self.procs = []

    def start(self, name, art):
        proc = subprocess.Popen([sys.executable, os.path.join(HERE, "fake-player.py"),
                                 "--name", name, "--art", art])
        self.procs.append(proc)
        bus = f"{MPRIS}.{name}"
        for _ in range(100):
            if bus in mpris_names():
                return bus
            time.sleep(0.05)
        raise RuntimeError(f"fake player {name} did not appear")

    def stop(self):
        for proc in self.procs:
            proc.terminate()
            proc.wait()


# ── scenarios ──────────────────────────────────────────────────────────────

def popup_open():
    widgets = (plugin_metrics() or {}).get("widgets") or []
    return any(w.get("open") for w in widgets)


def set_popup(want_open):
    """Opens or closes the popup, whatever state it is in (a click on the bar
    may have opened it), and waits until it is so."""
    for _ in range(20):
        if popup_open() == want_open:
            return
        subprocess.run(["omarchy-shell", "shell", "toggle", PLUGIN_ID, "{}"], capture_output=True)
        time.sleep(0.25)
    raise RuntimeError("could not " + ("open" if want_open else "close") + " the popup")


def scenario(name, seconds, players):
    """Returns (setup, action, teardown); action runs inside the window."""
    if name == "idle":
        return (lambda: None), (lambda: time.sleep(seconds)), (lambda: None)

    if name == "play":
        return (lambda: players.start("npbench", "always")), (lambda: time.sleep(seconds)), (lambda: None)

    if name in ("open-art", "open-spectrum"):
        art = "always" if name == "open-art" else "never"

        def setup():
            players.start("npbench", art)
            time.sleep(1.5)        # let the plugin settle on the new player
            set_popup(True)
            time.sleep(1.0)        # first open builds the popup: keep it out of the window
        return setup, (lambda: time.sleep(seconds)), (lambda: set_popup(False))

    if name == "churn":
        state = {}

        def setup():
            state["bus"] = players.start("npbench", "alternate")
            time.sleep(1.5)

        def act():
            for _ in range(20):
                mpris(state["bus"], "Next")
                time.sleep(0.4)
            time.sleep(max(0, seconds - 8))
        return setup, act, (lambda: None)

    if name == "switch":
        def setup():
            players.start("npbencha", "always")
            players.start("npbenchb", "always")
            time.sleep(1.5)

        def act():
            for _ in range(20):
                ipc("media", "sourceNext")
                time.sleep(0.4)
            time.sleep(max(0, seconds - 8))
        return setup, act, (lambda: None)

    if name == "startup":
        def act():
            subprocess.Popen(["omarchy-restart-shell"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(seconds)
        return (lambda: None), act, (lambda: None)

    raise SystemExit(f"unknown scenario {name}")


def run_once(name, seconds, pause_others):
    players = FakePlayers()
    paused = []
    needs_fake = name not in ("idle", "startup")
    busy = [n for n in mpris_names() if playing(n)]
    if needs_fake and busy:
        if not pause_others:
            raise SystemExit("playing now: " + ", ".join(busy) + " (pause them or pass --pause-others)")
        for bus in busy:
            mpris(bus, "Pause")
            paused.append(bus)

    setup, act, teardown = scenario(name, seconds, players)
    try:
        if name != "startup" and plugin_metrics() is not None:
            set_popup(False)
        setup()
        pid = shell_pid()
        before = cpu_ticks(pid)
        metrics_before = plugin_metrics()
        sniffer = SpawnSniffer()
        sniffer.start()
        started = time.monotonic()
        act()
        elapsed = time.monotonic() - started
        sniffer.stop()
        if name == "startup":
            pid = shell_pid()
            before = (0, 0)        # a new process: its whole life is the window
        after = cpu_ticks(pid)
        result = {
            "scenario": name,
            "seconds": round(elapsed, 1),
            "cpu_ms": round((after[0] - before[0]) * TICK_MS),
            "child_cpu_ms": round((after[1] - before[1]) * TICK_MS),
            "pss_kb": pss_kb(pid),
            "spawns": len(sniffer.roots),
            "processes": len(sniffer.seen),
            "commands": sorted({c.split(" ")[0] + " " + os.path.basename(c.split(" ")[1]) if " " in c else c
                                for c in sniffer.seen.values()}),
        }
        metrics_after = plugin_metrics()
        if metrics_after is not None:
            result["metrics"] = metrics_after
            if metrics_before is not None:
                result["metrics_delta"] = {k: v - metrics_before.get(k, 0) for k, v in metrics_after.items()
                                           if isinstance(v, (int, float))}
        return result
    finally:
        teardown()
        players.stop()
        for bus in paused:
            mpris(bus, "Play")


def popup_stayed_open(result):
    """An open-* run counts only if the popup was still open when the window
    ended: a click elsewhere closes it, and a closed popup costs nothing."""
    widgets = (result.get("metrics") or {}).get("widgets") or []
    return any(w.get("open") for w in widgets)


def main():
    parser = argparse.ArgumentParser(description="Measure the Now Playing plugin.")
    parser.add_argument("scenario")
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--label", default="")
    parser.add_argument("--pause-others", action="store_true")
    args = parser.parse_args()

    results = []
    attempts = 0
    while len(results) < args.runs:
        attempts += 1
        r = run_once(args.scenario, args.seconds, args.pause_others)
        r["label"] = args.label
        r["run"] = len(results) + 1
        r["valid"] = popup_stayed_open(r) if args.scenario.startswith("open-") else True
        print(json.dumps(r, ensure_ascii=False), flush=True)
        if r["valid"]:
            results.append(r)
        elif attempts >= args.runs * 3:
            raise SystemExit("the popup keeps closing during the window; is something clicking outside it?")
        time.sleep(1)
    if args.runs > 1:
        keys = ("cpu_ms", "child_cpu_ms", "pss_kb", "spawns", "processes")
        print(json.dumps({"scenario": args.scenario, "label": args.label, "median":
                          {k: statistics.median(r[k] for r in results) for k in keys}}))


if __name__ == "__main__":
    main()
