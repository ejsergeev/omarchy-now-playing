import QtQuick
import Quickshell.Io

// Runs scripts one at a time on one Process. A request made while one runs
// waits, replacing any request already waiting, so a burst of requests runs
// the first and the newest only. Every run ends in exactly one finished():
// ok is false when the script exited non-zero, could not start, or hung past
// timeout (it is then killed, and the next run waits for it to be gone).
QtObject {
  id: runner

  property int timeout: 5000
  property Metrics metrics: null

  // tag: what run() was given, to tell results apart.
  signal finished(var tag, bool ok, string output)

  property var current: null   // { tag, command } running now
  property var waiting: null   // the next one
  property string output: ""
  property bool outputDone: false
  property int exitCode: -1
  property bool killing: false   // a hung run is being stopped

  function run(tag, command) {
    waiting = { tag: tag, command: command }
    startWaiting()
  }

  function startWaiting() {
    if (current || killing || !waiting) return
    current = waiting
    waiting = null
    output = ""
    outputDone = false
    exitCode = -1
    process.command = current.command
    process.running = true
    watchdog.restart()
    if (metrics) metrics.count("spawns")
  }

  function settle(ok) {
    watchdog.stop()
    var done = current
    current = null
    finished(done.tag, ok, ok ? output.trim() : "")
    startWaiting()
  }

  // Exit status and stdout arrive separately; a run is over with both.
  function settleWhenDone() {
    if (current && exitCode >= 0 && outputDone) settle(exitCode === 0)
  }

  readonly property Process process: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        if (runner.killing) return
        runner.output = text
        runner.outputDone = true
        runner.settleWhenDone()
      }
    }
    onExited: function(code) {
      if (runner.killing) {
        runner.killing = false
        runner.startWaiting()
        return
      }
      runner.exitCode = code
      runner.settleWhenDone()
    }
  }

  readonly property Timer watchdog: Timer {
    interval: runner.timeout
    onTriggered: {
      runner.killing = runner.process.running
      runner.process.running = false
      runner.settle(false)
    }
  }
}
