import { test } from "node:test"
import assert from "node:assert/strict"
import { load } from "./qmljs.mjs"
import { player, node } from "../bench/fixtures.mjs"

const M = load("lib/MediaModel.js")

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

test("a player has a playback stream when the labels contain one another", () => {
  assert.equal(M.playerHasPlaybackStream(chromium(), [stream("Chromium")]), true)
  assert.equal(M.playerHasPlaybackStream(player({ desktopEntry: "spotify" }), [stream("PipeWire ALSA [Spotify]")]), true)
  assert.equal(M.playerHasPlaybackStream(player({ desktopEntry: "firefox" }), [stream("Mozilla Firefox")]), true)
  assert.equal(M.playerHasPlaybackStream(player({ desktopEntry: "mozillafirefoxnightly" }), [stream("Firefox")]), true)
  assert.equal(M.playerHasPlaybackStream(chromium(), [stream("mpv"), stream("")]), false)
  assert.equal(M.playerHasPlaybackStream(player({ identity: "", dbusName: "" }), [stream("x")]), false)
  assert.equal(M.playerHasPlaybackStream(chromium(), null), false)
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

test("volume keys step by 5, clamp, unmute; mute toggles", () => {
  assert.deepEqual({ ...M.volumeKeyStep("raise", 98, true) }, { percent: 100, muted: false })
  assert.deepEqual({ ...M.volumeKeyStep("raise", 120, false) }, { percent: 100, muted: false })
  assert.deepEqual({ ...M.volumeKeyStep("lower", 3, true) }, { percent: 0, muted: false })
  assert.deepEqual({ ...M.volumeKeyStep("mute-toggle", 40, false) }, { percent: 40, muted: true })
  assert.equal(M.volumeKeyStep("bogus", 40, false), null)
  assert.equal(M.volumeOsdIcon(0, false), "volume-muted")
  assert.equal(M.volumeOsdIcon(50, true), "volume-muted")
  assert.equal(M.volumeOsdIcon(50, false), "volume-high")
})

test("nodeProps is empty until the node is ready", () => {
  assert.deepEqual({ ...M.nodeProps(node({ ready: false, properties: { a: 1 } })) }, {})
  assert.deepEqual({ ...M.nodeProps(node({ properties: { a: 1 } })) }, { a: 1 })
  assert.deepEqual({ ...M.nodeProps(null) }, {})
})
