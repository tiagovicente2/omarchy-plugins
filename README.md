# Omarchy Plugins (Deprecated)

This monorepo has been migrated and deprecated. Each plugin is now developed and maintained in its own dedicated, standalone repository:

| Plugin | Repository | Description |
| :--- | :--- | :--- |
| **Battery Protection** | [tiagovicente2/battery-protection](https://github.com/tiagovicente2/battery-protection) | 80% charge threshold protection toggle and power profile management. |
| **Omarchy Glance** | [tiagovicente2/omarchy-glance](https://github.com/tiagovicente2/omarchy-glance) | Centered calendar, Caldir agenda sync with video links, and notification history drawer. |
| **Keyboard RGB** | [tiagovicente2/omarchy-kbd-rgb](https://github.com/tiagovicente2/omarchy-kbd-rgb) | ASUS Vivobook RGB backlight tray controller (HID LampArray via VRGB) with dynamic theme sync. |
| **Omarchy Agents** | [tiagovicente2/omarchy-agents](https://github.com/tiagovicente2/omarchy-agents) | Multi-agent token usage meters, rate limits, and pacing for Claude, Codex, AGY, and Fireworks. |
| **Quick AI** | [tiagovicente2/omarchy-quick-ai](https://github.com/tiagovicente2/omarchy-quick-ai) | Spotlight overlay for quick questions without opening a full TUI. |

---

## Installation & Updates

Plugin installation and synchronization are managed automatically through personal [dotfiles](https://github.com/tiagovicente2/dotfiles) via:

```bash
install-omarchy-plugins
```

To install any plugin individually using Omarchy's native plugin manager:

```bash
omarchy plugin add <repo-url> --enable
```
