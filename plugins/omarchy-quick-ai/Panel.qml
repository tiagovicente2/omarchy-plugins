import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  // Injected by omarchy-shell (panel loader)
  property var shell: null
  property var manifest: null
  property var service: null
  property string omarchyPath: ""

  // ---- lifecycle (required for shell summon/hide/toggle) ----
  property bool opened: false
  // Also track whether we are logically open for the panel loader's isPluginOpen check
  readonly property bool isOpen: opened

  function open(payloadJson) {
    // Fresh session on every invoke: cancel lingering and clear state.
    if (askProc.running) askProc.running = false
    elapsedTimer.running = false
    timeoutTimer.running = false
    promptText = ""
    responseText = ""
    // payloadJson is optional JSON from `omarchy-shell shell summon ... '{}'`.
    // Parse it after clearing the previous session so its prompt survives.
    if (payloadJson) {
      try {
        var payload = JSON.parse(String(payloadJson))
        if (payload && typeof payload.prompt === "string" && payload.prompt.trim() !== "")
          promptText = String(payload.prompt)
      } catch (e) { /* ignore non-json payloads */ }
    }
    errorText = ""
    elapsedText = ""
    requestStartedMs = 0
    opened = true
    if (settingsPanel) settingsPanel.visible = false
    // Defer focus one tick so window is mapped
    Qt.callLater(function() {
      if (inputField) {
        inputField.forceActiveFocus()
        inputField.selectAll()
      }
    })
  }

  function close() {
    // Cancel lingering request on close so next invoke is fresh
    if (askProc.running) askProc.running = false
    elapsedTimer.running = false
    timeoutTimer.running = false
    opened = false
  }

  function toggle() { opened ? close() : open("") }

  // ---- config ----
  readonly property string pluginDir: {
    var dir = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    if (dir) return dir
    return Quickshell.env("HOME") + "/.config/omarchy/plugins/omarchy-quick-ai"
  }

  readonly property string settingsPath: Quickshell.env("HOME") + "/.config/omarchy/quick-ai.json"
  property bool settingsLoaded: false
  property bool hydrating: false

  property string selectedAgent: ""
  property string selectedModel: ""
  property bool keepHistory: true
  property var history: [] // {prompt, response, agent, model, ts}
  property var allModels: []
  property var availableModels: []
  property var modelByAgent: ({})
  property string previousAgent: ""

  // Use defaults per agent if model empty
  readonly property string effectiveModel: selectedModel !== "" ? selectedModel : Model.defaultModelFor(selectedAgent)
  readonly property string displayModel: effectiveModel !== "" ? effectiveModel : "agent default"

  readonly property color foreground: Color.popups.text
  readonly property string fontFamily: Style.font.family

  // ---- prompt / response state ----
  property string promptText: ""
  property string responseText: ""
  property string errorText: ""
  property bool busy: askProc.running
  property string elapsedText: ""
  property double requestStartedMs: 0
  property string copyFeedback: ""

  function currentPluginId() {
    if (manifest && manifest.id) return String(manifest.id)
    return "omarchy-quick-ai"
  }

  function closeIfNotBusyOutside() {
    if (!busy) close()
  }

  // ---- settings persistence (mirrors omarchy-kbd-rgb/Service.qml:510) ----
  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
  }

  // ---- models cache (dynamic, not stored in code) ----
  readonly property string modelsCachePath: Quickshell.env("HOME") + "/.cache/omarchy/quick-ai/models.json"

  FileView {
    id: modelsCacheFile
    path: root.modelsCachePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyModelsCache(text())
    onLoadFailed: {
      // No cache yet — build it
      if (!modelsProc.running) modelsProc.running = true
    }
    onFileChanged: reload()
  }

  function applyModelsCache(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      if (data && Array.isArray(data.all)) {
        root.allModels = data.all.slice()
        if (data.byAgent && data.byAgent[root.selectedAgent] && Array.isArray(data.byAgent[root.selectedAgent])) {
          root.availableModels = data.byAgent[root.selectedAgent].slice()
        } else {
          root.availableModels = Model.modelsForAgent(root.selectedAgent, root.allModels)
        }
        return
      }
      if (data && Array.isArray(data.models)) {
        // Fallback for old format
        root.allModels = data.models.slice()
        root.availableModels = Model.modelsForAgent(root.selectedAgent, root.allModels)
        return
      }
    } catch (e) {
      console.warn("quick-ai: failed to parse models cache", e)
    }
    root.availableModels = Model.modelsForAgent(root.selectedAgent, root.allModels)
  }

  Timer {
    id: settingsSaveTimer
    interval: 300
    repeat: false
    onTriggered: root.flushSettings()
  }

  Timer {
    id: startupFallbackTimer
    interval: 1200
    repeat: false
    running: !root.settingsLoaded
    onTriggered: if (!root.settingsLoaded) root.loadSettings("")
  }

  function scheduleSettingsSave() {
    if (!root.settingsLoaded || root.hydrating) return
    settingsSaveTimer.restart()
  }

  onSelectedAgentChanged: {
    // Save previous agent's model before switching
    if (previousAgent !== "" && previousAgent !== selectedAgent) {
      var copyPrev = {}
      for (var k in modelByAgent) copyPrev[k] = modelByAgent[k]
      copyPrev[previousAgent] = selectedModel
      modelByAgent = copyPrev
      scheduleSettingsSave()
    }
    scheduleSettingsSave()
    if (agentDropdown && agentDropdown.value !== selectedAgent) agentDropdown.value = selectedAgent
    var filtered = Model.modelsForAgent(selectedAgent, allModels)
    var needsUpdate = JSON.stringify(filtered) !== JSON.stringify(availableModels)
    if (needsUpdate) availableModels = filtered
    // Restore per-agent model if exists
    var restored = modelByAgent[selectedAgent]
    if (restored !== undefined) {
      var r = String(restored || "")
      if (r !== selectedModel) selectedModel = r
    } else if (selectedModel !== "" && filtered.indexOf(selectedModel) === -1) {
      // No saved model for this agent and current model not in its list -> use default
      selectedModel = ""
    }
    previousAgent = selectedAgent
  }
  onSelectedModelChanged: {
    scheduleSettingsSave()
    if (modelField && modelField.text !== selectedModel) modelField.text = selectedModel
    if (selectedAgent !== "" && modelByAgent[selectedAgent] !== selectedModel) {
      var copy2 = {}
      for (var k in modelByAgent) copy2[k] = modelByAgent[k]
      copy2[selectedAgent] = selectedModel
      modelByAgent = copy2
      scheduleSettingsSave()
    }
  }
  onAllModelsChanged: {
    var filtered2 = Model.modelsForAgent(selectedAgent, allModels)
    if (JSON.stringify(filtered2) !== JSON.stringify(availableModels)) {
      availableModels = filtered2
    }
  }
  onKeepHistoryChanged: scheduleSettingsSave()

  function loadSettings(raw) {
    if (root.settingsLoaded) return
    root.hydrating = true
    var hasSettings = false
    if (raw && raw.trim() !== "") {
      try {
        var data = JSON.parse(raw)
        hasSettings = true
        if (typeof data.agent === "string" && Model.isValidAgent(data.agent)) root.selectedAgent = data.agent
        // Per-agent model map (new) or legacy single model
        if (data.modelByAgent && typeof data.modelByAgent === "object" && !Array.isArray(data.modelByAgent)) {
          var m = {}
          for (var k in data.modelByAgent) {
            if (Model.isValidAgent(k)) m[k] = Model.normalizeModel(data.modelByAgent[k])
          }
          root.modelByAgent = m
          if (m[root.selectedAgent] !== undefined) {
            root.selectedModel = String(m[root.selectedAgent] || "")
          } else if (typeof data.model === "string") {
            root.selectedModel = Model.normalizeModel(data.model)
            m[root.selectedAgent] = root.selectedModel
            root.modelByAgent = m
          }
        } else if (typeof data.model === "string") {
          root.selectedModel = Model.normalizeModel(data.model)
          var mm = {}
          if (root.selectedAgent !== "") mm[root.selectedAgent] = root.selectedModel
          // Keep existing map if any
          for (var kk in root.modelByAgent) if (!mm[kk]) mm[kk] = root.modelByAgent[kk]
          root.modelByAgent = mm
        }
        if (typeof data.keepHistory === "boolean") root.keepHistory = data.keepHistory
        if (Array.isArray(data.history) && data.keepHistory) root.history = data.history.slice(0, 20)
        if (Array.isArray(data.allModels)) {
          root.allModels = data.allModels.slice(0, 300)
        } else if (Array.isArray(data.availableModels)) {
          root.allModels = data.availableModels.slice(0, 300)
        }
      } catch (e) {
        console.warn("quick-ai: failed to parse settings:", e)
      }
    }
    // Compute per-agent model list after agent/allModels are known
    root.availableModels = Model.modelsForAgent(root.selectedAgent, root.allModels)
    // If no agent set, try omarchy default; otherwise ensure a sensible default
    if (root.selectedAgent === "" || !Model.isValidAgent(root.selectedAgent)) {
      if (!hasSettings) defaultAgentProc.running = true
      else if (root.selectedAgent === "") root.selectedAgent = "opencode"
    }
    root.previousAgent = root.selectedAgent
    root.hydrating = false
    root.settingsLoaded = true
    if (!hasSettings && root.selectedAgent === "") {
      defaultAgentProc.running = true
    }
    // Always refresh models list after load (throttled)
    Qt.callLater(function() { if (!modelsProc.running) modelsProc.running = true })
  }

  function flushSettings() {
    if (!root.settingsLoaded || root.hydrating) return
    try {
      // Ensure current agent's model is in the map before saving
      var mapCopy = {}
      for (var k in modelByAgent) mapCopy[k] = modelByAgent[k]
      if (selectedAgent !== "") mapCopy[selectedAgent] = selectedModel
      var payload = {
        agent: root.selectedAgent,
        model: root.selectedModel,
        modelByAgent: mapCopy,
        keepHistory: root.keepHistory,
        history: root.keepHistory ? root.history : [],
        allModels: root.allModels,
        availableModels: root.availableModels
      }
      settingsFile.setText(JSON.stringify(payload, null, 2) + "\n")
    } catch (e) {
      console.warn("quick-ai: failed to flush settings:", e)
    }
  }

  // ---- fetch default omarchy agent if no saved settings ----
  Process {
    id: defaultAgentProc
    command: ["bash", "-c", "cat \"$HOME/.config/omarchy/defaults/agent\" 2>/dev/null | tr -d ' \\n'"]
    stdout: StdioCollector { id: defaultAgentOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        var name = defaultAgentOut.text.trim()
        if (name !== "" && Model.isValidAgent(name) && !root.hydrating && (root.selectedAgent === "opencode" || root.selectedAgent === "")) {
          // Only override default if still at initial value
          root.selectedAgent = name
        } else if (root.selectedAgent === "") {
          root.selectedAgent = "opencode"
        }
      } else if (root.selectedAgent === "") {
        root.selectedAgent = "opencode"
      }
    }
  }

  // ---- models cache builder (dynamic, updates when models added/removed) ----
  Process {
    id: modelsProc
    command: [root.pluginDir + "/bin/build-models-cache", "--refresh"]
    stdout: StdioCollector { id: modelsOut; waitForEnd: true }
    stderr: StdioCollector { id: modelsErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        // FileView will pick up the new cache via watchChanges, but force reload as well
        modelsCacheFile.reload()
      } else {
        console.warn("quick-ai: build-models-cache failed", modelsErr.text)
        root.availableModels = Model.modelsForAgent(root.selectedAgent, root.allModels)
      }
    }
  }

  function refreshModels() {
    if (!modelsProc.running) modelsProc.running = true
  }

  // ---- request handling ----
  function send() {
    var trimmed = String(promptText || "").trim()
    if (trimmed === "") {
      inputField.forceActiveFocus()
      return
    }
    if (askProc.running) {
      // Already busy: treat as cancel + resend queued
      askProc.running = false
      errorText = ""
      responseText = ""
      promptQueue = trimmed
      restartDebounce.restart()
      return
    }
    internalSend(trimmed)
  }

  property string promptQueue: ""

  Timer {
    id: restartDebounce
    interval: 220
    onTriggered: {
      if (promptQueue !== "") {
        var q = promptQueue
        promptQueue = ""
        internalSend(q)
      }
    }
  }

  function internalSend(q) {
    errorText = ""
    responseText = ""
    elapsedText = ""
    requestStartedMs = Date.now()
    elapsedTimer.running = true
    timeoutTimer.restart()

    var agent = String(root.selectedAgent || "opencode")
    var model = String(root.selectedModel || "")

    // Use dispatcher script for uniform handling, fallback to direct opencode run
    var dispatcher = root.pluginDir + "/bin/quick-ask"
    // Ensure we pass prompt as single arg; if prompt contains nulls, we still pass as one element
    askProc.command = [dispatcher, agent, model, q]
    askProc.running = true
    copyFeedback = ""
  }

  function cancel() {
    if (askProc.running) {
      askProc.running = false
      errorText = "Cancelled."
      elapsedTimer.running = false
      timeoutTimer.running = false
    }
  }

  function clear() {
    promptText = ""
    responseText = ""
    errorText = ""
    elapsedText = ""
    elapsedTimer.running = false
    copyFeedback = ""
    if (inputField) inputField.forceActiveFocus()
  }

  function copyResult() {
    var text = String(responseText || "")
    if (text === "") {
      // copy prompt if no response yet
      text = String(promptText || "")
    }
    if (text === "") return
    // Use wl-copy via Process; fallback to xclip
    copyProc.textToCopy = text
    copyProc.command = ["bash", "-c", "printf %s \"$1\" | wl-copy 2>/dev/null || printf %s \"$1\" | xclip -selection clipboard 2>/dev/null || printf %s \"$1\" | xsel --clipboard 2>/dev/null; echo ok", "copy-helper", text]
    copyProc.running = true
  }

  function openInAgent() {
    var q = String(promptText || "").trim()
    if (q === "") return
    // Launch full agent TUI with prompt via omarchy-agent-prompt
    var cmd = ["bash", "-c", "omarchy agent prompt \"$1\" &", "launcher", q]
    launchProc.command = cmd
    launchProc.running = true
    close()
  }

  function appendHistory(prompt, response) {
    if (!keepHistory) return
    var entry = {
      prompt: String(prompt),
      response: String(response),
      agent: String(selectedAgent),
      model: String(effectiveModel),
      ts: Date.now()
    }
    var next = [entry].concat(history)
    // keep last 20
    if (next.length > 20) next = next.slice(0, 20)
    history = next
    scheduleSettingsSave()
  }

  // ---- elapsed timer while busy ----
  Timer {
    id: elapsedTimer
    interval: 500
    repeat: true
    running: false
    onTriggered: {
      if (!askProc.running) { running = false; return }
      var ms = Date.now() - requestStartedMs
      // Timeout after 90s
      if (ms > 90000) {
        askProc.running = false
        errorText = "Request timed out after 90s. Check network / model availability.\n" + Model.authHelpFor(selectedAgent)
        elapsedText = "timeout"
        running = false
        timeoutTimer.running = false
        return
      }
      var s = Math.floor(ms / 1000)
      if (s < 60) elapsedText = s + "s"
      else elapsedText = Math.floor(s/60) + "m " + (s%60) + "s"
    }
  }

  Timer {
    id: timeoutTimer
    interval: 90000
    repeat: false
    onTriggered: {
      if (askProc.running) {
        askProc.running = false
        errorText = "Request timed out after 90s. Check network / model availability.\n" + Model.authHelpFor(selectedAgent)
        elapsedText = "timeout"
        elapsedTimer.running = false
      }
    }
  }

  // ---- processes ----
  Process {
    id: askProc
    stdout: StdioCollector { id: askOut; waitForEnd: true }
    stderr: StdioCollector { id: askErr; waitForEnd: true }
    onExited: function(exitCode) {
      elapsedTimer.running = false
      timeoutTimer.running = false
      if (exitCode === 0) {
        var out = String(askOut.text || "").trim()
        var err = String(askErr.text || "").trim()
        var jsonErr = extractJsonError(out) || extractJsonError(err)
        if (jsonErr !== "") {
          errorText = jsonErr + "\n" + Model.authHelpFor(selectedAgent)
          responseText = ""
        } else {
          // opencode json mode: try to extract text chunks
          var extracted = extractFromJsonLines(out)
          if (extracted !== "") {
            responseText = extracted
          } else if (out !== "") {
            // For non-json agents (claude/codex) the answer is plain text
            responseText = Model.stripThinking(out)
          } else if (err !== "") {
            responseText = ""
            errorText = err.slice(0, 2000)
          } else {
            errorText = "No response (empty output)."
          }

          if (responseText !== "" && errorText === "") {
            appendHistory(promptText, responseText)
            elapsedText = Model.formatDuration(Date.now() - requestStartedMs) + " • " + Model.agentLabel(selectedAgent) + " / " + displayModel
          }
        }
      } else {
        // Don't overwrite a timeout/cancel that was already set (SIGTERM from our own cancel/timeout)
        if (errorText.indexOf("Cancelled") >= 0 || errorText.indexOf("timed out") >= 0 || errorText.indexOf("timeout") >= 0) {
          responseText = ""
        } else {
          var eout = String(askErr.text || "").trim()
          var sout = String(askOut.text || "").trim()
          var combined = (eout !== "" ? eout : sout)
          if (combined === "") {
            if (exitCode === 15) combined = "Cancelled."
            else combined = "Agent exited with code " + exitCode
          }
          // Map common auth failures to help
          if (combined.indexOf("not installed") >= 0 || combined.indexOf("auth") >= 0 || combined.indexOf("credentials") >= 0 || combined.indexOf("401") >= 0) {
            combined += "\n" + Model.authHelpFor(selectedAgent)
          }
          if (combined.indexOf("unknown model") >= 0 || combined.indexOf("model") >= 0 && combined.indexOf("not found") >= 0) {
            combined += "\nAvailable models: run `opencode models` or pick from selector."
          }
          errorText = combined.slice(0, 2500)
          responseText = ""
        }
      }
      // If there was a queued prompt, send it
      if (promptQueue !== "") {
        var q = promptQueue; promptQueue = ""
        Qt.callLater(function(){ internalSend(q) })
      }
    }
  }

  function extractFromJsonLines(raw) {
    var text = String(raw || "").trim()
    if (text === "") return ""
    var lines = text.split("\n")
    var out = ""
    var hadJson = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      // opencode json streaming: each line is a JSON event
      if (line.charAt(0) === "{" ) {
        try {
          var evt = JSON.parse(line)
          var type = String(evt.type || evt.event || "")
          // Try common fields for text delta
          var delta = ""
          if (evt.delta && typeof evt.delta === "string") delta = evt.delta
          else if (evt.text && typeof evt.text === "string") delta = evt.text
          else if (evt.data && typeof evt.data === "string") delta = evt.data
          else if (evt.message && evt.message.content) {
            // content may be string or parts
            if (typeof evt.message.content === "string") delta = evt.message.content
            else if (Array.isArray(evt.message.content)) {
              for (var p = 0; p < evt.message.content.length; p++) {
                var part = evt.message.content[p]
                if (part && typeof part.text === "string") delta += part.text
              }
            }
          } else if (evt.content && typeof evt.content === "string") delta = evt.content

          if (delta !== "") {
            out += delta
            hadJson = true
            continue
          }
          // If json but no text, ignore (status/tool events)
          if (type !== "") hadJson = true
          continue
        } catch (e) {
          // Not json, fall through to plain text
        }
      }
      // If we got here, treat line as plain text (non-json agent)
      if (!hadJson && lines.length === 1) {
        // Single non-json line payload: return raw
        return text
      }
      // For mixed, append raw line if it looks like answer
      // but don't append json noise
      if (line.charAt(0) !== "{") out += (out !== "" ? "\n" : "") + line
    }
    // If we saw json but extracted nothing, fallback to raw sans-json lines
    if (hadJson && out === "") {
      // Try to find last non-json blob
      for (var j = lines.length - 1; j >= 0; j--) {
        var l = lines[j].trim()
        if (l !== "" && l.charAt(0) !== "{") { out = lines.slice(j).join("\n"); break }
      }
    }
    return out
  }

  function extractJsonError(raw) {
    var text = String(raw || "").trim()
    if (text === "") return ""
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      if (line.charAt(0) === "{") {
        try {
          var obj = JSON.parse(line)
          if (obj.type === "error" || obj.error) {
            var msg = ""
            if (obj.error && obj.error.data && obj.error.data.message) msg = String(obj.error.data.message)
            else if (obj.error && obj.error.message) msg = String(obj.error.message)
            else if (obj.message) msg = String(obj.message)
            else if (obj.error) msg = String(obj.error)
            if (msg !== "" && msg !== "[object Object]") return msg
          }
        } catch (e) {}
      }
    }
    if (text.indexOf("Token refresh failed") >= 0 || text.indexOf("401") >= 0) {
      var first = text.split("\n")[0].trim()
      if (first.length > 0 && first.length < 600) return first
    }
    return ""
  }

  Process {
    id: copyProc
    property string textToCopy: ""
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        copyFeedback = "Copied!"
        copyResetTimer.restart()
      } else {
        copyFeedback = "Copy failed"
        copyResetTimer.restart()
      }
    }
  }

  Timer {
    id: copyResetTimer
    interval: 1800
    onTriggered: copyFeedback = ""
  }

  Process {
    id: launchProc
    onExited: function(code) {
      if (code !== 0) console.warn("quick-ai: openInAgent failed code", code)
    }
  }

  // ---- overlay window (layer-shell) ----
  PanelWindow {
    id: window
    visible: root.opened
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-quick-ai"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    focusable: true
    Keys.onEscapePressed: root.close()
    // Ensure closing clears shell registry when dismissed via Escape / scrim
    // (shell.hide is also called by outside click; deduped via isPluginOpen check)
    onVisibleChanged: {
      if (!visible) {
        // Notify shell that we closed ourselves, if the loader still thinks we're open
        if (root.shell && typeof root.shell.hide === "function" && root.shell.isPluginOpen && root.shell.isPluginOpen(root.currentPluginId())) {
          // Use callLater to avoid re-entrancy with shell.openPanelIds mutation
          Qt.callLater(function(){ root.shell.hide(root.currentPluginId()) })
        }
      }
    }

    // Scrim
    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.48)
      opacity: root.opened ? 1.0 : 0
      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      MouseArea {
        anchors.fill: parent
        onClicked: root.close()
      }
    }

    // Centered card
    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(680, parent.width - 48)
      // Dynamic height based on content column, capped to 78% of screen
      height: Math.min(mainColumn.implicitHeight + card.borderTop + card.borderBottom + 32,
                       parent.height * 0.78)
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.opened ? 1.0 : 0
      scale: root.opened ? 1.0 : 0.97
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      // Prevent scrim click when clicking card
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: cardContent
        anchors.fill: parent
        anchors.leftMargin: card.borderLeft + Style.space(16)
        anchors.rightMargin: card.borderRight + Style.space(16)
        anchors.topMargin: card.borderTop + Style.space(16)
        anchors.bottomMargin: card.borderBottom + Style.space(16)

        Column {
          id: mainColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(12)

          // ---- Header ----
          Item {
            width: parent.width
            implicitHeight: Math.max(headerIconBox.implicitHeight, headerTextCol.implicitHeight)

            Rectangle {
              id: headerIconBox
              width: Style.space(38)
              height: Style.space(38)
              radius: Style.space(10)
              color: root.busy ? Util.alpha(Color.accent, 0.16) : Util.alpha(Color.foreground, 0.07)
              border.width: 1
              border.color: root.busy ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.14)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Text {
                anchors.centerIn: parent
                text: root.busy ? "󰔟" : "󰚩"
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
                color: root.busy ? Color.accent : Color.foreground
                RotationAnimation on rotation {
                  from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: root.busy
                }
                transformOrigin: Item.Center
              }
            }

            Column {
              id: headerTextCol
              anchors.left: headerIconBox.right
              anchors.leftMargin: Style.space(12)
              anchors.right: headerActions.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Quick AI"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: (Model.agentLabel(root.selectedAgent) + " · " + displayModel).toUpperCase()
                color: Qt.darker(root.foreground, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Button {
                iconText: root.keepHistory ? "󰆓" : "󰈲"
                tooltipText: root.keepHistory ? "History on — click for anonymous" : "Anonymous — this chat won't be saved"
                foreground: root.keepHistory ? root.foreground : Color.accent
                fontFamily: root.fontFamily
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(6)
                implicitHeight: Style.spacing.controlHeight
                implicitWidth: Style.spacing.controlHeight
                selected: !root.keepHistory
                active: !root.keepHistory
                bordered: !root.keepHistory
                onClicked: root.keepHistory = !root.keepHistory
              }

              Button {
                iconText: "󰒓"
                tooltipText: "Settings"
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(6)
                implicitHeight: Style.spacing.controlHeight
                implicitWidth: Style.spacing.controlHeight
                onClicked: settingsPanel.visible = !settingsPanel.visible
              }

              Button {
                iconText: "󰅖"
                tooltipText: "Close (Esc)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(6)
                implicitHeight: Style.spacing.controlHeight
                implicitWidth: Style.spacing.controlHeight
                onClicked: root.close()
              }
            }
          }

          // ---- Settings strip (collapsible) ----
          Column {
            id: settingsPanel
            visible: false
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            }

            Row {
              width: parent.width
              spacing: Style.space(12)

              Column {
                width: (parent.width - parent.spacing) * 0.46
                spacing: Style.space(4)
                Row {
                  width: parent.width
                  height: Style.space(16)
                  spacing: Style.space(6)
                  Text {
                    text: "AGENT"
                    color: Qt.darker(root.foreground, 1.45)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
                Dropdown {
                  id: agentDropdown
                  width: parent.width
                  label: ""
                  showLabel: false
                  rowHeight: Style.spacing.controlHeight
                  value: root.selectedAgent
                  options: Model.supportedAgents()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(v) {
                    if (v && v !== root.selectedAgent) root.selectedAgent = v
                  }
                }
              }

              Column {
                width: (parent.width - parent.spacing) * 0.54
                spacing: Style.space(4)
                Row {
                  width: parent.width
                  height: Style.space(16)
                  spacing: Style.space(6)
                  Text {
                    text: "MODEL"
                    color: Qt.darker(root.foreground, 1.45)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: root.availableModels.length > 0 ? "(" + root.availableModels.length + " available)" : ""
                    color: Qt.darker(root.foreground, 1.9)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                  }
                  Item { width: 6; height: 1 }
                  Button {
                    iconText: "󰑐"
                    tooltipText: "Refresh models (`opencode models`)"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(6)
                    implicitHeight: Style.space(16)
                    implicitWidth: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.refreshModels()
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.space(6)
                  TextField {
                    id: modelField
                    width: parent.width - modelPicker.width - clearModelBtn.width - parent.spacing*2
                    height: Style.spacing.controlHeight
                    text: root.selectedModel
                    placeholderText: root.effectiveModel !== "" ? root.effectiveModel : "agent default"
                    foreground: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    onTextChanged: {
                      if (root.hydrating) return
                      var norm = Model.normalizeModel(text)
                      if (text === "") norm = ""
                      if (norm !== root.selectedModel) root.selectedModel = norm
                    }
                  }
                  SearchableDropdown {
                    id: modelPicker
                    width: Style.spacing.controlHeight
                    label: ""
                    showLabel: false
                    value: ""
                    options: root.availableModels
                    placeholderText: "Pick"
                    triggerLabel: "▼"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    rowHeight: Style.spacing.controlHeight
                    onChanged: function(v) {
                      if (v && v !== "") {
                        modelField.text = v
                        root.selectedModel = Model.normalizeModel(v)
                      }
                    }
                  }
                  Button {
                    id: clearModelBtn
                    iconText: "󰅖"
                    tooltipText: "Use default"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(6)
                    implicitHeight: Style.spacing.controlHeight
                    implicitWidth: Style.spacing.controlHeight
                    onClicked: { modelField.text = ""; root.selectedModel = "" }
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)
              Text {
                visible: root.copyFeedback !== ""
                text: root.copyFeedback
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Item { width: 8; height: 1; visible: root.copyFeedback !== "" && root.history.length>0 && root.keepHistory }
              Text {
                visible: root.history.length>0 && root.keepHistory
                text: root.history.length + " saved"
                color: Qt.darker(root.foreground, 1.8)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            }
          }

          // ---- Input row ----
          Column {
            width: parent.width
            spacing: Style.space(6)

            Row {
              width: parent.width
              height: Style.spacing.controlHeight
              spacing: Style.space(8)

              TextField {
                id: inputField
                width: parent.width - sendBtn.width - cancelBtn.width - parent.spacing*2
                height: parent.height
                text: root.promptText
                placeholderText: "Ask anything… (Enter to send, Shift+Enter for newline)"
                foreground: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: root.promptText = text
                onAccepted: root.send()
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (event.modifiers & Qt.ShiftModifier) {
                      // allow newline - but TextField is single-line, so ignore and send with newline insertion is not possible
                      // We instead insert "\n" into promptText if needed, but TextField is single line: just send
                      // For multiline, user can paste. For now Shift+Enter also sends.
                      root.send()
                      event.accepted = true
                    } else if (!(event.modifiers & Qt.ControlModifier)) {
                      // Plain Enter sends
                      // onAccepted already handles, but ensure
                    }
                  } else if (event.key === Qt.Key_Escape) {
                    root.close()
                    event.accepted = true
                  } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_K) {
                    root.clear()
                    event.accepted = true
                  }
                }
                // Select all on focus gain for quick replace
                onActiveFocusChanged: if (activeFocus) selectAll()
              }

              Button {
                id: sendBtn
                text: root.busy ? "Sending…" : "Send"
                iconText: root.busy ? "󰔟" : "󰭹"
                iconSpinning: root.busy
                enabled: !root.busy && String(root.promptText).trim() !== ""
                opacity: enabled ? 1.0 : 0.55
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(12)
                verticalPadding: Style.space(6)
                implicitHeight: parent.height
                bordered: true
                selected: !root.busy && String(root.promptText).trim() !== ""
                onClicked: root.send()
                tooltipText: "Send (Enter)"
              }

              Button {
                id: cancelBtn
                visible: root.busy
                iconText: "󰅖"
                tooltipText: "Cancel"
                foreground: root.foreground
                fontFamily: root.fontFamily
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(6)
                implicitHeight: parent.height
                implicitWidth: parent.height
                bordered: true
                onClicked: root.cancel()
              }
            }

            Text {
              visible: root.elapsedText !== ""
              text: root.elapsedText
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              leftPadding: Style.space(2)
            }
          }

          // ---- Response area ----
          BorderSurface {
            visible: root.responseText !== "" || root.errorText !== "" || root.busy
            width: parent.width
            height: {
              if (root.busy && responseText === "" && errorText === "") return Style.space(80)
              var desired = responseFlick.contentHeight + Style.space(24)
              return Math.max(Style.space(120), Math.min(desired, Style.space(380)))
            }
            color: Util.alpha(Color.foreground, 0.04)
            borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12), 1)
            radius: Style.space(8)

            Flickable {
              id: responseFlick
              anchors.fill: parent
              anchors.margins: Style.space(12)
              contentWidth: width
              contentHeight: responseCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              interactive: contentHeight > height

              Column {
                id: responseCol
                width: parent.width
                spacing: Style.space(6)

                Text {
                  visible: root.busy && root.responseText === "" && root.errorText === ""
                  width: parent.width
                  text: "Thinking…"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.italic: true
                }

                Text {
                  visible: root.errorText !== ""
                  width: parent.width
                  text: root.errorText
                  color: Color.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                }

                Text {
                  id: responseTextItem
                  visible: root.responseText !== "" && root.errorText === ""
                  width: parent.width
                  text: root.responseText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                  textFormat: Text.MarkdownText
                  selectByMouse: true
                  onLinkActivated: function(link){ Qt.openUrlExternally(link) }
                }
              }
            }

            // Subtle busy pulse along top edge while waiting
            Rectangle {
              visible: root.busy
              width: parent.width
              height: Style.space(2)
              radius: height/2
              color: Color.accent
              opacity: 0.9
              SequentialAnimation on opacity {
                running: root.busy
                loops: Animation.Infinite
                NumberAnimation { from: 0.35; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.0; to: 0.35; duration: 650; easing.type: Easing.InOutSine }
              }
            }
          }

          // ---- Empty state hint ----
          Text {
            visible: !root.busy && root.responseText === "" && root.errorText === ""
            width: parent.width
            text: "Tip: Enter to send • Esc to close • Super+Shift+K"
            color: Qt.darker(root.foreground, 1.9)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            topPadding: Style.space(6)
          }

          // ---- Footer actions ----
          Row {
            visible: root.responseText !== "" || root.errorText !== ""
            width: parent.width
            spacing: Style.space(6)
            layoutDirection: Qt.RightToLeft

            Button {
              text: "Close"
              iconText: "󰅖"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              bordered: true
              onClicked: root.close()
            }

            Button {
              text: "Open in Agent"
              iconText: "󰆍"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              bordered: true
              enabled: String(root.promptText).trim() !== ""
              onClicked: root.openInAgent()
              tooltipText: "Open full TUI (`omarchy agent prompt`)"
            }

            Button {
              text: root.copyFeedback !== "" ? root.copyFeedback : "Copy"
              iconText: root.copyFeedback !== "" ? "" : "󰆏"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              bordered: true
              enabled: root.responseText !== "" || String(root.promptText).trim() !== ""
              onClicked: root.copyResult()
            }

            Button {
              text: "Clear"
              iconText: "󰃢"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              bordered: true
              onClicked: root.clear()
            }
          }
        }
      }
    }
  }
}
