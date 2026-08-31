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

      // The one line that answers the question people opened this for.
      Text {
        width: parent.width
        text: root.headline
        color: root.borg && root.borg.summaryBad ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      // One line, one place. Ticks every second so a long copy visibly lives.
      Text {
        width: parent.width
        visible: !!root.borg && root.borg.liveDetail !== ""
        text: root.borg ? root.borg.liveDetail : ""
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
        text: "COPIES ARE KEPT ON"
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

        Row {
          id: repoRow
          width: column.width

          readonly property bool syncing: !!root.borg && root.borg.syncingNow(modelData.label || "")
          readonly property bool queued: !!root.borg && root.borg.queuedNow(modelData.label || "")
          readonly property real age: modelData.at ? (Date.now() / 1000) - modelData.at : -1
          readonly property bool behind: !syncing && !queued && (age < 0 || age > root.borg.staleHours * 3600)

          Text {
            width: parent.width * 0.42
            text: modelData.label || ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            width: parent.width * 0.58
            horizontalAlignment: Text.AlignRight
            // Always relative. "31 Aug 12:33" makes the reader do the sum, and
            // the answer to how safe their files are should not need arithmetic.
            text: {
              if (repoRow.syncing) return "copying now"
              if (repoRow.queued) return "waiting its turn"
              if (repoRow.age < 0) return "never copied"
              var ago = root.borg.relative(repoRow.age) + " ago"
              return repoRow.behind ? ago + " · out of date" : ago
            }
            color: repoRow.syncing ? Color.accent
                 : repoRow.queued  ? root.dim
                 : repoRow.behind  ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
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
