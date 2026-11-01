import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Front end for /usr/local/bin/tuxctl (see backend/). Reads the status the root
// daemon publishes; writes go through `sudo -n tuxctl set KEY VALUE`.
Panel {
  id: root
  moduleName: "kosto.tuxedo"
  ipcTarget: "kosto.tuxedo"

  readonly property string statusPath: "/run/tuxctl/status.json"
  readonly property string installPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/kosto.tuxedo/backend/install.sh"
  readonly property var fanModes: ["auto", "quiet", "balanced", "cool", "max"]
  readonly property var perfModes: ["power_save", "enthusiast", "overboost"]
  readonly property string fanGlyph: String.fromCodePoint(0xF0210)

  property var st: ({})
  property bool online: false
  property string lastError: ""

  readonly property int healthPercent: st.bat_charge_full_design > 0
    ? Math.round(100 * st.bat_charge_full / st.bat_charge_full_design) : 0

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function parseStatus(raw) {
    try {
      var next = JSON.parse(raw)
      // The daemon rewrites every 2s; a stale file means it died.
      online = typeof next.updated === "number" && Date.now() / 1000 - next.updated < 15
      st = next
    } catch (e) {
      online = false
    }
  }

  function setValue(key, value) {
    if (actionProc.running) return
    lastError = ""
    var next = Object.assign({}, st)
    next[key] = value
    st = next // optimistic; the next status refresh confirms
    actionProc.command = ["sudo", "-n", "/usr/local/bin/tuxctl", "set", key, value]
    actionProc.running = true
  }

  FileView {
    id: statusFile
    path: root.statusPath
    printErrors: false
    onLoaded: root.parseStatus(text())
    onLoadFailed: root.online = false
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.lastError = actionErr.text.trim() || ("exit " + code)
      statusFile.reload()
    }
  }

  Timer {
    interval: root.opened ? 2000 : 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: statusFile.reload()
  }

  onOpenedChanged: if (opened) statusFile.reload()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.fanGlyph
    active: root.online && root.st.fan !== undefined && root.st.fan !== "auto"
    tooltipText: root.online ? strings.t("statusLine").arg(root.st.temp1).arg(root.st.fan1) : ""
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroTemp.implicitHeight)

          Label {
            id: heroIcon
            text: root.fanGlyph
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroTemp.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Label {
              text: strings.t("title")
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }
            Label {
              visible: root.online
              text: strings.t("health").arg(Commons.I18n.formatNumber(root.healthPercent)).arg(Commons.I18n.formatNumber(Number(root.st.bat_cycle_count || 0))).toUpperCase()
              opacity: 0.7
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Label {
            id: heroTemp
            visible: root.online
            text: Commons.I18n.formatNumber(root.st.temp1 || 0) + "°"
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Backend missing ----------
        Column {
          visible: !root.online
          width: parent.width
          spacing: Style.space(6)
          Label { width: parent.width; wrapMode: Text.Wrap; text: strings.t("notInstalled") }
          Label {
            width: parent.width
            wrapMode: Text.WrapAnywhere
            text: "sudo " + root.installPath
            font.family: "monospace"
            opacity: 0.8
          }
        }

        Column {
          visible: root.online
          width: parent.width
          spacing: Style.space(14)

          Choice {
            title: strings.t("battery")
            options: root.st.charging_profiles || []
            current: root.st.charging_profile || ""
            labelPrefix: "charge."
            onPicked: function(v) { root.setValue("charging_profile", v) }
          }

          Choice {
            visible: root.st.perf_profile !== undefined
            title: strings.t("perf")
            options: root.perfModes
            current: root.st.perf_profile || ""
            labelPrefix: "perf."
            onPicked: function(v) { root.setValue("perf_profile", v) }
          }

          Choice {
            title: strings.t("fans")
            options: root.fanModes
            current: root.st.fan || ""
            labelPrefix: "fan."
            onPicked: function(v) { root.setValue("fan", v) }
          }

          Label {
            text: strings.t("fansReading").arg(Commons.I18n.formatNumber(root.st.fan1 || 0)).arg(Commons.I18n.formatNumber(root.st.fan2 || 0))
            opacity: 0.6
            font.pixelSize: Style.font.bodySmall
          }

          PanelSeparator { foreground: root.bar.foreground }

          Column {
            width: parent.width
            spacing: Style.space(8)
            PanelSectionHeader {
              text: strings.t("hardware")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }
            Switch { key: "fn_lock" }
            Switch { key: "usb_powershare" }
            Switch { key: "ac_auto_boot" }
          }

          Label {
            visible: root.lastError !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: strings.t("error").arg(root.lastError)
            color: root.bar.urgent
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
  }

  component Choice: Column {
    id: choice
    property string title: ""
    property var options: []
    property string current: ""
    property string labelPrefix: ""
    signal picked(string value)

    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: choice.title
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    Row {
      id: choiceRow
      width: parent.width
      spacing: Style.space(6)
      readonly property real cellWidth: choice.options.length > 0
        ? (width - spacing * (choice.options.length - 1)) / choice.options.length : 0

      Repeater {
        model: choice.options
        Button {
          required property var modelData
          width: choiceRow.cellWidth
          text: strings.t(choice.labelPrefix + modelData)
          fontSize: Style.font.bodySmall
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          active: choice.current === modelData
          onClicked: choice.picked(modelData)
        }
      }
    }
  }

  component Switch: Item {
    id: sw
    property string key: ""
    width: parent.width
    implicitHeight: Math.max(swLabel.implicitHeight, swToggle.implicitHeight)

    Label {
      id: swLabel
      text: strings.t(sw.key)
      anchors.left: parent.left
      anchors.right: swToggle.left
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
    }
    ToggleSwitch {
      id: swToggle
      checked: root.st[sw.key] === "1"
      foreground: root.bar.foreground
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      onToggled: root.setValue(sw.key, checked ? "0" : "1")
    }
  }
}
