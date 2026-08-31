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
  property string activePhase: ""   // syncing | checking | pruning | compacting
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

  // Where a repository sits in this run. borgmatic works through them in config
  // order, so anything after the live one is still to come — worth saying,
  // because a destination showing only an old date reads as abandoned when it
  // is in fact next in line.
  function queuedNow(label) {
    if (!running || activeRepo === "") return false
    var list = repos || []
    var mine = -1, live = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].label === label) mine = i
      if (list[i].label === activeRepo) live = i
    }
    return mine > live && live >= 0
  }

  // --- what a person actually opens this to find out ---------------------
  //
  // Not "did the last run exit zero" but "is my data safe". Those differ: a run
  // can exit cleanly having written one destination and skipped another, and a
  // run can fail at the end having already copied everything.

  readonly property int reposBehind: {
    var n = 0, list = repos || [], now = Date.now() / 1000
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      if (r.busy) continue
      if (r.error || !r.at || (now - r.at) > staleHours * 3600) n++
    }
    return n
  }

  readonly property real newestBackup: {
    var best = 0, list = repos || []
    for (var i = 0; i < list.length; i++)
      if (list[i].at && list[i].at > best) best = list[i].at
    return best
  }

  readonly property bool scheduleOff: timer !== "" && timer !== "active"

  // The headline. Plain words, and it leads with the bad news when there is any.
  readonly property string summary: {
    if (!known && !running) return "No backups recorded"
    if (scheduleOff) return "Backups are turned off"
    if (running) {
      if (activePhase === "syncing" && activeRepo !== "") {
        var p = percentOf(activeRepo)
        return p >= 0 ? "Backing up · " + p + "%" : "Backing up now"
      }
      if (activePhase !== "") return activePhase.charAt(0).toUpperCase() + activePhase.slice(1) + "…"
      return "Backing up now"
    }
    if (repos && repos.length && reposBehind > 0)
      return reposBehind === 1 ? "1 backup is out of date"
                               : reposBehind + " backups are out of date"
    if (newestBackup > 0)
      return "Backed up " + relative((Date.now() / 1000) - newestBackup) + " ago"
    return "Not checked yet"
  }

  readonly property bool summaryBad: scheduleOff || (!running && reposBehind > 0)

  function syncingNow(label) {
    return running && label !== "" && label === activeRepo
  }

  // Whole-job progress, not "new since last time": during a first seed there is
  // no previous archive to measure against, and that is exactly when someone is
  // watching. Capped, because the same source goes to each repository in turn.
  function percentOf(label) {
    // Only create moves bytes. A percentage during a check would be a leftover
    // from the copy that already finished, shown against work of a different
    // kind entirely.
    if (!syncingNow(label) || activePhase !== "syncing") return -1
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

  // A run finishing, or moving to the next repository, is exactly when the
  // cached view of the repositories became wrong — and the only moment worth
  // spending a network call on without being asked. Without this the panel goes
  // on calling a repository "never backed up" straight after backing it up.
  property bool wasRunning: false
  property string wasActive: ""
  onRunningChanged: {
    if (wasRunning && !running) refreshArchives()
    wasRunning = running
  }
  onActiveRepoChanged: {
    if (running && wasActive !== "" && activeRepo !== wasActive) refreshArchives()
    wasActive = activeRepo
  }

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
        root.activePhase = String(s.activePhase || "")
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
