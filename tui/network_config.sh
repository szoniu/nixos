#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_network_config() {
    local hostname
    hostname=$(dialog_inputbox "Hostname" "Enter hostname:" "${HOSTNAME:-nixos}") || return "${TUI_BACK}"
    HOSTNAME="${hostname}"
    export HOSTNAME
    einfo "Hostname: ${HOSTNAME}"
    return "${TUI_NEXT}"
}
