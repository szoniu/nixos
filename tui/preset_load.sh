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
            local default_preset=""
            local latest
            latest=$(ls -t "${SCRIPT_DIR}/presets/"custom-*.conf /root/nixos-preset*.conf 2>/dev/null | head -1) || true
            [[ -n "${latest}" ]] && default_preset="${latest}"
            : "${default_preset:=${SCRIPT_DIR}/presets/custom.conf}"
            local file
            file=$(dialog_inputbox "Preset File" "Enter path to preset:" "${default_preset}") || return "${TUI_BACK}"
            [[ -f "${file}" ]] || { dialog_msgbox "Error" "File not found: ${file}"; return "${TUI_BACK}"; }
            preset_import "${file}"
            _preset_ask_skip
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
            _preset_ask_skip
            return "${TUI_NEXT}" ;;
    esac
}

# _preset_ask_skip — Ask user whether to skip config screens after preset load
_preset_ask_skip() {
    local skip_rc=0
    dialog_yesno "Preset Loaded" \
        "Preset loaded successfully.\n\nSkip to summary? (You'll still select disk.)\n\nChoose 'No' to review all settings." \
        || skip_rc=$?
    if [[ ${skip_rc} -eq 0 ]]; then
        _PRESET_SKIP_TO_USER=1
        export _PRESET_SKIP_TO_USER
    fi
}
