#!/usr/bin/env bash
# constants.sh — Global constants for the NixOS installer
source "${LIB_DIR}/protection.sh"

readonly INSTALLER_VERSION="1.2.0"
readonly INSTALLER_NAME="NixOS TUI Installer"

# Paths (allow override from environment)
: "${MOUNTPOINT:=/mnt}"
: "${LOG_FILE:=/tmp/nixos-installer.log}"
: "${CHECKPOINT_DIR:=/tmp/nixos-installer-checkpoints}"
: "${CHECKPOINT_DIR_SUFFIX:=/tmp/nixos-installer-checkpoints}"
: "${CONFIG_FILE:=/tmp/nixos-installer.conf}"
: "${NIXOS_CONFIG_DIR:=/mnt/etc/nixos}"

# Gum backend
: "${GUM_VERSION:=0.17.0}"
: "${GUM_CACHE_DIR:=/tmp/nixos-installer-gum}"

# NixOS channels
readonly NIXOS_CHANNEL_STABLE="nixos-24.11"
readonly NIXOS_CHANNEL_UNSTABLE="nixos-unstable"

# Partition sizes (MiB)
readonly ESP_SIZE_MIB=512
readonly SWAP_DEFAULT_SIZE_MIB=4096

# GPT partition type GUIDs (for sfdisk)
readonly GPT_TYPE_EFI="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
readonly GPT_TYPE_LINUX="0FC63DAF-8483-4772-8E79-3D69D8477DE4"
readonly GPT_TYPE_SWAP="0657FD6D-A4AB-43C4-84E5-0933C84B4F4F"

# Minimum size for NixOS installation (10 GiB)
: "${NIXOS_MIN_SIZE_MIB:=10240}"

# GPU vendor PCI ID prefixes
readonly GPU_VENDOR_NVIDIA="10de"
readonly GPU_VENDOR_AMD="1002"
readonly GPU_VENDOR_INTEL="8086"

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
    DESKTOP_TYPE
    GPU_VENDOR
    GPU_DRIVER
    GPU_NVIDIA_OPEN
    DESKTOP_EXTRAS
    ROOT_PASSWORD_SET
    USERNAME
    USER_PASSWORD_SET
    USER_GROUPS
    ENABLE_SSH
    ENABLE_FLATPAK
    ENABLE_PRINTING
    ENABLE_BLUETOOTH
    ENABLE_HYPRLAND
    EXTRA_PACKAGES
    GPU_DEVICE_NAME
    GPU_DEVICE_ID
    ESP_PARTITION
    ESP_REUSE
    ROOT_PARTITION
    SWAP_PARTITION
    # Hybrid GPU
    HYBRID_GPU
    IGPU_VENDOR
    IGPU_DEVICE_NAME
    DGPU_VENDOR
    DGPU_DEVICE_NAME
    IGPU_BUS_ID
    DGPU_BUS_ID
    # ASUS ROG
    ASUS_ROG_DETECTED
    ENABLE_ASUSCTL
    # Peripheral detection
    BLUETOOTH_DETECTED
    FINGERPRINT_DETECTED
    ENABLE_FINGERPRINT
    THUNDERBOLT_DETECTED
    ENABLE_THUNDERBOLT
    SENSORS_DETECTED
    ENABLE_SENSORS
    WEBCAM_DETECTED
    WWAN_DETECTED
    ENABLE_WWAN
    # Multi-OS detection
    WINDOWS_DETECTED
    LINUX_DETECTED
    DETECTED_OSES_SERIALIZED
    # Partition shrink
    SHRINK_PARTITION
    SHRINK_PARTITION_FSTYPE
    SHRINK_NEW_SIZE_MIB
    # Bootloader
    BOOTLOADER_TYPE
)
