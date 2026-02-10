#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_channel_select() {
    local current="${NIXOS_CHANNEL:-${NIXOS_CHANNEL_STABLE}}"
    local on_stable="off" on_unstable="off"
    [[ "${current}" == "${NIXOS_CHANNEL_STABLE}" ]] && on_stable="on"
    [[ "${current}" == "${NIXOS_CHANNEL_UNSTABLE}" ]] && on_unstable="on"

    local choice
    choice=$(dialog_radiolist "NixOS Channel" \
        "${NIXOS_CHANNEL_STABLE}"   "Stable (${NIXOS_CHANNEL_STABLE}) — recommended" "${on_stable}" \
        "${NIXOS_CHANNEL_UNSTABLE}" "Unstable — latest packages, less tested" "${on_unstable}") \
        || return "${TUI_BACK}"

    [[ -z "${choice}" ]] && return "${TUI_BACK}"
    NIXOS_CHANNEL="${choice}"
    export NIXOS_CHANNEL

    # Flakes
    local use_flakes
    dialog_yesno "Nix Flakes" \
        "Enable Nix Flakes (experimental but widely used)?\n\n\
Flakes provide reproducible builds and better\n\
dependency management. Recommended for most users." \
        && use_flakes="yes" || use_flakes="no"
    USE_FLAKES="${use_flakes}"
    export USE_FLAKES

    einfo "Channel: ${NIXOS_CHANNEL}, Flakes: ${USE_FLAKES}"
    return "${TUI_NEXT}"
}
