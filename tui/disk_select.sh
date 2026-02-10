#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_disk_select() {
    local -a disk_items=()
    local entry; for entry in "${AVAILABLE_DISKS[@]}"; do
        local name size model tran
        IFS='|' read -r name size model tran <<< "${entry}"
        disk_items+=("/dev/${name}" "${size} ${model} (${tran})")
    done
    [[ ${#disk_items[@]} -eq 0 ]] && { dialog_msgbox "No Disks" "No disks found."; return "${TUI_ABORT}"; }

    local selected_disk
    selected_disk=$(dialog_menu "Select Target Disk" "${disk_items[@]}") || return "${TUI_BACK}"
    TARGET_DISK="${selected_disk}"
    export TARGET_DISK

    local scheme
    if [[ "${WINDOWS_DETECTED:-0}" == "1" ]]; then
        scheme=$(dialog_menu "Partition Scheme" \
            "dual-boot" "Dual-boot with Windows (reuse ESP)" \
            "auto"      "Auto-partition entire disk (DESTROYS ALL DATA)" \
            "manual"    "Manual partitioning (advanced)") || return "${TUI_BACK}"
    else
        scheme=$(dialog_menu "Partition Scheme" \
            "auto"   "Auto-partition entire disk (DESTROYS ALL DATA)" \
            "manual" "Manual partitioning (advanced)") || return "${TUI_BACK}"
    fi
    PARTITION_SCHEME="${scheme}"
    export PARTITION_SCHEME

    case "${scheme}" in
        dual-boot)
            if [[ -n "${WINDOWS_ESP:-}" ]]; then
                ESP_PARTITION="${WINDOWS_ESP}"; ESP_REUSE="yes"
            elif [[ ${#ESP_PARTITIONS[@]} -gt 0 ]]; then
                local -a esp_items=()
                local esp; for esp in "${ESP_PARTITIONS[@]}"; do esp_items+=("${esp}" "ESP"); done
                ESP_PARTITION=$(dialog_menu "Select ESP" "${esp_items[@]}") || return "${TUI_BACK}"
                ESP_REUSE="yes"
            else
                dialog_msgbox "No ESP" "No ESP found, falling back to auto."
                PARTITION_SCHEME="auto"; ESP_REUSE="no"
            fi
            export ESP_PARTITION ESP_REUSE ;;
        auto)
            ESP_REUSE="no"; export ESP_REUSE
            dialog_yesno "WARNING" "Auto-partitioning will DESTROY ALL DATA on:\n\n  ${TARGET_DISK}\n\nContinue?" || return "${TUI_BACK}" ;;
        manual)
            dialog_msgbox "Manual" "Drop to shell for partitioning.\nRequired: ESP (vfat, 512M+), root partition.\nType 'exit' when done."
            PS1="(nixos-partition) \w \$ " bash --norc --noprofile || true
            ESP_PARTITION=$(dialog_inputbox "ESP" "ESP partition path:" "/dev/${TARGET_DISK##*/}1") || return "${TUI_BACK}"
            ROOT_PARTITION=$(dialog_inputbox "Root" "Root partition path:" "/dev/${TARGET_DISK##*/}2") || return "${TUI_BACK}"
            ESP_REUSE=$(dialog_yesno "ESP Reuse" "Is this an existing ESP with other bootloaders?" && echo "yes" || echo "no")
            export ESP_PARTITION ROOT_PARTITION ESP_REUSE ;;
    esac

    einfo "Disk: ${TARGET_DISK}, Scheme: ${PARTITION_SCHEME}"
    return "${TUI_NEXT}"
}
