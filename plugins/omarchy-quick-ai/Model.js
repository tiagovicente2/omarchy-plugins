function supportedAgents() {
  return [
    { value: "opencode", label: "OpenCode", icon: "󰚩" },
    { value: "claude", label: "Claude Code", icon: "󰧑" },
    { value: "codex", label: "Codex", icon: "󰘦" },
    { value: "agy", label: "Antigravity", icon: "󰚩" },
    { value: "copilot", label: "Copilot", icon: "󰚩" },
    { value: "grok", label: "Grok", icon: "󰚩" },
    { value: "pi", label: "Pi", icon: "󰚩" },
    { value: "omp", label: "Oh My Pi", icon: "󰚩" },
    { value: "ori", label: "Ori", icon: "󰚩" },
    { value: "crush", label: "Crush", icon: "󰚩" }
  ]
}

function agentLabel(agent) {
  var list = supportedAgents()
  for (var i = 0; i < list.length; i++) if (list[i].value === agent) return list[i].label
  return agent || "opencode"
}

function isValidAgent(agent) {
  var list = supportedAgents()
  for (var i = 0; i < list.length; i++) if (list[i].value === agent) return true
  return false
}

// model is "provider/model" for opencode, or empty for default.
// We let any non-empty string through but sanitize for shell quoting.
function normalizeModel(model) {
  var s = String(model || "").trim()
  // disallow newlines, control chars, overly long
  if (s.indexOf("\n") >= 0 || s.indexOf("\r") >= 0) return ""
  if (s.length > 120) return s.slice(0, 120)
  return s
}

function defaultModelFor(agent) {
  var s = String(agent || "")
  if (s === "opencode") return "openai/gpt-5.6-sol"
  if (s === "codex") return "gpt-5.6-sol"
  if (s === "claude") return "claude-sonnet-4-5"
  if (s === "agy") return "gemini-3.7-flash"
  return ""
}

function parseModelsOutput(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    // opencode models prints one "provider/model" per line
    if (line.indexOf("/") >= 0) out.push(line)
  }
  return out
}

function providerFromModel(modelId) {
  var idx = String(modelId || "").indexOf("/")
  if (idx < 0) return ""
  return String(modelId).slice(0, idx)
}

function shortModelName(modelId) {
  var idx = String(modelId || "").indexOf("/")
  if (idx < 0) return String(modelId)
  return String(modelId).slice(idx + 1)
}

function modelsForAgent(agent, allModels) {
  var a = String(agent || "").toLowerCase()
  var list = Array.isArray(allModels) ? allModels : []
  // opencode shows the full list (dynamic, from cache)
  if (a === "" || a === "opencode") return list.slice()
  // For other agents, filter the full list by model name containing the agent's family
  var needle = ""
  if (a === "claude") needle = "claude"
  else if (a === "codex") needle = "gpt"
  else if (a === "agy" || a === "gemini" || a === "antigravity") needle = "gemini"
  else if (a === "copilot") needle = "copilot"
  else if (a === "grok") needle = "grok"
  else if (a === "pi") needle = "pi"
  else if (a === "omp") needle = "omp"
  else if (a === "ori") needle = "openrouter"
  else if (a === "crush") needle = "crush"
  if (needle) {
    var filtered = []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i]).toLowerCase().indexOf(needle) >= 0) filtered.push(list[i])
    }
    return filtered
  }
  return []
}

function authHelpFor(agent) {
  if (agent === "claude") return "Run `claude auth login` or `opencode providers` to add Anthropic key."
  if (agent === "codex") return "Run `codex login` or add OpenAI key."
  if (agent === "agy") return "Run `agy` to authenticate Antigravity."
  if (agent === "opencode") return "Run `opencode providers` or check ~/.local/share/opencode/auth.json"
  if (agent === "copilot") return "Run `gh auth login` and ensure Copilot access."
  if (agent === "grok") return "Set XAI key or run `grok auth`."
  return "Check provider credentials."
}

function stripThinking(text) {
  // Some agents wrap thinking in <thinking> blocks; we keep raw for v1
  return String(text || "")
}

function formatDuration(ms) {
  if (!(ms > 0)) return "now"
  var minutes = Math.floor(ms / 60000)
  var hours = Math.floor(minutes / 60)
  var days = Math.floor(hours / 24)
  if (days > 0) return days + "d " + (hours % 24) + "h"
  if (hours > 0) return hours + "h " + (minutes % 60) + "m"
  return Math.max(1, minutes) + "m"
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

if (typeof module !== "undefined") {
  module.exports = {
    supportedAgents: supportedAgents,
    agentLabel: agentLabel,
    isValidAgent: isValidAgent,
    normalizeModel: normalizeModel,
    defaultModelFor: defaultModelFor,
    parseModelsOutput: parseModelsOutput,
    providerFromModel: providerFromModel,
    shortModelName: shortModelName,
    modelsForAgent: modelsForAgent,
    authHelpFor: authHelpFor,
    stripThinking: stripThinking,
    formatDuration: formatDuration,
    clamp: clamp
  }
}
