#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" LOG_FILE="/tmp/nixos-test-disk.log"
export DRY_RUN=1 NON_INTERACTIVE=1
: > "${LOG_FILE}"

source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/dialog.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/disk.sh"

PASS=0 FAIL=0
assert_eq() {
    if [[ "$2" == "$3" ]]; then echo "  PASS: $1"; (( PASS++ )) || true
    else echo "  FAIL: $1 — expected '$2', got '$3'"; (( FAIL++ )) || true; fi
}

echo "=== Test: Auto-partition (ext4) ==="
TARGET_DISK="/dev/sda"; FILESYSTEM="ext4"; SWAP_TYPE="none"; ENCRYPTION="none"
disk_plan_auto
assert_eq "ESP" "/dev/sda1" "${ESP_PARTITION}"
assert_eq "Root" "/dev/sda2" "${ROOT_PARTITION}"

echo "=== Test: Auto-partition (btrfs + swap) ==="
disk_plan_reset; FILESYSTEM="btrfs"; SWAP_TYPE="partition"; SWAP_SIZE_MIB="4096"
disk_plan_auto
assert_eq "ESP" "/dev/sda1" "${ESP_PARTITION}"
assert_eq "Swap" "/dev/sda2" "${SWAP_PARTITION:-}"
assert_eq "Root" "/dev/sda3" "${ROOT_PARTITION}"

echo "=== Test: NVMe naming ==="
disk_plan_reset; TARGET_DISK="/dev/nvme0n1"; FILESYSTEM="ext4"; SWAP_TYPE="none"
disk_plan_auto
assert_eq "NVMe ESP" "/dev/nvme0n1p1" "${ESP_PARTITION}"
assert_eq "NVMe Root" "/dev/nvme0n1p2" "${ROOT_PARTITION}"

echo "=== Test: Dry-run execution ==="
disk_execute_plan
assert_eq "Dry-run OK" "0" "$?"

rm -f "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
