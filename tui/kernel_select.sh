#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_kernel_select() {
    local current="${KERNEL_PACKAGE:-default}"
    local on_def="off" on_latest="off" on_lts="off" on_zen="off"
    case "${current}" in default) on_def="on";; latest) on_latest="on";; lts) on_lts="on";; zen) on_zen="on";; esac

    local choice
    choice=$(dialog_radiolist "Kernel" \
        "default" "Default kernel (matches NixOS channel)" "${on_def}" \
        "latest"  "Latest stable kernel" "${on_latest}" \
        "lts"     "LTS kernel (long-term support)" "${on_lts}" \
        "zen"     "Zen kernel (desktop-optimized)" "${on_zen}") || return "${TUI_BACK}"
    [[ -z "${choice}" ]] && return "${TUI_BACK}"

    KERNEL_PACKAGE="${choice}"
    export KERNEL_PACKAGE
    einfo "Kernel: ${KERNEL_PACKAGE}"
    return "${TUI_NEXT}"
}
