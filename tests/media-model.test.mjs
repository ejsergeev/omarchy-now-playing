import { test } from "node:test"
import assert from "node:assert/strict"
import { load } from "./qmljs.mjs"
import { player, node } from "../bench/fixtures.mjs"

// One namespace over the three model modules.
const M = { ...load("lib/MediaModel.js"), ...load("lib/Streams.js"), ...load("lib/Actions.js") }

const chromium = (o = {}) => player({ dbusName: "org.mpris.MediaPlayer2.chromium.instance42", identity: "Chromium", ...o })
const proxy = (o = {}) => player({ dbusName: "org.mpris.MediaPlayer2.playerctld", desktopEntry: "playerctld", ...o })
const stream = label => node({ isStream: true, isSink: true, type: "Stream/Output/Audio", properties: { "application.name": label } })

test("proxy players are playerctld by bus name or desktop entry", () => {
  assert.equal(M.isProxyPlayer(proxy()), true)
  assert.equal(M.isProxyPlayer(player({ dbusName: "org.mpris.MediaPlayer2.Playerctld" })), true)
  assert.equal(M.isProxyPlayer(player({ desktopEntry: "playerctld" })), true)
  assert.equal(M.isProxyPlayer(chromium()), false)
  assert.equal(M.isProxyPlayer(null), false)
})

test("metadata predicates", () => {
  assert.equal(M.hasMetadata(player({ identity: "", desktopEntry: "" })), false)
  assert.equal(M.hasMetadata(player({ identity: "X" })), true)
  assert.equal(M.hasTrackMetadata(player({ trackArtUrl: "file:///a" })), true)
  assert.equal(M.hasTrackMetadata(player()), false)
  assert.equal(M.hasShownTrack(player({ trackArtist: "A" })), true)
  assert.equal(M.hasShownTrack(player({ trackAlbum: "A" })), false)
  assert.equal(M.hasShownTrack(null), false)
})

test("canHandleAction follows the MPRIS capabilities", () => {
  const none = player({ canPlay: false, canPause: false, canTogglePlaying: false, canGoNext: false, canGoPrevious: false })
  for (const action of ["next", "previous", "play", "pause", "playPause"]) {
    assert.equal(M.canHandleAction(none, action), false, action)
    assert.equal(M.canHandleAction(player(), action), true, action)
  }
  assert.equal(M.canHandleAction(player({ ...none, canTogglePlaying: true }), "pause"), true)
  assert.equal(M.canHandleAction(player(), "stop"), false)
  assert.equal(M.canHandleAction(null, "play"), false)
})

test("playerCanControl and canCycleSource", () => {
  assert.equal(M.playerCanControl(player()), true)
  assert.equal(M.playerCanControl(player({ canPlay: false, canPause: false, canTogglePlaying: false, canGoNext: false, canGoPrevious: false })), false)
  assert.equal(M.canCycleSource(player({ isPlaying: true, canPlay: false })), true)
  assert.equal(M.canCycleSource(player({ canPlay: false })), false)
  assert.equal(M.canCycleSource(player({ identity: "", desktopEntry: "" })), false)
})

test("playback streams are output streams", () => {
  assert.equal(M.isPlaybackStream(node({ isStream: true, isSink: true })), true)
  assert.equal(M.isPlaybackStream(node({ isStream: true, type: "Stream/Output/Audio" })), true)
  assert.equal(M.isPlaybackStream(node({ isStream: true, type: "AudioOutStream" })), true)
  assert.equal(M.isPlaybackStream(node({ isStream: true, type: "Stream/Input/Audio" })), false)
  assert.equal(M.isPlaybackStream(node({ isStream: false, isSink: true })), false)
  assert.equal(M.isPlaybackStream(null), false)
})

test("stream labels are normalised for matching", () => {
  assert.equal(M.streamLabelKey("PipeWire ALSA [Spotify]"), "spotify")
  assert.equal(M.streamLabelKey("ALSA Playback [mpv]"), "mpv")
  assert.equal(M.streamLabelKey("Mozilla Firefox"), "mozillafirefox")
  assert.equal(M.streamLabelKey(null), "")
})

test("raw stream label prefers application.name, then description, media.name, node.name, name", () => {
  assert.equal(M.rawStreamLabel(stream("App")), "App")
  assert.equal(M.rawStreamLabel(node({ description: "Desc" })), "Desc")
  assert.equal(M.rawStreamLabel(node({ properties: { "media.name": "Media" } })), "Media")
  assert.equal(M.rawStreamLabel(node({ properties: { "node.name": "Node" } })), "Node")
  assert.equal(M.rawStreamLabel(node({ ready: false, name: "Name" })), "Name")
  assert.equal(M.rawStreamLabel(null), "")
})

test("player app label: desktop entry, identity, then the bus name without instance", () => {
  assert.equal(M.playerAppLabel(player({ desktopEntry: "spotify", identity: "Spotify" })), "spotify")
  assert.equal(M.playerAppLabel(chromium()), "Chromium")
  assert.equal(M.playerAppLabel(player({ identity: "", dbusName: "org.mpris.MediaPlayer2.vlc.instance7" })), "vlc")
  assert.equal(M.playerAppLabel(null), "")
})

test("streams belong to a player when the labels contain one another", () => {
  const spotify = player({ dbusName: "org.mpris.MediaPlayer2.spotify", desktopEntry: "spotify" })
  const firefox = player({ dbusName: "org.mpris.MediaPlayer2.firefox", desktopEntry: "firefox" })
  const nightly = player({ dbusName: "org.mpris.MediaPlayer2.nightly", desktopEntry: "mozillafirefoxnightly" })
  const nameless = player({ dbusName: "", identity: "", desktopEntry: "" })
  const s1 = stream("Chromium"), s2 = stream("PipeWire ALSA [Spotify]"), s3 = stream("Mozilla Firefox"), s4 = stream("Firefox"), s5 = stream("")
  const map = M.streamsByPlayer([chromium(), spotify, firefox, nightly, nameless], [s1, s2, s3, s4, s5])
  assert.deepEqual(map["org.mpris.MediaPlayer2.chromium.instance42"], [s1])
  assert.deepEqual(map["org.mpris.MediaPlayer2.spotify"], [s2])
  assert.deepEqual(map["org.mpris.MediaPlayer2.firefox"], [s3, s4])
  assert.deepEqual(map["org.mpris.MediaPlayer2.nightly"], [s3, s4])   // "mozillafirefox" is in its name
  assert.equal(Object.keys(map).length, 4)
  assert.equal(Object.keys(M.streamsByPlayer([chromium()], [stream("mpv")])).length, 0)
})

test("playbackStreams keeps output streams with audio", () => {
  const out = stream("A"), noAudio = { ...stream("B"), audio: null }, input = node({ isStream: true, type: "Stream/Input/Audio" })
  assert.deepEqual(M.playbackStreams([out, noAudio, input, null]), [out])
})

test("idlePlayer: a stream beats track metadata, which beats controls, which beat identity", () => {
  const hasStream = p => p.hasStream === true
  const identityOnly = player({ identity: "Idle", canPlay: false, canPause: false, canTogglePlaying: false, canGoNext: false, canGoPrevious: false })
  const controllable = player({ identity: "Ctl" })
  const withTrack = player({ trackTitle: "Song" })
  const withStream = player({ trackTitle: "Loud", hasStream: true })
  assert.equal(M.idlePlayer([identityOnly, controllable, withTrack, withStream], null, hasStream), withStream)
  assert.equal(M.idlePlayer([identityOnly, controllable, withTrack], null, hasStream), withTrack)
  assert.equal(M.idlePlayer([identityOnly, controllable], null, hasStream), controllable)
  assert.equal(M.idlePlayer([identityOnly], null, hasStream), identityOnly)
  assert.equal(M.idlePlayer([player({ identity: "", desktopEntry: "", canPlay: false, canPause: false, canTogglePlaying: false, canGoNext: false, canGoPrevious: false }), null], null, hasStream), null)
})

test("idlePlayer: real players beat proxies, shown tracks beat art-only, and the preferred one wins", () => {
  const none = () => false
  const realTrack = player({ trackTitle: "Real" })
  const proxyTrack = proxy({ trackTitle: "Proxy" })
  assert.equal(M.idlePlayer([proxyTrack, realTrack], null, none), realTrack)

  const artOnly = chromium({ trackArtUrl: "file:///icon.png" })
  const shown = player({ identity: "B", trackArtist: "Shown" })
  assert.equal(M.idlePlayer([artOnly, shown], null, none), shown)
  assert.equal(M.idlePlayer([artOnly, shown], artOnly, none), artOnly)

  // Nothing would be shown: the first candidate is the fallback.
  const artOnly2 = player({ identity: "C", trackArtUrl: "file:///b" })
  assert.equal(M.idlePlayer([artOnly, artOnly2], null, none), artOnly)

  // A preferred player with a stream comes first of all.
  const loud = player({ trackTitle: "Loud", hasStream: true })
  const preferredLoud = player({ identity: "Pref", hasStream: true })
  assert.equal(M.idlePlayer([loud, preferredLoud], preferredLoud, p => p.hasStream === true), preferredLoud)
})

test("player keys, track signatures and labels", () => {
  assert.equal(M.playerKey(chromium()), "org.mpris.MediaPlayer2.chromium.instance42")
  assert.equal(M.playerKey(player({ dbusName: "", desktopEntry: "mpv" })), "mpv")
  assert.equal(M.playerKey(null), "")
  const p = player({ trackTitle: "T", trackArtist: "A" })
  const sig = M.trackSignature(p)
  assert.equal(M.trackChanged(sig, p), false)
  assert.equal(M.trackChanged(sig, player({ trackTitle: "U" })), true)
  assert.equal(M.trackChanged(undefined, player()), true)   // separators make even an empty track non-empty
  assert.equal(M.trackSignature(null), "")
  assert.equal(M.labelFor(p), "T")
  assert.equal(M.labelFor(player({ identity: "", desktopEntry: "mpv" })), "mpv")
  assert.equal(M.labelFor(null), "")
})

test("osd messages", () => {
  assert.equal(M.osdMessage(player({ trackTitle: "T", trackArtist: "A" }), "x"), "T - A")
  assert.equal(M.osdMessage(player({ trackTitle: "T" }), "x"), "T")
  assert.equal(M.osdMessage(player({ identity: "", desktopEntry: "" }), "x"), "x")
  assert.equal(M.osdMessage(null, "x"), "x")
})

test("nodeProps is empty until the node is ready", () => {
  assert.deepEqual({ ...M.nodeProps(node({ ready: false, properties: { a: 1 } })) }, {})
  assert.deepEqual({ ...M.nodeProps(node({ properties: { a: 1 } })) }, { a: 1 })
  assert.deepEqual({ ...M.nodeProps(null) }, {})
})

test("indexByKey skips players without a key", () => {
  const a = chromium(), b = player({ dbusName: "", identity: "", desktopEntry: "" })
  const index = M.indexByKey([a, b])
  assert.equal(index[M.playerKey(a)], a)
  assert.deepEqual(Object.keys(index), [M.playerKey(a)])
})

test("sourceHost is the site of a browser player's xesam:url", () => {
  assert.equal(M.sourceHost(player({ metadata: { "xesam:url": "https://www.youtube.com/watch?v=x" } })), "youtube.com")
  assert.equal(M.sourceHost(player({ metadata: { "xesam:url": "http://music.example.org:8080/a" } })), "music.example.org")
  assert.equal(M.sourceHost(player({ metadata: { "xesam:url": "file:///music/a.flac" } })), "")
  assert.equal(M.sourceHost(player()), "")
  assert.equal(M.sourceHost(null), "")
})

test("iconNames: desktop icon, entry, bus name, identity, without repeats", () => {
  const spotify = player({ dbusName: "org.mpris.MediaPlayer2.spotify", desktopEntry: "spotify", identity: "Spotify" })
  assert.deepEqual([...M.iconNames(spotify, "spotify-client")], ["spotify-client", "spotify"])
  assert.deepEqual([...M.iconNames(chromium(), "ignored")], ["chromium", "chromium"].filter((n, i, a) => a.indexOf(n) === i))
  assert.deepEqual([...M.iconNames(player({ dbusName: "org.mpris.MediaPlayer2.YouTubeMusic.instance_1_2", identity: "YouTube Music" }), "")],
    ["YouTubeMusic", "youtubemusic", "youtube-music"])
  assert.deepEqual([...M.iconNames(null, "")], [])
})

test("playOrder numbers players as they start and keeps the numbers while they play", () => {
  const a = player({ dbusName: "a", isPlaying: true }), b = player({ dbusName: "b", isPlaying: true }), c = player({ dbusName: "c" })
  const first = M.playOrder([a, b, c, player({ dbusName: "", identity: "", desktopEntry: "" })], {}, 0)
  assert.deepEqual({ ...first.order }, { a: 1, b: 2 })
  assert.equal(first.serial, 2)
  assert.deepEqual(Object.keys(first.alive), ["a", "b", "c"])
  b.isPlaying = false
  c.isPlaying = true
  const second = M.playOrder([a, b, c], first.order, first.serial)
  assert.deepEqual({ ...second.order }, { a: 1, c: 3 })
})

test("playingPlayer: longest playing, with a stream first, real before proxy", () => {
  const a = player({ dbusName: "a", isPlaying: true }), b = player({ dbusName: "b", isPlaying: true })
  const px = proxy({ isPlaying: true })
  const order = { a: 2, b: 1, "org.mpris.MediaPlayer2.playerctld": 0 }
  assert.equal(M.playingPlayer([a, b, px], order, {}), b)
  assert.equal(M.playingPlayer([a, b, px], order, { a: [1] }), a)
  assert.equal(M.playingPlayer([px], order, {}), px)
  assert.equal(M.playingPlayer([px, a], order, { "org.mpris.MediaPlayer2.playerctld": [1] }), px)
  assert.equal(M.playingPlayer([player({ dbusName: "x" }), null], {}, {}), null)
  // Unknown order: list position decides, first wins a tie.
  const c = player({ dbusName: "c", isPlaying: true }), d = player({ dbusName: "d", isPlaying: true })
  assert.equal(M.playingPlayer([c, d], {}, {}), c)
})

test("activePlayer: the pick while playing or pinned, then what plays, played last, idle", () => {
  const picked = player({ dbusName: "picked", trackTitle: "P" })
  const loud = player({ dbusName: "loud", trackTitle: "L", isPlaying: true })
  const last = player({ dbusName: "last", trackTitle: "Last" })
  const players = [picked, loud, last]
  const s = o => ({ players, byKey: M.indexByKey(players), streams: {}, playing: loud, preferredKey: "", pinnedKey: "", lastPlayingKey: "", ...o })
  assert.equal(M.activePlayer(s({ preferredKey: "picked" })), loud)
  assert.equal(M.activePlayer(s({ preferredKey: "picked", pinnedKey: "picked" })), picked)
  picked.isPlaying = true
  assert.equal(M.activePlayer(s({ preferredKey: "picked" })), picked)
  picked.isPlaying = false
  assert.equal(M.activePlayer(s({ playing: null, lastPlayingKey: "last" })), last)
  assert.equal(M.activePlayer(s({ playing: null, lastPlayingKey: "gone" })), picked)
  // Between tracks (no metadata, Stopped) a source stays shown: as the pick, or as what played last.
  const skipping = player({ dbusName: "skipping", identity: "YouTube Music" })
  const all = [picked, skipping]
  const t = o => ({ players: all, byKey: M.indexByKey(all), streams: {}, playing: null, preferredKey: "", pinnedKey: "", lastPlayingKey: "", held: { skipping: { title: "Old", artist: "" } }, ...o })
  assert.equal(M.activePlayer(t({ preferredKey: "skipping" })), skipping)
  assert.equal(M.activePlayer(t({ lastPlayingKey: "skipping" })), skipping)
  assert.equal(M.activePlayer(t({ lastPlayingKey: "skipping", held: {} })), picked)
  const bare = player({ dbusName: "bare", identity: "", desktopEntry: "", isPlaying: true })
  assert.equal(M.activePlayer({ ...s({ playing: null }), byKey: { bare }, preferredKey: "bare", players: [bare] }), bare)
})

test("sourceRows: players with a track, by app then key", () => {
  const z = player({ dbusName: "z", identity: "mpv", trackTitle: "1" })
  const a2 = player({ dbusName: "b", identity: "Chromium", trackTitle: "2" })
  const a1 = player({ dbusName: "a", identity: "Chromium", trackTitle: "3" })
  const empty = player({ dbusName: "e", identity: "Chromium" })
  const appOnly = player({ dbusName: "org.mpris.MediaPlayer2.vlc", identity: "", trackArtist: "4" })
  assert.deepEqual(M.sourceRows([z, a2, empty, a1, appOnly]), [a1, a2, z, appOnly])
  // Between tracks a source keeps its row.
  assert.deepEqual(M.sourceRows([z, empty], { e: { title: "3", artist: "" } }), [empty, z])
})

test("cycleOrder and cycle", () => {
  const b = player({ dbusName: "b", trackTitle: "B" }), a = player({ dbusName: "a", trackTitle: "A" })
  const px = proxy({ trackTitle: "0" }), off = player({ dbusName: "o", trackTitle: "O", canPlay: false })
  const list = M.cycleOrder([px, b, off, a])
  assert.deepEqual(list, [a, b, px])
  assert.equal(M.cycle(list, a, 1), b)
  assert.equal(M.cycle(list, a, -1), px)
  assert.equal(M.cycle(list, null, 1), b)
  assert.equal(M.cycle([], a, 1), null)
})

test("actionPlayer: target, playing for pause, control, active, then any that can", () => {
  const loud = player({ dbusName: "loud", trackTitle: "L", isPlaying: true })
  const control = player({ dbusName: "control", trackTitle: "C" })
  const active = player({ dbusName: "active", trackTitle: "A" })
  const players = [loud, control, active]
  const s = o => ({ players, byKey: M.indexByKey(players), playing: loud, control, active, order: {}, ...o })
  assert.equal(M.actionPlayer(s(), "next", "active"), active)
  assert.equal(M.actionPlayer(s(), "pause", ""), loud)
  assert.equal(M.actionPlayer(s(), "next", ""), control)
  assert.equal(M.actionPlayer(s({ control: null }), "next", ""), active)

  const stuck = { canGoNext: false }
  const quiet = player({ dbusName: "q", trackTitle: "Q", canGoNext: true })
  const loud2 = player({ dbusName: "l2", trackTitle: "Z", isPlaying: true, canGoNext: true })
  const loud1 = player({ dbusName: "l1", trackTitle: "Y", isPlaying: true, canGoNext: true })
  const pxy = proxy({ trackTitle: "X", isPlaying: true, canGoNext: true })
  const all = [quiet, pxy, loud2, loud1]
  const t = { players: all, byKey: {}, playing: null, control: { ...stuck }, active: { ...stuck }, order: { l1: 1, l2: 2 } }
  assert.equal(M.actionPlayer(t, "next", ""), loud1)
  assert.equal(M.actionPlayer({ ...t, order: { l1: 2, l2: 1 } }, "next", ""), loud2)
  assert.equal(M.actionPlayer({ ...t, order: {} }, "next", ""), loud1)   // same order: by label
  assert.equal(M.actionPlayer({ ...t, players: [quiet, pxy] }, "next", ""), pxy)   // playing first
  assert.equal(M.actionPlayer({ ...t, players: [proxy({ trackTitle: "A" }), quiet] }, "next", ""), quiet)   // then real before proxy
  assert.equal(M.actionPlayer({ ...t, players: [] }, "next", ""), t.active)
})

test("actionFeedback is decided from the state before the action", () => {
  assert.equal(M.actionFeedback("next").icon, "media-next")
  assert.equal(M.actionFeedback("playPause", player({ isPlaying: true })).label, "media.pause")
  assert.equal(M.actionFeedback("playPause", player()).label, "media.play")
  assert.equal(M.actionFeedback("bogus").label, "media.playPause")
})

test("performAction uses what the player allows, toggling as a fallback", () => {
  const calls = []
  const make = o => player({ ...o, next() { calls.push("next") }, previous() { calls.push("previous") }, play() { calls.push("play") },
    pause() { calls.push("pause") }, togglePlaying() { calls.push("toggle") } })
  const run = (o, action) => { calls.length = 0; const handled = M.performAction(make(o), action); return [handled, calls.join(",")] }
  assert.deepEqual(run({}, "next"), [true, "next"])
  assert.deepEqual(run({ canGoPrevious: false }, "previous"), [false, ""])
  assert.deepEqual(run({}, "play"), [true, "play"])
  assert.deepEqual(run({ canPlay: false }, "play"), [true, "toggle"])
  assert.deepEqual(run({ canPlay: false, isPlaying: true }, "play"), [false, ""])
  assert.deepEqual(run({ canPause: false, isPlaying: true }, "pause"), [true, "toggle"])
  assert.deepEqual(run({ canPause: false }, "pause"), [false, ""])
  assert.deepEqual(run({ isPlaying: true }, "playPause"), [true, "pause"])
  assert.deepEqual(run({}, "playPause"), [true, "play"])
  assert.deepEqual(run({ canPlay: false }, "playPause"), [true, "toggle"])
  assert.deepEqual(run({ canPlay: false, canTogglePlaying: false }, "playPause"), [false, ""])
  assert.deepEqual(run({}, "stop"), [false, ""])
  assert.equal(M.performAction(null, "play"), false)
})

test("stream label keys stay right past the memo's bound", () => {
  for (let i = 0; i < 1200; i++) assert.equal(M.streamLabelKey(`PipeWire ALSA [App ${i}]`), `app${i}`)
  assert.equal(M.streamLabelKey("pipewire alsa [alsa playback [x]]"), "x")
})
