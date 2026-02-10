#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_user_config() {
    # Root password
    dialog_yesno "Root Password" \
        "Set a root password?\n\n(You will be prompted during installation.\nThe default NixOS root has no password.)" \
        && ROOT_PASSWORD_SET="yes" || ROOT_PASSWORD_SET="no"
    export ROOT_PASSWORD_SET

    # Regular user
    local username
    username=$(dialog_inputbox "Username" "Enter username:" "${USERNAME:-user}") || return "${TUI_BACK}"
    USERNAME="${username}"; export USERNAME

    USER_PASSWORD_SET="yes"; export USER_PASSWORD_SET

    # Groups
    USER_GROUPS="wheel,networkmanager,audio,video"
    local groups
    groups=$(dialog_inputbox "User Groups" "Groups for ${USERNAME}:" "${USER_GROUPS}") || return "${TUI_BACK}"
    USER_GROUPS="${groups}"; export USER_GROUPS

    # SSH
    dialog_yesno "SSH Server" "Enable SSH server?" && ENABLE_SSH="yes" || ENABLE_SSH="no"
    export ENABLE_SSH

    einfo "User: ${USERNAME}, SSH: ${ENABLE_SSH}"
    return "${TUI_NEXT}"
}
