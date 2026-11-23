// P3: the cost of one selection pass (every binding that re-evaluates when a
// player or a PipeWire node changes), 10 players over 20 playback streams.
import { load } from "../tests/qmljs.mjs"
import { bench } from "./run.mjs"
import * as fx from "./fixtures.mjs"

const PLAYERS = 10
const STREAMS = 20

function state() {
  const players = fx.players(PLAYERS)
  return {
    players, nodes: fx.nodes(STREAMS), playbackStreams: [],
    playerStartedAt: Object.fromEntries(players.map((p, i) => [p.dbusName, i + 1])),
    preferredPlayerKey: "", pinnedPlayerKey: "", lastPlayingKey: "",
  }
}

const baseline = load("bench/baseline/Selection.js")
const s = state()
const results = { baseline: bench(`baseline selection pass (${PLAYERS}p × ${STREAMS}s)`, () => baseline.selectionPass(s)) }
export default results
