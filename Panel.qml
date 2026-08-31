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

  readonly property string headline: borg ? borg.summary : "No backup service"



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
    // Deliberately the same figures the panel shows. These were computed two
    // different ways and disagreed: the bar carried an estimate against what
    // changed since the last archive while the panel measured the whole job, so
    // the bar could read 100% beside a panel reading 4%.
    text: {
      if (!root.showAge || !root.borg || !root.borg.known) return root.glyph
      if (root.borg.running) return root.glyph + " …"
      // Age of the most recent successful backup, not of the last run. A run
      // that failed still leaves a good backup behind it.
      var newest = root.borg.newestBackup
      var a = newest > 0 ? root.borg.relative((Date.now() / 1000) - newest)
                         : root.borg.relative(root.borg.ageSeconds)
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
        text: {
          if (!root.borg || !root.borg.running) return root.headline
          var started = root.borg.elapsed !== "" ? " · started " + root.borg.elapsed + " ago" : ""
          return "Backup running" + started
        }
        color: root.borg && root.borg.running ? Color.accent
             : root.borg && root.borg.summaryBad ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: !!root.borg && root.borg.running
                 && (root.borg.repos || []).length > 0
                 && root.borg.activeRepo !== ""
        text: {
          if (!root.borg) return ""
          var total = (root.borg.repos || []).length
          return root.borg.destinationsCompleted + " of " + total + " destinations completed"
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        visible: !!root.borg && root.borg.scheduleOff
        text: "Automatic backups are off — nothing will run on its own."
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { width: parent.width }

      PanelSectionHeader {
        text: "DESTINATIONS"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        visible: !root.borg || root.borg.refreshing || (root.borg.repos || []).length === 0
        text: root.borg && root.borg.refreshing ? "Checking…" : "Not checked yet — press Check below."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.borg && !root.borg.refreshing ? (root.borg.repos || []) : []

        Column {
          id: repoRow
          width: column.width
          spacing: Style.space(5)

          readonly property bool syncing: !!root.borg && root.borg.syncingNow(modelData.label || "")
          readonly property bool queued:  !!root.borg && root.borg.queuedNow(modelData.label || "")
          readonly property bool completed: !!root.borg && root.borg.completedNow(modelData.label || "")
          readonly property int pct: root.borg ? root.borg.percentOf(modelData.label || "") : -1
          readonly property real age:     modelData.at ? (Date.now() / 1000) - modelData.at : -1
          readonly property bool behind:  !syncing && !queued && !completed && (age < 0 || age > root.borg.staleHours * 3600)

          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              id: repoIcon
              width: Style.space(16)
              text: repoRow.syncing ? "●" : repoRow.queued ? "○" : repoRow.completed ? "✓" : repoRow.behind ? "!" : "✓"
              color: repoRow.syncing ? Color.accent : repoRow.behind ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              id: repoName
              width: parent.width * 0.38
              text: modelData.label || ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              width: parent.width - repoIcon.width - repoName.width - Style.space(12)
              horizontalAlignment: Text.AlignRight
              // Always relative. An absolute date makes the reader do the sum,
              // and how safe their files are should not need arithmetic.
              text: {
                if (repoRow.syncing)
                  return repoRow.pct >= 0 ? "copying · " + repoRow.pct + "%"
                                          : root.borg.plainPhase.toLowerCase()
                if (repoRow.queued)  return "waiting its turn"
                if (repoRow.completed) return "completed this run"
                if (repoRow.age < 0) return "never copied"
                var ago = root.borg.relative(repoRow.age) + " ago"
                return repoRow.behind ? ago + " · out of date" : ago
              }
              color: repoRow.syncing ? Color.accent
                   : repoRow.queued  ? root.dim
                   : repoRow.completed ? root.dim
                   : repoRow.behind  ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          Item {
            width: parent.width - Style.space(22)
            height: Style.space(6)
            x: Style.space(22)
            visible: repoRow.syncing && repoRow.pct >= 0

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
            }
            Rectangle {
              height: parent.height
              radius: height / 2
              color: Color.accent
              width: parent.width * Math.max(0, Math.min(100, repoRow.pct)) / 100
              Behavior on width { NumberAnimation { duration: 400 } }
            }
          }

          Text {
            width: parent.width - Style.space(22)
            x: Style.space(22)
            visible: repoRow.syncing && text !== ""
            text: {
              if (!root.borg) return ""
              var p = root.borg.progress || ({})
              if (p.addedBytes && p.sourceBytes)
                return root.borg.humanBytes(p.addedBytes) + " of " + root.borg.humanBytes(p.sourceBytes) + " copied · estimate"
              return root.borg.liveDetail
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      PanelSeparator { width: parent.width }

      Row {
        width: parent.width

        Text {
          width: parent.width * 0.55
          text: "Next automatic backup"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width * 0.45
          horizontalAlignment: Text.AlignRight
          text: {
            if (!root.borg) return "Unknown"
            if (root.borg.scheduleOff) return "Switched off"
            if (root.borg.running) return "After this run"
            var next = root.borg.untilNext()
            return next === "" ? "Unknown" : "In " + next
          }
          color: root.borg && root.borg.scheduleOff ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Button {
          visible: !root.borg || !root.borg.running
          text: "Back up now"
          bordered: true
          enabled: !!root.borg && !root.borg.running
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onClicked: if (root.borg) root.borg.backUpNow()
        }
        Button {
          text: "Check copies"
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
