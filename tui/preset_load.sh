#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_preset_load() {
    local choice
    choice=$(dialog_menu "Load Preset" \
        "skip"   "Start fresh configuration" \
        "file"   "Load preset from file" \
        "browse" "Browse example presets") || return "${TUI_BACK}"

    case "${choice}" in
        skip) return "${TUI_NEXT}" ;;
        file)
            local file
            file=$(dialog_inputbox "Preset File" "Enter path to preset:" "/root/nixos-preset.conf") || return "${TUI_BACK}"
            [[ -f "${file}" ]] || { dialog_msgbox "Error" "File not found: ${file}"; return "${TUI_BACK}"; }
            preset_import "${file}"
            dialog_msgbox "Loaded" "Preset loaded. Hardware values will be re-detected."
            return "${TUI_NEXT}" ;;
        browse)
            local -a presets=()
            local f; for f in "${SCRIPT_DIR}/presets/"*.conf; do
                [[ -f "${f}" ]] || continue
                presets+=("${f}" "$(basename "${f}")")
            done
            [[ ${#presets[@]} -eq 0 ]] && { dialog_msgbox "None" "No presets found."; return "${TUI_BACK}"; }
            local selected
            selected=$(dialog_menu "Select Preset" "${presets[@]}") || return "${TUI_BACK}"
            preset_import "${selected}"
            dialog_msgbox "Loaded" "Preset: $(basename "${selected}")"
            return "${TUI_NEXT}" ;;
    esac
}
