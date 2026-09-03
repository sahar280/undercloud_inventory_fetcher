#!/usr/bin/env bash
set -euo pipefail

TARGET='*compute*'
VLAN_INTERFACE='vlan1'
BRIDGE='br-all'
OUTPUT='inventory.csv'

usage() {
  cat <<'EOF'
Collect compute-node network and hardware inventory through Salt.

Usage:
  ./undercloud_inventory.sh [options]

Options:
  --target PATTERN          Salt target expression (default: *compute*)
  --vlan-interface NAME     VLAN interface to inspect (default: vlan1)
  --bridge NAME             Linux bridge to inspect (default: br-all)
  --output FILE             Destination CSV file (default: inventory.csv)
  -h, --help                Show this help
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --target)
      (($# >= 2)) || die '--target requires a value'
      TARGET=$2
      shift 2
      ;;
    --vlan-interface)
      (($# >= 2)) || die '--vlan-interface requires a value'
      VLAN_INTERFACE=$2
      shift 2
      ;;
    --bridge)
      (($# >= 2)) || die '--bridge requires a value'
      BRIDGE=$2
      shift 2
      ;;
    --output)
      (($# >= 2)) || die '--output requires a value'
      OUTPUT=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

command -v salt >/dev/null 2>&1 || die 'salt is not installed or not in PATH'

[[ $VLAN_INTERFACE =~ ^[[:alnum:]_.:-]+$ ]] || die 'invalid VLAN interface name'
[[ $BRIDGE =~ ^[[:alnum:]_.:-]+$ ]] || die 'invalid bridge name'

WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT

collect_column() {
  local label=$1
  local remote_command=$2
  local raw_file="$WORK_DIR/${label}.raw"

  salt "$TARGET" cmd.run "$remote_command" >"$raw_file"
  awk '
    /^[^[:space:]][^:]*:$/ {
      host = $0
      sub(/:$/, "", host)
      next
    }
    /^[[:space:]]*VALUE=/ {
      value = $0
      sub(/^[[:space:]]*VALUE=/, "", value)
      if (value == "") value = "#N/A"
      print host "," value
    }
  ' "$raw_file" | sort -t',' -k1,1 >"$WORK_DIR/${label}.csv"

  [[ -s "$WORK_DIR/${label}.csv" ]] || die "no values returned for ${label}"
}

collect_column \
  vlan \
  "value=\$(ip -o -4 address show dev '${VLAN_INTERFACE}' 2>/dev/null | awk 'NR == 1 {print \$4}'); printf 'VALUE=%s\\n' \"\${value:-#N/A}\""

collect_column \
  bmc \
  "value=\$(ipmitool lan print 1 2>/dev/null | awk -F: '/^IP Address[[:space:]]*:/ {gsub(/^[[:space:]]+/, \"\", \$2); print \$2}'); printf 'VALUE=%s\\n' \"\${value:-#N/A}\""

collect_column \
  bridge \
  "value=\$(ip -o -4 address show dev '${BRIDGE}' 2>/dev/null | awk 'NR == 1 {print \$4}'); printf 'VALUE=%s\\n' \"\${value:-#N/A}\""

collect_column \
  bios \
  "value=\$(dmidecode -s bios-version 2>/dev/null | head -n 1); printf 'VALUE=%s\\n' \"\${value:-#N/A}\""

collect_column \
  firmware \
  "value=\$(ipmitool mc info 2>/dev/null | awk -F: '/Firmware Revision/ {gsub(/^[[:space:]]+/, \"\", \$2); print \$2}'); printf 'VALUE=%s\\n' \"\${value:-#N/A}\""

collect_column \
  serial \
  "value=\$(dmidecode -s system-serial-number 2>/dev/null | head -n 1); printf 'VALUE=%s\\n' \"\${value:-#N/A}\""

expected_rows=$(wc -l <"$WORK_DIR/vlan.csv")
for column in bmc bridge bios firmware serial; do
  actual_rows=$(wc -l <"$WORK_DIR/${column}.csv")
  [[ $actual_rows -eq $expected_rows ]] || die "row count mismatch for ${column}"
done

awk -F',' '{print $2}' "$WORK_DIR/bmc.csv" >"$WORK_DIR/bmc.values"
awk -F',' '{print $2}' "$WORK_DIR/bridge.csv" >"$WORK_DIR/bridge.values"
awk -F',' '{print $2}' "$WORK_DIR/bios.csv" >"$WORK_DIR/bios.values"
awk -F',' '{print $2}' "$WORK_DIR/firmware.csv" >"$WORK_DIR/firmware.values"
awk -F',' '{print $2}' "$WORK_DIR/serial.csv" >"$WORK_DIR/serial.values"

{
  printf 'Compute,VLAN IP,BMC IP,Bridge IP,BIOS,BMC Firmware,Serial Number\n'
  paste -d ',' \
    "$WORK_DIR/vlan.csv" \
    "$WORK_DIR/bmc.values" \
    "$WORK_DIR/bridge.values" \
    "$WORK_DIR/bios.values" \
    "$WORK_DIR/firmware.values" \
    "$WORK_DIR/serial.values"
} >"$OUTPUT"

printf 'Inventory written to %s\n' "$OUTPUT"
