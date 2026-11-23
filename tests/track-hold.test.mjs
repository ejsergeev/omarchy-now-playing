import { test } from "node:test"
import assert from "node:assert/strict"
import { load } from "./qmljs.mjs"

const H = load("lib/TrackHold.js")
const base = { hasPlayer: true, key: "a", shownKey: "a", shownGone: false, explicit: false, liveMedia: true, stopped: false }

test("a switch to another player waits, unless it is explicit, the shown one quit, or none is left", () => {
  assert.equal(H.refreshAction({ ...base, key: "b" }), "waitSwitch")
  assert.equal(H.refreshAction({ ...base, key: "b", explicit: true }), "apply")
  assert.equal(H.refreshAction({ ...base, key: "b", shownGone: true }), "apply")
  assert.equal(H.refreshAction({ ...base, hasPlayer: false, key: "" }), "apply")
})

test("blank metadata waits unless the player stopped", () => {
  assert.equal(H.refreshAction(base), "apply")
  assert.equal(H.refreshAction({ ...base, liveMedia: false }), "waitBlank")
  assert.equal(H.refreshAction({ ...base, liveMedia: false, stopped: true }), "apply")
})

test("art: new art is probed, known or rejected art kept, missing art cleared now or later", () => {
  const art = { liveArtUrl: "file:///b", artUrl: "file:///a", rejectedArtUrl: "", liveMedia: true }
  assert.equal(H.artAction(art), "probe")
  assert.equal(H.artAction({ ...art, artUrl: "file:///b" }), "keep")
  assert.equal(H.artAction({ ...art, rejectedArtUrl: "file:///b" }), "keep")
  assert.equal(H.artAction({ ...art, liveArtUrl: "" }), "clearLater")
  assert.equal(H.artAction({ ...art, liveArtUrl: "", liveMedia: false }), "clear")
})

test("track identity, probe keys and retries", () => {
  assert.equal(H.trackIdentity("k", { trackTitle: "T", trackArtist: "A" }), "k\u001fT\u001fA")
  assert.equal(H.trackIdentity("k", { trackTitle: "T" }), "k\u001fT\u001f")
  assert.equal(H.trackIdentity("", null), "\u001f")
  assert.notEqual(H.probeKey("u", "t1"), H.probeKey("u", "t2"))
  assert.equal(H.retryArt(1), true)
  assert.equal(H.retryArt(2), true)
  assert.equal(H.retryArt(3), false)
})
