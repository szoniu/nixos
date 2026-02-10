#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" LOG_FILE="/tmp/nixos-test-config.log"
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

echo "=== Test: Config Round-Trip ==="
NIXOS_CHANNEL="nixos-24.11"; FILESYSTEM="btrfs"; HOSTNAME="test-host"
LOCALE="pl_PL.UTF-8"; SWAP_TYPE="zram"; ENCRYPTION="luks"
BTRFS_SUBVOLUMES="@:/:@home:/home:@nix:/nix"
EXTRA_PACKAGES="neovim tmux"
export NIXOS_CHANNEL FILESYSTEM HOSTNAME LOCALE SWAP_TYPE ENCRYPTION BTRFS_SUBVOLUMES EXTRA_PACKAGES

TMPFILE="/tmp/nixos-test-config-$$.conf"
config_save "${TMPFILE}"
unset NIXOS_CHANNEL FILESYSTEM HOSTNAME LOCALE SWAP_TYPE ENCRYPTION BTRFS_SUBVOLUMES EXTRA_PACKAGES
config_load "${TMPFILE}"

assert_eq "NIXOS_CHANNEL" "nixos-24.11" "${NIXOS_CHANNEL:-}"
assert_eq "FILESYSTEM" "btrfs" "${FILESYSTEM:-}"
assert_eq "HOSTNAME" "test-host" "${HOSTNAME:-}"
assert_eq "LOCALE" "pl_PL.UTF-8" "${LOCALE:-}"
assert_eq "SWAP_TYPE" "zram" "${SWAP_TYPE:-}"
assert_eq "ENCRYPTION" "luks" "${ENCRYPTION:-}"
assert_eq "BTRFS_SUBVOLUMES" "@:/:@home:/home:@nix:/nix" "${BTRFS_SUBVOLUMES:-}"
assert_eq "EXTRA_PACKAGES" "neovim tmux" "${EXTRA_PACKAGES:-}"

echo ""
echo "=== Test: config_set / config_get ==="
config_set "HOSTNAME" "new-host"
assert_eq "config_set" "new-host" "$(config_get HOSTNAME)"
config_set "EXTRA_PACKAGES" "pkg with spaces"
assert_eq "Spaces" "pkg with spaces" "$(config_get EXTRA_PACKAGES)"

TMPFILE2="/tmp/nixos-test-config-special-$$.conf"
config_save "${TMPFILE2}"
unset HOSTNAME EXTRA_PACKAGES
config_load "${TMPFILE2}"
assert_eq "Round-trip HOSTNAME" "new-host" "${HOSTNAME:-}"
assert_eq "Round-trip EXTRA_PACKAGES" "pkg with spaces" "${EXTRA_PACKAGES:-}"

rm -f "${TMPFILE}" "${TMPFILE2}" "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
