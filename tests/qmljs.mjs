// Loads a QML JavaScript resource (a lib/*.js file) in Node, the way the QML
// engine does: `.pragma library` is dropped, each `.import "X.js" as Name`
// makes X's functions available as Name, and the file's top-level functions
// and constants come back as one object.

import { readFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import vm from "node:vm"

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..")
const cache = new Map()

export function load(relativePath) {
  const file = resolve(root, relativePath)
  if (cache.has(file)) return cache.get(file)

  const imports = {}
  const lines = readFileSync(file, "utf8").split("\n").map(line => {
    const directive = line.match(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/)
    if (directive) {
      imports[directive[2]] = load(resolve(dirname(file), directive[1]).slice(root.length + 1))
      return ""
    }
    return /^\.pragma\s/.test(line) ? "" : line
  })

  // Top-level declarations are collected by listing them after the code, so
  // `const` and `function` both come back, and line numbers stay intact for
  // coverage and stack traces.
  const source = lines.join("\n")
  const names = [...source.matchAll(/^(?:function\s+(\w+)|(?:const|var|let)\s+(\w+))/gm)]
    .map(m => m[1] || m[2])
  const context = vm.createContext({ ...imports, Math, Date, String, Number, Array, Object, JSON, isFinite })
  const script = new vm.Script(`${source}\n;({ ${names.join(", ")} })`, { filename: file })
  const module = script.runInContext(context)
  cache.set(file, module)
  return module
}
