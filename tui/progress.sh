#!/usr/bin/env bash
# tui/progress.sh — Installation progress screen with resume detection
source "${LIB_DIR}/protection.sh"

readonly -a INSTALL_PHASES=(
    "preflight|Preflight checks"
    "disks|Disk operations"
    "nixos_generate|Hardware config generation"
    "nixos_config|NixOS configuration"
    "nixos_install|nixos-install (downloading & installing)"
    "finalize|Setting passwords & finalization"
)

# _save_config_to_target — Persist config file to target disk for --resume
_save_config_to_target() {
    if [[ -n "${MOUNTPOINT:-}" ]] && mountpoint -q "${MOUNTPOINT}" 2>/dev/null; then
        config_save "${MOUNTPOINT}/tmp/$(basename "${CONFIG_FILE}")"
    fi
}

# _detect_and_handle_resume — Returns 0 if resuming, 1 if fresh
_detect_and_handle_resume() {
    local has_checkpoints=0

    if [[ -d "${CHECKPOINT_DIR}" ]] && ls "${CHECKPOINT_DIR}/"* &>/dev/null 2>&1; then
        has_checkpoints=1
    fi

    local target_checkpoint_dir="${MOUNTPOINT}${CHECKPOINT_DIR_SUFFIX}"
    if [[ -d "${target_checkpoint_dir}" ]] && ls "${target_checkpoint_dir}/"* &>/dev/null 2>&1; then
        has_checkpoints=1
        if [[ ! -d "${CHECKPOINT_DIR}" ]] || ! ls "${CHECKPOINT_DIR}/"* &>/dev/null 2>&1; then
            CHECKPOINT_DIR="${target_checkpoint_dir}"; export CHECKPOINT_DIR
        fi
    fi

    [[ "${has_checkpoints}" -eq 0 ]] && return 1

    local completed_list="" cp_name
    for cp_name in "${CHECKPOINTS[@]}"; do
        checkpoint_reached "${cp_name}" && completed_list+="  - ${cp_name}\n"
    done

    if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
        einfo "Non-interactive mode — resuming from previous progress"
        _validate_and_clean_checkpoints; return 0
    fi

    if dialog_yesno "Resume Installation" \
        "Previous installation progress detected:\n\n${completed_list}\nResume from where it left off?\n\nChoose 'No' to start fresh."; then
        _validate_and_clean_checkpoints; return 0
    else
        checkpoint_clear; return 1
    fi
}

_validate_and_clean_checkpoints() {
    local cp_name
    for cp_name in "${CHECKPOINTS[@]}"; do
        if checkpoint_reached "${cp_name}" && ! checkpoint_validate "${cp_name}"; then
            ewarn "Checkpoint '${cp_name}' failed validation — will re-run"
            rm -f "${CHECKPOINT_DIR}/${cp_name}"
        fi
    done
}

screen_progress() {
    local total=${#INSTALL_PHASES[@]}
    local i=0

    if ! _detect_and_handle_resume; then
        einfo "Starting fresh installation"
    else
        einfo "Resuming installation from previous progress"
    fi

    exec 4>&2
    exec 2>>"${LOG_FILE}"

    for entry in "${INSTALL_PHASES[@]}"; do
        local phase_name phase_desc
        IFS='|' read -r phase_name phase_desc <<< "${entry}"
        (( i++ )) || true

        if checkpoint_reached "${phase_name}"; then
            einfo "Phase ${phase_name} already completed (checkpoint)"
            if [[ "${phase_name}" == "disks" ]]; then
                exec 2>&4
                mount_filesystems
                checkpoint_migrate_to_target
                _save_config_to_target
                exec 2>>"${LOG_FILE}"
            fi
            continue
        fi

        if [[ "${phase_name}" == "nixos_install" ]]; then
            _run_phase_with_live_output "${phase_name}" "${phase_desc}"
        else
            _show_phase_status "${i}" "${total}" "${phase_desc}"
            _execute_phase "${phase_name}" "${phase_desc}"
        fi
    done

    exec 2>&4
    exec 4>&-

    dialog_msgbox "Complete" "NixOS has been installed successfully!"
    return "${TUI_NEXT}"
}

_run_phase_with_live_output() {
    local phase_name="$1" phase_desc="$2"
    exec 2>&4

    clear 2>/dev/null
    echo -e "\033[1;36m══════════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[1;37m  NixOS TUI Installer — ${phase_desc}                             \033[0m"
    echo -e "\033[1;36m══════════════════════════════════════════════════════════════════\033[0m"
    echo -e "\033[0;33m  Live output below. Full log: ${LOG_FILE}    \033[0m"
    echo -e "\033[1;36m══════════════════════════════════════════════════════════════════\033[0m"
    echo ""

    export LIVE_OUTPUT=1
    _execute_phase "${phase_name}" "${phase_desc}"
    unset LIVE_OUTPUT

    echo ""
    echo -e "\033[1;32m  ${phase_desc} complete!                                         \033[0m"
    sleep 2

    exec 2>>"${LOG_FILE}"
}

_show_phase_status() {
    local current="$1" total="$2" desc="$3"
    local bar="" j
    for (( j = 1; j <= total; j++ )); do
        if (( j < current )); then bar+="[done] "
        elif (( j == current )); then bar+="[>>>>] "
        else bar+="[    ] "; fi
    done
    dialog_infobox "Installing NixOS  [${current}/${total}]" \
        "${bar}\n\n${desc}...\n\nPlease wait. See ${LOG_FILE} for details."
}

_execute_phase() {
    local phase_name="$1" phase_desc="$2"
    einfo "=== Phase: ${phase_desc} ==="

    case "${phase_name}" in
        preflight)
            maybe_exec 'before_preflight'
            preflight_checks
            maybe_exec 'after_preflight'
            ;;
        disks)
            maybe_exec 'before_disks'
            disk_execute_plan
            mount_filesystems
            checkpoint_migrate_to_target
            _save_config_to_target
            maybe_exec 'after_disks'
            ;;
        nixos_generate)
            maybe_exec 'before_generate'
            run_nixos_generate_config
            maybe_exec 'after_generate'
            ;;
        nixos_config)
            maybe_exec 'before_config'
            generate_nixos_config
            maybe_exec 'after_config'
            ;;
        nixos_install)
            maybe_exec 'before_install'
            run_nixos_install
            maybe_exec 'after_install'
            ;;
        finalize)
            maybe_exec 'before_finalize'
            set_nixos_passwords
            maybe_exec 'after_finalize'
            ;;
    esac

    checkpoint_set "${phase_name}"
}
