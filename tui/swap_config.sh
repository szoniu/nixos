#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_swap_config() {
    local current="${SWAP_TYPE:-none}"
    local on_zram="off" on_part="off" on_none="off"
    case "${current}" in zram) on_zram="on";; partition) on_part="on";; none) on_none="on";; esac

    local choice
    choice=$(dialog_radiolist "Swap Configuration" \
        "zram"      "zram — compressed RAM swap (NixOS has built-in support)" "${on_zram}" \
        "partition" "Swap partition — traditional disk swap" "${on_part}" \
        "none"      "No swap" "${on_none}") || return "${TUI_BACK}"
    [[ -z "${choice}" ]] && return "${TUI_BACK}"

    SWAP_TYPE="${choice}"
    export SWAP_TYPE

    if [[ "${SWAP_TYPE}" == "partition" ]]; then
        SWAP_SIZE_MIB=$(dialog_inputbox "Swap Size" "Swap partition size in MiB:" "${SWAP_DEFAULT_SIZE_MIB}") || return "${TUI_BACK}"
        export SWAP_SIZE_MIB
    fi

    einfo "Swap: ${SWAP_TYPE}"
    return "${TUI_NEXT}"
}
