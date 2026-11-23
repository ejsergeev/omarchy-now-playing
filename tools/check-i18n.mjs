#!/usr/bin/env node
// Q4: every catalog in i18n/ has exactly the keys of en.json, each value is a
// non-empty string with the same %N placeholders, and the QML uses exactly
// those keys (no missing, no unused).
import { readFileSync, readdirSync } from "node:fs"
import { dirname, join, relative } from "node:path"
import { fileURLToPath } from "node:url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const problems = []
const placeholders = s => [...String(s).matchAll(/%\d/g)].map(m => m[0]).sort().join(",")

const en = JSON.parse(readFileSync(join(root, "i18n/en.json"), "utf8"))
const keys = Object.keys(en)

for (const file of readdirSync(join(root, "i18n")).filter(f => f.endsWith(".json")).sort()) {
  let catalog
  try {
    catalog = JSON.parse(readFileSync(join(root, "i18n", file), "utf8"))
  } catch (e) {
    problems.push(`${file}: invalid JSON (${e.message})`)
    continue
  }
  for (const key of keys) {
    if (!(key in catalog)) problems.push(`${file}: missing ${key}`)
    else if (typeof catalog[key] !== "string" || !catalog[key].trim()) problems.push(`${file}: empty ${key}`)
    else if (placeholders(catalog[key]) !== placeholders(en[key])) problems.push(`${file}: placeholders differ in ${key}`)
  }
  for (const key of Object.keys(catalog)) if (!(key in en)) problems.push(`${file}: unknown key ${key}`)
}

function qmlFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(e => {
    if (e.name.startsWith(".") || ["node_modules", "bench", "tests", "tools"].includes(e.name)) return []
    const path = join(dir, e.name)
    return e.isDirectory() ? qmlFiles(path) : /\.(qml|js)$/.test(e.name) ? [path] : []
  })
}

const used = new Set()
for (const file of qmlFiles(root)) {
  for (const m of readFileSync(file, "utf8").matchAll(/strings\.t\("([^"]+)"/g)) {
    used.add(m[1])
    if (!(m[1] in en)) problems.push(`${relative(root, file)}: uses unknown key ${m[1]}`)
  }
}
for (const key of keys) if (!used.has(key)) problems.push(`en.json: unused key ${key}`)

for (const p of problems) console.log(p)
console.log(`i18n: ${readdirSync(join(root, "i18n")).length} catalogs, ${keys.length} keys, ${problems.length} problems`)
process.exit(problems.length ? 1 : 0)
