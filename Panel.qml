import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// Bar face and dropdown in one entry point, the shape omarchy.audio uses.
Panel {
  id: root
  moduleName: "io.github.epicbagel.borgbar"
  manageIpc: false

  readonly property var borg: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool showAge: setting("showAge", true) === true

  // One identity glyph, a hard disk, with state carried by colour. Swapping
  // the shape per state makes the bar twitch and reads as a different widget.
  // U+F02CA, a hard disk - the same mark the old waybar module used.
  // Above the BMP, so it needs a surrogate pair rather than one \u escape.
  readonly property string glyph: "\uDB80\uDECA"

  readonly property color stateColor: {
    if (!borg || !borg.known) return Qt.darker(barForeground, 1.6)
    if (borg.failed) return root.urgent
    if (borg.stale) return root.urgent
    if (borg.running) return Color.accent
    return barForeground
  }

  readonly property string headline: {
    if (!borg) return "No backup service"
    if (borg.running) {
      var p = borg.progressLabel()
      return p === "" ? "Backing up now" : "Backing up now · " + p + " (est.)"
    }
    if (borg.failed) return "Last backup failed"
    if (!borg.known) return "No backup recorded"
    var age = borg.relative(borg.ageSeconds)
    return borg.stale ? ("Last backup " + age + " ago") : ("Backed up " + age + " ago")
  }

  // Nothing to say on a machine without borgmatic, so take up no room.
  visible: !borg || borg.installed
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: bar ? bar.barSize : Style.space(26)

  WidgetButton {
    id: button
    bar: root.bar
    anchors.centerIn: parent
    // The neighbouring command modules set horizontalMargin 14; WidgetButton
    // defaults to 8.5, which made these two sit tighter to their neighbours
    // than everything else on the bar.
    horizontalMargin: 14
    text: {
      if (!root.showAge || !root.borg || !root.borg.known) return root.glyph
      if (root.borg.running) {
        var p = root.borg.progressLabel()
        return p === "" ? root.glyph + " …" : root.glyph + " " + p
      }
      var a = root.borg.relative(root.borg.ageSeconds)
      return a === "" ? root.glyph : root.glyph + " " + a
    }
    tooltipText: root.headline
    foreground: root.stateColor
    onPressed: function (btn) {
      if (btn === Qt.MiddleButton && root.borg) root.borg.backUpNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    bar: root.bar
    anchorItem: button
    owner: root
    open: root.opened
    popoutSwitching: root.popoutSwitching
    popoutSwitchClosing: root.popoutSwitchClosing
    contentWidth: Style.space(330)
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(460))
    padding: Style.space(14)

    Column {
      id: column
      width: parent.width
      spacing: Style.space(12)

      Text {
        width: parent.width
        text: root.headline
        color: root.borg && (root.borg.failed || root.borg.stale) ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: !!root.borg && root.borg.lastRun > 0
        text: root.borg ? root.borg.clockOf(root.borg.lastRun) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: !!root.borg && root.borg.running && root.borg.progressDetail() !== ""
        text: root.borg ? root.borg.progressDetail() : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      PanelSeparator { width: parent.width }

      // --- schedule ---------------------------------------------------------
      Row {
        width: parent.width
        Text {
          width: parent.width / 2
          text: "Next run"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width / 2
          horizontalAlignment: Text.AlignRight
          // The timer runs on OnUnitActiveSec, so systemd cannot name the next
          // time until the current run ends. "not scheduled" was the literal
          // reading of that and the wrong one — it says the schedule is broken
          // when it is merely waiting, and it says it during every backup.
          text: {
            if (!root.borg) return "unknown"
            if (root.borg.nextRun) return "in " + root.borg.untilNext()
            if (root.borg.running) return "after this run"
            return root.borg.timer === "active" ? "waiting on the timer" : "not scheduled"
          }
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Row {
        width: parent.width
        Text {
          width: parent.width / 2
          text: "Timer"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width / 2
          horizontalAlignment: Text.AlignRight
          text: root.borg ? root.borg.timer : ""
          color: root.borg && root.borg.timer === "active" ? root.foreground : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Row {
        width: parent.width
        visible: !!root.borg && root.borg.result !== "" && root.borg.result !== "unknown"
        Text {
          width: parent.width / 2
          text: "Last result"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width / 2
          horizontalAlignment: Text.AlignRight
          text: root.borg ? root.borg.result : ""
          color: root.borg && root.borg.result === "success" ? root.foreground : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      PanelSeparator { width: parent.width }

      // --- the repositories -------------------------------------------------
      // One row per configured destination. borgmatic writes the same source to
      // each in turn, so they drift apart whenever one is slower or failing —
      // which is precisely the thing worth seeing, and precisely what a single
      // "latest archive" line used to hide.
      PanelSectionHeader {
        text: "REPOSITORIES"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        visible: !root.borg || root.borg.refreshing || (root.borg.repos || []).length === 0
        text: {
          if (!root.borg) return ""
          if (root.borg.refreshing) return "Reading the repositories…"
          return "Not checked yet. Reading them goes over the network, so it is only done on request."
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.borg && !root.borg.refreshing ? (root.borg.repos || []) : []

        Column {
          width: column.width
          spacing: Style.space(2)

          Row {
            width: parent.width
            Text {
              width: parent.width / 2
              text: modelData.label || ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Text {
              width: parent.width / 2
              horizontalAlignment: Text.AlignRight
              text: {
                if (modelData.busy) return "backing up…"
                if (modelData.error) return "unreachable"
                if (!modelData.at) return "no archives"
                return root.borg.relative((Date.now() / 1000) - modelData.at) + " ago"
              }
              // Stale here means this destination is behind the others, not that
              // the run failed — the schedule block above already reports that.
              // Busy is the normal state of the repository a run is currently
              // writing to, so it stays quiet. Only a real fault goes urgent.
              color: {
                if (modelData.busy) return Color.accent
                if (modelData.error || !modelData.at) return root.urgent
                var age = (Date.now() / 1000) - modelData.at
                return age > root.borg.staleHours * 3600 ? root.urgent : root.dim
              }
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Text {
            width: parent.width
            visible: !!modelData.name
            text: modelData.name || ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Button {
          text: root.borg && root.borg.running ? "Running…" : "Back up now"
          bordered: true
          enabled: !!root.borg && !root.borg.running
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onClicked: if (root.borg) root.borg.backUpNow()
        }
        Button {
          text: "Check repos"
          bordered: true
          enabled: !!root.borg && !root.borg.refreshing
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onClicked: if (root.borg) root.borg.refreshArchives()
        }
      }
    }
  }
}
