import { test } from "node:test"
import assert from "node:assert/strict"
import { load } from "./qmljs.mjs"

const C = load("lib/CoverStyle.js")

test("styles cycle cover, duotone, spectrum and back", () => {
  assert.equal(C.next("cover"), "duotone")
  assert.equal(C.next("duotone"), "spectrum")
  assert.equal(C.next("spectrum"), "cover")
  assert.equal(C.next("bogus"), "duotone")   // an unknown style counts as the default
})

test("stored values other than a style read as the default", () => {
  for (const style of ["cover", "duotone", "spectrum"]) assert.equal(C.normalize(style), style)
  for (const junk of ["", "Cover", null, undefined, 3, {}]) assert.equal(C.normalize(junk), "cover")
})

test("without a cover the box always shows the spectrum", () => {
  assert.equal(C.shown("duotone", true), "duotone")
  assert.equal(C.shown("bogus", true), "cover")
  assert.equal(C.shown("cover", false), "spectrum")
  assert.equal(C.shown("duotone", false), "spectrum")
})
