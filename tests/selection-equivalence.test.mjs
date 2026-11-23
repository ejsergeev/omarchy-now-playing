// The selection rewrite against version 1.0.0's code (bench/baseline), on
// thousands of random players and streams: the same player is shown, plays,
// takes the keys, and gets the same streams; the source list and the cycle
// order match.
import { test } from "node:test"
import assert from "node:assert/strict"
import { load } from "./qmljs.mjs"
import { player, node } from "../bench/fixtures.mjs"

// One namespace over the three model modules.
const M = { ...load("lib/MediaModel.js"), ...load("lib/Streams.js"), ...load("lib/Actions.js") }
const V1 = load("bench/baseline/Selection.js")

// Mulberry32: a small seeded generator, so a failure reproduces.
function random(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const APPS = [["chromium.instance1", "Chromium", ""], ["chromium.instance2", "Chromium", ""], ["spotify", "Spotify", "spotify"],
  ["mpv", "mpv", "mpv"], ["firefox", "Mozilla Firefox", "firefox"], ["playerctld", "playerctld", "playerctld"], ["vlc", "", ""]]
const LABELS = ["Chromium", "spotify", "PipeWire ALSA [mpv]", "Firefox", "Mozilla Firefox", "vlc", "", "speech-dispatcher"]

function scenario(rand) {
  const pick = list => list[Math.floor(rand() * list.length)]
  const flag = p => rand() < p
  const players = APPS.filter(() => flag(0.6)).map(([bus, identity, desktopEntry]) => player({
    dbusName: `org.mpris.MediaPlayer2.${bus}`, identity, desktopEntry,
    trackTitle: flag(0.6) ? pick(["Alpha", "Beta", "Gamma", ""]) : "",
    trackArtist: flag(0.4) ? pick(["Ann", "Bob"]) : "",
    trackAlbum: flag(0.3) ? "Album" : "",
    trackArtUrl: flag(0.3) ? "file:///art.png" : "",
    isPlaying: flag(0.45),
    canPlay: flag(0.8), canPause: flag(0.8), canTogglePlaying: flag(0.7), canGoNext: flag(0.7), canGoPrevious: flag(0.7),
  }))
  const nodes = Array.from({ length: Math.floor(rand() * 6) }, () => node({
    isStream: flag(0.9), isSink: flag(0.5), type: pick(["Stream/Output/Audio", "Stream/Input/Audio", "Audio/Sink"]),
    properties: { "application.name": pick(LABELS) }, audio: flag(0.9) ? { volume: 1, muted: false } : null,
  }))
  const keys = ["", ...players.map(M.playerKey), "org.mpris.MediaPlayer2.gone"]
  const playerStartedAt = {}
  for (const p of players) if (p.isPlaying && flag(0.8)) playerStartedAt[M.playerKey(p)] = Math.floor(rand() * 5)
  return { players, nodes, playerStartedAt, preferredPlayerKey: pick(keys), pinnedPlayerKey: pick(keys), lastPlayingKey: pick(keys) }
}

function rewrite(s) {
  const streams = M.playbackStreams(s.nodes)
  const byStream = M.streamsByPlayer(s.players, streams)
  const byKey = M.indexByKey(s.players)
  const playing = M.playingPlayer(s.players, s.playerStartedAt, byStream)
  const active = M.activePlayer({ players: s.players, byKey, streams: byStream, playing,
    preferredKey: s.preferredPlayerKey, pinnedKey: s.pinnedPlayerKey, lastPlayingKey: s.lastPlayingKey })
  const control = playing || byKey[s.lastPlayingKey] || active
  return { active, playing, control, rows: M.sourceRows(s.players), cycle: M.cycleOrder(s.players),
    activeStreams: (active && byStream[M.playerKey(active)]) || [] }
}

function original(s) {
  const state = { ...s, playbackStreams: [] }
  const r = V1.selectionPass(state)
  return { active: r.activePlayer, playing: r.playingPlayer, control: r.controlPlayer,
    rows: V1.widgetSourcePlayers(state, V1.orderedSourcePlayers(state)), cycle: V1.orderedCycleSourcePlayers(state),
    activeStreams: V1.widgetPlayerStreams(state, r.activePlayer) }
}

test("selection matches 1.0.0 on 3000 random states", () => {
  const rand = random(20261123)
  for (let i = 0; i < 3000; i++) {
    const s = scenario(rand)
    const expected = original(s)
    const actual = rewrite(s)
    for (const field of Object.keys(expected)) {
      assert.equal(actual[field] === expected[field] || (Array.isArray(expected[field])
        && actual[field].length === expected[field].length && actual[field].every((x, j) => x === expected[field][j])),
      true, `case ${i}, ${field}: ${JSON.stringify({ s, field })}`)
    }
  }
})

test("action routing matches 1.0.0 on 3000 random states", () => {
  const rand = random(7)
  const actions = ["next", "previous", "play", "pause", "playPause"]
  for (let i = 0; i < 3000; i++) {
    const s = scenario(rand)
    const r = rewrite(s)
    const action = actions[i % actions.length]
    const target = i % 4 === 0 ? M.playerKey(s.players[0]) : ""
    // 1.0.0's playerForAction, over its own state.
    const state = { ...s, playbackStreams: V1.playbackStreams(s.nodes) }
    let expected = V1.playerForKey(state, target)
    if (!expected && (action === "pause" || action === "playPause")) expected = V1.oldestPlayingPlayer(state, true) || V1.oldestPlayingPlayer(state, false)
    if (!expected && M.canHandleAction(r.control, action)) expected = r.control
    if (!expected && M.canHandleAction(r.active, action)) expected = r.active
    if (!expected) expected = V1.orderedSourcePlayers(state).find(p => M.canHandleAction(p, action)) || r.active
    const actual = M.actionPlayer({ players: s.players, byKey: M.indexByKey(s.players), playing: r.playing,
      control: r.control, active: r.active, order: s.playerStartedAt }, action, target)
    assert.equal(actual, expected, `case ${i}`)
  }
})
