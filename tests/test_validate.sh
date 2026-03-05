#!/usr/bin/env bash
# tests/test_validate.sh — Tests for validate_config() in lib/config.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" LOG_FILE="/tmp/nixos-test-validate.log"
export DRY_RUN=1 NON_INTERACTIVE=1
: > "${LOG_FILE}"

source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/config.sh"

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

# Helper: set all required vars to valid defaults
set_valid_config() {
    TARGET_DISK="/dev/sda"
    FILESYSTEM="ext4"
    HOSTNAME="testbox"
    TIMEZONE="Europe/Warsaw"
    KERNEL_PACKAGE="default"
    GPU_VENDOR="nvidia"
    USERNAME="alice"
    PARTITION_SCHEME="auto"
    SWAP_TYPE="none"
    ENCRYPTION="none"
    export TARGET_DISK FILESYSTEM HOSTNAME TIMEZONE KERNEL_PACKAGE GPU_VENDOR USERNAME
    export PARTITION_SCHEME SWAP_TYPE ENCRYPTION
}

# Helper: clear config vars
clear_config() {
    local var
    for var in "${CONFIG_VARS[@]}"; do
        unset "${var}" 2>/dev/null || true
    done
}

echo "=== Test 1: All required vars present -> passes ==="
clear_config
set_valid_config
rc=0; validate_config >/dev/null 2>&1 || rc=$?
assert_eq "Valid config passes" "0" "${rc}"

echo ""
echo "=== Test 2: Missing TARGET_DISK -> fails ==="
clear_config
set_valid_config
unset TARGET_DISK
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Missing TARGET_DISK fails" "1" "${rc}"
assert_contains "Error mentions TARGET_DISK" "TARGET_DISK" "${output}"

echo ""
echo "=== Test 3: Missing HOSTNAME -> fails ==="
clear_config
set_valid_config
unset HOSTNAME
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Missing HOSTNAME fails" "1" "${rc}"
assert_contains "Error mentions HOSTNAME" "HOSTNAME" "${output}"

echo ""
echo "=== Test 4: Invalid FILESYSTEM value -> fails ==="
clear_config
set_valid_config
FILESYSTEM="zfs"
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Invalid FILESYSTEM fails" "1" "${rc}"
assert_contains "Error mentions FILESYSTEM" "FILESYSTEM" "${output}"

echo ""
echo "=== Test 5: Invalid SWAP_TYPE -> fails; zram passes ==="
clear_config
set_valid_config
SWAP_TYPE="invalid"
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Invalid SWAP_TYPE fails" "1" "${rc}"
assert_contains "Error mentions SWAP_TYPE" "SWAP_TYPE" "${output}"

# zram should pass
clear_config
set_valid_config
SWAP_TYPE="zram"
rc=0; validate_config >/dev/null 2>&1 || rc=$?
assert_eq "SWAP_TYPE=zram passes" "0" "${rc}"

echo ""
echo "=== Test 6: Invalid ENCRYPTION -> fails ==="
clear_config
set_valid_config
ENCRYPTION="aes256"
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Invalid ENCRYPTION fails" "1" "${rc}"
assert_contains "Error mentions ENCRYPTION" "ENCRYPTION" "${output}"

echo ""
echo "=== Test 7: Valid hostname -> passes ==="
clear_config
set_valid_config
HOSTNAME="my-nixos-box"
rc=0; validate_config >/dev/null 2>&1 || rc=$?
assert_eq "Valid hostname passes" "0" "${rc}"

echo ""
echo "=== Test 8: Invalid hostname (RFC 1123) -> fails ==="
clear_config
set_valid_config
HOSTNAME="-invalid-start"
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Hostname starting with hyphen fails" "1" "${rc}"
assert_contains "Error mentions HOSTNAME" "HOSTNAME" "${output}"

# Hostname with underscore
clear_config
set_valid_config
HOSTNAME="bad_hostname"
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Hostname with underscore fails" "1" "${rc}"

echo ""
echo "=== Test 9: SWAP_TYPE=partition without SWAP_SIZE_MIB -> fails ==="
clear_config
set_valid_config
SWAP_TYPE="partition"
unset SWAP_SIZE_MIB 2>/dev/null || true
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "SWAP_TYPE=partition without size fails" "1" "${rc}"
assert_contains "Error mentions SWAP_SIZE_MIB" "SWAP_SIZE_MIB" "${output}"

echo ""
echo "=== Test 10: Dual-boot without ESP_PARTITION -> fails ==="
clear_config
set_valid_config
PARTITION_SCHEME="dual-boot"
unset ESP_PARTITION 2>/dev/null || true
rc=0; output=$(validate_config 2>&1) || rc=$?
assert_eq "Dual-boot without ESP fails" "1" "${rc}"
assert_contains "Error mentions ESP_PARTITION" "ESP_PARTITION" "${output}"

rm -f "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
