#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_desktop_select() {
    local current="${DESKTOP_TYPE:-kde}"
    local on_kde="off" on_gnome="off"
    case "${current}" in kde) on_kde="on";; gnome) on_gnome="on";; esac

    local choice
    choice=$(dialog_radiolist "Desktop Environment" \
        "kde"   "KDE Plasma 6 — Modern desktop with SDDM" "${on_kde}" \
        "gnome" "GNOME — Clean desktop with GDM" "${on_gnome}") || return "${TUI_BACK}"
    [[ -z "${choice}" ]] && return "${TUI_BACK}"

    DESKTOP_TYPE="${choice}"
    export DESKTOP_TYPE
    einfo "Desktop: ${DESKTOP_TYPE}"
    return "${TUI_NEXT}"
}
