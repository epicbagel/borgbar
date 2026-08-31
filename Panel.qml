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

      // The one line that answers the question. Everything else is detail.
      Text {
        width: parent.width
        text: root.headline
        color: root.borg && root.borg.summaryBad ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      // Shown only when it is bad news. A working schedule needs no announcing.
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        visible: !!root.borg && root.borg.scheduleOff
        text: "Nothing will run until the timer is started again."
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: !!root.borg && !root.borg.running && root.borg.newestBackup > 0
        text: root.borg ? root.borg.clockOf(root.borg.newestBackup) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { width: parent.width }

      PanelSectionHeader {
        text: "EACH RUN COPIES TO"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        visible: !root.borg || root.borg.refreshing || (root.borg.repos || []).length === 0
        text: {
          if (!root.borg) return ""
          if (root.borg.refreshing) return "Checking…"
          return "Not checked yet — press Check below."
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.borg && !root.borg.refreshing ? (root.borg.repos || []) : []

        Column {
          id: repoRow
          width: column.width
          spacing: Style.space(2)

          readonly property bool syncing: !!root.borg && root.borg.syncingNow(modelData.label || "")
          readonly property bool queued: !!root.borg && root.borg.queuedNow(modelData.label || "")
          readonly property int pct: root.borg ? root.borg.percentOf(modelData.label || "") : -1
          readonly property real age: modelData.at ? (Date.now() / 1000) - modelData.at : -1
          readonly property bool behind: !syncing && !queued && (age < 0 || age > root.borg.staleHours * 3600)

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
                if (repoRow.syncing)
                  return repoRow.pct >= 0 ? repoRow.pct + "%"
                       : (root.borg.activePhase || "working") + "…"
                if (repoRow.queued) return "waiting its turn"
                if (repoRow.age < 0) return "never backed up"
                var ago = root.borg.relative(repoRow.age)
                return repoRow.behind ? ago + " behind" : ago + " ago"
              }
              color: repoRow.syncing ? Color.accent
                   : repoRow.queued  ? root.dim
                   : repoRow.behind  ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignRight
            visible: text !== ""
            text: {
              if (repoRow.syncing && repoRow.pct >= 0) {
                var p = root.borg.progress || ({})
                if (p.addedBytes && p.sourceBytes)
                  return root.borg.humanBytes(p.addedBytes) + " of " + root.borg.humanBytes(p.sourceBytes)
              }
              return ""
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
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
          text: "Check"
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
