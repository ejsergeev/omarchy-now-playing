.pragma library

// The popup's letter keys. On a Latin layout a key acts by its letter, so
// shuffle is the s key on Dvorak too. On any other layout (Cyrillic, Greek,
// Arabic, ...) it acts by its place on a US keyboard, so the keys work without
// switching layout. Places are XKB keycodes (evdev + 8), which is what Qt
// reports as nativeScanCode on Wayland and what Hyprland's code:N binds.

var BY_LETTER = {
  "h": "previous", "l": "next",
  "j": "volumeDown", "k": "volumeUp",
  ",": "seekBack", ".": "seekForward",
  "m": "mute", "s": "shuffle", "r": "repeat",
}

var BY_KEYCODE = {
  43: "previous", 46: "next",
  44: "volumeDown", 45: "volumeUp",
  59: "seekBack", 60: "seekForward",
  58: "mute", 39: "shuffle", 27: "repeat",
}

// Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier: chords are left to
// the shell.
var CHORD_MODIFIERS = 0x04000000 | 0x08000000 | 0x10000000

// The action for a key press, or "" when the popup has none for it.
function action(text, keycode, modifiers) {
  if (modifiers & CHORD_MODIFIERS) return ""
  var letter = String(text || "").toLowerCase()
  if (letter.length !== 1) return ""
  if (letter.charCodeAt(0) < 128) return BY_LETTER[letter] || ""
  return BY_KEYCODE[keycode] || ""
}
