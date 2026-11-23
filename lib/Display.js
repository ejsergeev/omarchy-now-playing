.pragma library
.import "Glyphs.js" as Glyphs

// Small decisions about what the popup shows, kept out of the QML so they can
// be tested.

// m:ss or h:mm:ss, digits through formatNumber (the language's numerals).
function formatTime(seconds, formatNumber) {
  var sec = isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0
  var h = Math.floor(sec / 3600)
  var m = Math.floor((sec % 3600) / 60)
  var s = sec % 60
  function two(v) { return (v < 10 ? formatNumber(0) : "") + formatNumber(v) }
  return h > 0 ? formatNumber(h) + ":" + two(m) + ":" + two(s) : formatNumber(m) + ":" + two(s)
}

// A playful name for where playback is, as an i18n key, in the spirit of the
// audio panel's volume ladder. s: { hasPlayer, muted, playing, hasTimeline,
// position, length } (seconds).
function moodKey(s) {
  if (!s.hasPlayer) return "media.mood.silence"
  if (s.muted) return "media.mood.silentDisco"
  if (!s.playing) return "media.mood.intermission"
  if (!s.hasTimeline) return "media.mood.onAir"
  if (s.position < 10) return "media.mood.needleDrop"
  if (s.length - s.position < 15) return "media.mood.encore"
  var progress = s.position / s.length
  if (progress < 0.4) return "media.mood.warmingUp"
  if (progress < 0.75) return "media.mood.inTheGroove"
  return "media.mood.finalChorus"
}

// Players send "-" and the like for no album.
function albumText(album) {
  return /[^\s\-–—_.·]/.test(album || "") ? album : ""
}

function capitalize(text) {
  text = String(text || "")
  return text.length ? text.charAt(0).toUpperCase() + text.slice(1) : ""
}

// Nerd Font speaker glyphs: muted, low, medium, high.
function volumeGlyph(volume, muted) {
  if (muted || volume <= 0) return ""
  return volume >= 0.67 ? "" : volume >= 0.34 ? "" : ""
}

// The next MPRIS loop state: off, all, one. None/Track/Playlist are
// MprisLoopState's values, passed in to keep this free of QML imports.
function nextLoopState(state, none, playlist, track) {
  return state === none ? playlist : state === playlist ? track : none
}

// ImageMagick reads #RRGGBBAA where Qt writes #AARRGGBB: pass rgba() instead.
function imColor(c) {
  return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(3) + ")"
}

// The filesystem path of a file:// URL, or "" for any other URL.
function localPath(url) {
  var match = String(url).match(/^file:\/\/(?:localhost)?(\/.*)$/)
  if (!match) return ""
  try {
    return decodeURIComponent(match[1])
  } catch (e) {
    return ""
  }
}
