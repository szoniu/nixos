#!/usr/bin/env bash
# tui/bootloader_select.sh — Bootloader selection (systemd-boot / GRUB)
source "${LIB_DIR}/protection.sh"

screen_bootloader_select() {
    local default="systemd-boot"

    # Auto-suggest GRUB when other OSes are detected (multi-boot)
    if [[ "${WINDOWS_DETECTED:-0}" == "1" ]] || [[ "${LINUX_DETECTED:-0}" == "1" ]] || \
       [[ "${PARTITION_SCHEME:-auto}" == "dual-boot" ]]; then
        default="grub"
    fi

    local choice
    choice=$(dialog_radiolist "Bootloader" \
        "systemd-boot" "systemd-boot — lightweight, EFI native" "$([[ "${default}" == "systemd-boot" ]] && echo on || echo off)" \
        "grub"         "GRUB — multi-boot support (os-prober)" "$([[ "${default}" == "grub" ]] && echo on || echo off)") || return "${TUI_BACK}"

    [[ -z "${choice}" ]] && return "${TUI_BACK}"

    BOOTLOADER_TYPE="${choice}"
    export BOOTLOADER_TYPE

    if [[ "${choice}" == "systemd-boot" ]] && \
       { [[ "${WINDOWS_DETECTED:-0}" == "1" ]] || [[ "${LINUX_DETECTED:-0}" == "1" ]]; }; then
        dialog_msgbox "Multi-boot Notice" \
            "systemd-boot does not detect other Linux installations.\n\nFor multi-boot setups (multiple Linux distros), GRUB with os-prober is recommended.\n\nYou can continue with systemd-boot, but only NixOS will appear in the boot menu."
    fi

    return "${TUI_NEXT}"
}
