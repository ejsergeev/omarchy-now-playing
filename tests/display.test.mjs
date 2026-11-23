import { test } from "node:test"
import assert from "node:assert/strict"
import { load } from "./qmljs.mjs"

const D = load("lib/Display.js")
const latin = n => String(n)
const arabic = n => String(n).replace(/\d/g, d => "٠١٢٣٤٥٦٧٨٩"[d])

test("formatTime", () => {
  assert.equal(D.formatTime(0, latin), "0:00")
  assert.equal(D.formatTime(65.9, latin), "1:05")
  assert.equal(D.formatTime(3725, latin), "1:02:05")
  assert.equal(D.formatTime(-3, latin), "0:00")
  assert.equal(D.formatTime(NaN, latin), "0:00")
  assert.equal(D.formatTime(Infinity, latin), "0:00")
  assert.equal(D.formatTime(65, arabic), "١:٠٥")
})

test("moodKey follows playback", () => {
  const s = { hasPlayer: true, muted: false, playing: true, hasTimeline: true, position: 50, length: 200 }
  assert.equal(D.moodKey({ ...s, hasPlayer: false }), "media.mood.silence")
  assert.equal(D.moodKey({ ...s, muted: true }), "media.mood.silentDisco")
  assert.equal(D.moodKey({ ...s, playing: false }), "media.mood.intermission")
  assert.equal(D.moodKey({ ...s, hasTimeline: false }), "media.mood.onAir")
  assert.equal(D.moodKey({ ...s, position: 5 }), "media.mood.needleDrop")
  assert.equal(D.moodKey({ ...s, position: 190 }), "media.mood.encore")
  assert.equal(D.moodKey({ ...s, position: 50 }), "media.mood.warmingUp")
  assert.equal(D.moodKey({ ...s, position: 100 }), "media.mood.inTheGroove")
  assert.equal(D.moodKey({ ...s, position: 160 }), "media.mood.finalChorus")
})

test("albumText drops placeholder albums", () => {
  assert.equal(D.albumText("Abbey Road"), "Abbey Road")
  for (const none of ["-", " – ", "_", ".", "·", "", undefined]) assert.equal(D.albumText(none), "")
})

test("capitalize, volumeGlyph, nextLoopState", () => {
  assert.equal(D.capitalize("chromium"), "Chromium")
  assert.equal(D.capitalize(""), "")
  assert.equal(D.capitalize(null), "")
  assert.equal(D.volumeGlyph(0.5, true), "")
  assert.equal(D.volumeGlyph(0, false), "")
  assert.equal(D.volumeGlyph(0.2, false), "")
  assert.equal(D.volumeGlyph(0.5, false), "")
  assert.equal(D.volumeGlyph(0.9, false), "")
  assert.equal(D.nextLoopState(0, 0, 2, 1), 2)
  assert.equal(D.nextLoopState(2, 0, 2, 1), 1)
  assert.equal(D.nextLoopState(1, 0, 2, 1), 0)
})

test("imColor writes rgba() and localPath reads file URLs", () => {
  assert.equal(D.imColor({ r: 1, g: 0.5, b: 0, a: 0.25 }), "rgba(255,128,0,0.250)")
  assert.equal(D.localPath("file:///tmp/a%20b.png"), "/tmp/a b.png")
  assert.equal(D.localPath("file://localhost/x"), "/x")
  assert.equal(D.localPath("https://x/y.png"), "")
  assert.equal(D.localPath("file:///bad%E0%A4%A"), "")
})
