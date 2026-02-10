#!/usr/bin/env bash
# install.sh — Main entry point for the NixOS TUI Installer
set -euo pipefail
shopt -s inherit_errexit

export _NIXOS_INSTALLER=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR
export LIB_DIR="${SCRIPT_DIR}/lib"
export TUI_DIR="${SCRIPT_DIR}/tui"
export DATA_DIR="${SCRIPT_DIR}/data"

# --- Source library modules ---
source "${LIB_DIR}/constants.sh"
source "${LIB_DIR}/logging.sh"
source "${LIB_DIR}/utils.sh"
source "${LIB_DIR}/dialog.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/hardware.sh"
source "${LIB_DIR}/disk.sh"
source "${LIB_DIR}/nixos_config.sh"
source "${LIB_DIR}/hooks.sh"
source "${LIB_DIR}/preset.sh"

# --- Source TUI screens ---
source "${TUI_DIR}/welcome.sh"
source "${TUI_DIR}/preset_load.sh"
source "${TUI_DIR}/hw_detect.sh"
source "${TUI_DIR}/channel_select.sh"
source "${TUI_DIR}/disk_select.sh"
source "${TUI_DIR}/filesystem_select.sh"
source "${TUI_DIR}/swap_config.sh"
source "${TUI_DIR}/network_config.sh"
source "${TUI_DIR}/locale_config.sh"
source "${TUI_DIR}/kernel_select.sh"
source "${TUI_DIR}/gpu_config.sh"
source "${TUI_DIR}/desktop_config.sh"
source "${TUI_DIR}/user_config.sh"
source "${TUI_DIR}/extra_packages.sh"
source "${TUI_DIR}/preset_save.sh"
source "${TUI_DIR}/summary.sh"
source "${TUI_DIR}/progress.sh"

# --- Cleanup trap ---
cleanup() {
    local rc=$?
    if [[ ${rc} -ne 0 ]]; then
        eerror "Installer exited with code ${rc}"
        eerror "Log file: ${LOG_FILE}"
    fi
    return ${rc}
}
trap cleanup EXIT

# --- Parse arguments ---
MODE="full"
DRY_RUN=0
FORCE=0
NON_INTERACTIVE=0
export DRY_RUN FORCE NON_INTERACTIVE

usage() {
    cat <<'EOF'
NixOS TUI Installer

Usage:
  install.sh [OPTIONS] [COMMAND]

Commands:
  (default)       Full installation (wizard + install)
  --configure     Run only the TUI wizard (generate config)
  --install       Run only installation (requires existing config)

Options:
  --config FILE   Use specified config file
  --dry-run       Simulate without destructive operations
  --force         Continue past failed prerequisites
  --non-interactive  Abort on any error
  --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configure)     MODE="configure"; shift ;;
        --install)       MODE="install"; shift ;;
        --config)        CONFIG_FILE="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=1; shift ;;
        --force)         FORCE=1; shift ;;
        --non-interactive) NON_INTERACTIVE=1; shift ;;
        --help|-h)       usage; exit 0 ;;
        *) eerror "Unknown: $1"; usage; exit 1 ;;
    esac
done

# --- Main functions ---

run_configuration_wizard() {
    init_dialog
    register_wizard_screens \
        screen_welcome \
        screen_preset_load \
        screen_hw_detect \
        screen_channel_select \
        screen_disk_select \
        screen_filesystem_select \
        screen_swap_config \
        screen_network_config \
        screen_locale_config \
        screen_kernel_select \
        screen_gpu_config \
        screen_desktop_config \
        screen_user_config \
        screen_extra_packages \
        screen_preset_save \
        screen_summary
    run_wizard
    config_save "${CONFIG_FILE}"
    einfo "Configuration saved to ${CONFIG_FILE}"
}

preflight_checks() {
    einfo "Running preflight checks..."
    if [[ "${DRY_RUN}" != "1" ]]; then
        is_root || die "Must run as root"
        is_efi || die "UEFI boot required"
        has_network || die "Network required"
    fi
    einfo "Preflight OK"
}

run_post_install() {
    einfo "=== Post-installation ==="
    unmount_filesystems

    dialog_msgbox "Installation Complete" \
        "NixOS has been successfully installed!\n\n\
Remove the installation media and reboot.\n\n\
After first boot, log in and run:\n\
  sudo nixos-rebuild switch\n\
to apply any configuration changes.\n\n\
Log: ${LOG_FILE}"

    if dialog_yesno "Reboot" "Reboot now?"; then
        [[ "${DRY_RUN}" != "1" ]] && reboot || einfo "[DRY-RUN] Would reboot"
    else
        einfo "Reboot manually when ready."
    fi
}

# --- Entry point ---
main() {
    init_logging
    einfo "========================================="
    einfo "${INSTALLER_NAME} v${INSTALLER_VERSION}"
    einfo "========================================="
    einfo "Mode: ${MODE}"
    [[ "${DRY_RUN}" == "1" ]] && ewarn "DRY-RUN mode"

    case "${MODE}" in
        full)
            run_configuration_wizard
            init_dialog
            screen_progress
            run_post_install
            ;;
        configure)
            run_configuration_wizard
            ;;
        install)
            config_load "${CONFIG_FILE}"
            init_dialog
            screen_progress
            run_post_install
            ;;
    esac

    einfo "Done."
}

main "$@"
