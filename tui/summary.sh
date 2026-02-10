#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_summary() {
    local s=""
    s+="=== Installation Summary ===\n\n"
    s+="Channel:      ${NIXOS_CHANNEL:-${NIXOS_CHANNEL_STABLE}}\n"
    s+="Flakes:       ${USE_FLAKES:-yes}\n"
    s+="Target disk:  ${TARGET_DISK:-?}\n"
    s+="Partitioning: ${PARTITION_SCHEME:-auto}\n"
    s+="Filesystem:   ${FILESYSTEM:-ext4}\n"
    [[ "${FILESYSTEM}" == "btrfs" ]] && s+="Subvolumes:   yes\n"
    [[ "${ENCRYPTION:-none}" == "luks" ]] && s+="Encryption:   LUKS2\n"
    s+="Swap:         ${SWAP_TYPE:-none}\n\n"
    s+="Hostname:     ${HOSTNAME:-nixos}\n"
    s+="Timezone:     ${TIMEZONE:-UTC}\n"
    s+="Locale:       ${LOCALE:-en_US.UTF-8}\n"
    s+="Keymap:       ${KEYMAP:-us}\n\n"
    s+="Kernel:       ${KERNEL_PACKAGE:-default}\n"
    s+="GPU:          ${GPU_VENDOR:-unknown} (${GPU_DRIVER:-auto})\n"
    s+="Desktop:      KDE Plasma 6 + SDDM + PipeWire\n"
    s+="Username:     ${USERNAME:-user}\n"
    s+="SSH:          ${ENABLE_SSH:-no}\n"
    [[ -n "${DESKTOP_EXTRAS:-}" ]] && s+="Apps:         ${DESKTOP_EXTRAS}\n"
    [[ -n "${EXTRA_PACKAGES:-}" ]] && s+="Extra pkgs:   ${EXTRA_PACKAGES}\n"
    [[ "${ESP_REUSE:-no}" == "yes" ]] && s+="\nDual-boot:    YES (ESP: ${ESP_PARTITION:-?})\n"

    dialog_msgbox "Summary" "${s}" || return "${TUI_BACK}"

    if [[ "${PARTITION_SCHEME:-auto}" == "auto" ]]; then
        dialog_msgbox "WARNING" \
            "!!! DATA DESTRUCTION !!!\n\n${TARGET_DISK} will be COMPLETELY ERASED.\n\nType 'YES' to confirm."
        local confirm
        confirm=$(dialog_inputbox "Confirm" "Type YES to begin:" "") || return "${TUI_BACK}"
        [[ "${confirm}" != "YES" ]] && { dialog_msgbox "Cancelled" "You typed: '${confirm}'"; return "${TUI_BACK}"; }
    else
        dialog_yesno "Confirm" "Ready to install. Continue?" || return "${TUI_BACK}"
    fi

    (
        local i; for (( i = COUNTDOWN_DEFAULT; i > 0; i-- )); do
            echo "$(( (COUNTDOWN_DEFAULT - i) * 100 / COUNTDOWN_DEFAULT ))"; sleep 1
        done; echo "100"
    ) | dialog_gauge "Starting" "Installation begins in ${COUNTDOWN_DEFAULT}s..."

    return "${TUI_NEXT}"
}
