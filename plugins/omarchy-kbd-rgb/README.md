# Keyboard RGB

RGB keyboard backlight control service and tray control panel for **ASUS Vivobook** laptops on [Omarchy](https://omarchy.org/) (HID LampArray via [VRGB](https://github.com/vrgb-dev/vrgb)).

---

## ✨ Features

- **🎨 Modern Control Panel**: 12 curated color presets, custom hex input with validation, and smooth brightness slider.
- **󰏘 Dynamic Theme Tracking**: Real-time sync with your active Omarchy theme, with an instant toggle between Theme Accent and Bar Text color.
- **🌈 Smooth Rainbow Spectrum**: Animated color cycling mode with fluid transitions.
- **⌨️ Dynamic Tray Icon**: 22×22 StatusNotifierItem icon rendered via Cairo matching current color and backlight state.
- **⚡ Hardware Hotkey Sync**: Bidirectional sync with laptop brightness hotkeys (<kbd>Fn</kbd>+<kbd>F7</kbd> / <kbd>Fn</kbd>+<kbd>F4</kbd>).
- **🔋 Battery Saver & Night Light**: Automatically caps brightness to 33% on low battery and applies zero-blue amber tint during Night Light.
- **💾 Boot Persistence**: Automatically restores your configured colors and mode across reboots.

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
ln -sfn ~/Projects/omarchy-plugins/plugins/omarchy-kbd-rgb ~/.config/omarchy/plugins/omarchy-kbd-rgb

# 2. Rescan Omarchy plugins
omarchy-shell shell rescanPlugins
```

---

## ⚙️ Prerequisites

Ensure **VRGB** and the ASUS WMI kernel module are enabled:

```bash
# 1. Install VRGB
paru -S vrgb 2>/dev/null || {
  git clone https://github.com/vrgb-dev/vrgb /tmp/vrgb
  cd /tmp/vrgb && sudo ./install.sh
}

# 2. Reload udev rules & load kernel module
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo modprobe asus-nb-wmi
echo asus-nb-wmi | sudo tee /etc/modules-load.d/asus-nb-wmi.conf
```

---

## ⌨️ CLI & Keybindings

Control `omarchy-kbd-rgb` from terminal scripts or Hyprland keybindings:

```bash
omarchy-shell omarchy-kbd-rgb toggle                   # Open / close control panel
omarchy-shell omarchy-kbd-rgb togglePower              # Toggle backlight on/off
omarchy-shell omarchy-kbd-rgb stepBrightness 10        # Increase brightness by 10%
omarchy-shell omarchy-kbd-rgb stepBrightness -10       # Decrease brightness by 10%
omarchy-shell omarchy-kbd-rgb nextPreset               # Cycle to next color preset
omarchy-shell omarchy-kbd-rgb setMode theme            # Switch to theme tracking mode
omarchy-shell omarchy-kbd-rgb setMode rainbow          # Start rainbow spectrum cycle
omarchy-shell omarchy-kbd-rgb setHex 00E5FF            # Set custom hex color
omarchy-shell omarchy-kbd-rgb status                   # Output JSON status
```

---

## 📄 License

[MIT](LICENSE)