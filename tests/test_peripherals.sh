#!/usr/bin/env bash
# tests/test_peripherals.sh — Tests for peripheral CONFIG_VARS and _nix_peripherals()
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" LOG_FILE="/tmp/nixos-test-peripherals.log"
export DRY_RUN=1 MOUNTPOINT="/tmp/nixos-test-peripherals-mount-$$"
: > "${LOG_FILE}"

source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/disk.sh"
source "${LIB_DIR}/nixos_config.sh"

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
assert_not_contains() {
    if [[ "$3" != *"$2"* ]]; then echo "  PASS: $1"; (( PASS++ )) || true
    else echo "  FAIL: $1 — '$2' should not be present"; (( FAIL++ )) || true; fi
}

# Base config for generating nix output
set_base_config() {
    HOSTNAME="testbox"; TIMEZONE="Europe/Warsaw"; LOCALE="en_US.UTF-8"; KEYMAP="us"
    GPU_VENDOR="intel"; GPU_DRIVER="modesetting"; GPU_NVIDIA_OPEN="no"
    NIXOS_CHANNEL="nixos-24.11"; USERNAME="alice"; USER_GROUPS="wheel,networkmanager"
    ENABLE_SSH="no"; ENABLE_BLUETOOTH="no"; ENABLE_PRINTING="no"; ENABLE_FLATPAK="no"
    ENCRYPTION="none"; WINDOWS_DETECTED=0; ESP_REUSE="no"; KERNEL_PACKAGE="default"
    DESKTOP_EXTRAS=""; EXTRA_PACKAGES=""
    ENABLE_FINGERPRINT="no"; ENABLE_THUNDERBOLT="no"; ENABLE_SENSORS="no"
    ENABLE_WWAN="no"; ENABLE_ASUSCTL="no"; HYBRID_GPU="no"
}

echo "=== Test 1: ENABLE_FINGERPRINT=yes -> fprintd ==="
set_base_config
ENABLE_FINGERPRINT="yes"
output=$(_write_configuration_nix)
assert_contains "fprintd enabled" "fprintd" "${output}"

echo ""
echo "=== Test 2: ENABLE_THUNDERBOLT=yes -> bolt ==="
set_base_config
ENABLE_THUNDERBOLT="yes"
output=$(_write_configuration_nix)
assert_contains "bolt enabled" "bolt" "${output}"

echo ""
echo "=== Test 3: ENABLE_SENSORS=yes -> iio ==="
set_base_config
ENABLE_SENSORS="yes"
output=$(_write_configuration_nix)
assert_contains "iio enabled" "iio" "${output}"

echo ""
echo "=== Test 4: ENABLE_WWAN=yes -> ModemManager ==="
set_base_config
ENABLE_WWAN="yes"
output=$(_write_configuration_nix)
assert_contains "ModemManager enabled" "enableModemManager" "${output}"

echo ""
echo "=== Test 5: ENABLE_ASUSCTL=yes -> asusd (via _nix_services) ==="
set_base_config
ENABLE_ASUSCTL="yes"
output=$(_write_configuration_nix)
assert_contains "asusd enabled" "asusd" "${output}"

echo ""
echo "=== Test 6: All peripherals disabled -> none present ==="
set_base_config
output=$(_write_configuration_nix)
assert_not_contains "No fprintd" "fprintd" "${output}"
assert_not_contains "No bolt" "bolt" "${output}"
assert_not_contains "No iio" "iio" "${output}"
assert_not_contains "No ModemManager" "enableModemManager" "${output}"
assert_not_contains "No asusd" "asusd" "${output}"

echo ""
echo "=== Test 7: Config round-trip of peripheral vars ==="
FINGERPRINT_DETECTED=1; ENABLE_FINGERPRINT="yes"
THUNDERBOLT_DETECTED=1; ENABLE_THUNDERBOLT="yes"
SENSORS_DETECTED=1; ENABLE_SENSORS="yes"
WWAN_DETECTED=1; ENABLE_WWAN="yes"
BLUETOOTH_DETECTED=1; WEBCAM_DETECTED=1
ASUS_ROG_DETECTED=1; ENABLE_ASUSCTL="yes"
export FINGERPRINT_DETECTED ENABLE_FINGERPRINT THUNDERBOLT_DETECTED ENABLE_THUNDERBOLT
export SENSORS_DETECTED ENABLE_SENSORS WWAN_DETECTED ENABLE_WWAN
export BLUETOOTH_DETECTED WEBCAM_DETECTED ASUS_ROG_DETECTED ENABLE_ASUSCTL

TMPFILE="/tmp/nixos-test-peripherals-$$.conf"
config_save "${TMPFILE}"

# Clear and reload
unset FINGERPRINT_DETECTED ENABLE_FINGERPRINT THUNDERBOLT_DETECTED ENABLE_THUNDERBOLT
unset SENSORS_DETECTED ENABLE_SENSORS WWAN_DETECTED ENABLE_WWAN
unset BLUETOOTH_DETECTED WEBCAM_DETECTED ASUS_ROG_DETECTED ENABLE_ASUSCTL
config_load "${TMPFILE}"

assert_eq "FINGERPRINT_DETECTED round-trip" "1" "${FINGERPRINT_DETECTED:-}"
assert_eq "ENABLE_FINGERPRINT round-trip" "yes" "${ENABLE_FINGERPRINT:-}"
assert_eq "THUNDERBOLT_DETECTED round-trip" "1" "${THUNDERBOLT_DETECTED:-}"
assert_eq "ENABLE_THUNDERBOLT round-trip" "yes" "${ENABLE_THUNDERBOLT:-}"
assert_eq "SENSORS_DETECTED round-trip" "1" "${SENSORS_DETECTED:-}"
assert_eq "ENABLE_SENSORS round-trip" "yes" "${ENABLE_SENSORS:-}"
assert_eq "WWAN_DETECTED round-trip" "1" "${WWAN_DETECTED:-}"
assert_eq "ENABLE_WWAN round-trip" "yes" "${ENABLE_WWAN:-}"
assert_eq "BLUETOOTH_DETECTED round-trip" "1" "${BLUETOOTH_DETECTED:-}"
assert_eq "WEBCAM_DETECTED round-trip" "1" "${WEBCAM_DETECTED:-}"
assert_eq "ASUS_ROG_DETECTED round-trip" "1" "${ASUS_ROG_DETECTED:-}"
assert_eq "ENABLE_ASUSCTL round-trip" "yes" "${ENABLE_ASUSCTL:-}"

rm -f "${TMPFILE}" "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
