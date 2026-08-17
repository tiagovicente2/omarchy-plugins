# Battery Protection

An Omarchy Shell power-panel replacement with a **Battery protection** toggle.
It keeps the stock battery statistics and power profiles while adding:

- an 80% charge limit when battery protection is enabled;
- a 100% charge limit when battery protection is disabled;
- privileged writes through a small, root-owned helper;
- password-free changes for the active local user through a restricted Polkit rule;
- automatic restoration of the selected limit after reboot.

The plugin requires a laptop that exposes
`/sys/class/power_supply/BAT*/charge_control_end_threshold`.

## Install

```bash
omarchy plugin add https://github.com/tiagovicente2/battery-protection.git --enable
~/.config/omarchy/plugins/battery-protection/install-helper.sh
```

The second command asks for your password once to install the restricted helper,
Polkit rule, and boot restore service. Changing the limit from the power menu does
not ask for a password. Restart the shell if the panel does not reload:

```bash
omarchy restart shell
```

## Update

Plugin updates do not automatically replace the root-owned helper. Update both
parts together:

```bash
omarchy plugin update battery-protection
~/.config/omarchy/plugins/battery-protection/install-helper.sh
```

If the helper is missing or uses an incompatible protocol, the panel disables
the toggle and asks you to rerun `install-helper.sh`.

## Uninstall

```bash
pkexec /usr/local/bin/battery-protection 100
omarchy plugin remove battery-protection
sudo systemctl disable --now battery-protection.service
sudo rm /usr/local/bin/battery-protection \
  /etc/polkit-1/rules.d/49-battery-protection.rules \
  /etc/systemd/system/battery-protection.service \
  /etc/battery-protection.conf
sudo systemctl daemon-reload
```

## Development

```bash
omarchy plugin validate .
bash -n install-helper.sh scripts/battery-protection
tests/battery-protection-test.sh
```

`Panel.qml` and `Model.js` are derived from Omarchy's MIT-licensed
`omarchy.power` plugin.

## License

MIT
