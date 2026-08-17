#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
helper_source="$repo_dir/scripts/battery-protection"
rule_source="$repo_dir/scripts/49-battery-protection.rules"
service_source="$repo_dir/scripts/battery-protection.service"

for source_file in "$helper_source" "$rule_source" "$service_source"; do
  [[ -r $source_file ]] || {
    echo "Missing install file: $source_file" >&2
    exit 1
  }
done

sudo install -o root -g root -m 755 \
  "$helper_source" /usr/local/bin/battery-protection
sudo install -o root -g root -m 644 \
  "$rule_source" /etc/polkit-1/rules.d/49-battery-protection.rules
sudo install -o root -g root -m 644 \
  "$service_source" /etc/systemd/system/battery-protection.service

# Migrate installations from the former omarchy-power-limit project name.
sudo systemctl disable --now omarchy-power-limit.service 2>/dev/null || true
sudo sh -c '
  if [ -f /etc/omarchy-power-limit.conf ] && [ ! -e /etc/battery-protection.conf ]; then
    mv /etc/omarchy-power-limit.conf /etc/battery-protection.conf
  fi
  if [ -e /etc/battery-protection.conf ]; then
    chown root:root /etc/battery-protection.conf
    chmod 0644 /etc/battery-protection.conf
  fi
'
sudo rm -f \
  /usr/local/bin/battery-charge-limit \
  /etc/polkit-1/rules.d/49-omarchy-power-limit.rules \
  /etc/systemd/system/omarchy-power-limit.service

sudo systemctl daemon-reload
sudo systemctl enable --now battery-protection.service

echo "Installed Battery Protection's helper, Polkit rule, and boot restore service."
