# Quick AI — Omarchy Quick Question Overlay

Spotlight-style overlay for fast AI questions. Press a keybind, type a prompt, pick an **agent + model already supported by Omarchy**, get an answer without opening a full TUI.

> **Kind:** `panel` (`keepLoaded: true`) • **IPC:** `omarchy-shell shell toggle omarchy-quick-ai` • **Settings:** `~/.config/omarchy/quick-ai.json`

---

## Features

- Centered overlay (`PanelWindow` + scrim) — not a floating Hyprland window
- One-line prompt input (Enter to send, Esc to close)
- Agent picker: `opencode`, `claude`, `codex`, `agy`, `copilot`, `grok`, `pi`, `omp`, `ori`, `crush` (from `omarchy-default-agent`)
- Model input: `provider/model` (e.g. `openai/gpt-5.6-sol`, `anthropic/claude-opus-4`) — empty = agent default; list via `opencode models`
- Streaming-friendly backend via `bin/quick-ask` dispatcher → `opencode run --format json` or native CLIs
- Copy result (`wl-copy`/`xclip`/`xsel`), Clear, Open in full agent (`omarchy agent prompt`), elapsed timer + error help
- Persists `agent`, `model`, `keepHistory` (+ last 20 Q&A) to `~/.config/omarchy/quick-ai.json`

## Installation

```bash
# inside this monorepo (symlink method):
ln -sfn ~/Projects/omarchy-plugins/plugins/omarchy-quick-ai ~/.config/omarchy/plugins/omarchy-quick-ai
omarchy-shell shell rescanPlugins   # or: qs ipc call shell rescan

# standalone git repo (after splitting):
# omarchy plugin add https://github.com/tiagovicente2/omarchy-quick-ai.git --enable
```

## Keybind (recommended)

> `SUPER+K` / `SUPER+ALT+K` / `SUPER+CTRL+K` are taken (Keybindings, Tmux, Herdr).

Add to your Hyprland config (e.g. `~/.config/hypr/bindings.lua` — personal overrides, not `/usr/share/omarchy/...`):

```lua
-- Lua style (omarchy) — suggested: SUPER+SHIFT+K (mnemonic Quick)
o.bind("SUPER + SHIFT + K", "Quick AI", "omarchy-shell shell toggle omarchy-quick-ai")

-- Alternatives if SHIFT+K conflicts with your layout:
-- o.bind("SUPER + ALT + I", "Quick AI", "omarchy-shell shell toggle omarchy-quick-ai")  -- I → AI
-- o.bind("SUPER + CTRL + SHIFT + K", "Quick AI", "omarchy-shell shell toggle omarchy-quick-ai")

-- Or plain Hyprland conf:
-- bind = SUPER SHIFT, K, exec, omarchy-shell shell toggle omarchy-quick-ai
```

Also callable with payload (pre-fill prompt):

```bash
omarchy-shell shell summon omarchy-quick-ai '{"prompt":"explain this error: ..."}'
```

## Configuration

Settings live at `~/.config/omarchy/quick-ai.json` (auto-created):

```json
{
  "agent": "opencode",
  "model": "openai/gpt-5.6-sol",
  "keepHistory": false,
  "history": [],
  "availableModels": ["openai/gpt-5.6-sol", "anthropic/claude-opus-4.7", "opencode/mimo-v2.5-free"]
}
```

- **Agent** — enum from `omarchy-default-agent` (`omarchy default agent <name>`). Plugin reads `~/.config/omarchy/defaults/agent` as fallback default if no settings yet.
- **Model** — free-form `provider/model` for `opencode`. Empty = agent default (see `Model.js:defaultModelFor`). Refresh list via ↻ button (`opencode models`).
- **keepHistory** — when on, saves last 20 Q&A to disk; off = ephemeral.

To change via CLI:

```bash
# edit file directly, then rescan is not needed — FileView reloads on next open
jq '.model="anthropic/claude-sonnet-4-5"' ~/.config/omarchy/quick-ai.json > /tmp/q && mv /tmp/q ~/.config/omarchy/quick-ai.json
```

## How it works

```
Panel.qml ──(Process)──▶ bin/quick-ask <agent> <model> <prompt>
                               │
                               ├─ opencode? ─▶ opencode run --agent build --model <provider/model> --format json "prompt"
                               ├─ claude ─────▶ claude --permission-mode auto -- "prompt"
                               ├─ codex ──────▶ codex --approve-for-me -- "prompt"
                               ├─ agy ────────▶ agy --prompt-interactive "prompt"
                               └─ other ──────▶ omarchy agent fallback / native binary
```

`Panel.qml` uses `StdioCollector` (blocking, simple) and extracts JSON streaming fields (`delta`/`text`/`content`) if present, else falls back to plain stdout. Errors are surfaced with auth hints (`Model.js:authHelpFor`).

## Layout

```
┌─────────────────────────────────────────────┐
│ ▣ Quick AI                        [⚙][×]   │  header (icon + agent/model)
│─────────────────────────────────────────────│  settings (collapsible: Agent dropdown + Model field)
│ [Ask anything…                ] [Send][×]  │  input row
│ 12s • opencode / openai/gpt-5.6-sol         │  elapsed
│ ┌─────────────────────────────────────────┐ │
│ │ Thinking… / response text / error       │ │  response (Flickable, selectable Copy)
│ │                                         │ │
│ └─────────────────────────────────────────┘ │
│ Tip: Enter to send • Esc to close • Super+Shift+K │ hint
│              [Clear][Copy][Open in Agent][Close] │ footer
└─────────────────────────────────────────────┘
```

Colors/spacing/radius from `qs.Commons.Style` + `Color.popups.*`, `BorderSurface` for card, matches `omarchy-kbd-rgb` overlay patterns.

## Edge cases handled

- **Empty prompt** — Send disabled, focus stays
- **Agent not installed** — dispatcher exits 3, panel shows `… not installed. omarchy default agent <name>` + auth hint
- **Invalid model** — `opencode run` error → “unknown model” + suggest `opencode models`
- **No credentials** — detects `401`/`auth`/`credentials` in stderr, appends `authHelpFor(agent)`
- **Offline / rate limited** — shows stderr + exit code; future: read `~/.local/state/omarchy/agents/usage/*.json` limits to warn when `percent≈1.0`
- **Cancel** — while `busy`, Send becomes Cancel; second send queues prompt and restarts after 220ms
- **Clipboard** — tries `wl-copy` → `xclip` → `xsel`, shows “Copied!” feedback
- **Focus theft** — `WlrLayershell.keyboardFocus: Exclusive` while open, `Esc`/scrim click closes and calls `shell.hide(...)`
- **History privacy** — only written when `keepHistory:true`, file `0600`, no prompt logged otherwise

## Development

```bash
omarchy plugin validate ./plugins/omarchy-quick-ai
qmllint plugins/omarchy-quick-ai/Panel.qml
node -e "require('./plugins/omarchy-quick-ai/Model.js')"
# live reload after edit:
omarchy-shell shell rescanPlugins
omarchy-shell shell toggle omarchy-quick-ai
```

## TODO / Next

- Streaming `SplitParser` incremental update (replace `StdioCollector` waitForEnd)
- Markdown rendering (selectable `TextEdit` with links)
- Model autocomplete dropdown (from `availableModels` filtered)
- History drawer UI when `keepHistory:true`
- Keybind docs in user Hyprland file auto-suggestion
