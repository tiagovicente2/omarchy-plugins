# Omarchy Plugins

Collection of personal and community shell plugins and bar widgets for [Omarchy](https://omarchy.org/).

## Included Plugins

| Plugin | ID | Type | Description |
| :--- | :--- | :--- | :--- |
| [**Battery Protection**](plugins/battery-protection) | `battery-protection` | Bar Widget | Omarchy power panel with an 80% battery protection threshold toggle and power profile switching. |
| [**Omarchy Glance**](plugins/omarchy-glance) | `omarchy-glance` | Bar Widget | Centered calendar, Caldir agenda, and interactive notification history panel. |
| [**Keyboard RGB**](plugins/omarchy-kbd-rgb) | `omarchy-kbd-rgb` | Background Service | ASUS Vivobook keyboard RGB control from a system tray icon via HID LampArray (VRGB), with boot persistence. |
| [**Omarchy Agents**](plugins/omarchy-agents) | `omarchy-agents` | Bar Widget | Rate-limit meters, pacing, and model usage breakdowns for Claude Code, Codex, AGY, and Fireworks. |

## Installation

### With Dotfiles

Managed automatically via the Omarchy package installer:

```bash
install-omarchy-plugins
```

### Manual Symlink / Development

To link all plugins directly into your active Omarchy environment:

```bash
for plugin in plugins/*/; do
  ln -snf "$(pwd)/${plugin%/}" ~/.config/omarchy/plugins/"$(basename "$plugin")"
done
omarchy-shell shell rescanPlugins
```

## License

MIT License. See individual plugin directories for details.
