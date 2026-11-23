.pragma library

// How the shown track rides out what players do between tracks. Players blank
// their metadata for a moment, report Stopped, or hand the "active" role to
// another player and back; showing every such blip would hide the bar
// button, drop the cover and resize the popup. These decisions keep the shown
// track steady and let real changes through.

// A switch to another player must last this long before it shows.
var SWITCH_HOLD_MS = 400
// Blank metadata from a Playing or Paused player is held this long.
var BLANK_HOLD_MS = 2500
// A track that really has no art clears the previous cover after this.
var ART_CLEAR_MS = 2500
// A cover that failed to load is retried this often, this far apart: browsers
// announce an art file before it is fully written.
var ART_RETRIES = 2
var ART_RETRY_MS = 1000
// A probe that never reports back is given up after this; a cold first
// ImageMagick run can take a couple of seconds.
var PROBE_TIMEOUT_MS = 5000

// What to do when the active player or its metadata changes. s:
//   hasPlayer  there is an active player
//   key        its key; shownKey the key of the player shown now
//   shownGone  the shown player has quit
//   explicit   the user just picked this player: no hold
//   liveMedia  the active player has a title or artist now
//   stopped    the active player reports Stopped
// Returns "waitSwitch" (hold before switching players), "apply" (show the
// active player's metadata now) or "waitBlank" (hold through a blank).
function refreshAction(s) {
  if (s.hasPlayer && s.key !== s.shownKey && !s.shownGone && !s.explicit) return "waitSwitch"
  // Blank metadata from a Stopped player is a closed tab or a finished video,
  // not a skip: it applies at once, as do no player and a quit one.
  if (s.liveMedia || !s.hasPlayer || s.shownGone || s.stopped) return "apply"
  return "waitBlank"
}

// What to do with the cover once metadata applies. s:
//   liveArtUrl      the art the player announces now
//   artUrl          the art shown
//   rejectedArtUrl  a placeholder the player served instead of art
//   liveMedia       the player has a title or artist
// Returns "probe" (check the new art), "keep", "clear" (no track: clear at
// once) or "clearLater" (a track without art: clear after a grace period).
function artAction(s) {
  if (s.liveArtUrl !== "") return s.liveArtUrl !== s.artUrl && s.liveArtUrl !== s.rejectedArtUrl ? "probe" : "keep"
  return s.liveMedia ? "clearLater" : "clear"
}

// The identity of the track shown: a change resets rejected art and retries.
function trackIdentity(key, player) {
  return key + "\u001f" + (player ? (player.trackTitle || "") + "\u001f" + (player.trackArtist || "") : "")
}

// A probe verdict holds for one art file on one track of one player. A player
// may write the next track's art over the same file, so the track is part of
// the key; switching back to a source on the same track is a cache hit.
function probeKey(url, trackId) {
  return trackId + "\u001f" + url
}

// Whether a cover that failed to load for the n-th time gets another try.
function retryArt(failures) {
  return failures <= ART_RETRIES
}
