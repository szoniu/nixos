#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_preset_save() {
    dialog_yesno "Save Preset" "Export configuration as a reusable preset?" || return "${TUI_NEXT}"
    local file
    file=$(dialog_inputbox "Preset File" "Save preset to:" "/root/nixos-preset-$(date +%Y%m%d).conf") || return "${TUI_BACK}"
    preset_export "${file}"
    dialog_msgbox "Saved" "Preset saved to: ${file}"
    return "${TUI_NEXT}"
}
