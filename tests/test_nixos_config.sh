#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export _NIXOS_INSTALLER=1 LIB_DIR="${SCRIPT_DIR}/lib" LOG_FILE="/tmp/nixos-test-nix.log"
export DRY_RUN=1 MOUNTPOINT="/tmp/nixos-test-mount-$$"
: > "${LOG_FILE}"

source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/disk.sh"
source "${LIB_DIR}/nixos_config.sh"

PASS=0 FAIL=0
assert_contains() {
    if [[ "$3" == *"$2"* ]]; then echo "  PASS: $1"; (( PASS++ )) || true
    else echo "  FAIL: $1 — '$2' not found"; (( FAIL++ )) || true; fi
}
assert_not_contains() {
    if [[ "$3" != *"$2"* ]]; then echo "  PASS: $1"; (( PASS++ )) || true
    else echo "  FAIL: $1 — '$2' should not be present"; (( FAIL++ )) || true; fi
}

echo "=== Test: configuration.nix (NVIDIA + Plasma) ==="
HOSTNAME="testbox"; TIMEZONE="Europe/Warsaw"; LOCALE="en_US.UTF-8"; KEYMAP="us"
GPU_VENDOR="nvidia"; GPU_DRIVER="nvidia"; GPU_NVIDIA_OPEN="yes"
NIXOS_CHANNEL="nixos-24.11"; USERNAME="alice"; USER_GROUPS="wheel,networkmanager"
ENABLE_SSH="yes"; ENABLE_BLUETOOTH="yes"; ENABLE_PRINTING="yes"; ENABLE_FLATPAK="yes"
ENCRYPTION="none"; WINDOWS_DETECTED=0; ESP_REUSE="no"; KERNEL_PACKAGE="default"
DESKTOP_EXTRAS="firefox kdePackages.kate"; EXTRA_PACKAGES="neovim tmux"

output=$(_write_configuration_nix)
assert_contains "Has hostname" 'hostName = "testbox"' "${output}"
assert_contains "Has timezone" 'timeZone = "Europe/Warsaw"' "${output}"
assert_contains "Has locale" 'defaultLocale = "en_US.UTF-8"' "${output}"
assert_contains "Has SDDM" "sddm.enable = true" "${output}"
assert_contains "Has Plasma 6" "plasma6.enable = true" "${output}"
assert_contains "Has PipeWire" "pipewire" "${output}"
assert_contains "Has NVIDIA" 'videoDrivers = [ "nvidia" ]' "${output}"
assert_contains "Has nvidia open" "open = true" "${output}"
assert_contains "Has SSH" "openssh.enable = true" "${output}"
assert_contains "Has user" "users.users.alice" "${output}"
assert_contains "Has bluetooth" "bluetooth.enable = true" "${output}"
assert_contains "Has printing" "printing.enable = true" "${output}"
assert_contains "Has flatpak" "flatpak.enable = true" "${output}"
assert_contains "Has firefox" "firefox" "${output}"
assert_contains "Has neovim" "neovim" "${output}"
assert_contains "Has flakes" "flakes" "${output}"
assert_contains "Has stateVersion" "stateVersion" "${output}"

echo ""
echo "=== Test: configuration.nix (AMD, no NVIDIA) ==="
GPU_VENDOR="amd"; GPU_DRIVER="amdgpu"; GPU_NVIDIA_OPEN="no"
ENABLE_SSH="no"; ENABLE_FLATPAK="no"
output=$(_write_configuration_nix)
assert_contains "Has amdvlk" "amdvlk" "${output}"
assert_not_contains "No NVIDIA" "nvidia" "${output}"
assert_not_contains "No flatpak" "flatpak" "${output}"

echo ""
echo "=== Test: LUKS config ==="
ENCRYPTION="luks"; LUKS_PARTITION="/dev/sda2"
# Mock get_uuid
get_uuid() { echo "test-uuid-1234"; }
output=$(_write_configuration_nix)
assert_contains "Has LUKS" 'luks.devices' "${output}"
assert_contains "Has LUKS UUID" "test-uuid-1234" "${output}"

rm -f "${LOG_FILE}"
echo ""
echo "=== Results: Passed: ${PASS}, Failed: ${FAIL} ==="
[[ ${FAIL} -eq 0 ]] && exit 0 || exit 1
