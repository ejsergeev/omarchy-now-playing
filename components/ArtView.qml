import QtQuick
import qs.Commons
import qs.Ui

// The cover, in two layers: the next cover decodes in the back layer and
// fades in over the current one once ready, so the art never blinks. Each
// layer decodes at the size it is drawn (SizedImage).
Item {
  id: view

  required property string url
  readonly property bool showing: layerA.opacity >= 0.01 || layerB.opacity >= 0.01

  // The cover could not be loaded.
  signal failed(string url)

  property bool aFront: true
  property string wanted: ""
  readonly property int fadeMs: 160
  // SizedImage retries some failed decodes once; give it time first.
  readonly property int failGraceMs: 500

  onUrlChanged: show(url)
  Component.onCompleted: show(url)

  function front() { return aFront ? layerA : layerB }
  function back() { return aFront ? layerB : layerA }

  function setLayer(layer, url) {
    layer.key = url
    layer.url = url
  }

  function show(url) {
    wanted = url
    fade.stop()
    if (url === "") {
      clear(front())
      clear(back())
    } else if (front().key === url) {
      front().opacity = 1
      clear(back())
    } else {
      load(url)
    }
  }

  // Loads url again into the back layer, after a failed load.
  function reload(url) {
    fade.stop()
    wanted = url
    if (front().key === url) setLayer(front(), "")
    clear(back())
    load(url)
  }

  function load(url) {
    var layer = back()
    layer.opacity = 0
    setLayer(layer, url)
    if (layer.status === Image.Ready) promote()
  }

  function clear(layer) {
    layer.opacity = 0
    setLayer(layer, "")
  }

  function promote() {
    if (back().key !== wanted || fade.running) return
    fade.target = back()
    fade.start()
  }

  function statusChanged(layer) {
    if (layer.status === Image.Ready && layer === back()) promote()
    else if (layer.status === Image.Error && layer.key === wanted && wanted !== "") failCheck.restart()
  }

  Timer {
    id: failCheck
    interval: view.failGraceMs
    onTriggered: {
      var layer = view.back().key === view.wanted ? view.back() : view.front()
      if (layer.status === Image.Error && layer.key === view.wanted) view.failed(view.wanted)
    }
  }

  NumberAnimation {
    id: fade
    property: "opacity"
    from: 0
    to: 1
    duration: Style.duration(view.fadeMs)
    easing.type: Easing.OutCubic
    onFinished: {
      var fadedA = fade.target === layerA
      if ((fadedA ? layerA.key : layerB.key) !== view.wanted || view.aFront === fadedA) return
      view.clear(view.front())
      view.aFront = !view.aFront
    }
  }

  SizedImage {
    id: layerA
    property string key: ""   // the URL as given; Qt normalises url on read
    anchors.fill: parent
    crop: true
    opacity: 0
    onStatusChanged: view.statusChanged(layerA)
  }

  SizedImage {
    id: layerB
    property string key: ""
    anchors.fill: parent
    crop: true
    opacity: 0
    onStatusChanged: view.statusChanged(layerB)
  }
}
