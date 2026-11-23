#!/usr/bin/env node
// Q5: structure of the plugin's own code (QML, JS, shell): lines per file,
// lines per function, and repeated blocks (the same four non-trivial lines,
// whitespace aside, in more than one place). Exits non-zero past the limits.
//   node tools/metrics.mjs [--json]
import { readFileSync, readdirSync } from "node:fs"
import { dirname, join, relative } from "node:path"
import { fileURLToPath } from "node:url"

const LIMITS = { fileLines: 350, functionLines: 40, duplicateBlocks: 0 }
const WINDOW = 4
const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const SKIP = new Set(["node_modules", "bench", "tests", "tools", "docs", "i18n"])

function sources(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(e => {
    if (e.name.startsWith(".") || SKIP.has(e.name)) return []
    const path = join(dir, e.name)
    return e.isDirectory() ? sources(path) : /\.(qml|js|sh)$/.test(e.name) ? [path] : []
  })
}

// Functions in QML/JS: from `function name(` to its matching brace. Shell:
// `name() {` to the closing `}` at the same indent.
function functions(text, isShell) {
  const lines = text.split("\n")
  const found = []
  lines.forEach((line, i) => {
    const m = isShell ? line.match(/^(\s*)(\w+)\(\)\s*\{/) : line.match(/\bfunction\s+(\w+)\s*\(/)
    if (!m) return
    if (isShell) {
      const end = lines.findIndex((l, j) => j > i && l === `${m[1]}}`)
      found.push({ name: m[2], line: i + 1, lines: (end < 0 ? lines.length : end) - i + 1 })
      return
    }
    let depth = 0, started = false
    for (let j = i; j < lines.length; j++) {
      for (const ch of lines[j].replace(/"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|\/\/.*$/g, "")) {
        if (ch === "{") { depth++; started = true }
        else if (ch === "}") depth--
      }
      if (started && depth <= 0) { found.push({ name: m[1], line: i + 1, lines: j - i + 1 }); return }
    }
  })
  return found
}

const TRIVIAL = /^(?:[{}()\[\],;]*|\/\/.*|#.*|else|return|import .*|\.\w+ .*)$/
const files = sources(root).sort()
const report = { files: [], functions: [], duplicates: [] }
const windows = new Map()

for (const file of files) {
  const rel = relative(root, file)
  const text = readFileSync(file, "utf8")
  const lines = text.split("\n")
  report.files.push({ file: rel, lines: lines.length - (text.endsWith("\n") ? 1 : 0) })
  for (const f of functions(text, rel.endsWith(".sh"))) report.functions.push({ file: rel, ...f })

  const code = lines.map((l, i) => ({ text: l.trim().replace(/\s+/g, " "), line: i + 1 }))
    .filter(l => !TRIVIAL.test(l.text))
  for (let i = 0; i + WINDOW <= code.length; i++) {
    const key = code.slice(i, i + WINDOW).map(l => l.text).join("\n")
    if (!windows.has(key)) windows.set(key, [])
    windows.get(key).push(`${rel}:${code[i].line}`)
  }
}
for (const [block, where] of windows) if (where.length > 1) report.duplicates.push({ where, block })

const overFiles = report.files.filter(f => f.lines > LIMITS.fileLines)
const overFunctions = report.functions.filter(f => f.lines > LIMITS.functionLines)
const summary = {
  files: report.files.length,
  totalLines: report.files.reduce((a, f) => a + f.lines, 0),
  largestFile: report.files.reduce((a, f) => (f.lines > a.lines ? f : a), { lines: 0 }),
  functions: report.functions.length,
  longestFunction: report.functions.reduce((a, f) => (f.lines > a.lines ? f : a), { lines: 0 }),
  filesOverLimit: overFiles.length,
  functionsOverLimit: overFunctions.length,
  duplicateBlocks: report.duplicates.length,
}

if (process.argv.includes("--json")) {
  console.log(JSON.stringify({ summary, ...report }, null, 2))
} else {
  for (const f of overFiles) console.log(`file over ${LIMITS.fileLines} lines: ${f.file} (${f.lines})`)
  for (const f of overFunctions) console.log(`function over ${LIMITS.functionLines} lines: ${f.file}:${f.line} ${f.name} (${f.lines})`)
  for (const d of report.duplicates) console.log(`repeated block: ${d.where.join(", ")}`)
  console.log("structure: " + JSON.stringify(summary))
}
process.exit(overFiles.length || overFunctions.length || report.duplicates.length > LIMITS.duplicateBlocks ? 1 : 0)
