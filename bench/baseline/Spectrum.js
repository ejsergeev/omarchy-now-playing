.pragma library

// Version 1.0.0's ASCII spectrum step (BarWidget.qml, asciiArt), frozen for
// the P4 baseline. `a` stands in for the asciiArt item's properties.

function noise(a, i, t) {
  var seed = String(a.title) + "|" + String(a.artist)
  var h = 2166136261
  for (var k = 0; k < seed.length; k++) { h ^= seed.charCodeAt(k); h = Math.imul(h, 16777619) >>> 0 }
  h ^= Math.imul(i + 1, 0x9e3779b1) >>> 0
  h ^= Math.imul(t + 7, 0x85ebca6b) >>> 0
  h ^= h >>> 15; h = Math.imul(h, 0x2c1b3c6d) >>> 0; h ^= h >>> 12
  return (h >>> 0) / 4294967295
}

function base(a, i) {
  var x = a.bars > 1 ? i / (a.bars - 1) : 0
  var curve = 0.55 + 0.35 * Math.sin(x * Math.PI * (1.2 + noise(a, 99, 0)) + noise(a, 98, 0) * 6)
  return Math.min(1, Math.max(0.25, curve * (0.75 + 0.45 * noise(a, i, 0))))
}

function step(a) {
  var next = [], nextPeaks = []
  for (var i = 0; i < a.bars; i++) {
    var target = base(a, i) * a.rows
    if (a.live) target *= 0.5 + 0.8 * noise(a, i, a.tick)
    var cur = a.levels[i] !== undefined ? a.levels[i] : target
    var v = a.live ? cur * 0.45 + target * 0.55 : target
    v = Math.max(0.6, Math.min(a.rows, v))
    next.push(v)
    var pk = a.live && a.peaks[i] !== undefined ? a.peaks[i] - 0.25 : v
    nextPeaks.push(Math.max(v, pk))
  }
  a.levels = next
  a.peaks = nextPeaks
  a.tick++
}
