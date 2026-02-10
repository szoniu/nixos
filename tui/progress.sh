#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

readonly -a INSTALL_PHASES=(
    "preflight|Preflight checks|5"
    "disks|Disk operations|15"
    "nixos_generate|Hardware config generation|5"
    "nixos_config|NixOS configuration|10"
    "nixos_install|nixos-install (downloading & installing)|55"
    "finalize|Setting passwords & finalization|10"
)

screen_progress() {
    local total_weight=0
    local entry; for entry in "${INSTALL_PHASES[@]}"; do
        local w; IFS='|' read -r _ _ w <<< "${entry}"; (( total_weight += w ))
    done

    local progress_pipe="/tmp/nixos-progress-$$"
    mkfifo "${progress_pipe}" 2>/dev/null || true
    dialog_gauge "Installing NixOS" "Preparing..." 0 < "${progress_pipe}" &
    local gauge_pid=$!
    exec 3>"${progress_pipe}"

    local completed_weight=0
    for entry in "${INSTALL_PHASES[@]}"; do
        local phase_name phase_desc weight
        IFS='|' read -r phase_name phase_desc weight <<< "${entry}"

        local percent=$(( completed_weight * 100 / total_weight ))
        echo "XXX" >&3 2>/dev/null || true
        echo "${percent}" >&3 2>/dev/null || true
        echo "${phase_desc}..." >&3 2>/dev/null || true
        echo "XXX" >&3 2>/dev/null || true

        if ! checkpoint_reached "${phase_name}"; then
            _execute_phase "${phase_name}" "${phase_desc}"
        fi
        (( completed_weight += weight ))
    done

    echo "XXX" >&3 2>/dev/null || true
    echo "100" >&3 2>/dev/null || true
    echo "Installation complete!" >&3 2>/dev/null || true
    echo "XXX" >&3 2>/dev/null || true

    exec 3>&-
    wait "${gauge_pid}" 2>/dev/null || true
    rm -f "${progress_pipe}"

    dialog_msgbox "Complete" "NixOS has been installed successfully!"
    return "${TUI_NEXT}"
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
