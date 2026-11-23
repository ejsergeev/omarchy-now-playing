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

// The rewrite: the same bindings in Service.qml, each evaluated once.
const M = load("lib/MediaModel.js")
const Streams = load("lib/Streams.js")
function pass(s) {
  const streams = Streams.playbackStreams(s.nodes)
  const byStream = Streams.streamsByPlayer(s.players, streams)
  const byKey = M.indexByKey(s.players)
  const playing = M.playingPlayer(s.players, s.playerStartedAt, byStream)
  const active = M.activePlayer({ players: s.players, byKey, streams: byStream, playing,
    preferredKey: s.preferredPlayerKey, pinnedKey: s.pinnedPlayerKey, lastPlayingKey: s.lastPlayingKey })
  const control = playing || byKey[s.lastPlayingKey] || active
  M.sourceRows(s.players)
  return { active, playing, control, activeStreams: byStream[M.playerKey(active)] || [] }
}
results.rewrite = bench(`rewrite selection pass (${PLAYERS}p × ${STREAMS}s)`, () => pass(s))
console.log(`speed-up: ${(results.baseline / results.rewrite).toFixed(1)}×`)

// Play/pause. 1.0.0 read isPlaying in its source and cycle sorts and matched
// stream labels inside the playing-player search, so all of that ran again
// (all but the node filter). The rewrite re-evaluates the play order, the
// playing, active and control players; streams and the source list do not
// read isPlaying.
function baselinePlayPause(state) {
  const sourcePlayers = baseline.orderedSourcePlayers(state)
  baseline.orderedCycleSourcePlayers(state)
  const active = baseline.selectActivePlayer(state)
  const playing = baseline.oldestPlayingPlayer(state, true) || baseline.oldestPlayingPlayer(state, false)
  void (playing || baseline.playerForKey(state, state.lastPlayingKey) || active)
  baseline.widgetSourcePlayers(state, sourcePlayers)
  baseline.widgetPlayerStreams(state, active)
}
const byStream = Streams.streamsByPlayer(s.players, Streams.playbackStreams(s.nodes))
const byKey = M.indexByKey(s.players)
function rewritePlayPause(state) {
  const order = M.playOrder(state.players, state.playerStartedAt, 100).order
  const playing = M.playingPlayer(state.players, order, byStream)
  const active = M.activePlayer({ players: state.players, byKey, streams: byStream, playing,
    preferredKey: state.preferredPlayerKey, pinnedKey: state.pinnedPlayerKey, lastPlayingKey: state.lastPlayingKey })
  return playing || byKey[state.lastPlayingKey] || active
}
baseline.selectionPass(s)   // fills s.playbackStreams for the baseline
results.baselinePlayPause = bench("baseline play/pause pass", () => baselinePlayPause(s))
results.rewritePlayPause = bench("rewrite play/pause pass", () => rewritePlayPause(s))
console.log(`speed-up: ${(results.baselinePlayPause / results.rewritePlayPause).toFixed(1)}×`)
