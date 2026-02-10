#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_filesystem_select() {
    local current="${FILESYSTEM:-ext4}"
    local on_ext4="off" on_btrfs="off" on_xfs="off"
    case "${current}" in ext4) on_ext4="on";; btrfs) on_btrfs="on";; xfs) on_xfs="on";; esac

    local choice
    choice=$(dialog_radiolist "Root Filesystem" \
        "ext4"  "ext4 — stable, proven, recommended" "${on_ext4}" \
        "btrfs" "btrfs — snapshots, compression, rollback" "${on_btrfs}" \
        "xfs"   "XFS — high performance, large files" "${on_xfs}") || return "${TUI_BACK}"
    [[ -z "${choice}" ]] && return "${TUI_BACK}"

    FILESYSTEM="${choice}"
    export FILESYSTEM

    if [[ "${FILESYSTEM}" == "btrfs" ]]; then
        BTRFS_SUBVOLUMES="@:/:@home:/home:@nix:/nix:@var-log:/var/log:@snapshots:/.snapshots"
        dialog_yesno "Btrfs Subvolumes" \
            "Default subvolumes:\n\n  @         -> /\n  @home     -> /home\n  @nix      -> /nix\n  @var-log  -> /var/log\n  @snapshots -> /.snapshots\n\nUse defaults?" || {
            local custom
            custom=$(dialog_inputbox "Custom Subvolumes" "name:mountpoint pairs:" "${BTRFS_SUBVOLUMES}") || return "${TUI_BACK}"
            BTRFS_SUBVOLUMES="${custom}"
        }
        export BTRFS_SUBVOLUMES
    else
        BTRFS_SUBVOLUMES=""; export BTRFS_SUBVOLUMES
    fi

    # Encryption
    local encrypt
    dialog_yesno "Disk Encryption" \
        "Enable LUKS2 full-disk encryption?\n\nYou will need to enter a passphrase at every boot." \
        && encrypt="luks" || encrypt="none"
    ENCRYPTION="${encrypt}"
    export ENCRYPTION

    einfo "Filesystem: ${FILESYSTEM}, Encryption: ${ENCRYPTION}"
    return "${TUI_NEXT}"
}
