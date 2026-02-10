#!/usr/bin/env bash
# constants.sh — Global constants for the NixOS installer
source "${LIB_DIR}/protection.sh"

readonly INSTALLER_VERSION="1.0.0"
readonly INSTALLER_NAME="NixOS TUI Installer"

# Paths (allow override from environment)
: "${MOUNTPOINT:=/mnt}"
: "${LOG_FILE:=/tmp/nixos-installer.log}"
: "${CHECKPOINT_DIR:=/tmp/nixos-installer-checkpoints}"
: "${CONFIG_FILE:=/tmp/nixos-installer.conf}"
: "${NIXOS_CONFIG_DIR:=/mnt/etc/nixos}"

# NixOS channels
readonly NIXOS_CHANNEL_STABLE="nixos-24.11"
readonly NIXOS_CHANNEL_UNSTABLE="nixos-unstable"

# Partition sizes (MiB)
readonly ESP_SIZE_MIB=512
readonly SWAP_DEFAULT_SIZE_MIB=4096

# Timeouts
readonly COUNTDOWN_DEFAULT=10

# Exit codes for TUI screens
readonly TUI_NEXT=0
readonly TUI_BACK=1
readonly TUI_ABORT=2

# Checkpoint names
readonly -a CHECKPOINTS=(
    "preflight"
    "disks"
    "nixos_generate"
    "nixos_config"
    "nixos_install"
    "finalize"
)

# Configuration variable names (for save/load)
readonly -a CONFIG_VARS=(
    NIXOS_CHANNEL
    USE_FLAKES
    TARGET_DISK
    PARTITION_SCHEME
    FILESYSTEM
    BTRFS_SUBVOLUMES
    ENCRYPTION
    LUKS_PARTITION
    SWAP_TYPE
    SWAP_SIZE_MIB
    HOSTNAME
    TIMEZONE
    LOCALE
    KEYMAP
    KERNEL_PACKAGE
    GPU_VENDOR
    GPU_DRIVER
    DESKTOP_EXTRAS
    ROOT_PASSWORD_SET
    USERNAME
    USER_PASSWORD_SET
    USER_GROUPS
    ENABLE_SSH
    ENABLE_FLATPAK
    ENABLE_PRINTING
    ENABLE_BLUETOOTH
    EXTRA_PACKAGES
    CPU_MARCH
    VIDEO_CARDS
    ESP_PARTITION
    ESP_REUSE
    ROOT_PARTITION
    SWAP_PARTITION
    BOOT_PARTITION
)
