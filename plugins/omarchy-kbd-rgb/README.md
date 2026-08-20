# omarchy-kbd-rgb

RGB keyboard backlight control service and control panel for **ASUS Vivobook** laptops on [Omarchy](https://omarchy.org/) (HID LampArray via [VRGB](https://github.com/vrgb-dev/vrgb)).

---

## ✨ Features

- **🎨 Modern Control Panel**: 12 curated presets with dynamic contrast checkmarks, custom hex input with validation, and smooth brightness controls.
- **󰏘 Theme Mode (Accent vs Bar Text)**: Automatically tracks your active Omarchy theme in real time, with an instant toggle between Theme Accent (`#7D82D9`) and Bar Text / Icon color (`#FFCEAD`).
- **🌈 Smooth Rainbow Spectrum Cycle**: Animated RGB color cycling that smoothly transitions your keyboard backlight through the full color spectrum.
- **⌨️ Vector Tray Icon**: Dynamic 22×22 StatusNotifierItem keyboard icon rendered in Cairo, illuminated with your active color, dynamic rainbow wave, or off state.
- **⚡ Hardware Hotkey Sync**: Full bidirectional sync with laptop Fn brightness hotkeys (<kbd>Fn</kbd>+<kbd>F7</kbd> / <kbd>Fn</kbd>+<kbd>F4</kbd>) via UPower DBus.
- **🔋 Battery Saver**: Turns off keyboard backlight after 15s of idle to save power, and caps brightness to 33% when battery level is low ($\le 25\%$).
- **🌙 Night Light Warm Tint**: Automatically transitions to zero-blue warm amber (`#FF7700`) during Night Light to reduce eye strain, reacting in real time to toggle events.
- **💾 Boot & Theme Persistence**: Automatically persists your color, theme target, and brightness preferences across reboots and shell reloads.

---

## 🚀 Quick Install

Install in one command using the Omarchy CLI:

```bash
omarchy plugin add https://github.com/tiagovicente2/omarchy-kbd-rgb --enable
```

*(To update in the future: `omarchy plugin update omarchy-kbd-rgb`)*.

---

## ⚙️ Prerequisites

Ensure **VRGB** and the ASUS WMI kernel module are installed:

```bash
# 1. Install VRGB (Arch / Omarchy)
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

## ⌨️ Shortcuts & CLI

Control `omarchy-kbd-rgb` from terminal scripts or Hyprland keybindings:

```bash
omarchy-shell omarchy-kbd-rgb toggle                   # Open / close control panel
omarchy-shell omarchy-kbd-rgb togglePower              # Toggle backlight on/off
omarchy-shell omarchy-kbd-rgb stepBrightness 10        # Increase brightness by 10%
omarchy-shell omarchy-kbd-rgb stepBrightness -10       # Decrease brightness by 10%
omarchy-shell omarchy-kbd-rgb nextPreset               # Cycle to next color preset
omarchy-shell omarchy-kbd-rgb setMode theme            # Switch to theme tracking mode
omarchy-shell omarchy-kbd-rgb setThemeTarget accent    # Track Theme Accent color
omarchy-shell omarchy-kbd-rgb setThemeTarget foreground# Track Theme Bar Text color
omarchy-shell omarchy-kbd-rgb setMode rainbow          # Start animated rainbow spectrum cycle
omarchy-shell omarchy-kbd-rgb setHex 00E5FF            # Set custom hex color
omarchy-shell omarchy-kbd-rgb setBrightness 80         # Set brightness percentage
omarchy-shell omarchy-kbd-rgb status                   # Output JSON status
```

---

## 📖 Architecture & Deep Dive

For hardware protocol details (HID LampArray vs WMI), UPower DBus synchronization, and Cairo rendering internals, see [**How It Works (Architecture & Deep Dive)**](docs/HOW_IT_WORKS.md).

---

## 📄 License

[MIT](LICENSE)