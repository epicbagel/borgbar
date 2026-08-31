import QtQuick
import Quickshell
import Quickshell.Io

// Headless singleton. Polls `borgbar status`, which reads local systemd state
// only, so it is cheap enough to run on a timer. Asking the repository what
// archives it holds goes over ssh and takes seconds, so that is never polled -
// it is cached on disk and refreshed only when asked.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.epicbagel.borgbar"
  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string bin: sourceDir ? sourceDir + "/bin/borgbar" : ""

  // ------------------------------------------------------------------- state
  // Whether borgmatic exists at all. A machine that does not back up with
  // borg should show nothing, not an empty widget waiting for news.
  property bool installed: true
  property string state: "unknown"      // ok | running | failed | stale | unknown
  property bool running: false
  property string result: ""
  property string timer: ""
  property real lastRun: 0
  property real nextRun: 0
  property real ageSeconds: -1
  property int staleHours: 24
  // One entry per configured repository, newest archive each. A repository
  // that could not be read still appears, carrying an error, so a destination
  // going quiet looks different from never having configured it.
  property var repos: []
  property real checkedAt: 0
  // Always an estimate — see progress_json in bin/borgbar for why borg
  // cannot give a real one.
  property var progress: ({})
  property bool refreshing: false

  readonly property bool ok: state === "ok"
  readonly property bool failed: state === "failed"
  readonly property bool stale: state === "stale"
  readonly property bool known: state !== "unknown"

  // ---------------------------------------------------------------- commands
  function run(args) {
    if (!bin) return
    Quickshell.execDetached([bin].concat(args))
    settle.restart()
  }

  function backUpNow() { run(["run"]) }

  // The slow one: goes to the repository. Runs as a tracked process so the
  // panel can show that it is working rather than appearing to do nothing.
  // Worst state across the repositories, for the panel's summary line. The bar
  // itself keeps taking its colour from systemd — see cmd_status for why.
  readonly property int reposBehind: {
    var n = 0
    var list = repos || []
    for (var i = 0; i < list.length; i++)
      if (list[i].error || !list[i].at) n++
    return n
  }

  function refreshArchives() {
    if (!bin || refreshProc.running) return
    refreshing = true
    refreshProc.command = [bin, "refresh"]
    refreshProc.running = true
  }

  // ------------------------------------------------------------- formatting
  function relative(seconds) {
    var s = Math.floor(Number(seconds))
    if (!isFinite(s) || s < 0) return ""
    if (s < 60) return s + "s"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h"
    return Math.floor(s / 86400) + "d"
  }

  function untilNext() {
    if (!nextRun) return ""
    var s = nextRun - (Date.now() / 1000)
    return s > 0 ? relative(s) : "due"
  }

  function humanBytes(bytes) {
    var b = Number(bytes || 0)
    if (!isFinite(b) || b <= 0) return ""
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    while (b >= 1024 && i < units.length - 1) { b /= 1024; i++ }
    return (i === 0 ? Math.round(b) : b.toFixed(1)) + units[i]
  }

  // The tilde is doing real work: this is a guess against a cached denominator,
  // and it should never read as though borg reported it.
  function progressLabel() {
    var p = progress || ({})
    if (p.percent === null || p.percent === undefined) return ""
    return "~" + p.percent + "%"
  }

  function progressDetail() {
    var p = progress || ({})
    if (!p.addedBytes) return ""
    var added = humanBytes(p.addedBytes) + " added"
    if (p.percent === null || p.percent === undefined)
      return added + " · run Check repo for an estimate"
    return added + " of ~" + humanBytes(p.deltaBytes) + " · estimated"
  }

  function clockOf(epoch) {
    if (!epoch) return ""
    return new Date(epoch * 1000).toLocaleString(Qt.locale(), "ddd d MMM HH:mm")
  }

  // ------------------------------------------------------------------ status
  function refresh() {
    if (!bin || statusProc.running) return
    statusProc.command = [bin, "status"]
    statusProc.running = true
  }

  Timer {
    interval: 10000
    repeat: true
    running: root.bin !== ""
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer { id: settle; interval: 700; onTriggered: root.refresh() }

  Process {
    id: statusProc
    stdout: StdioCollector {
      onStreamFinished: {
        var s
        try { s = JSON.parse(this.text) } catch (e) { return }
        if (!s || typeof s !== "object") return
        root.installed = s.installed !== false
        root.state = String(s.state || "unknown")
        root.running = s.running === true
        root.result = String(s.result || "")
        root.timer = String(s.timer || "")
        root.lastRun = Number(s.lastRun) || 0
        root.nextRun = Number(s.nextRun) || 0
        root.ageSeconds = Number(s.ageSeconds)
        root.staleHours = Number(s.staleHours) || 24
        root.repos = s.repos || []
        root.checkedAt = Number(s.checkedAt) || 0
        root.progress = s.progress || ({})
      }
    }
  }

  Process {
    id: refreshProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var c = JSON.parse(this.text)
          root.repos = c.repos || []
          root.checkedAt = Number(c.checkedAt) || 0
        } catch (e) { /* keep the old one */ }
      }
    }
    onExited: { root.refreshing = false; root.refresh() }
  }

  onBinChanged: root.refresh()

  IpcHandler {
    target: "borgbar"
    function status(): string {
      return JSON.stringify({ state: root.state, lastRun: root.lastRun,
                              nextRun: root.nextRun, age: root.ageSeconds })
    }
    function backup(): string { root.backUpNow(); return "ok" }
    function refresh(): string { root.refreshArchives(); return "ok" }
  }
}
