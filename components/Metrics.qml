import QtQuick

// The plugin's own counters for docs/METRICS.md, read with
//   qs -p /usr/share/omarchy/shell ipc call media metrics
// Counting starts with the first such call, so a shell nobody measures pays
// one bool check per counted event. Rare one-off values (how long the popup
// took to build) are always kept.
QtObject {
  id: metrics

  property bool counting: false
  // A plain object, mutated in place: counters are read on request, never
  // bound, so they must not notify.
  property var counters: ({})

  function count(name) {
    if (counting) counters[name] = (counters[name] || 0) + 1
  }

  function record(name, value) {
    counters[name] = value
  }

  // Objects in a tree: an object, its children and resources. Objects in
  // `opaque` count as one; their insides belong to the host.
  function objectCount(object, opaque) {
    if (!object) return 0
    if (opaque.indexOf(object) !== -1) return 1
    var total = 1
    var data = object.data || []
    for (var i = 0; i < data.length; i++) total += objectCount(data[i], opaque)
    return total
  }

  // Starts counting, and reports the counters with `live` (values sampled now).
  function report(live) {
    counting = true
    var out = {}
    for (var name in counters) out[name] = counters[name]
    for (var key in live) out[key] = live[key]
    return JSON.stringify(out)
  }
}
