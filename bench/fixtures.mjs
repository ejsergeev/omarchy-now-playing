// Synthetic MPRIS players and PipeWire nodes shaped like the real objects
// (only the properties the plugin reads), for benchmarks and tests.

const APPS = [
  { bus: "chromium.instance", identity: "Chromium", desktopEntry: "", stream: "Chromium" },
  { bus: "spotify", identity: "Spotify", desktopEntry: "spotify", stream: "spotify" },
  { bus: "mpv", identity: "mpv", desktopEntry: "mpv", stream: "mpv" },
  { bus: "firefox.instance_1_", identity: "Mozilla Firefox", desktopEntry: "firefox", stream: "Firefox" },
  { bus: "cliamp", identity: "cliamp", desktopEntry: "", stream: "cliamp" },
]

export function player(overrides = {}) {
  return {
    dbusName: "org.mpris.MediaPlayer2.test", identity: "Test", desktopEntry: "",
    trackTitle: "", trackArtist: "", trackAlbum: "", trackArtUrl: "",
    isPlaying: false, playbackState: 0,
    canPlay: true, canPause: true, canTogglePlaying: true, canGoNext: true, canGoPrevious: true,
    ...overrides,
  }
}

// count players over the apps above, every third one playing, plus a
// playerctld proxy that mirrors the first.
export function players(count) {
  const list = []
  for (let i = 0; i < count - 1; i++) {
    const app = APPS[i % APPS.length]
    list.push(player({
      dbusName: `org.mpris.MediaPlayer2.${app.bus}${i}`,
      identity: app.identity, desktopEntry: app.desktopEntry,
      trackTitle: `Track ${i}`, trackArtist: `Artist ${i}`, trackAlbum: `Album ${i}`,
      trackArtUrl: i % 2 ? `file:///tmp/art-${i}.png` : "",
      isPlaying: i % 3 === 0,
    }))
  }
  list.push(player({ dbusName: "org.mpris.MediaPlayer2.playerctld", identity: "playerctld",
    desktopEntry: "playerctld", trackTitle: "Track 0", isPlaying: true }))
  return list
}

export function node(overrides = {}) {
  return { ready: true, isStream: false, isSink: false, type: "", name: "", description: "",
    properties: {}, audio: { volume: 1, muted: false }, ...overrides }
}

// streamCount playback streams named after the apps (some PipeWire-ALSA
// style), plus as many devices and capture streams that must be skipped.
export function nodes(streamCount) {
  const list = []
  for (let i = 0; i < streamCount; i++) {
    const app = APPS[i % APPS.length]
    const label = i % 4 === 3 ? `PipeWire ALSA [${app.stream}]` : app.stream
    list.push(node({ isStream: true, isSink: true, type: "Stream/Output/Audio", name: `${app.stream}-${i}`,
      properties: { "application.name": label, "media.name": `Playback ${i}` } }))
  }
  for (let i = 0; i < streamCount; i++) {
    list.push(node({ isStream: i % 2 === 0, type: i % 2 ? "Audio/Sink" : "Stream/Input/Audio",
      name: `alsa_output.device-${i}`, properties: { "node.name": `device-${i}` } }))
  }
  return list
}
