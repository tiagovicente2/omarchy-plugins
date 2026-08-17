import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.power"
  ipcTarget: "omarchy.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  property int detectedChargeLimit: -1
  property int requestedChargeLimit: -1
  property string kernelBatteryState: ""
  property string expectedBatteryState: ""
  property string chargeLimitCapability: "unknown"
  readonly property int helperProtocolVersion: 3
  readonly property bool showPercentage: setting("showPercentage", false) === true
  readonly property int chargeLimit: detectedChargeLimit >= 0 ? detectedChargeLimit : 100
  readonly property bool chargeLimitAvailable: chargeLimitCapability === "available"
  readonly property bool batteryProtectionEnabled: chargeLimitAvailable && chargeLimit < 100
  // Render the requested limit while the privileged helper is running. This
  // makes the battery state, icon, and stats react to the click instead of
  // waiting for UPower to notice the sysfs threshold change.
  readonly property int effectiveChargeLimit: requestedChargeLimit >= 0 ? requestedChargeLimit : chargeLimit
  readonly property bool effectiveBatteryProtectionEnabled: chargeLimitAvailable && effectiveChargeLimit < 100
  property string chargeLimitError: ""
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && !button.vertical ? button.glyphPaintedWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function batteryIcon() {
    var device = effectiveBatteryDevice()
    return Model.batteryIcon(device, root.discharging, upowerStates())
  }

  function stateForKernelStatus(state) {
    if (state === "Charging") return UPowerDeviceState.Charging
    if (state === "Discharging") return UPowerDeviceState.Discharging
    if (state === "Not charging") return UPowerDeviceState.PendingCharge
    if (state === "Full") return UPowerDeviceState.FullyCharged
    return -1
  }

  function desiredKernelBatteryState(limit) {
    if (root.discharging) return "Discharging"
    if (root.batteryFraction >= 1 && limit >= 100) return "Full"
    if (limit < 100 && root.batteryFraction >= limit / 100) return "Not charging"
    return "Charging"
  }

  function effectiveBatteryState() {
    if (root.requestedChargeLimit >= 0) {
      return stateForKernelStatus(desiredKernelBatteryState(root.requestedChargeLimit))
    }
    var expectedState = stateForKernelStatus(root.expectedBatteryState)
    if (expectedState >= 0) return expectedState
    var kernelState = stateForKernelStatus(root.kernelBatteryState)
    if (kernelState >= 0) return kernelState
    var device = UPower.displayDevice
    return device && device.isPresent ? device.state : -1
  }

  function effectiveBatteryDevice() {
    var device = UPower.displayDevice
    if (!device || !device.isPresent) return device
    return {
      isPresent: true,
      percentage: device.percentage,
      state: effectiveBatteryState(),
      changeRate: device.changeRate,
      timeToFull: device.timeToFull
    }
  }

  function updateKernelBatteryState(state) {
    var kernelState = stateForKernelStatus(state)
    var device = UPower.displayDevice
    if (kernelState < 0 || device && device.isPresent && device.state === kernelState) {
      kernelBatteryState = ""
      batteryStateOverrideTimer.stop()
      return
    }
    kernelBatteryState = state
    batteryStateOverrideTimer.restart()
  }

  function modeLabel() {
    var device = UPower.displayDevice
    if (root.chargeLimitAvailable) {
      if (root.chargeThresholdActive) return "Threshold"
      if (root.discharging) return "On battery"
      if (root.batteryFraction >= 1) return "Fully charged"
      return "Charging"
    }
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  function profileIcon(name) {
    return Model.profileIcon(name)
  }

  readonly property bool fullyCharged: {
    return root.effectiveBatteryState() === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = root.effectiveBatteryDevice()
    var upowerThresholdActive = Model.chargeThresholdActive(device, root.discharging, upowerStates())
    if (!root.chargeLimitAvailable) return upowerThresholdActive
    if (!root.effectiveBatteryProtectionEnabled) return false
    return upowerThresholdActive || (!root.discharging && root.batteryFraction >= root.effectiveChargeLimit / 100)
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the visual progress bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  readonly property color batteryFillColor: {
    return root.bar ? root.bar.foreground : Color.foreground
  }

  // Cute agent-flavored phrases shown in the hero status line, rotated on a
  // timer so the panel feels alive when current is flowing (either direction).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  // Whichever list is "active" given the current power state.
  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!chargeLimitProc.running && !chargeLimitStatusProc.running) chargeLimitStatusProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateChargeLimitStatus(exitCode, raw, error) {
    var values = Model.parseKeyValue(raw)
    var version = parseInt(values.version || "", 10)
    var value = parseInt(values.threshold || "", 10)
    var state = String(values.state || "")
    if (exitCode !== 0 || version !== helperProtocolVersion || value < 0 || value > 100) {
      chargeLimitCapability = "unavailable"
      detectedChargeLimit = -1
      var detail = String(error || "").trim()
      chargeLimitError = detail.indexOf("Battery ") === 0 || detail === "No battery found"
        ? detail
        : "Battery helper is missing or outdated. Re-run this plugin's install-helper.sh."
      return
    }

    var wasAvailable = chargeLimitAvailable
    detectedChargeLimit = value
    chargeLimitCapability = "available"
    // A status read immediately after changing the threshold can still expose
    // the old kernel state. Keep the requested state until sysfs catches up.
    if (root.expectedBatteryState === "" || state === root.expectedBatteryState) {
      updateKernelBatteryState(state)
      if (state === root.expectedBatteryState) root.expectedBatteryState = ""
    }
    if (!wasAvailable) chargeLimitError = ""
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function toggleBatteryProtection() {
    if (!chargeLimitAvailable || chargeLimitProc.running || chargeLimitStatusProc.running) return
    chargeLimitError = ""
    requestedChargeLimit = root.batteryProtectionEnabled ? 100 : 80
    chargeLimitProc.command = [
      "pkexec",
      "/usr/local/bin/battery-protection",
      String(requestedChargeLimit)
    ]
    chargeLimitProc.running = true
  }

  IpcHandler {
    target: "omarchy.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      refresh()
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
    }
  }

  onBatteryPresentChanged: {
    chargeLimitCapability = "unknown"
    detectedChargeLimit = -1
    kernelBatteryState = ""
    expectedBatteryState = ""
    chargeLimitError = ""
    if (!batteryPresent) close()
  }

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "battery") }
  }

  Process {
    id: chargeLimitStatusProc
    command: ["/usr/local/bin/battery-protection", "status"]
    stdout: StdioCollector { id: chargeLimitStatusStdout; waitForEnd: true }
    stderr: StdioCollector { id: chargeLimitStatusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.updateChargeLimitStatus(exitCode, chargeLimitStatusStdout.text, chargeLimitStatusStderr.text)
    }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateProfiles(text) }
  }

  Process {
    id: systemProc
    command: ["omarchy-system-stats"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateKeyValue(text, "system") }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Process {
    id: chargeLimitProc
    stderr: StdioCollector { id: chargeLimitStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        // Preserve the optimistic state after requestedChargeLimit is cleared.
        // The first status read may still report the pre-toggle state, so wait
        // until either sysfs or UPower reaches this expected state.
        root.expectedBatteryState = root.desiredKernelBatteryState(root.requestedChargeLimit)
        root.kernelBatteryState = root.expectedBatteryState
        batteryStateOverrideTimer.restart()
        root.detectedChargeLimit = root.requestedChargeLimit
      } else {
        root.chargeLimitError = chargeLimitStderr.text.trim() || "Could not change the charge limit"
      }
      root.requestedChargeLimit = -1
      // onExited fires before Process.running becomes false. Defer so refresh()
      // can start the authoritative status read even if the panel just closed.
      Qt.callLater(root.refresh)
    }
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  Timer {
    id: batteryStateOverrideTimer
    interval: 60000
    onTriggered: {
      root.expectedBatteryState = ""
      root.kernelBatteryState = ""
    }
  }

  Connections {
    target: UPower.displayDevice
    function onStateChanged() {
      var device = UPower.displayDevice
      var targetState = root.expectedBatteryState !== ""
        ? root.expectedBatteryState
        : root.kernelBatteryState
      if (device && device.isPresent && device.state === root.stateForKernelStatus(targetState)) {
        root.expectedBatteryState = ""
        root.kernelBatteryState = ""
        batteryStateOverrideTimer.stop()
      }
    }
  }

  // Rotate the status phrase while the panel is open and we're in a
  // rotating state (charging or on battery). The text swap is wrapped in a
  // fade so the changeover reads as one organism rather than a hard cut.
  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    triggeredOnStart: false
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: {
        var n = root.activePhrases.length
        if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
      }
    }
    PropertyAnimation {
      target: heroStatus; property: "opacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  // If we leave a rotating state mid-swap, halt the animation and snap back
  // to full opacity so "FULLY CHARGED" is legible immediately rather than
  // appearing dimmed.
  Connections {
    target: root
    function onRotatingPhrasesChanged() {
      if (!root.rotatingPhrases) {
        phraseSwap.stop()
        heroStatus.opacity = 1.0
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showPercentage && !vertical
      ? Math.round(root.batteryFraction * 100) + "% " + root.batteryIcon()
      : root.batteryIcon()
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dx !== 0) root.selectProfileByDelta(dx)
        else if (dy !== 0) root.selectProfileByDelta(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateSelectedProfile()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: battery icon · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            text: root.batteryIcon()
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Battery"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              id: heroStatus
              text: root.heroStatusText.toUpperCase()
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
            id: heroPercent
            text: root.batteryInfo.percentage || "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }

        // ---------- Battery progress bar ----------
        Item {
          width: parent.width
          implicitHeight: Style.space(8)

          Rectangle {
            id: barTrack
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
          }

          Rectangle {
            id: barFill
            anchors.left: barTrack.left
            anchors.verticalCenter: barTrack.verticalCenter
            height: barTrack.height
            radius: barTrack.radius
            color: root.batteryFillColor
            width: Math.max(barTrack.height, barTrack.width * root.batteryFraction)

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 220 } }

            // Subtle pulse while charging — visible signal that energy is flowing in.
            SequentialAnimation on opacity {
              running: root.charging && !root.fullyCharged && root.opened
              loops: Animation.Infinite
              alwaysRunToEnd: true
              NumberAnimation { from: 1.0; to: 0.55; duration: 950; easing.type: Easing.InOutSine }
              NumberAnimation { from: 0.55; to: 1.0; duration: 950; easing.type: Easing.InOutSine }
            }
          }
        }

        // ---------- Stats ----------
        // Visibility is intentionally only gated by "we've ever loaded data" so
        // the section never collapses mid-transition. fullyCharged is *not* part
        // of the condition: UPower briefly reports FullyCharged on plug-in when
        // the battery sits above the charge-control start threshold, and we
        // refuse to flicker the whole panel for that ~1s window.
        Row {
          visible: root.batteryInfo.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: "Battery size"; value: root.batteryInfo.size || "" }
            InfoPair { label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.chargeThresholdActive ? "Charge limit" : (root.discharging ? "Time left" : "Time to full")
              value: root.chargeThresholdActive ? (root.effectiveChargeLimit + "%") : (root.batteryFlowIdle ? "-" : (root.batteryInfo.time || "—"))
            }
            InfoPair {
              label: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
              value: root.chargeThresholdActive ? "Holding" : (root.batteryFull ? "-" : (root.batteryInfo.rate || ""))
            }
          }
        }

        // ---------- Battery protection ----------
        Toggle {
          width: parent.width
          label: "Battery protection"
          description: root.requestedChargeLimit === 80
            ? "Enabling 80% charge limit"
            : root.requestedChargeLimit === 100
              ? "Disabling charge limit"
              : root.chargeLimitCapability === "unknown"
            ? "Checking charge-limit support"
            : !root.chargeLimitAvailable
              ? "Charge-limit control is unavailable"
              : root.batteryProtectionEnabled
                ? "Charging stops at " + root.chargeLimit + "%"
                : "Limit charging to 80% to reduce battery wear"
          foreground: root.bar.foreground
          accent: root.bar.foreground
          fontFamily: root.bar.fontFamily
          checked: root.requestedChargeLimit >= 0
            ? root.requestedChargeLimit < 100
            : root.batteryProtectionEnabled
          enabled: root.chargeLimitAvailable && !chargeLimitProc.running && !chargeLimitStatusProc.running
          opacity: enabled ? 1.0 : 0.6
          onClicked: root.toggleBatteryProtection()
        }

        Text {
          visible: root.chargeLimitError !== ""
          width: parent.width
          text: root.chargeLimitError
          color: root.bar.foreground
          opacity: 0.7
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        // ---------- Power profile picker ----------
        PanelSeparator {
          foreground: root.bar.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "POWER PROFILE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)

            readonly property real cellWidth: root.profiles.length > 0
              ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
              : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cellWidth
                iconText: root.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: String(modelData).charAt(0).toUpperCase() + String(modelData).slice(1)
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.controlPaddingX
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.profileIndex === index
                onClicked: root.setProfile(modelData)
                onHovered: function(h) {
                  if (h) {
                    root.cursorActive = true
                    root.profileIndex = index
                  }
                }
              }
            }
          }
        }
      }
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
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
