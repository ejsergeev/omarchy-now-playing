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
| `qs -p /usr/share/omarchy/shell ipc call media metrics` | the plugin's own counters, when the shell runs with `NOW_PLAYING_METRICS=1` (M2, L1, S1–S3) |

`tools/measure.py` drives silent fake MPRIS players (`tools/fake-player.py`)
so scenarios are repeatable and never touch real music. A fake player must be
the only one playing; `--pause-others` pauses the rest for the run and
resumes them after. Raw results are kept in `docs/metrics/*.jsonl`.

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

Baseline is version 1.0.0 (commit `d285467`), measured 2026-11-23.

| # | Metric | Baseline (1.0.0) | Final |
|---|---|---|---|
| P1 | CPU, `play`, 20 s | 30 ms | |
| P2 | CPU, `open-art`, 20 s | 610 ms (3.0%) | |
| P2 | CPU, `open-spectrum`, 20 s | 1315 ms (6.6%) | |
| P3 | selection pass | 84.4 µs | |
| P4 | spectrum tick | 106.5 µs | |
| M1 | PSS with − without plugin, after startup | ≈ 7.3 MB (284.6 vs 277.3 MB, noisy) | |
| M2 | objects per bar, closed / open | ≈ 290 / ≈ 290 (eager: built at startup on every bar; 217 of them the spectrum) | |
| S1 | processes at startup (1 bar) | 3 spawns, 14 processes (`command -v magick`, `app-icon.sh`, `probe-art.sh` and their children) | |
| S2 | `churn`: 20 changes, 10 with art | 10 spawns, 24 processes | |
| S3 | `switch`: 20 switches | 39 spawns, 98 processes | |
| L1 | first popup open | not measurable (no counters in 1.0.0) | |
| Q1 | coverage | `MediaModel.js` 100% lines / 98% branches (tests added after 1.0.0); no other logic testable | |
| Q2 | qmllint | 80 warnings (53 unqualified, 27 missing-property) | |
| Q3 | shellcheck | not run (not installed) | |
| Q4 | i18n | 0 problems | |
| Q5 | structure | 2 files over 350 lines (`BarWidget.qml` 1393, `Service.qml` 609), 1 function over 40 (`runAction`, 64), 3 repeated blocks | |
| Q6 | validate | passes | |

Each bar has its own `BarWidget`, so with more than one monitor everything in
M2 and S1–S3 was multiplied by the number of bars.
