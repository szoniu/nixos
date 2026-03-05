#!/usr/bin/env bash
# tests/test_shrink.sh — Tests for shrink helpers in lib/disk.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" LOG_FILE="/tmp/nixos-test-shrink.log"
export DRY_RUN=1 NON_INTERACTIVE=1
: > "${LOG_FILE}"

source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/disk.sh"

PASS=0 FAIL=0
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then echo "  PASS: ${desc}"; (( PASS++ )) || true
    else echo "  FAIL: ${desc} — expected '${expected}', got '${actual}'"; (( FAIL++ )) || true; fi
}
assert_contains() {
    if [[ "$3" == *"$2"* ]]; then echo "  PASS: $1"; (( PASS++ )) || true
    else echo "  FAIL: $1 — '$2' not found in output"; (( FAIL++ )) || true; fi
}

echo "=== Test 1: disk_can_shrink_fstype ==="

rc=0; disk_can_shrink_fstype "ntfs" || rc=$?
assert_eq "ntfs can shrink" "0" "${rc}"

rc=0; disk_can_shrink_fstype "ext4" || rc=$?
assert_eq "ext4 can shrink" "0" "${rc}"

rc=0; disk_can_shrink_fstype "btrfs" || rc=$?
assert_eq "btrfs can shrink" "0" "${rc}"

rc=0; disk_can_shrink_fstype "xfs" || rc=$?
assert_eq "xfs cannot shrink" "1" "${rc}"

rc=0; disk_can_shrink_fstype "vfat" || rc=$?
assert_eq "vfat cannot shrink" "1" "${rc}"

rc=0; disk_can_shrink_fstype "swap" || rc=$?
assert_eq "swap cannot shrink" "1" "${rc}"

echo ""
echo "=== Test 2: validate_config with valid shrink config ==="

# Set required config
TARGET_DISK="/dev/sda"; FILESYSTEM="ext4"; HOSTNAME="testbox"
TIMEZONE="Europe/Warsaw"; KERNEL_PACKAGE="default"; GPU_VENDOR="intel"; USERNAME="alice"
PARTITION_SCHEME="dual-boot"; SWAP_TYPE="none"; ENCRYPTION="none"
ESP_PARTITION="/dev/sda1"
SHRINK_PARTITION="/dev/sda2"; SHRINK_PARTITION_FSTYPE="ntfs"; SHRINK_NEW_SIZE_MIB="50000"
export TARGET_DISK FILESYSTEM HOSTNAME TIMEZONE KERNEL_PACKAGE GPU_VENDOR USERNAME
export PARTITION_SCHEME SWAP_TYPE ENCRYPTION ESP_PARTITION
export SHRINK_PARTITION SHRINK_PARTITION_FSTYPE SHRINK_NEW_SIZE_MIB

rc=0; validate_config >/dev/null 2>&1 || rc=$?
assert_eq "Valid shrink config passes" "0" "${rc}"

echo ""
echo "=== Test 3: validate_config with invalid SHRINK_PARTITION_FSTYPE ==="

SHRINK_PARTITION_FSTYPE="xfs"
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Invalid shrink fstype fails" "1" "${rc}"
assert_contains "Error mentions SHRINK_PARTITION_FSTYPE" "SHRINK_PARTITION_FSTYPE" "${output}"

echo ""
echo "=== Test 4: validate_config with SHRINK_PARTITION but no SHRINK_NEW_SIZE_MIB ==="

SHRINK_PARTITION_FSTYPE="ntfs"
unset SHRINK_NEW_SIZE_MIB
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Missing shrink size fails" "1" "${rc}"
assert_contains "Error mentions SHRINK_NEW_SIZE_MIB" "SHRINK_NEW_SIZE_MIB" "${output}"

echo ""
echo "=== Test 5: validate_config with SHRINK_NEW_SIZE_MIB=0 ==="

SHRINK_NEW_SIZE_MIB="0"
export SHRINK_NEW_SIZE_MIB
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Zero shrink size fails" "1" "${rc}"

echo ""
echo "=== Test 6: validate_config with each valid shrink fstype ==="

for fstype in ntfs ext4 btrfs; do
    SHRINK_PARTITION_FSTYPE="${fstype}"; SHRINK_NEW_SIZE_MIB="50000"
    export SHRINK_PARTITION_FSTYPE SHRINK_NEW_SIZE_MIB
    rc=0; validate_config >/dev/null 2>&1 || rc=$?
    assert_eq "Shrink fstype ${fstype} passes" "0" "${rc}"
done

echo ""
echo "=== Test 7: No SHRINK_PARTITION -> shrink checks skipped ==="

unset SHRINK_PARTITION SHRINK_PARTITION_FSTYPE SHRINK_NEW_SIZE_MIB
PARTITION_SCHEME="auto"; unset ESP_PARTITION 2>/dev/null || true
export PARTITION_SCHEME
rc=0; validate_config >/dev/null 2>&1 || rc=$?
assert_eq "No shrink -> passes (shrink checks skipped)" "0" "${rc}"

rm -f "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
