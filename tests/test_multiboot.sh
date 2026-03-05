#!/usr/bin/env bash
# tests/test_multiboot.sh — Tests for serialize/deserialize_detected_oses in lib/hardware.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" LOG_FILE="/tmp/nixos-test-multiboot.log"
export DRY_RUN=1 NON_INTERACTIVE=1
: > "${LOG_FILE}"

source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/hardware.sh"

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

echo "=== Test 1: serialize_detected_oses ==="

declare -gA DETECTED_OSES=()
DETECTED_OSES["/dev/sda1"]="Windows 11"
DETECTED_OSES["/dev/sda3"]="Ubuntu 24.04"
DETECTED_OSES_SERIALIZED=""

serialize_detected_oses

# DETECTED_OSES_SERIALIZED should be non-empty
if [[ -n "${DETECTED_OSES_SERIALIZED}" ]]; then
    echo "  PASS: DETECTED_OSES_SERIALIZED is non-empty"; (( PASS++ )) || true
else
    echo "  FAIL: DETECTED_OSES_SERIALIZED is empty"; (( FAIL++ )) || true
fi

# Should contain both entries
assert_contains "Contains sda1" "/dev/sda1" "${DETECTED_OSES_SERIALIZED}"
assert_contains "Contains sda3" "/dev/sda3" "${DETECTED_OSES_SERIALIZED}"
assert_contains "Contains Windows 11" "Windows 11" "${DETECTED_OSES_SERIALIZED}"
assert_contains "Contains Ubuntu 24.04" "Ubuntu 24.04" "${DETECTED_OSES_SERIALIZED}"

echo ""
echo "=== Test 2: deserialize_detected_oses ==="

saved_serialized="${DETECTED_OSES_SERIALIZED}"

# Clear and deserialize
unset DETECTED_OSES
WINDOWS_DETECTED=0; LINUX_DETECTED=0
DETECTED_OSES_SERIALIZED="${saved_serialized}"

deserialize_detected_oses

assert_eq "Windows 11 restored" "Windows 11" "${DETECTED_OSES[/dev/sda1]:-}"
assert_eq "Ubuntu 24.04 restored" "Ubuntu 24.04" "${DETECTED_OSES[/dev/sda3]:-}"

echo ""
echo "=== Test 3: WINDOWS_DETECTED and LINUX_DETECTED after deserialize ==="

assert_eq "WINDOWS_DETECTED=1" "1" "${WINDOWS_DETECTED}"
assert_eq "LINUX_DETECTED=1" "1" "${LINUX_DETECTED}"

echo ""
echo "=== Test 4: Config save/load round-trip of DETECTED_OSES_SERIALIZED ==="

# Set up full state for save
WINDOWS_DETECTED=1; LINUX_DETECTED=1
export WINDOWS_DETECTED LINUX_DETECTED DETECTED_OSES_SERIALIZED

TMPFILE="/tmp/nixos-test-multiboot-$$.conf"
config_save "${TMPFILE}"

# Clear everything
unset DETECTED_OSES_SERIALIZED WINDOWS_DETECTED LINUX_DETECTED
unset DETECTED_OSES

config_load "${TMPFILE}"

# Verify serialized string survived round-trip
assert_contains "Serialized contains sda1 after load" "/dev/sda1" "${DETECTED_OSES_SERIALIZED:-}"
assert_contains "Serialized contains sda3 after load" "/dev/sda3" "${DETECTED_OSES_SERIALIZED:-}"
assert_eq "WINDOWS_DETECTED after load" "1" "${WINDOWS_DETECTED:-0}"
assert_eq "LINUX_DETECTED after load" "1" "${LINUX_DETECTED:-0}"

# Now deserialize again and verify values
deserialize_detected_oses
assert_eq "Windows 11 after full round-trip" "Windows 11" "${DETECTED_OSES[/dev/sda1]:-}"
assert_eq "Ubuntu 24.04 after full round-trip" "Ubuntu 24.04" "${DETECTED_OSES[/dev/sda3]:-}"

echo ""
echo "=== Test 5: Empty serialization ==="

unset DETECTED_OSES
declare -gA DETECTED_OSES=()
serialize_detected_oses
assert_eq "Empty DETECTED_OSES -> empty serialized" "" "${DETECTED_OSES_SERIALIZED}"

# Deserialize empty
WINDOWS_DETECTED=0; LINUX_DETECTED=0
deserialize_detected_oses
assert_eq "No WINDOWS_DETECTED from empty" "0" "${WINDOWS_DETECTED}"
assert_eq "No LINUX_DETECTED from empty" "0" "${LINUX_DETECTED}"

echo ""
echo "=== Test 6: Pipe in OS name gets sanitized ==="

unset DETECTED_OSES
declare -gA DETECTED_OSES=()
DETECTED_OSES["/dev/sda5"]="Some|Linux|Distro"
serialize_detected_oses

# Pipe chars should be replaced with hyphens
assert_contains "Pipe sanitized" "Some-Linux-Distro" "${DETECTED_OSES_SERIALIZED}"

rm -f "${TMPFILE}" "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
