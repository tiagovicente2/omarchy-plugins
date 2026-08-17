# Omarchy Plugins

A unified collection of personal shell plugins and bar widgets for [Omarchy](https://omarchy.org/).

---

## 🧩 Included Plugins

| Plugin | ID | Kind | Description |
| :--- | :--- | :--- | :--- |
| [**Battery Protection**](plugins/battery-protection) | `battery-protection` | Bar Widget | 80% charge threshold protection toggle and power profile management. |
| [**Omarchy Glance**](plugins/omarchy-glance) | `omarchy-glance` | Bar Widget | Centered calendar, Caldir agenda sync with video links, and notification history drawer. |
| [**Keyboard RGB**](plugins/omarchy-kbd-rgb) | `omarchy-kbd-rgb` | Background Service | ASUS Vivobook RGB backlight tray controller (HID LampArray via VRGB) with dynamic theme sync. |
| [**Omarchy Agents**](plugins/omarchy-agents) | `omarchy-agents` | Bar Widget | Multi-agent token usage meters, rate limits, and pacing for Claude, Codex, AGY, and Fireworks. |

---

## 📦 Installation

### Automated with Dotfiles

Managed automatically via the personal dotfiles package installer:

```bash
install-omarchy-plugins
```

### Manual Installation (All Plugins)

To install or link all plugins into your Omarchy environment at once:

```bash
# 1. Clone the monorepo
git clone https://github.com/tiagovicente2/omarchy-plugins.git ~/Projects/omarchy-plugins

# 2. Symlink each plugin into Omarchy's config
for plugin in ~/Projects/omarchy-plugins/plugins/*/; do
  ln -sfn "$plugin" ~/.config/omarchy/plugins/"$(basename "$plugin")"
done

# 3. Run helper scripts
~/.config/omarchy/plugins/battery-protection/install-helper.sh
~/.config/omarchy/plugins/omarchy-agents/install-helper.sh

# 4. Rescan Omarchy plugins
omarchy-shell shell rescanPlugins
```

---

## 📄 License

All plugins in this repository are distributed under the [MIT License](LICENSE).
