import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/CoverStyle.js" as CoverStyle

// What the user chose in the popup, kept across shell restarts in
// $XDG_STATE_HOME/omarchy-now-playing/preferences.json. A missing or broken
// file reads as the defaults; the file is written on the first change, and
// if its directory is missing then, it is made once and the write retried.
FileView {
  id: file

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
  readonly property string directory: stateHome + "/omarchy-now-playing"
  readonly property string coverStyle: CoverStyle.normalize(stored.coverStyle)
  property bool retried: false

  function setCoverStyle(style) {
    stored.coverStyle = CoverStyle.normalize(style)
  }

  path: directory + "/preferences.json"
  watchChanges: true
  printErrors: false
  onFileChanged: reload()
  onAdapterUpdated: writeAdapter()
  onSaveFailed: {
    if (retried) return
    retried = true
    directoryMaker.run(null, ["mkdir", "-p", directory])
  }

  readonly property ScriptRunner directoryMaker: ScriptRunner {
    onFinished: function(tag, ok) { if (ok) file.writeAdapter() }
  }

  JsonAdapter {
    id: stored
    property string coverStyle: CoverStyle.DEFAULT
  }
}
