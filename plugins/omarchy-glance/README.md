# Omarchy Glance

Centered calendar, Caldir agenda, and interactive notification history panel for the [Omarchy](https://omarchy.org/) top bar.

---

## ✨ Features

- **📅 Centered Bar Widget**: Clean time and date display designed to act as the primary center anchor on your bar.
- **🗓️ Caldir Agenda Sync**: Automatically discovers, expands, and displays upcoming calendar events with direct **Join** links (Meet, Teams, Zoom).
- **🔔 Notification History**: Recent notifications drawer with quick actions and one-click **Dismiss all**.
- **⏳ Year & Life Progress**: Optional visual progress bars tracking the current year and milestones.

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
ln -sfn ~/Projects/omarchy-plugins/plugins/omarchy-glance ~/.config/omarchy/plugins/omarchy-glance

# 2. Set Glance as your bar center anchor
~/.config/omarchy/plugins/omarchy-glance/setup/center-anchor

# 3. Rescan Omarchy plugins
omarchy-shell shell rescanPlugins
```

---

## ⚙️ Prerequisites & Calendar Setup

Glance synchronizes events via the standard Caldir RFC5545 format:

1. **Install Caldir CLI**:
   ```bash
   cargo install --git https://github.com/t4t5/caldir.git \
     caldir-cli --bin caldir --root "$HOME/.local" --force
   ```
2. **Connect Providers**: Configure your calendar in [renCal](https://github.com/t4t5/rencal). Glance automatically reads the resulting Caldir files.

---

## ⌨️ Keybindings

To toggle Glance with <kbd>SUPER</kbd> + <kbd>V</kbd>, add to `~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + V")
o.bind("SUPER + V", "Toggle calendar", "omarchy-shell shell toggle omarchy.clock")
```

Then reload Hyprland:

```bash
hyprctl reload
```

---

## 📄 License

[MIT](LICENSE)
