#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_extra_packages() {
    local packages
    packages=$(dialog_inputbox "Extra Packages" \
        "Additional nix packages (space-separated).\n\n\
Examples: neovim tmux ripgrep fd bat\n\n\
Leave empty to skip:" \
        "${EXTRA_PACKAGES:-}") || return "${TUI_BACK}"
    EXTRA_PACKAGES="${packages}"; export EXTRA_PACKAGES
    einfo "Extra packages: ${EXTRA_PACKAGES:-none}"
    return "${TUI_NEXT}"
}
