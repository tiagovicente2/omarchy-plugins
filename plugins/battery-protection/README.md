# Battery Protection

An Omarchy Shell power-panel replacement with an **80% Battery Protection** toggle, charge threshold controls, and power profile management.

---

## Features

- **80% / 100% Threshold Switch**: Set maximum charge limit to 80% to preserve battery lifespan, or 100% for maximum runtime.
- **Password-Free Switching**: Active local users can toggle limits seamlessly via a secure, restricted Polkit rule.
- **Boot Persistence**: Automatically restores your configured charge limit across reboots and system resume.
- **Native Power Profiles**: Retains stock Omarchy battery statistics, health monitoring, and system power profiles.

---

## Installation

### From Monorepo (Dotfiles)

Managed automatically via the Omarchy package installer:

```bash
install-omarchy-plugins
```

### Manual Installation

```bash
# 1. Link the plugin into Omarchy
ln -sfn ~/Projects/omarchy-plugins/plugins/battery-protection ~/.config/omarchy/plugins/battery-protection

# 2. Run the privileged helper installer (installs systemd service & Polkit rule)
~/.config/omarchy/plugins/battery-protection/install-helper.sh

# 3. Rescan Omarchy plugins
omarchy-shell shell rescanPlugins
```

---

## Updates & Maintenance

When updating the plugin, rerun the helper if the privileged backend changes:

```bash
~/.config/omarchy/plugins/battery-protection/install-helper.sh
```

---

## Uninstallation

```bash
# 1. Reset battery charge limit to 100%
pkexec /usr/local/bin/battery-protection 100

# 2. Disable and remove the service and Polkit rules
sudo systemctl disable --now battery-protection.service
sudo rm -f \
  /usr/local/bin/battery-protection \
  /etc/polkit-1/rules.d/49-battery-protection.rules \
  /etc/systemd/system/battery-protection.service \
  /etc/battery-protection.conf
sudo systemctl daemon-reload

# 3. Remove plugin symlink
rm -f ~/.config/omarchy/plugins/battery-protection
omarchy-shell shell rescanPlugins
```

---

## License

[MIT](LICENSE)
