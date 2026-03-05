#!/usr/bin/env bash
# tui/summary.sh — Full summary + confirmation + countdown for NixOS
source "${LIB_DIR}/protection.sh"

screen_summary() {
    # Validate configuration before showing summary
    local validation_errors
    validation_errors=$(validate_config) || {
        dialog_msgbox "Configuration Errors" \
            "Fix these issues before proceeding:\n\n${validation_errors}"
        return "${TUI_BACK}"
    }

    local s=""
    s+="=== Installation Summary ===\n\n"
    s+="Channel:      ${NIXOS_CHANNEL:-${NIXOS_CHANNEL_STABLE}}\n"
    s+="Flakes:       ${USE_FLAKES:-yes}\n"
    s+="Target disk:  ${TARGET_DISK:-?}\n"
    s+="Partitioning: ${PARTITION_SCHEME:-auto}\n"
    s+="Filesystem:   ${FILESYSTEM:-ext4}\n"
    [[ "${FILESYSTEM}" == "btrfs" ]] && s+="Subvolumes:   yes\n"
    [[ "${ENCRYPTION:-none}" == "luks" ]] && s+="Encryption:   LUKS2\n"
    s+="Swap:         ${SWAP_TYPE:-none}"
    [[ -n "${SWAP_SIZE_MIB:-}" ]] && s+=" (${SWAP_SIZE_MIB} MiB)"
    s+="\n\n"
    s+="Hostname:     ${HOSTNAME:-nixos}\n"
    s+="Timezone:     ${TIMEZONE:-UTC}\n"
    s+="Locale:       ${LOCALE:-en_US.UTF-8}\n"
    s+="Keymap:       ${KEYMAP:-us}\n\n"
    s+="Kernel:       ${KERNEL_PACKAGE:-default}\n"

    if [[ "${HYBRID_GPU:-no}" == "yes" ]]; then
        s+="GPU:          ${IGPU_VENDOR:-?} + ${DGPU_DEVICE_NAME:-?} (hybrid)\n"
    else
        s+="GPU:          ${GPU_VENDOR:-unknown} (${GPU_DRIVER:-auto})\n"
    fi
    [[ "${GPU_VENDOR:-}" == "nvidia" ]] && s+="NVIDIA open:  ${GPU_NVIDIA_OPEN:-no}\n"
    [[ "${ASUS_ROG_DETECTED:-0}" == "1" ]] && s+="ASUS ROG:     detected\n"
    [[ "${ENABLE_FINGERPRINT:-no}" == "yes" ]] && s+="Fingerprint:  fprintd enabled\n"
    [[ "${ENABLE_THUNDERBOLT:-no}" == "yes" ]] && s+="Thunderbolt:  bolt enabled\n"
    [[ "${ENABLE_SENSORS:-no}" == "yes" ]] && s+="IIO sensors:  iio-sensor-proxy enabled\n"
    [[ "${ENABLE_WWAN:-no}" == "yes" ]] && s+="WWAN LTE:     ModemManager enabled\n"
    s+="\n"
    s+="Desktop:      KDE Plasma 6 + SDDM + PipeWire\n"
    s+="Username:     ${USERNAME:-user}\n"
    s+="SSH:          ${ENABLE_SSH:-no}\n"
    [[ -n "${DESKTOP_EXTRAS:-}" ]] && s+="Apps:         ${DESKTOP_EXTRAS}\n"
    [[ "${ENABLE_FLATPAK:-no}" == "yes" ]] && s+="Flatpak:      yes\n"
    [[ "${ENABLE_PRINTING:-no}" == "yes" ]] && s+="Printing:     yes\n"
    [[ "${ENABLE_BLUETOOTH:-no}" == "yes" ]] && s+="Bluetooth:    yes\n"
    [[ -n "${EXTRA_PACKAGES:-}" ]] && s+="Extra pkgs:   ${EXTRA_PACKAGES}\n"

    if [[ -n "${SHRINK_PARTITION:-}" ]]; then
        s+="\nShrink:       ${SHRINK_PARTITION} (${SHRINK_PARTITION_FSTYPE:-?}) -> ${SHRINK_NEW_SIZE_MIB:-?} MiB\n"
    fi

    if [[ "${ESP_REUSE:-no}" == "yes" ]]; then
        s+="\nDual-boot:    YES (reusing ESP ${ESP_PARTITION:-?})\n"
    fi

    # Show detected operating systems
    if [[ ${#DETECTED_OSES[@]} -gt 0 ]]; then
        s+="\nDetected OSes:\n"
        local p
        for p in "${!DETECTED_OSES[@]}"; do
            s+="  ${p}: ${DETECTED_OSES[${p}]}\n"
        done
    fi

    dialog_msgbox "Installation Summary" "${s}" || return "${TUI_BACK}"

    # Destructive warning
    if [[ "${PARTITION_SCHEME:-auto}" == "auto" ]]; then
        local warning=""
        warning+="!!! WARNING: DATA DESTRUCTION !!!\n\n"
        warning+="The following disk will be COMPLETELY ERASED:\n\n"
        warning+="  ${TARGET_DISK:-?}\n\n"
        warning+="ALL existing data on this disk will be permanently lost.\n"
        warning+="This action CANNOT be undone.\n\n"
        warning+="Type 'YES' in the next dialog to confirm."

        dialog_msgbox "WARNING" "${warning}" || return "${TUI_BACK}"

        local confirmation
        confirmation=$(dialog_inputbox "Confirm Installation" \
            "Type YES (all caps) to confirm and begin installation:" \
            "") || return "${TUI_BACK}"

        if [[ "${confirmation}" != "YES" ]]; then
            dialog_msgbox "Cancelled" "Installation cancelled. You typed: '${confirmation}'"
            return "${TUI_BACK}"
        fi
    elif [[ "${PARTITION_SCHEME:-auto}" == "dual-boot" ]]; then
        local warning=""
        warning+="!!! DUAL-BOOT INSTALLATION !!!\n\n"

        # What WILL be formatted
        warning+="WILL BE FORMATTED (data destroyed):\n"
        if [[ -n "${ROOT_PARTITION:-}" ]]; then
            warning+="  ${ROOT_PARTITION} -> ${FILESYSTEM:-ext4}\n"
        else
            warning+="  (new partition will be created) -> ${FILESYSTEM:-ext4}\n"
        fi
        if [[ -n "${SHRINK_PARTITION:-}" ]]; then
            warning+="WILL BE SHRUNK (data preserved):\n"
            warning+="  ${SHRINK_PARTITION} (${SHRINK_PARTITION_FSTYPE:-?}) -> ${SHRINK_NEW_SIZE_MIB:-?} MiB\n"
        fi
        warning+="\n"

        # What will SURVIVE
        warning+="WILL BE PRESERVED:\n"
        warning+="  ${ESP_PARTITION:-?}: EFI System Partition\n"
        local p
        for p in "${!DETECTED_OSES[@]}"; do
            [[ "${p}" == "${ROOT_PARTITION:-}" ]] && continue
            warning+="  ${p}: ${DETECTED_OSES[${p}]}\n"
        done

        warning+="\nType 'YES' in the next dialog to confirm."

        dialog_msgbox "WARNING" "${warning}" || return "${TUI_BACK}"

        local confirmation
        confirmation=$(dialog_inputbox "Confirm Dual-Boot Installation" \
            "Type YES (all caps) to confirm and begin installation:" \
            "") || return "${TUI_BACK}"

        if [[ "${confirmation}" != "YES" ]]; then
            dialog_msgbox "Cancelled" "Installation cancelled. You typed: '${confirmation}'"
            return "${TUI_BACK}"
        fi
    else
        dialog_yesno "Confirm Installation" \
            "Ready to begin installation. Continue?" \
            || return "${TUI_BACK}"
    fi

    # Countdown
    einfo "Installation starting in ${COUNTDOWN_DEFAULT} seconds..."
    (
        local i
        for (( i = COUNTDOWN_DEFAULT; i > 0; i-- )); do
            echo "$(( (COUNTDOWN_DEFAULT - i) * 100 / COUNTDOWN_DEFAULT ))"
            sleep 1
        done
        echo "100"
    ) | dialog_gauge "Starting Installation" \
        "Installation will begin in ${COUNTDOWN_DEFAULT} seconds...\nPress Ctrl+C to abort."

    return "${TUI_NEXT}"
}
