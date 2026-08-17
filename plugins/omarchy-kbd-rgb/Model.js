var PRESETS = [
  { name: "White", hex: "FFFFFF" },
  { name: "Warm Amber", hex: "FF8800" },
  { name: "Crimson", hex: "FF1744" },
  { name: "Sunset Orange", hex: "FF5500" },
  { name: "Cyber Gold", hex: "FFD600" },
  { name: "Neon Green", hex: "00E676" },
  { name: "Cyan Teal", hex: "00E5FF" },
  { name: "Sky Blue", hex: "00B0FF" },
  { name: "Royal Blue", hex: "2979FF" },
  { name: "Electric Purple", hex: "7C4DFF" },
  { name: "Deep Violet", hex: "AA00FF" },
  { name: "Hot Pink", hex: "FF1493" }
]

function normalizeHex(input) {
  var raw = String(input || "").trim().replace(/^#/, "")
  if (!validHex(raw)) return ""
  return raw.toUpperCase()
}

function validHex(input) {
  var raw = String(input || "").trim().replace(/^#/, "")
  return /^[0-9a-fA-F]{6}$/.test(raw)
}

function colorValue(hex) {
  var normalized = normalizeHex(hex)
  return normalized ? "#" + normalized.toLowerCase() : "#00aa55"
}

function hexLabel(hex) {
  var normalized = normalizeHex(hex)
  return normalized ? "#" + normalized.toUpperCase() : ""
}

function qcolorToHex(col) {
  if (!col) return ""
  if (typeof col === "string") {
    return normalizeHex(col)
  }
  if (typeof col.r === "number" && typeof col.g === "number" && typeof col.b === "number") {
    var r = Math.max(0, Math.min(255, Math.round(col.r * 255))).toString(16)
    var g = Math.max(0, Math.min(255, Math.round(col.g * 255))).toString(16)
    var b = Math.max(0, Math.min(255, Math.round(col.b * 255))).toString(16)
    if (r.length < 2) r = "0" + r
    if (g.length < 2) g = "0" + g
    if (b.length < 2) b = "0" + b
    return (r + g + b).toUpperCase()
  }
  return normalizeHex(String(col))
}

function colorName(hex) {
  var norm = normalizeHex(hex)
  for (var i = 0; i < PRESETS.length; i++) {
    if (PRESETS[i].hex === norm) return PRESETS[i].name
  }
  return norm ? "#" + norm : "Custom"
}

// Calculate luminance to decide checkmark contrast (dark checkmark for light colors, white for dark)
function isLightColor(hex) {
  var norm = normalizeHex(hex)
  if (!norm || norm.length !== 6) return false
  var r = parseInt(norm.substr(0, 2), 16)
  var g = parseInt(norm.substr(2, 2), 16)
  var b = parseInt(norm.substr(4, 2), 16)
  var luminance = (r * 299 + g * 587 + b * 114) / 1000
  return luminance > 150
}

function brightnessIcon(percent, mode) {
  if (mode === "off" || percent <= 0) return "󰃚"
  if (percent <= 33) return "󰃞"
  if (percent <= 66) return "󰃟"
  return "󰃠"
}

function modeIcon(mode, followTheme) {
  if (mode === "off") return "󰅚"
  if (mode === "rainbow") return "󰃮"
  if (mode === "theme" || followTheme) return "󰏘"
  return "󰌌"
}

function parseStatus(raw) {
  var text = String(raw || "")
  var state = { hex: "", brightness: -1, mode: "" }

  var hexMatch = text.match(/(?:^|[^0-9a-fA-F])([0-9a-fA-F]{6})(?:[^0-9a-fA-F]|$)/)
  if (hexMatch) state.hex = hexMatch[1].toUpperCase()

  var briMatch = text.match(/(\d{1,3})\s*%/)
  if (briMatch) state.brightness = Math.max(0, Math.min(100, parseInt(briMatch[1], 10)))

  var lower = text.toLowerCase()
  var modeLine = lower.match(/saved mode:\s*([a-z/ ]+)/)
  var modeVal = modeLine ? modeLine[1] : ""
  if (modeVal.indexOf("rainbow") !== -1 || modeVal.indexOf("autonomous") !== -1) state.mode = "rainbow"
  else if (modeVal.indexOf("off") !== -1 || modeVal.indexOf("disabled") !== -1) state.mode = "off"
  else state.mode = "static"

  return state
}

function hsvToHex(h, s, v) {
  h = ((h % 360) + 360) % 360
  var c = v * s
  var x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  var m = v - c
  var r = 0, g = 0, b = 0
  if (h < 60) { r = c; g = x; b = 0 }
  else if (h < 120) { r = x; g = c; b = 0 }
  else if (h < 180) { r = 0; g = c; b = x }
  else if (h < 240) { r = 0; g = x; b = c }
  else if (h < 300) { r = x; g = 0; b = c }
  else { r = c; g = 0; b = x }
  var rHex = Math.round((r + m) * 255).toString(16)
  var gHex = Math.round((g + m) * 255).toString(16)
  var bHex = Math.round((b + m) * 255).toString(16)
  if (rHex.length < 2) rHex = "0" + rHex
  if (gHex.length < 2) gHex = "0" + gHex
  if (bHex.length < 2) bHex = "0" + bHex
  return (rHex + gHex + bHex).toUpperCase()
}

if (typeof module !== "undefined") {
  module.exports = {
    PRESETS: PRESETS,
    normalizeHex: normalizeHex,
    validHex: validHex,
    colorValue: colorValue,
    hexLabel: hexLabel,
    qcolorToHex: qcolorToHex,
    colorName: colorName,
    isLightColor: isLightColor,
    brightnessIcon: brightnessIcon,
    modeIcon: modeIcon,
    parseStatus: parseStatus,
    hsvToHex: hsvToHex
  }
}