#!/bin/bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${HOME}/.local/bin"
mkdir -p "$bin_dir"

for bin in "$script_dir"/bin/omarchy-agent-usage-*; do
  [[ -x "$bin" ]] || continue
  target="$bin_dir/$(basename "$bin")"
  ln -sfn "$bin" "$target"
done

echo "Linked Omarchy Agents usage collectors into $bin_dir."
