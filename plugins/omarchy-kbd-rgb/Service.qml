import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  // Injected by omarchy-shell (the service loader).
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  // ------------------------------------------------------------------ state

  property string hex: "00E5FF"
  property int acBrightness: 100
  property int batteryBrightness: 100
  readonly property int brightness: root.onBattery ? root.batteryBrightness : root.acBrightness
  property string mode: "static"
  property bool followTheme: false
  property string themeTarget: "accent" // "accent" | "foreground"
  property int rainbowHue: 0
  property bool batterySaver: false
  property bool nightLightSync: false
  property string savedPreNightLightHex: ""
  property bool isBatterySaverIdled: false
  property bool restoringProfile: false
  property bool opened: false
  property bool persistOnIdle: false
  property var queue: []
  property bool vrgbAvailable: true
  property string applyError: ""

  readonly property var nightlightService: shell ? shell.firstPartyServiceFor("omarchy.nightlight") : null
  readonly property bool isNightlightActive: !!(nightlightService && nightlightService.enabled)
  readonly property bool isNightLightEffective: root.nightLightSync && root.isNightlightActive && root.mode !== "off"
  readonly property string activeDisplayHex: root.isNightLightEffective ? root.nightLightHex : root.hex

  readonly property string pluginDir: {
    var dir = root.manifest && root.manifest.__sourceDir
      ? String(root.manifest.__sourceDir) : ""
    if (dir) return dir
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/omarchy-kbd-rgb"
  }
  readonly property color foreground: Color.popups.text
  readonly property string fontFamily: Style.font.family
  readonly property bool onBattery: UPower.onBattery
  // The active value is a stored preference for the current power source, not a cap.
  readonly property int effectiveBrightness: root.brightness
  readonly property int rgbIdleTimeout: root.onBattery
    ? (root.batterySaver ? 10 : 15)
    : (root.batterySaver ? 30 : 0)
  readonly property bool idleMonitorEnabled: root.mode !== "off" && root.rgbIdleTimeout > 0
  property int armedIdleTimeout: 0
  property bool idleMonitorActive: false

  readonly property string tooltip: {
    if (root.isBatterySaverIdled) return "Keyboard: Off (Idle)"
    if (root.mode === "off") return "Keyboard: Off"
    var powerSuffix = root.onBattery ? " (Battery)" : " (AC)"
    if (root.isNightLightEffective) return "Keyboard: #" + root.nightLightHex + " (" + root.brightness + "%) (Night Light)" + powerSuffix
    if (root.mode === "rainbow") return "Keyboard: Rainbow (" + root.brightness + "%)" + powerSuffix
    var suffix = root.followTheme ? (root.themeTarget === "foreground" ? " (Theme Text)" : " (Theme Accent)") : ""
    return "Keyboard: #" + root.hex.toUpperCase() + " (" + root.brightness + "%)" + suffix + powerSuffix
  }

  readonly property string modeLabel: {
    if (root.mode === "off") return "Off"
    if (root.isNightLightEffective) return "Night Light"
    if (root.mode === "rainbow") return "Rainbow"
    if (root.followTheme) return root.themeTarget === "foreground" ? "Theme (Text)" : "Theme (Accent)"
    return "Static"
  }

  // ------------------------------------------------ theme synchronization

  Connections {
    target: Color
    function onAccentChanged() {
      if (root.followTheme && root.themeTarget === "accent" && root.mode !== "off" && root.mode !== "rainbow") {
        root.applyThemeAccent()
      }
    }
    function onForegroundChanged() {
      if (root.followTheme && root.themeTarget === "foreground" && root.mode !== "off" && root.mode !== "rainbow") {
        root.applyThemeAccent()
      }
    }
  }

  function currentThemeColor() {
    return root.themeTarget === "foreground" ? Color.foreground : Color.accent
  }

  function applyThemeAccent() {
    var targetCol = root.currentThemeColor()
    var accentHex = Model.qcolorToHex(targetCol)
    if (accentHex && Model.validHex(accentHex)) {
      root.hex = accentHex
      if (root.mode === "off" || root.mode === "rainbow") root.mode = "static"
      apply()
      scheduleSettingsSave()
    }
  }

  function setThemeTarget(target) {
    if (target !== "accent" && target !== "foreground") return
    root.themeTarget = target
    if (root.followTheme && root.mode !== "off" && root.mode !== "rainbow") {
      root.applyThemeAccent()
    } else {
      scheduleSettingsSave()
    }
  }

  // --------------------------------------------- smart automation listeners

  // Night Light warm tint synchronization (uses pure warm amber FF7700 with zero blue light)
  readonly property string nightLightHex: "FF7700"

  onIsNightLightEffectiveChanged: {
    if (!root.settingsLoaded || root.hydrating) return
    if (root.isNightLightEffective) {
      if (root.savedPreNightLightHex === "") {
        root.savedPreNightLightHex = root.hex
      }
      apply()
    } else {
      root.savedPreNightLightHex = ""
      if (root.followTheme && root.mode !== "off" && root.mode !== "rainbow") {
        root.applyThemeAccent()
      } else {
        apply()
      }
    }
  }

  // Recreate the monitor after policy changes. Quickshell 0.3 only arms idle
  // notifications when the monitor is created enabled with a fixed timeout.
  function resetIdleMonitor() {
    if (!root.settingsLoaded || root.hydrating) return
    root.idleMonitorActive = false
    root.armedIdleTimeout = 0
    Qt.callLater(function() {
      if (!root.settingsLoaded || root.hydrating) return
      root.armedIdleTimeout = root.idleMonitorEnabled ? root.rgbIdleTimeout : 0
      root.idleMonitorActive = root.armedIdleTimeout > 0
    })
  }

  // Switching power source or saver policy restores RGB, then uses the new idle timeout.
  function updatePowerBrightness() {
    if (!root.settingsLoaded || root.hydrating) return
    root.isBatterySaverIdled = false
    root.resetIdleMonitor()
    Qt.callLater(function() {
      if (!root.settingsLoaded || root.hydrating) return
      root.apply()
    })
  }

  onOnBatteryChanged: updatePowerBrightness()
  onBatterySaverChanged: {
    updatePowerBrightness()
    scheduleSettingsSave()
  }

  Loader {
    id: batterySaverIdleMonitorLoader
    active: root.idleMonitorActive
    sourceComponent: root.armedIdleTimeout === 10 ? idle10Monitor
      : (root.armedIdleTimeout === 15 ? idle15Monitor : idle30Monitor)
  }

  Component {
    id: idle10Monitor
    IdleMonitor {
      timeout: 10
      respectInhibitors: false
      onIsIdleChanged: root.handleBatterySaverIdleChanged(isIdle)
    }
  }

  Component {
    id: idle15Monitor
    IdleMonitor {
      timeout: 15
      respectInhibitors: false
      onIsIdleChanged: root.handleBatterySaverIdleChanged(isIdle)
    }
  }

  Component {
    id: idle30Monitor
    IdleMonitor {
      timeout: 30
      respectInhibitors: false
      onIsIdleChanged: root.handleBatterySaverIdleChanged(isIdle)
    }
  }

  function handleBatterySaverIdleChanged(isIdle) {
    if (!root.idleMonitorEnabled) {
      if (root.isBatterySaverIdled) {
        root.isBatterySaverIdled = false
        apply()
      }
      return
    }

    if (isIdle) {
      root.isBatterySaverIdled = true
      enqueue(["vrgb", "off"])
      feedSni()
    } else if (root.isBatterySaverIdled) {
      root.isBatterySaverIdled = false
      apply()
    }
  }

  function setActiveBrightness(value) {
    var next = Math.max(0, Math.min(100, Math.round(value)))
    if (root.onBattery) root.batteryBrightness = next
    else root.acBrightness = next
  }

  // ------------------------------------------------------------ vrgb apply

  function enqueue(cmd) {
    if (cmd.length >= 2 && (cmd[1] === "set" || cmd[1] === "brightness")) {
      root.queue = root.queue.filter(function(c) {
        return !(c.length >= 2 && (c[1] === "set" || c[1] === "brightness"))
      })
    }
    root.queue.push(cmd)
    pump()
  }

  function pump() {
    if (applyProc.running || root.queue.length === 0) return
    applyProc.command = root.queue.shift()
    applyProc.running = true
  }

  // Active smooth spectrum color cycle timer for single-zone rainbow mode
  Timer {
    id: rainbowTimer
    interval: 80
    repeat: true
    running: root.mode === "rainbow" && !root.isBatterySaverIdled && !root.isNightLightEffective
    onTriggered: {
      root.rainbowHue = (root.rainbowHue + 3) % 360
      var currentHex = Model.hsvToHex(root.rainbowHue, 1.0, 1.0)
      root.hex = currentHex
      root.enqueue(["vrgb", "set", currentHex, String(root.effectiveBrightness)])
      root.feedSni()
    }
  }

  function apply() {
    if (root.isBatterySaverIdled) {
      root.persistOnIdle = true
      syncHwBrightnessToHelper()
      scheduleSettingsSave()
      return
    }

    var cmd
    if (root.mode === "off") {
      cmd = ["vrgb", "off"]
    } else if (root.isNightLightEffective) {
      cmd = ["vrgb", "set", root.nightLightHex, String(root.effectiveBrightness)]
    } else if (root.mode === "rainbow") {
      var rainbowHex = Model.hsvToHex(root.rainbowHue, 1.0, 1.0)
      root.hex = rainbowHex
      cmd = ["vrgb", "set", rainbowHex, String(root.effectiveBrightness)]
    } else {
      cmd = ["vrgb", "set", root.hex, String(root.effectiveBrightness)]
    }
    root.applyError = ""
    root.persistOnIdle = true
    enqueue(cmd)
    feedSni()
    syncHwBrightnessToHelper()
    scheduleSettingsSave()
  }

  function setHex(next) {
    if (!Model.validHex(next)) return
    root.isBatterySaverIdled = false
    var normalized = Model.normalizeHex(next)
    root.hex = normalized
    if (root.savedPreNightLightHex !== "") {
      root.savedPreNightLightHex = normalized
    }
    root.followTheme = false
    if (root.mode === "off" || root.mode === "rainbow") root.mode = "static"
    apply()
  }

  function setBrightness(value) {
    var val = Math.max(0, Math.min(100, Math.round(value)))
    root.isBatterySaverIdled = false
    root.setActiveBrightness(val)
    if (val === 0) {
      root.mode = "off"
    } else if (root.mode === "off") {
      root.mode = "static"
      if (root.followTheme) {
        root.applyThemeAccent()
        return
      }
    }
    apply()
  }

  function setMode(next) {
    root.isBatterySaverIdled = false
    if (next === "theme") {
      root.followTheme = true
      root.mode = "static"
      root.applyThemeAccent()
      return
    }
    root.followTheme = false
    root.mode = next
    if ((next === "static" || next === "rainbow") && root.brightness === 0) {
      root.setActiveBrightness(100)
    }
    apply()
  }

  // ------------------------------------------------- hardware sync & tray

  function feedSni() {
    if (!sniProc.running) return
    if (root.isBatterySaverIdled) {
      sniProc.write("mode off " + root.hex + "\n")
      sniProc.write("tooltip " + root.tooltip + "\n")
      return
    }
    if (root.isNightLightEffective) {
      sniProc.write("mode static " + root.nightLightHex + "\n")
      sniProc.write("tooltip " + root.tooltip + "\n")
      return
    }
    var sniMode = root.mode
    if (root.followTheme && root.mode !== "off" && root.mode !== "rainbow") {
      sniMode = "theme"
    }
    sniProc.write("mode " + sniMode + " " + root.hex + "\n")
    sniProc.write("tooltip " + root.tooltip + "\n")
  }

  function syncHwBrightnessToHelper() {
    if (!sniProc.running) return
    var target = root.mode === "off" ? 0 : root.brightness
    sniProc.write("set_hw_brightness " + target + "\n")
  }

  function handleSniOutput(line) {
    var text = String(line || "").trim()
    if (text.indexOf("hw_brightness ") === 0) {
      var pct = parseInt(text.substring(14).trim(), 10)
      if (!isNaN(pct)) {
        root.onHardwareBrightnessChanged(pct)
      }
    }
  }

  function onHardwareBrightnessChanged(pct) {
    pct = Math.max(0, Math.min(100, pct))
    if (pct === 0) {
      if (root.mode !== "off") {
        root.mode = "off"
        root.setActiveBrightness(0)
        enqueue(["vrgb", "off"])
        feedSni()
      }
    } else {
      var modeChanged = root.mode === "off"
      if (modeChanged) {
        root.mode = "static"
        root.setActiveBrightness(pct)
        if (root.followTheme) {
          root.applyThemeAccent()
          return
        }
      }
      root.setActiveBrightness(pct)
      enqueue(["vrgb", "brightness", String(root.brightness)])
      feedSni()
    }
    root.persistOnIdle = true
    scheduleSettingsSave()
  }

  // ------------------------------------------------------- window control

  function open() {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    root.opened ? close() : open()
  }

  // ------------------------------------------------------------ hydration

  function hydrate() {
    if (!statusProc.running) statusProc.running = true
  }

  function onStatus(raw) {
    var state = Model.parseStatus(raw)
    if (!root.settingsLoaded || root.restoringProfile) {
      if (state.hex) root.hex = state.hex
      if (state.brightness >= 0) {
        // A legacy VRGB profile predates per-power settings, so seed both sides.
        root.acBrightness = state.brightness
        root.batteryBrightness = state.brightness
      }
      if (state.mode) root.mode = state.mode
    }
    root.restoringProfile = false

    if (root.settingsLoaded) {
      resetIdleMonitor()
      apply()
    } else feedSni()
  }

  function restore() {
    if (!restoreProc.running) restoreProc.running = true
  }

  // -------------------------------------------------------------- IPC

  IpcHandler {
    target: "omarchy-kbd-rgb"

    function ping(): string { return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function setHex(hexStr: string): string { root.setHex(hexStr); return "ok" }
    function setBrightness(value: int): string { root.setBrightness(value); return "ok" }
    function setMode(modeStr: string): string { root.setMode(modeStr); return "ok" }
    function applyThemeAccent(): string { root.setMode("theme"); return "ok" }
    function setThemeTarget(target: string): string { root.setThemeTarget(target); return "ok" }
    function setFollowTheme(enabled: bool): string { root.followTheme = enabled; if (enabled) root.applyThemeAccent(); return "ok" }
    function setBatterySaver(enabled: bool): string { root.batterySaver = enabled; return "ok" }
    function setNightLightSync(enabled: bool): string { root.nightLightSync = enabled; root.scheduleSettingsSave(); return "ok" }
    function stepBrightness(delta: int): string {
      var next = Math.max(0, Math.min(100, root.brightness + delta))
      root.setBrightness(next)
      return String(root.brightness)
    }
    function togglePower(): string {
      if (root.mode === "off") {
        root.setMode(root.followTheme ? "theme" : "static")
      } else {
        root.setMode("off")
      }
      return root.mode
    }
    function nextPreset(): string {
      root.followTheme = false
      var presets = Model.PRESETS
      var currentIndex = -1
      for (var i = 0; i < presets.length; i++) {
        if (presets[i].hex === root.hex) {
          currentIndex = i
          break
        }
      }
      var nextIndex = (currentIndex + 1) % presets.length
      root.setHex(presets[nextIndex].hex)
      return presets[nextIndex].name + " (#" + presets[nextIndex].hex + ")"
    }
    function status(): string {
      return JSON.stringify({
        hex: root.hex,
        brightness: root.brightness,
        acBrightness: root.acBrightness,
        batteryBrightness: root.batteryBrightness,
        onBattery: root.onBattery,
        batterySaver: root.batterySaver,
        rgbIdleTimeout: root.rgbIdleTimeout,
        batterySaverIdled: root.isBatterySaverIdled,
        idleMonitorEnabled: root.idleMonitorEnabled,
        idleMonitorIdle: !!(batterySaverIdleMonitorLoader.item && batterySaverIdleMonitorLoader.item.isIdle),
        mode: root.followTheme ? "theme" : root.mode,
        followTheme: root.followTheme,
        themeTarget: root.themeTarget,
        nightLightSync: root.nightLightSync,
        nightLightActive: root.isNightLightEffective,
        opened: root.opened,
        vrgb: root.vrgbAvailable
      })
    }
  }

  // Backward compatibility alias for kbd-rgb target
  IpcHandler {
    target: "kbd-rgb"

    function ping(): string { return "ok" }
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function setHex(hexStr: string): string { root.setHex(hexStr); return "ok" }
    function setBrightness(value: int): string { root.setBrightness(value); return "ok" }
    function setMode(modeStr: string): string { root.setMode(modeStr); return "ok" }
    function applyThemeAccent(): string { root.setMode("theme"); return "ok" }
    function setThemeTarget(target: string): string { root.setThemeTarget(target); return "ok" }
    function setFollowTheme(enabled: bool): string { root.followTheme = enabled; if (enabled) root.applyThemeAccent(); return "ok" }
    function setBatterySaver(enabled: bool): string { root.batterySaver = enabled; return "ok" }
    function setNightLightSync(enabled: bool): string { root.nightLightSync = enabled; root.scheduleSettingsSave(); return "ok" }
    function stepBrightness(delta: int): string {
      var next = Math.max(0, Math.min(100, root.brightness + delta))
      root.setBrightness(next)
      return String(root.brightness)
    }
    function togglePower(): string {
      if (root.mode === "off") {
        root.setMode(root.followTheme ? "theme" : "static")
      } else {
        root.setMode("off")
      }
      return root.mode
    }
    function nextPreset(): string {
      root.followTheme = false
      var presets = Model.PRESETS
      var currentIndex = -1
      for (var i = 0; i < presets.length; i++) {
        if (presets[i].hex === root.hex) {
          currentIndex = i
          break
        }
      }
      var nextIndex = (currentIndex + 1) % presets.length
      root.setHex(presets[nextIndex].hex)
      return presets[nextIndex].name + " (#" + presets[nextIndex].hex + ")"
    }
    function status(): string {
      return JSON.stringify({
        hex: root.hex,
        brightness: root.brightness,
        acBrightness: root.acBrightness,
        batteryBrightness: root.batteryBrightness,
        onBattery: root.onBattery,
        batterySaver: root.batterySaver,
        rgbIdleTimeout: root.rgbIdleTimeout,
        batterySaverIdled: root.isBatterySaverIdled,
        idleMonitorEnabled: root.idleMonitorEnabled,
        idleMonitorIdle: !!(batterySaverIdleMonitorLoader.item && batterySaverIdleMonitorLoader.item.isIdle),
        mode: root.followTheme ? "theme" : root.mode,
        followTheme: root.followTheme,
        themeTarget: root.themeTarget,
        nightLightSync: root.nightLightSync,
        nightLightActive: root.isNightLightEffective,
        opened: root.opened,
        vrgb: root.vrgbAvailable
      })
    }
  }

  // ------------------------------------------------ settings persistence

  readonly property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/kbd-rgb.json"

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
  }

  Timer {
    id: settingsSaveTimer
    interval: 300
    repeat: false
    onTriggered: root.flushSettings()
  }

  property bool settingsLoaded: false
  property bool hydrating: false

  onModeChanged: {
    scheduleSettingsSave()
    resetIdleMonitor()
  }
  onHexChanged: {
    if (root.mode !== "rainbow") scheduleSettingsSave()
  }
  onAcBrightnessChanged: scheduleSettingsSave()
  onBatteryBrightnessChanged: scheduleSettingsSave()
  onFollowThemeChanged: scheduleSettingsSave()
  onThemeTargetChanged: scheduleSettingsSave()
  onNightLightSyncChanged: scheduleSettingsSave()

  Timer {
    id: startupFallbackTimer
    interval: 1200
    repeat: false
    running: !root.settingsLoaded
    onTriggered: {
      if (!root.settingsLoaded) {
        root.loadSettings("")
      }
    }
  }

  function scheduleSettingsSave() {
    if (!root.settingsLoaded || root.hydrating) return
    settingsSaveTimer.restart()
  }

  function loadSettings(raw) {
    if (root.settingsLoaded) return
    root.hydrating = true
    var hasSettings = false
    if (raw && raw.trim() !== "") {
      try {
        var data = JSON.parse(raw)
        hasSettings = true
        if (typeof data.themeTarget === "string" && (data.themeTarget === "accent" || data.themeTarget === "foreground")) {
          root.themeTarget = data.themeTarget
        }
        if (typeof data.followTheme === "boolean") {
          root.followTheme = data.followTheme
        }
        if (typeof data.batterySaver === "boolean") {
          root.batterySaver = data.batterySaver
        }
        if (typeof data.nightLightSync === "boolean") {
          root.nightLightSync = data.nightLightSync
        }
        // Migrate the former single brightness setting to both power sources.
        if (typeof data.brightness === "number" && data.brightness >= 0 && data.brightness <= 100) {
          root.acBrightness = data.brightness
          root.batteryBrightness = data.brightness
        }
        if (typeof data.acBrightness === "number" && data.acBrightness >= 0 && data.acBrightness <= 100) {
          root.acBrightness = data.acBrightness
        }
        if (typeof data.batteryBrightness === "number" && data.batteryBrightness >= 0 && data.batteryBrightness <= 100) {
          root.batteryBrightness = data.batteryBrightness
        }
        if (typeof data.hex === "string" && Model.validHex(data.hex)) {
          root.hex = Model.normalizeHex(data.hex)
        }
        if (typeof data.mode === "string") {
          if (data.mode === "theme") {
            root.followTheme = true
            root.mode = "static"
          } else if (data.mode === "rainbow" || data.mode === "off" || data.mode === "static") {
            root.mode = data.mode
          }
        }
      } catch (e) {
        console.warn("kbd-rgb: failed to parse settings:", e)
      }
    }
    root.hydrating = false
    root.settingsLoaded = true

    if (hasSettings) {
      root.resetIdleMonitor()
      if (root.isNightLightEffective) {
        if (root.savedPreNightLightHex === "") {
          root.savedPreNightLightHex = root.hex
        }
        root.apply()
      } else if (root.followTheme) {
        root.applyThemeAccent()
      } else {
        root.apply()
      }
    } else {
      root.restoringProfile = true
      root.restore()
    }
  }

  function flushSettings() {
    if (!root.settingsLoaded || root.hydrating) return
    try {
      var payload = {
        mode: root.followTheme ? "theme" : root.mode,
        hex: root.hex,
        acBrightness: root.acBrightness,
        batteryBrightness: root.batteryBrightness,
        batterySaver: root.batterySaver,
        followTheme: root.followTheme,
        themeTarget: root.themeTarget,
        nightLightSync: root.nightLightSync
      }
      settingsFile.setText(JSON.stringify(payload, null, 2) + "\n")
    } catch (e) {
      console.warn("kbd-rgb: failed to flush settings:", e)
    }
  }

  // ------------------------------------------------------------ processes

  Process {
    id: sniProc
    command: ["python3", "-u", root.pluginDir + "/sni.py"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.handleSniOutput(line) }
    }
    onExited: function() {
      sniRestartTimer.restart()
    }
  }

  Timer {
    id: sniRestartTimer
    interval: 2000
    onTriggered: sniProc.running = true
  }

  Process {
    id: applyProc
    stderr: StdioCollector { id: applyStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.persistOnIdle && exitCode === 0) {
        root.persistOnIdle = false
        enqueue(["vrgb", "profile", "save", "kbd"])
      } else if (exitCode !== 0 && applyStderr.text.trim() !== "") {
        root.applyError = applyStderr.text.trim()
      }
      pump()
    }
  }

  Process {
    id: statusProc
    command: ["vrgb", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onStatus(text) }
    onExited: function(exitCode) {
      root.vrgbAvailable = exitCode === 0
    }
  }

  Process {
    id: restoreProc
    command: ["vrgb", "profile", "load", "kbd"]
    onExited: function(exitCode) {
      if (exitCode !== 0 && !fallbackProc.running) {
        fallbackProc.command = ["vrgb", "restore"]
        fallbackProc.running = true
        return
      }
      root.hydrate()
    }
  }

  Process {
    id: fallbackProc
    onExited: function() {
      root.hydrate()
    }
  }

  Component.onCompleted: {
    sniProc.running = true
  }

  // --------------------------------------------------------- control window

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-kbd-rgb"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    Keys.onEscapePressed: root.close()

    // Scrim overlay; clicking outside closes
    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.45)

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    BorderSurface {
      id: card
      anchors.top: parent.top
      anchors.topMargin: Style.bar.sizeHorizontal + Style.gapsOut * 2
      anchors.right: parent.right
      anchors.rightMargin: Style.gapsOut * 2
      width: Style.space(340)
      height: card.borderTop + column.implicitHeight + card.borderBottom + Style.space(24)
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      MouseArea {
        anchors.fill: parent
        // Prevent clicks inside card from closing panel
      }

      Column {
        id: column
        x: card.borderLeft + Style.space(16)
        y: card.borderTop + Style.space(16)
        width: parent.width - card.borderLeft - card.borderRight - Style.space(32)
        spacing: Style.space(12)

        // ==================== Header Hero ====================
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIconBox.implicitHeight, heroTextCol.implicitHeight)

          Rectangle {
            id: heroIconBox
            width: Style.space(38)
            height: Style.space(38)
            radius: Style.space(10)
            color: root.mode === "off"
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
              : (root.isNightLightEffective
                  ? Util.alpha(Model.colorValue(root.nightLightHex), 0.18)
                  : (root.mode === "rainbow"
                      ? Util.alpha(Color.accent, 0.15)
                      : Util.alpha(Model.colorValue(root.hex), 0.18)))
            border.width: 1
            border.color: root.mode === "off"
              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
              : (root.isNightLightEffective
                  ? Model.colorValue(root.nightLightHex)
                  : (root.mode === "rainbow"
                      ? Color.accent
                      : Model.colorValue(root.hex)))
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter

            Text {
              anchors.centerIn: parent
              text: root.isNightLightEffective ? "󰖔" : Model.modeIcon(root.mode, root.followTheme)
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
              color: root.mode === "off"
                ? Qt.darker(root.foreground, 1.8)
                : (root.isNightLightEffective
                    ? Model.colorValue(root.nightLightHex)
                    : (root.mode === "rainbow"
                        ? Color.accent
                        : Model.colorValue(root.hex)))
            }
          }

          Column {
            id: heroTextCol
            anchors.left: heroIconBox.right
            anchors.leftMargin: Style.space(12)
            anchors.right: closeBtn.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Keyboard RGB"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: {
                if (root.mode === "off") return "DISABLED · OFF"
                if (root.isNightLightEffective) return "NIGHT LIGHT · #" + root.nightLightHex + " · " + root.effectiveBrightness + "%"
                if (root.mode === "rainbow") return "DYNAMIC · RAINBOW · " + root.effectiveBrightness + "%"
                var tag = root.followTheme
                  ? (root.themeTarget === "foreground" ? "THEME TEXT" : "THEME ACCENT")
                  : Model.colorName(root.hex).toUpperCase()
                return tag + " · " + root.effectiveBrightness + "%"
              }
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.1
            }
          }

          Button {
            id: closeBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰅖"
            fontSize: Style.font.caption
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(4)
            foreground: Qt.darker(root.foreground, 1.3)
            onClicked: root.close()
          }
        }

        // ==================== Mode Buttons (4 options) ====================
        Row {
          width: parent.width
          spacing: Style.space(6)

          readonly property real cellWidth: (width - spacing * 3) / 4

          Button {
            width: parent.cellWidth
            text: "Theme"
            iconText: "󰏘"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(6)
            bordered: true
            selected: root.followTheme && root.mode !== "off" && root.mode !== "rainbow"
            active: root.followTheme && root.mode !== "off" && root.mode !== "rainbow"
            onClicked: root.setMode("theme")
          }

          Button {
            width: parent.cellWidth
            text: "Static"
            iconText: "󰌌"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(6)
            bordered: true
            selected: !root.followTheme && root.mode === "static"
            active: !root.followTheme && root.mode === "static"
            onClicked: root.setMode("static")
          }

          Button {
            width: parent.cellWidth
            text: "Rainbow"
            iconText: "󰃮"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(6)
            bordered: true
            selected: root.mode === "rainbow"
            active: root.mode === "rainbow"
            onClicked: root.setMode("rainbow")
          }

          Button {
            width: parent.cellWidth
            text: "Off"
            iconText: "󰅚"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(4)
            verticalPadding: Style.space(6)
            bordered: true
            selected: root.mode === "off"
            active: root.mode === "off"
            onClicked: root.setMode("off")
          }
        }

        // ==================== Theme Target Selector (when Theme mode active) ====================
        Column {
          visible: root.followTheme && root.mode !== "off" && root.mode !== "rainbow"
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "THEME COLOR TARGET"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            readonly property real targetBtnWidth: (width - spacing) / 2

            Button {
              width: parent.targetBtnWidth
              text: "Accent (#" + Model.qcolorToHex(Color.accent) + ")"
              iconText: "󰏘"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(4)
              verticalPadding: Style.space(6)
              bordered: true
              selected: root.themeTarget === "accent"
              active: root.themeTarget === "accent"
              onClicked: root.setThemeTarget("accent")
            }

            Button {
              width: parent.targetBtnWidth
              text: "Bar Text (#" + Model.qcolorToHex(Color.foreground) + ")"
              iconText: "󰌌"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(4)
              verticalPadding: Style.space(6)
              bordered: true
              selected: root.themeTarget === "foreground"
              active: root.themeTarget === "foreground"
              onClicked: root.setThemeTarget("foreground")
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        // ==================== Color Presets ====================
        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: presetHeader.implicitHeight

            PanelSectionHeader {
              id: presetHeader
              text: "PRESET COLORS"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: Model.hexLabel(root.activeDisplayHex)
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          GridLayout {
            id: grid
            width: parent.width
            columns: 6
            rowSpacing: Style.space(8)
            columnSpacing: Style.space(8)

            Repeater {
              model: Model.PRESETS

              Item {
                id: swatchItem
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(38)

                readonly property bool isSelected: !root.followTheme && (root.mode === "static" || root.isNightLightEffective) && root.activeDisplayHex === modelData.hex
                readonly property bool isLight: Model.isLightColor(modelData.hex)

                Rectangle {
                  id: swatchRect
                  anchors.fill: parent
                  radius: Style.space(8)
                  color: Model.colorValue(modelData.hex)
                  border.width: swatchItem.isSelected ? 2 : 1
                  border.color: swatchItem.isSelected
                    ? root.foreground
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
                  scale: swatchMouse.containsMouse ? 1.08 : 1.0

                  Behavior on scale {
                    NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                  }

                  // Active Selection Checkmark
                  Text {
                    visible: swatchItem.isSelected
                    anchors.centerIn: parent
                    text: ""
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    color: swatchItem.isLight ? "#111111" : "#ffffff"
                  }

                  MouseArea {
                    id: swatchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.setHex(modelData.hex)
                    }
                  }

                  QQC.ToolTip {
                    visible: swatchMouse.containsMouse
                    text: modelData.name + " (#" + modelData.hex + ")"
                    delay: 250
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        // ==================== Custom Hex & Brightness ====================
        Column {
          width: parent.width
          spacing: Style.space(10)

          // --- Hex Input Row ---
          Row {
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: Style.space(32)
              height: Style.space(32)
              radius: Style.space(6)
              color: Model.colorValue(root.activeDisplayHex)
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: "#"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            TextField {
              id: hexField
              width: Style.space(120)
              text: root.activeDisplayHex
              maximumLength: 6
              font.capitalization: Font.AllUppercase
              validator: RegularExpressionValidator { regularExpression: /[0-9a-fA-F]{6}/ }
              placeholderText: "RRGGBB"
              anchors.verticalCenter: parent.verticalCenter
              onAccepted: root.setHex(text)
              onTextEdited: {
                if (Model.validHex(text)) root.setHex(text)
              }
            }

            Button {
              text: "Apply"
              iconText: ""
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              bordered: true
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.setHex(hexField.text)
            }
          }

          // --- Brightness Header & Slider ---
          Column {
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: briHeader.implicitHeight

              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                Text {
                  text: Model.brightnessIcon(root.effectiveBrightness, root.mode)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconSmall
                  color: Qt.darker(root.foreground, 1.4)
                }

                PanelSectionHeader {
                  id: briHeader
                  text: root.onBattery ? "BRIGHTNESS · BATTERY" : "BRIGHTNESS · AC"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
              }

              Text {
                text: root.mode === "off" ? "0%" : root.effectiveBrightness + "%"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            PanelSlider {
              id: brightnessSlider
              width: parent.width
              minimum: 0
              maximum: 100
              step: 5
              integer: true
              value: root.mode === "off" ? 0 : root.brightness
              onMoved: function(v) {
                root.setActiveBrightness(v)
              }
              onReleased: function(v) {
                root.setBrightness(v)
              }
            }

            // Quick preset steps (matching hardware steps)
            Row {
              width: parent.width
              spacing: Style.space(6)

              readonly property real stepWidth: (width - spacing * 3) / 4

              Repeater {
                model: [
                  { label: "Off", val: 0 },
                  { label: "33%", val: 33 },
                  { label: "67%", val: 67 },
                  { label: "100%", val: 100 }
                ]

                Button {
                  required property var modelData
                  width: parent.stepWidth
                  text: modelData.label
                  fontSize: Style.font.caption
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  horizontalPadding: Style.space(4)
                  verticalPadding: Style.space(4)
                  bordered: true
                  selected: (modelData.val === 0 && root.mode === "off") || (root.mode !== "off" && Math.abs(root.brightness - modelData.val) <= 15)
                  active: (modelData.val === 0 && root.mode === "off") || (root.mode !== "off" && Math.abs(root.brightness - modelData.val) <= 15)
                  onClicked: {
                    if (modelData.val === 0) {
                      root.setMode("off")
                    } else {
                      root.setBrightness(modelData.val)
                    }
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        // ==================== Smart Automations ====================
        Row {
          width: parent.width
          spacing: Style.space(8)

          readonly property real autoBtnWidth: (width - spacing) / 2

          Button {
            width: parent.autoBtnWidth
            text: "Battery Saver"
            iconText: "󰁹"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(6)
            bordered: true
            selected: root.batterySaver
            active: root.batterySaver
            onClicked: root.batterySaver = !root.batterySaver
            tooltipText: root.batterySaver
              ? "Turns RGB off after 10s on battery or 30s on AC"
              : "Turns RGB off after 15s on battery; keeps it on while on AC"
          }

          Button {
            width: parent.autoBtnWidth
            text: "Night Light"
            iconText: "󰖔"
            fontSize: Style.font.caption
            foreground: root.foreground
            fontFamily: root.fontFamily
            horizontalPadding: Style.space(6)
            verticalPadding: Style.space(6)
            bordered: true
            selected: root.nightLightSync
            active: root.nightLightSync
            onClicked: root.nightLightSync = !root.nightLightSync
            tooltipText: "Warm keyboard color automatically when Night Light is active"
          }
        }

        // ==================== Status & Warnings ====================
        Rectangle {
          visible: !root.vrgbAvailable || root.applyError !== ""
          width: parent.width
          implicitHeight: warnRow.implicitHeight + Style.space(12)
          radius: Style.space(6)
          color: Util.alpha(Color.urgent, 0.15)
          border.width: 1
          border.color: Util.alpha(Color.urgent, 0.4)

          Row {
            id: warnRow
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            spacing: Style.space(8)

            Text {
              text: "󰀪"
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
              color: Color.urgent
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              width: parent.width - Style.space(28)
              text: !root.vrgbAvailable
                ? "VRGB not found on PATH. Install it first (see README)."
                : root.applyError
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }
    }
  }
}