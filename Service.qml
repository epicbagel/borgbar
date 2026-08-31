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
  // Which repository the run is writing to right now. Comes from the running
  // process, so it tracks the run moving from one repository to the next.
  property string activeRepo: ""
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

  function syncingNow(label) {
    return running && label !== "" && label === activeRepo
  }

  // Whole-job progress, not "new since last time": during a first seed there is
  // no previous archive to measure against, and that is exactly when someone is
  // watching. Capped, because the same source goes to each repository in turn.
  function percentOf(label) {
    if (!syncingNow(label)) return -1
    var p = progress || ({})
    if (!p.addedBytes || !p.sourceBytes) return -1
    return Math.min(100, Math.floor(100 * p.addedBytes / p.sourceBytes))
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

  // A quantity on its own tells you nothing — "154GB added" could be a job
  // nearly finished or barely begun. The source total is what makes it read as
  // progress, so it is always shown when known, even though it comes from the
  // last Check repos rather than this instant.
  function progressDetail() {
    var p = progress || ({})
    if (!p.addedBytes) return ""
    var added = humanBytes(p.addedBytes) + " added"
    if (p.sourceBytes)
      return added + " of " + humanBytes(p.sourceBytes) + " to back up"
    return added + " · run Check repos to see the total"
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
        root.activeRepo = String(s.activeRepo || "")
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
