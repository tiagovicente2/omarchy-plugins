#!/bin/bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$repo_dir/scripts/battery-protection"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ $actual == "$expected" ]] || fail "$label: expected '$expected', got '$actual'"
}

reset_fixture() {
  rm -rf "$test_dir/power"
  mkdir -p "$test_dir/power"
  rm -f "$test_dir/state" "$test_dir/lock"
}

add_battery() {
  local name="$1"
  local threshold="${2:-}"
  local state="${3:-Not charging}"

  mkdir -p "$test_dir/power/$name"
  if [[ -n $threshold ]]; then
    printf '%s' "$threshold" > "$test_dir/power/$name/charge_control_end_threshold"
  fi
  printf '%s\n' "$state" > "$test_dir/power/$name/status"
}

run_helper() {
  BATTERY_PROTECTION_POWER_SUPPLY_PATH="$test_dir/power" \
    BATTERY_PROTECTION_STATE_FILE="$test_dir/state" \
    BATTERY_PROTECTION_LOCK_FILE="$test_dir/lock" \
    "$helper" "$@"
}

reset_fixture
add_battery BAT0 100
assert_equal "3" "$(run_helper version)" "protocol version"
assert_equal $'version\t3\nthreshold\t100\nstate\tNot charging' "$(run_helper status)" "single-battery status"
[[ ! -e $test_dir/lock ]] || fail "first unlocked status read created the privileged lock"

(umask 000; run_helper 80)
[[ -r $test_dir/lock ]] || fail "first write did not create a readable lock"
assert_equal "80" "$(<"$test_dir/power/BAT0/charge_control_end_threshold")" "enabled threshold"
assert_equal "80" "$(<"$test_dir/state")" "persisted threshold"
assert_equal "644" "$(stat -c '%a' "$test_dir/state")" "state permissions"

reset_fixture
add_battery BAT0 100
if error=$(
  BATTERY_PROTECTION_POWER_SUPPLY_PATH="$test_dir/power" \
    BATTERY_PROTECTION_STATE_FILE="$test_dir/missing/state" \
    BATTERY_PROTECTION_LOCK_FILE="$test_dir/lock" \
    "$helper" 80 2>&1
); then
  fail "unpersisted threshold change was accepted"
fi
[[ $error == *"restored the previous threshold"* ]] || fail "persistence rollback error was not specific"
assert_equal "100" "$(<"$test_dir/power/BAT0/charge_control_end_threshold")" "persistence failure rollback"

reset_fixture
add_battery BAT0 100
add_battery BAT1 100
run_helper 80
assert_equal "80" "$(<"$test_dir/power/BAT0/charge_control_end_threshold")" "BAT0 threshold"
assert_equal "80" "$(<"$test_dir/power/BAT1/charge_control_end_threshold")" "BAT1 threshold"
assert_equal $'version\t3\nthreshold\t80\nstate\tNot charging' "$(run_helper status)" "multi-battery status"

reset_fixture
add_battery BAT0 80 Full
add_battery BAT1 80 Charging
assert_equal $'version\t3\nthreshold\t80\nstate\tCharging' "$(run_helper status)" "charging multi-battery state"

reset_fixture
add_battery BAT0 80 Charging
add_battery BAT1 80 Discharging
assert_equal $'version\t3\nthreshold\t80\nstate\tUnknown' "$(run_helper status)" "conflicting multi-battery state"

reset_fixture
add_battery BAT0 100
add_battery BAT1
if error=$(run_helper 80 2>&1); then
  fail "unsupported BAT1 was accepted"
fi
[[ $error == *"BAT1 does not expose"* ]] || fail "unsupported BAT1 error was not specific"
assert_equal "100" "$(<"$test_dir/power/BAT0/charge_control_end_threshold")" "preflight preserved BAT0"

reset_fixture
add_battery BAT0 80
add_battery BAT1 100
if error=$(run_helper status 2>&1); then
  fail "mixed thresholds were reported as consistent"
fi
[[ $error == *"do not match"* ]] || fail "mixed-threshold error was not specific"

reset_fixture
add_battery BAT0 100
printf '80\n' > "$test_dir/state"
run_helper restore
assert_equal "80" "$(<"$test_dir/power/BAT0/charge_control_end_threshold")" "restored threshold"

printf '75\n' > "$test_dir/state"
if run_helper restore >/dev/null 2>&1; then
  fail "invalid persisted threshold was restored"
fi
assert_equal "80" "$(<"$test_dir/power/BAT0/charge_control_end_threshold")" "invalid restore preserved threshold"

echo "PASS: battery-protection helper"
