# Omarchy Agents

Multi-agent AI coding subscription monitor, token usage fuel gauges, and pacing panel for [Omarchy](https://omarchy.org/).

---

## ✨ Features

- **🤖 Multi-Agent Support**: Native rate-limit and token metrics for **Claude Code**, **OpenAI Codex**, **Antigravity (AGY)**, and **Fireworks**.
- **⛽ Fuel-Gauge Meters**: Real-time visualization of current session limits, 7-day allowances, and credit balances.
- **📊 Usage Breakdown**: Daily token bar charts and model breakdown with input/output/cache splits.
- **🔄 Synced Aggregation**: Optional cross-device usage aggregation across laptop and desktop workstations.
- **👻 Self-Hiding**: Hides automatically from the bar if no AI subscriptions or usage are detected on the system.

---

## 📦 Installation

### From Monorepo (Dotfiles)

Managed automatically via the Omarchy package installer:

```bash
install-omarchy-plugins
```

### Manual Installation

```bash
# 1. Link the plugin into Omarchy
ln -sfn ~/Projects/omarchy-plugins/plugins/omarchy-agents ~/.config/omarchy/plugins/omarchy-agents

# 2. Run the helper to link CLI collectors (e.g. omarchy-agent-usage-agy)
~/.config/omarchy/plugins/omarchy-agents/install-helper.sh

# 3. Rescan Omarchy plugins
omarchy-shell shell rescanPlugins
```

---

## ⚙️ Configuration

Configure the widget in `~/.config/omarchy/shell.json` or via the Omarchy CLI:

```bash
# Change refresh interval (seconds)
omarchy bar set omarchy-agents refreshIntervalSec 300 --json

# Enable cross-machine sync
omarchy bar set omarchy-agents syncMode "On"
omarchy bar set omarchy-agents syncDir "~/Sync/agent-usage"
```

---

## ⌨️ Interactions & IPC

- **Left-Click**: Open agent details panel.
- **Middle-Click**: Switch to the next enabled agent subscription.
- **Right-Click**: Launch configured default agent terminal.
- **IPC Commands**:
  ```bash
  omarchy-shell omarchy-agents toggle      # Open/close panel
  omarchy-shell omarchy-agents refresh     # Force usage update
  omarchy-shell omarchy-agents next        # Cycle active agent
  ```

---

## 📄 License

[MIT](LICENSE)
