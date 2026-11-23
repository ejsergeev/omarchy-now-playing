# Metrics

How Now Playing is measured, what it is held to, and where it stands. Every
number here can be reproduced with the tools in `tools/` and `bench/`.

## How to measure

| Tool | Measures |
|---|---|
| `tools/measure.py SCENARIO` | CPU, child CPU, PSS and spawned processes of the running shell during a scenario (P1, P2, M1, S1–S3) |
| `node bench/selection.bench.mjs` | one selection pass: every binding that re-evaluates when a player or a PipeWire node changes (P3) |
| `node bench/spectrum.bench.mjs` | one ASCII spectrum tick (P4) |
| `tools/lint.sh` | qmllint, shellcheck, unit tests with coverage, i18n, structure, manifest (Q1–Q6) |
| `qs -p /usr/share/omarchy/shell ipc call media metrics` | the plugin's own counters (spawns, cache hits, popup build time) and object counts per bar; counting starts with the first call (M2, L1, S1–S3) |

`tools/measure.py` drives silent fake MPRIS players (`tools/fake-player.py`)
so scenarios are repeatable and never touch real music. A fake player must be
the only one playing; `--pause-others` pauses the rest for the run and
resumes them after. It puts the popup in the state a scenario needs, and
repeats an `open-*` run whose popup closed during the window (a click
anywhere else closes it, and a closed popup costs nothing). Raw results are
kept in `docs/metrics/*.jsonl`.

Scenarios:

| Scenario | What happens in the window |
|---|---|
| `play` | a fake player plays, popup closed |
| `open-art` | a fake player plays a track with art, popup open (opened 1 s before the window) |
| `open-spectrum` | the same, track without art: the ASCII spectrum runs |
| `churn` | 20 track changes, 0.4 s apart, every other track with local art |
| `switch` | 20 `media sourceNext` calls, 0.4 s apart, between two fake players |
| `startup` | `omarchy-restart-shell`, then 15 s of the new shell's life |

Machine for the numbers below: one monitor, Omarchy shell on Quickshell,
Qt 6, aarch64, Node 26. CPU is in milliseconds of CPU time per window, so
1000 ms over 20 s is 5% of one core.

## Metrics and targets

| # | Metric | Target |
|---|---|---|
| P1 | CPU, popup closed, music playing | in the noise; no plugin timer runs while the popup is closed |
| P2 | CPU, popup open: art / spectrum | spectrum at least halved; art close to the 1 Hz position update only |
| P3 | one selection pass, 10 players × 20 streams | at least 5× faster |
| P4 | one spectrum tick | under 20 µs, no string work per tick |
| M1 | shell PSS with the plugin vs without, popup never opened | at least 80% less |
| M2 | objects the plugin creates per bar: popup closed / open | closed ≤ 5, open ≤ 70 |
| M3 | decoded cover bitmaps | at most 2, box-sized |
| S1 | processes started at shell startup | at most 1 per shell, not per bar |
| S2 | processes per track change with local art | at most 1, none for an art URL seen before |
| S3 | processes per source switch with known icons | 0 |
| L1 | first popup open (lazy build) | under 30 ms; reopening within a frame |
| L2 | MPRIS change to updated state | within one event loop turn, except deliberate hold delays |
| Q1 | unit-test coverage of `lib/*.js` | 100% lines, ≥ 95% branches |
| Q2 | qmllint warnings | 0 |
| Q3 | shellcheck findings | 0 |
| Q4 | i18n problems (missing, extra, empty keys; placeholders; unused) | 0 |
| Q5 | structure | files ≤ 350 lines, functions ≤ 40 lines, no repeated blocks |
| Q6 | `omarchy plugin validate` | passes |

## Results

Baseline is version 1.0.0 (commit `d285467`), rewrite is the rebuild
(`2016dc3`), cover styles adds the three ways to show a cover and the
handling of YouTube Music skips (`fea620c`). All measured on 2026-11-23 on
the same machine with the same tools; raw results in `docs/metrics/`
(`baseline`, `final`, `cover-styles`).

| # | Metric | 1.0.0 | Rewrite | Cover styles | Target |
|---|---|---|---|---|---|
| P1 | CPU, `play` (popup closed), 20 s | 30 ms | 50 ms | 30 ms | met: both are noise; neither runs a timer while the popup is closed |
| P2 | CPU, `open-art`, 20 s | 610 ms | 555 ms (−9%) | 535 ms (cover), 540 ms (duotone) | **not met**, see below |
| P2 | CPU, `open-spectrum`, 20 s | 1315 ms | 1185 ms (−10%) | 1140 ms | **not met**, see below |
| P3 | selection, full pass (players or nodes change) | 29.1 µs | 8.4 µs (3.5×) | 8.4 µs | not met for the full pass |
| P3 | selection, play/pause (the frequent change) | 28.1 µs | 1.1 µs (25×) | 1.1 µs | met |
| P4 | spectrum tick | 5.6 µs | 0.06–0.15 µs (≈ 40–90×) | 0.06 µs | met |
| M1 | shell PSS with − without plugin, after startup | ≈ 7.3 MB | ≈ 5.0 MB | ≈ −1.3 MB (noise) | not provable: PSS noise is ±3 MB; M2 is the precise measure |
| M2 | objects per bar, popup never opened | 380 (41 bar + 339 popup, built at startup on every bar) | 25 (popup not built) | 25 | −93%; the 25 are the host's BarIconButton and panel |
| M2 | objects per bar, popup open | 339 | 135 | 136; 138 with the duotone layer | −60%; most of the rest are host controls' insides |
| M3 | decoded covers | ≤ 2, box-sized | ≤ 2, box-sized, none before the first open | ≤ 2, box-sized | met |
| S1 | processes at startup (1 bar) | 3 spawns, 14 processes | 1 spawn, 6–7 processes (the app icon) | 2 spawns, 9 processes: the app icon, and a probe of the cover playing at startup | met |
| S2 | `churn`: 20 changes, 10 with art | 10 spawns, 24 processes | 9 spawns, 18 processes | 9 spawns, 18 processes | met: one probe per new cover is the floor |
| S3 | `switch`: 20 switches between 2 players | 39 spawns, 98 processes, 190 ms child CPU | 2 spawns, 4 processes, 10 ms | 2 spawns, 4 processes, 20 ms | met: only the first look at a player runs anything |
| L1 | first popup open | not measurable | 20–40 ms; reopening keeps the built popup | 18 ms | about met |
| Q1 | coverage of `lib/*.js` | `MediaModel.js` only, 100% / 98% | 8 modules, 100% lines / 98.3% branches, 46 tests | 9 modules, 100% lines / 98.4% branches, 49 tests | met |
| Q2 | qmllint warnings | 80 | 0 | 0 | met |
| Q3 | shellcheck | not run | not run | not run | open: shellcheck is not installed here |
| Q4 | i18n problems | 0 | 0 | 0 | met |
| Q5 | structure | 2 files over 350 lines (largest 1393), 1 function over 40, 3 repeated blocks | 0, 0, 0 (largest file 322 lines) | 0, 0, 0 (largest file 345 lines) | met |
| Q6 | `omarchy plugin validate` | passes | passes | passes | met |

P3 and P4 baselines are lower than first recorded (84 and 106 µs): the first
bench ran code in a separate V8 context, which slowed both versions alike.
Both columns above run in the same context.

**Why P2 is not met.** With the popup open and nothing playing, the shell
spends nothing: 0 ms over 10 s. Playing, the cost is frames, not the plugin's
JavaScript. The host's `PanelSlider` animates its fill and knob for 140 ms on
every value change, and the seek bar's value changes once a second, so each
second draws a short animation at the display's refresh rate. With the seek
bar's value frozen as an experiment, `open-art` drops to 105 ms and
`open-spectrum` to 745 ms. The plugin keeps `PanelSlider` so the seek bar
stays exactly the shell's own; the fix belongs in the shell (not animating
small programmatic steps). The spectrum's own JavaScript went from 5.6 µs to
about 0.1 µs a tick, which is invisible next to the frame cost.

**Why the full P3 pass is 3.5×, not 5×.** What is left is matching stream
labels to player labels by substring, which is inherent to how streams are
named. It now runs only when players or streams appear, go or are renamed;
play/pause, the change that happens all the time, no longer runs it.

**Not measured here.** Media keys still reach the plugin through
`omarchy-shell media …`, one process per key press: the shell routes key
presses in-process only to `omarchy.media` and its clones, and the plugin
does not claim to be one.
