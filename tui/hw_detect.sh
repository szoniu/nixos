#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_hw_detect() {
    dialog_msgbox "Hardware Detection" "Scanning your hardware..." || return "${TUI_ABORT}"
    detect_all_hardware
    local summary
    summary=$(get_hardware_summary)
    dialog_yesno "Hardware Detected" "${summary}\n\nLooks correct? Yes to continue, No to go back." \
        && return "${TUI_NEXT}" || return "${TUI_BACK}"
}
