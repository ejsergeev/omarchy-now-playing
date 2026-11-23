// P4: JavaScript time per ASCII spectrum tick (8 bars × 8 rows, playing).
import { load } from "../tests/qmljs.mjs"
import { bench } from "./run.mjs"

const TITLE = "Breeze (Extended Mix)"
const ARTIST = "Lonely in the Rain"

const baseline = load("bench/baseline/Spectrum.js")
const a = { title: TITLE, artist: ARTIST, bars: 8, rows: 8, live: true, levels: [], peaks: [], tick: 0 }
const results = { baseline: bench("baseline spectrum tick (8×8)", () => baseline.step(a)) }
export default results
