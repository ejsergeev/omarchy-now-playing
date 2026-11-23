.pragma library

// The ASCII spectrum shown when a track has no cover: an LED-meter grid of
// bars made of stacked cells, empty cells drawn as dots, with falling peak
// caps. Its resting shape comes from the track's name, so each track gets its
// own; while playing, the bars dance. Everything per tick works on numbers in
// preallocated arrays: the track's name is hashed once, when it changes.

var BARS = 8
var ROWS = 8
var TICK_MS = 110
var LIT = 0.12          // a cell this full or less is drawn as a dot
var PEAK_FALL = 0.25    // cells a peak cap falls per tick
var FLOOR = 0.6         // no bar drops below this many cells

// FNV-1a over the text.
function seedOf(text) {
  var h = 2166136261
  for (var k = 0; k < text.length; k++) {
    h ^= text.charCodeAt(k)
    h = Math.imul(h, 16777619) >>> 0
  }
  return h
}

// Deterministic noise in [0, 1] for a bar and a step, from the track's seed.
function noise(seed, i, t) {
  var h = seed
  h ^= Math.imul(i + 1, 0x9e3779b1) >>> 0
  h ^= Math.imul(t + 7, 0x85ebca6b) >>> 0
  h ^= h >>> 15
  h = Math.imul(h, 0x2c1b3c6d) >>> 0
  h ^= h >>> 12
  return (h >>> 0) / 4294967295
}

function create(bars, rows) {
  return {
    bars: bars, rows: rows, seed: 0, tick: 0, primed: false,
    base: new Float64Array(bars), levels: new Float64Array(bars), peaks: new Float64Array(bars),
  }
}

// A new track: its resting shape, a gentle curve plus per-bar character, and
// levels that start from it.
function reset(state, title, artist) {
  var seed = seedOf(String(title) + "|" + String(artist))
  var bend = 1.2 + noise(seed, 99, 0)
  var phase = noise(seed, 98, 0) * 6
  for (var i = 0; i < state.bars; i++) {
    var x = state.bars > 1 ? i / (state.bars - 1) : 0
    var curve = 0.55 + 0.35 * Math.sin(x * Math.PI * bend + phase)
    state.base[i] = Math.min(1, Math.max(0.25, curve * (0.75 + 0.45 * noise(seed, i, 0))))
  }
  state.seed = seed
  state.primed = false
}

// One tick. Live, bars move toward a noisy target and peaks fall slowly;
// still (paused, closed), bars rest on their shape and caps sit on them.
function step(state, live) {
  for (var i = 0; i < state.bars; i++) {
    var target = state.base[i] * state.rows
    if (live) target *= 0.5 + 0.8 * noise(state.seed, i, state.tick)
    var current = state.primed ? state.levels[i] : target
    var level = live ? current * 0.45 + target * 0.55 : target
    level = Math.max(FLOOR, Math.min(state.rows, level))
    var peak = live && state.primed ? state.peaks[i] - PEAK_FALL : level
    state.levels[i] = level
    state.peaks[i] = Math.max(level, peak)
  }
  state.primed = true
  state.tick++
}

// Cell and gap sizes that fill a width × height box exactly.
function geometry(state, width, height) {
  var gap = Math.max(1, Math.round(width / 40))
  return {
    width: width, height: height, gap: gap,
    barWidth: (width - gap * (state.bars - 1)) / state.bars,
    cellHeight: (height - gap * (state.rows - 1)) / state.rows,
    dot: Math.max(1, Math.round(gap * 1.2)),
  }
}

function rect(ctx, x, y, w, h, radius) {
  if (radius > 0) {
    ctx.beginPath()
    ctx.roundedRect(x, y, w, h, radius, radius)
    ctx.fill()
  } else {
    ctx.fillRect(x, y, w, h)
  }
}

// Draws the grid on a Canvas 2D context. colors: { foreground, accent };
// radius: the theme's corner radius.
function paint(ctx, state, g, colors, radius) {
  ctx.clearRect(0, 0, g.width, g.height)
  var cellRadius = Math.min(1, radius)
  var dotRadius = Math.min(g.dot / 2, radius)
  var capHeight = Math.max(2, Math.round(g.cellHeight * 0.3))
  for (var i = 0; i < state.bars; i++) {
    var x = i * (g.barWidth + g.gap)
    var level = state.levels[i]
    ctx.fillStyle = colors.foreground
    for (var r = 0; r < state.rows; r++) {
      var y = g.height - (r + 1) * g.cellHeight - r * g.gap
      var fill = Math.max(0, Math.min(1, level - r))
      if (fill > LIT) {
        var lit = Math.round(g.cellHeight * fill)
        ctx.globalAlpha = 0.45 + 0.4 * (r / Math.max(1, state.rows - 1))
        rect(ctx, x, y + g.cellHeight - lit, g.barWidth, lit, cellRadius)
      } else {
        ctx.globalAlpha = 0.25
        rect(ctx, x + (g.barWidth - g.dot) / 2, y + (g.cellHeight - g.dot) / 2, g.dot, g.dot, dotRadius)
      }
    }
    // The peak cap, in the accent colour, above the lit cells.
    var top = Math.ceil(level)
    var cell = Math.min(state.rows, Math.ceil(state.peaks[i])) - 1
    if (state.peaks[i] > top - 0.01 && cell >= top) {
      ctx.globalAlpha = 1
      ctx.fillStyle = colors.accent
      rect(ctx, x, g.height - (cell + 1) * g.cellHeight - cell * g.gap, g.barWidth, capHeight, cellRadius)
    }
  }
  ctx.globalAlpha = 1
}
