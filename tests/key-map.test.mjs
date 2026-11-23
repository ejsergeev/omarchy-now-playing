import { test } from "node:test"
import assert from "node:assert/strict"
import { load } from "./qmljs.mjs"

const K = load("lib/KeyMap.js")
const CTRL = 0x04000000, SHIFT = 0x02000000

test("Latin letters act by letter, wherever the key is", () => {
  assert.equal(K.action("h", 43, 0), "previous")
  assert.equal(K.action("s", 47, 0), "shuffle")   // Dvorak: s sits on the US ; key
  assert.equal(K.action("S", 39, SHIFT), "shuffle")
  assert.equal(K.action(",", 59, 0), "seekBack")
  assert.equal(K.action("x", 53, 0), "")
})

test("other layouts act by the key's US position", () => {
  const ru = { р: 43, д: 46, о: 44, л: 45, б: 59, ю: 60, ь: 58, ы: 39, к: 27 }
  const expected = { р: "previous", д: "next", о: "volumeDown", л: "volumeUp", б: "seekBack", ю: "seekForward", ь: "mute", ы: "shuffle", к: "repeat" }
  for (const [letter, code] of Object.entries(ru)) assert.equal(K.action(letter, code, 0), expected[letter], letter)
  assert.equal(K.action("Ж", 47, SHIFT), "")
})

test("chords, empty text and multi-character text are not popup keys", () => {
  assert.equal(K.action("s", 39, CTRL), "")
  assert.equal(K.action("", 113, 0), "")
  assert.equal(K.action(undefined, 0, 0), "")
  assert.equal(K.action("ab", 0, 0), "")
})
