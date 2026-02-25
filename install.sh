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
    if { true >&4; } 2>/dev/null; then
        exec 2>&4; exec 4>&-
    fi
    if [[ ${rc} -ne 0 ]]; then
        eerror "Installer exited with code ${rc}"
        eerror "Log file: ${LOG_FILE}"
    fi
    return ${rc}
}
trap cleanup EXIT
trap 'trap - EXIT; cleanup; exit 130' INT
trap 'trap - EXIT; cleanup; exit 143' TERM

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
  --resume        Resume interrupted installation (scan disks for checkpoints)

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
        --resume)        MODE="resume"; shift ;;
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
        resume)
            local resume_rc=0
            try_resume_from_disk || resume_rc=$?

            case ${resume_rc} in
                0)
                    config_load "${CONFIG_FILE}"
                    init_dialog
                    local completed_list="" cp_name
                    for cp_name in "${CHECKPOINTS[@]}"; do
                        checkpoint_reached "${cp_name}" && completed_list+="  - ${cp_name}\n"
                    done
                    dialog_msgbox "Resume: Data Recovered" \
                        "Found previous installation on ${RESUME_FOUND_PARTITION}.\n\nRecovered config and checkpoints:\n\n${completed_list}\nResuming installation..."
                    screen_progress
                    run_post_install
                    ;;
                1)
                    init_dialog
                    local infer_rc=0
                    infer_config_from_partition "${RESUME_FOUND_PARTITION}" "${RESUME_FOUND_FSTYPE}" || infer_rc=$?
                    if [[ ${infer_rc} -eq 0 ]]; then
                        config_save "${CONFIG_FILE}"
                        local inferred_summary=""
                        inferred_summary+="Partition: ${ROOT_PARTITION:-?}\n"
                        inferred_summary+="Disk: ${TARGET_DISK:-?}\n"
                        inferred_summary+="Filesystem: ${FILESYSTEM:-?}\n"
                        inferred_summary+="ESP: ${ESP_PARTITION:-?}\n"
                        [[ -n "${HOSTNAME:-}" ]] && inferred_summary+="Hostname: ${HOSTNAME}\n"
                        [[ -n "${TIMEZONE:-}" ]] && inferred_summary+="Timezone: ${TIMEZONE}\n"
                        local completed_list="" cp_name
                        for cp_name in "${CHECKPOINTS[@]}"; do
                            checkpoint_reached "${cp_name}" && completed_list+="  - ${cp_name}\n"
                        done
                        dialog_msgbox "Resume: Config Inferred" \
                            "Found checkpoints on ${RESUME_FOUND_PARTITION} (no config file).\n\nInferred configuration:\n${inferred_summary}\nCompleted phases:\n${completed_list}\nResuming installation..."
                        screen_progress
                        run_post_install
                    else
                        dialog_msgbox "Resume: Partial Recovery" \
                            "Found checkpoints but could not fully infer configuration.\nPlease complete the wizard."
                        run_configuration_wizard
                        screen_progress
                        run_post_install
                    fi
                    ;;
                2)
                    init_dialog
                    dialog_msgbox "Resume: Nothing Found" \
                        "No previous installation data found.\n\nStarting full installation."
                    run_configuration_wizard
                    init_dialog
                    screen_progress
                    run_post_install
                    ;;
            esac
            ;;
    esac

    einfo "Done."
}

main "$@"
