import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Keyboard status: connection (USB cable / 2.4G dongle / Bluetooth) and lock
// keys. Shaped after io.github.twoscott.mouse-battery so the two sit side by
// side on the bar. Battery is not shown in the bar because most 2.4G boards
// (Epomaker included) report it only over a vendor protocol, not to the kernel.
//
// All Text pins PlainText: device names come from the hardware.
Panel {
  id: root
  moduleName: "hell0world.keyboard-status"
  ipcTarget: "hell0world.keyboard-status"

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---------------------------------------------------------------- settings
  readonly property string matchSetting: String(setting("match", ""))
  readonly property bool showCaps: setting("showCaps", true) !== false
  readonly property bool hideWhenAbsent: setting("hideWhenAbsent", false) === true

  // ------------------------------------------------------------------ state
  property bool capsLock: false
  property bool numLock: false
  property bool scrollLock: false
  property bool wired: false
  property bool dongle: false
  property bool bluetooth: false
  property string wiredName: ""
  property string dongleName: ""
  property string layoutName: ""

  readonly property bool hasDevice: wired || dongle || bluetooth

  // Drop an all-caps vendor token ("RDMCTMZT Epomaker Galaxy100") and the
  // dongle's own suffix so the name reads like the product.
  function cleanName(raw) {
    var words = String(raw || "").trim().split(/\s+/).filter(function(w) { return w !== "" })
    if (words.length > 1 && /^[A-Z0-9]{5,}$/.test(words[0])) words.shift()
    var out = words.join(" ").replace(/\s*(2\.4G|wireless)?\s*(dongle|receiver)$/i, "")
    return out.substring(0, 60)
  }

  readonly property string deviceName: {
    var n = cleanName(wiredName) || cleanName(dongleName)
    return n || strings.t("fallbackName")
  }

  // Cable wins: with it plugged the board types (and charges) over USB.
  readonly property string connectionText: wired ? strings.t("status.wired")
    : bluetooth ? strings.t("status.bluetooth")
    : dongle ? strings.t("status.dongle")
    : strings.t("status.absent")

  readonly property string glyph: String.fromCodePoint(0xF030C)   // nf-md-keyboard
  readonly property string connGlyph: wired ? String.fromCodePoint(0xF0553)      // usb
    : bluetooth ? String.fromCodePoint(0xF00AF)                                   // bluetooth
    : dongle ? String.fromCodePoint(0xF05A9)                                      // wifi
    : ""

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property bool capsTagShown: showCaps && capsLock && !vertical

  function applyLine(line) {
    var parts = String(line || "").split("\t")
    var flags = (parts[0] || "").split(" ")
    if (flags.length < 6) return
    capsLock = flags[0] === "1"
    numLock = flags[1] === "1"
    scrollLock = flags[2] === "1"
    wired = flags[3] === "1"
    dongle = flags[4] === "1"
    bluetooth = flags[5] === "1"
    wiredName = String(parts[1] || "").substring(0, 120)
    dongleName = String(parts[2] || "").substring(0, 120)
  }

  // ------------------------------------------------------------- processes
  readonly property string scriptPath: String(Qt.resolvedUrl("watch.sh")).replace(/^file:\/\//, "")

  Process {
    id: watcher
    running: true
    command: ["bash", root.scriptPath, root.matchSetting]
    stdout: SplitParser { onRead: function(data) { root.applyLine(data) } }
    // Restart the watcher if it ever exits (or the match setting changes).
    onRunningChanged: if (!running) restartTimer.restart()
  }
  onMatchSettingChanged: { watcher.running = false }

  Timer { id: restartTimer; interval: 2000; onTriggered: watcher.running = true }

  Process {
    id: layoutProc
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var kbs = JSON.parse(text || "{}").keyboards || []
          var main = kbs.filter(function(k) { return k.main })[0] || kbs[0]
          root.layoutName = main ? String(main.active_keymap || "").substring(0, 60) : ""
        } catch (e) {}
      }
    }
  }

  onOpenedChanged: if (opened && !layoutProc.running) layoutProc.running = true

  // ----------------------------------------------------------------- bar
  visible: hasDevice || !hideWhenAbsent
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0
  readonly property real openPanelIndicatorWidth: capsTagShown ? content.implicitWidth : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.round(content.implicitWidth + Style.bar.iconSlot - Style.bar.iconCanvas)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    dimmed: !root.hasDevice
    active: root.capsLock
    tooltipText: !root.hasDevice ? strings.t("tooltip.absent")
      : root.capsLock ? strings.t("tooltip.caps").arg(root.deviceName).arg(root.connectionText)
      : strings.t("tooltip.status").arg(root.deviceName).arg(root.connectionText)
    onPressed: function(b) { root.toggle() }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: root.capsTagShown ? Style.space(2) : 0

      OpticalGlyph {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        text: root.glyph
        fontFamily: button.fontFamily
        fontSize: Style.bar.iconFont
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
      }

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        visible: root.capsTagShown
        text: strings.t("tag.caps")
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        renderType: Text.NativeRendering
      }
    }
  }

  // ----------------------------------------------------------------- panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // Hero: keyboard glyph · name / connection · connection glyph
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.glyph
            color: root.bar.foreground
            opacity: root.hasDevice ? 1 : 0.5
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroConn.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.deviceName
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.connectionText.toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroConn
            textFormat: Text.PlainText
            text: root.connGlyph
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // Lock keys as three chips
        Row {
          width: parent.width
          spacing: Style.space(8)

          LockChip { label: strings.t("label.caps"); on: root.capsLock; urgentWhenOn: true }
          LockChip { label: strings.t("label.num"); on: root.numLock }
          LockChip { label: strings.t("label.scroll"); on: root.scrollLock }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          InfoPair { label: strings.t("label.connection"); value: root.connectionText }
          InfoPair {
            label: strings.t("label.dongle")
            value: root.dongle ? strings.t("value.plugged") : strings.t("value.unplugged")
          }
          InfoPair { label: strings.t("label.layout"); value: root.layoutName || "—" }
          InfoPair { label: strings.t("label.battery"); value: strings.t("value.noBattery") }
        }
      }
    }
  }

  component LockChip: Rectangle {
    property string label: ""
    property bool on: false
    property bool urgentWhenOn: false
    readonly property color tint: on && urgentWhenOn ? root.bar.urgent : root.bar.foreground

    width: (parent.width - parent.spacing * 2) / 3
    height: chipText.implicitHeight + Style.space(12)
    radius: Style.space(6)
    color: Qt.rgba(tint.r, tint.g, tint.b, on ? 0.18 : 0.06)
    border.width: 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, on ? 0.55 : 0.15)

    Behavior on color { ColorAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }

    Text {
      id: chipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: parent.label
      color: parent.tint
      opacity: parent.on ? 1 : 0.5
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: parent.on
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
