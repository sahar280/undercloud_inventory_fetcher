#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

cp "$ROOT_DIR/tests/mock_salt.sh" "$TEST_DIR/salt"
chmod +x "$TEST_DIR/salt"
PATH="$TEST_DIR:$PATH" "$ROOT_DIR/undercloud_inventory.sh" --output "$TEST_DIR/inventory.csv"

expected_header='Compute,VLAN IP,BMC IP,Bridge IP,BIOS,BMC Firmware,Serial Number'
[[ $(head -n 1 "$TEST_DIR/inventory.csv") == "$expected_header" ]]
[[ $(wc -l <"$TEST_DIR/inventory.csv") -eq 3 ]]
grep -q '^compute-0,192\.0\.2\.10/24,198\.51\.100\.10,203\.0\.113\.10/24,2\.8\.0,4\.10,SAMPLE001$' "$TEST_DIR/inventory.csv"

printf 'Smoke test passed.\n'
