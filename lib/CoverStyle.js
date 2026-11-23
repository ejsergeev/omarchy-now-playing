.pragma library

// How the popup shows a track's cover. A click on the cover steps through the
// styles; the choice is kept (components/Preferences.qml) and applies to every
// source. A track without a cover always gets the spectrum.

var STYLES = ["cover", "duotone", "spectrum"]
var DEFAULT = "cover"

// A stored value as a known style: anything else is the default.
function normalize(value) {
  return STYLES.indexOf(value) !== -1 ? value : DEFAULT
}

function next(style) {
  return STYLES[(STYLES.indexOf(normalize(style)) + 1) % STYLES.length]
}

// What the cover box shows for a style, given whether there is a cover.
function shown(style, hasArt) {
  return hasArt ? normalize(style) : "spectrum"
}
