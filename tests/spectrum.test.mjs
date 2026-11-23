import { test } from "node:test"
import assert from "node:assert/strict"
import { load } from "./qmljs.mjs"

const S = load("lib/Spectrum.js")
const V1 = load("bench/baseline/Spectrum.js")

test("levels and peaks match 1.0.0 tick for tick, live and still, across track changes", () => {
  const state = S.create(S.BARS, S.ROWS)
  const old = { bars: S.BARS, rows: S.ROWS, live: true, levels: [], peaks: [], tick: 0, title: "", artist: "" }
  const tracks = [["Breeze", "Lonely in the Rain"], ["", ""], ["Ünïcödé ♪", "Ärtist"]]
  for (const [title, artist] of tracks) {
    S.reset(state, title, artist)
    Object.assign(old, { title, artist, levels: [], peaks: [] })
    for (let t = 0; t < 60; t++) {
      const live = t % 17 < 12
      old.live = live
      S.step(state, live)
      V1.step(old)
      assert.deepEqual([...state.levels], old.levels, `${title} tick ${t} levels`)
      assert.deepEqual([...state.peaks], old.peaks, `${title} tick ${t} peaks`)
    }
  }
})

test("a single bar has a flat shape", () => {
  const state = S.create(1, 4)
  S.reset(state, "a", "b")
  S.step(state, false)
  assert.ok(state.levels[0] >= S.FLOOR && state.levels[0] <= 4)
})

test("geometry fills the box exactly", () => {
  const state = S.create(8, 8)
  const g = S.geometry(state, 70, 70)
  assert.equal(g.gap, 2)
  assert.equal(g.barWidth * 8 + g.gap * 7, 70)
  assert.equal(g.cellHeight * 8 + g.gap * 7, 70)
  assert.equal(S.geometry(state, 20, 20).gap, 1)
})

function recorder() {
  const calls = []
  return {
    calls,
    set fillStyle(v) { calls.push(["fillStyle", v]) },
    set globalAlpha(v) { calls.push(["alpha", v]) },
    clearRect: (...a) => calls.push(["clear", ...a]),
    fillRect: (...a) => calls.push(["rect", ...a]),
    beginPath: () => {},
    roundedRect: (...a) => calls.push(["rounded", ...a]),
    fill: () => {},
  }
}

test("paint draws a lit cell or a dot per cell, and a cap above a fallen bar", () => {
  const state = S.create(2, 4)
  state.levels.set([2.5, 4])
  state.peaks.set([3.6, 4])
  const g = S.geometry(state, 40, 40)
  const ctx = recorder()
  S.paint(ctx, state, g, { foreground: "fg", accent: "ac" }, 0)
  const shapes = ctx.calls.filter(c => c[0] === "rect")
  // Bar 0: rows 0,1 lit, row 2 half lit, row 3 a dot, plus a cap; bar 1: 4 lit, no cap.
  assert.equal(shapes.length, 4 + 1 + 4)
  assert.ok(ctx.calls.some(c => c[0] === "fillStyle" && c[1] === "ac"))
  assert.deepEqual(ctx.calls.at(-1), ["alpha", 1])

  const rounded = recorder()
  S.paint(rounded, state, g, { foreground: "fg", accent: "ac" }, 6)
  assert.equal(rounded.calls.filter(c => c[0] === "rounded").length, 9)
})
