#!/usr/bin/env bash
# disk.sh — Two-phase disk operations (plan -> execute), UUID persistence
source "${LIB_DIR}/protection.sh"

declare -ga DISK_ACTIONS=()

disk_plan_reset() { DISK_ACTIONS=(); }

disk_plan_add() {
    local desc="$1"; shift
    DISK_ACTIONS+=("${desc}|||$*")
}

disk_plan_show() {
    einfo "Planned disk operations:"
    local i
    for (( i = 0; i < ${#DISK_ACTIONS[@]}; i++ )); do
        einfo "  $((i + 1)). ${DISK_ACTIONS[$i]%%|||*}"
    done
}

disk_plan_auto() {
    local disk="${TARGET_DISK}"
    local fs="${FILESYSTEM:-ext4}"
    local swap_type="${SWAP_TYPE:-none}"
    local swap_size="${SWAP_SIZE_MIB:-${SWAP_DEFAULT_SIZE_MIB}}"

    disk_plan_reset

    disk_plan_add "Create GPT partition table on ${disk}" \
        parted -s "${disk}" mklabel gpt

    disk_plan_add "Create ESP partition (${ESP_SIZE_MIB} MiB)" \
        parted -s "${disk}" mkpart "EFI System Partition" fat32 1MiB "$((ESP_SIZE_MIB + 1))MiB"
    disk_plan_add "Set ESP flag" \
        parted -s "${disk}" set 1 esp on

    local next_start="$((ESP_SIZE_MIB + 1))"

    if [[ "${swap_type}" == "partition" ]]; then
        local swap_end="$((next_start + swap_size))"
        disk_plan_add "Create swap partition (${swap_size} MiB)" \
            parted -s "${disk}" mkpart "Linux swap" linux-swap "${next_start}MiB" "${swap_end}MiB"
        next_start="${swap_end}"
    fi

    disk_plan_add "Create root partition (remaining space)" \
        parted -s "${disk}" mkpart "Linux filesystem" "${next_start}MiB" "100%"

    local part_prefix="${disk}"
    [[ "${disk}" =~ [0-9]$ ]] && part_prefix="${disk}p"

    local part_num=1
    ESP_PARTITION="${part_prefix}${part_num}"
    disk_plan_add "Format ESP as FAT32" mkfs.vfat -F 32 -n EFI "${ESP_PARTITION}"
    (( part_num++ ))

    if [[ "${swap_type}" == "partition" ]]; then
        SWAP_PARTITION="${part_prefix}${part_num}"
        disk_plan_add "Format swap partition" mkswap -L swap "${SWAP_PARTITION}"
        (( part_num++ ))
    fi

    ROOT_PARTITION="${part_prefix}${part_num}"
    case "${fs}" in
        ext4)  disk_plan_add "Format root as ext4"  mkfs.ext4 -L nixos "${ROOT_PARTITION}" ;;
        btrfs) disk_plan_add "Format root as btrfs" mkfs.btrfs -f -L nixos "${ROOT_PARTITION}" ;;
        xfs)   disk_plan_add "Format root as XFS"   mkfs.xfs -f -L nixos "${ROOT_PARTITION}" ;;
    esac

    if [[ "${ENCRYPTION:-none}" == "luks" ]]; then
        # Wrap root in LUKS
        LUKS_PARTITION="${ROOT_PARTITION}"
        disk_plan_add "LUKS encrypt root partition" \
            cryptsetup luksFormat --type luks2 "${LUKS_PARTITION}"
        disk_plan_add "Open LUKS device" \
            cryptsetup open "${LUKS_PARTITION}" cryptroot
        ROOT_PARTITION="/dev/mapper/cryptroot"
        case "${fs}" in
            ext4)  disk_plan_add "Format LUKS root as ext4"  mkfs.ext4 -L nixos "${ROOT_PARTITION}" ;;
            btrfs) disk_plan_add "Format LUKS root as btrfs" mkfs.btrfs -f -L nixos "${ROOT_PARTITION}" ;;
            xfs)   disk_plan_add "Format LUKS root as XFS"   mkfs.xfs -f -L nixos "${ROOT_PARTITION}" ;;
        esac
    fi

    export ESP_PARTITION ROOT_PARTITION SWAP_PARTITION LUKS_PARTITION
    einfo "Auto-partition plan generated for ${disk}"
}

disk_plan_dualboot() {
    local fs="${FILESYSTEM:-ext4}"
    disk_plan_reset

    einfo "Reusing existing ESP: ${ESP_PARTITION}"

    if [[ -z "${ROOT_PARTITION:-}" ]]; then
        local part_count
        part_count=$(lsblk -lno NAME "${TARGET_DISK}" 2>/dev/null | wc -l)
        local part_prefix="${TARGET_DISK}"
        [[ "${TARGET_DISK}" =~ [0-9]$ ]] && part_prefix="${TARGET_DISK}p"
        ROOT_PARTITION="${part_prefix}${part_count}"
    fi

    case "${fs}" in
        ext4)  disk_plan_add "Format root as ext4"  mkfs.ext4 -L nixos "${ROOT_PARTITION}" ;;
        btrfs) disk_plan_add "Format root as btrfs" mkfs.btrfs -f -L nixos "${ROOT_PARTITION}" ;;
        xfs)   disk_plan_add "Format root as XFS"   mkfs.xfs -f -L nixos "${ROOT_PARTITION}" ;;
    esac

    export ROOT_PARTITION
}

disk_execute_plan() {
    if [[ ${#DISK_ACTIONS[@]} -eq 0 ]]; then
        case "${PARTITION_SCHEME:-auto}" in
            auto)      disk_plan_auto ;;
            dual-boot) disk_plan_dualboot ;;
            manual)    einfo "Manual partitioning — no automated plan"; return 0 ;;
        esac
    fi

    cleanup_target_disk
    disk_plan_show

    local i
    for (( i = 0; i < ${#DISK_ACTIONS[@]}; i++ )); do
        local entry="${DISK_ACTIONS[$i]}"
        local desc="${entry%%|||*}"
        local cmd="${entry#*|||}"
        einfo "[$((i + 1))/${#DISK_ACTIONS[@]}] ${desc}"
        try "${desc}" bash -c "${cmd}"
    done

    if [[ "${DRY_RUN}" != "1" ]]; then
        partprobe "${TARGET_DISK}" 2>/dev/null || true
        sleep 2
    fi
    einfo "All disk operations completed"
}

mount_filesystems() {
    einfo "Mounting filesystems..."
    [[ "${DRY_RUN}" == "1" ]] && { einfo "[DRY-RUN] Would mount"; return 0; }

    mkdir -p "${MOUNTPOINT}"
    local fs="${FILESYSTEM:-ext4}"

    if [[ "${fs}" == "btrfs" ]]; then
        try "Mounting btrfs root" mount "${ROOT_PARTITION}" "${MOUNTPOINT}"
        local IFS=':'
        local -a parts
        if [[ -n "${BTRFS_SUBVOLUMES:-}" ]]; then
            read -ra parts <<< "${BTRFS_SUBVOLUMES}"
            local idx
            for (( idx = 0; idx < ${#parts[@]}; idx += 2 )); do
                local subvol="${parts[$idx]}"
                btrfs subvolume list "${MOUNTPOINT}" 2>/dev/null | grep -q " ${subvol}$" || \
                    try "Creating subvolume ${subvol}" btrfs subvolume create "${MOUNTPOINT}/${subvol}"
            done
        fi
        umount "${MOUNTPOINT}"
        try "Mounting @ subvolume" mount -o subvol=@,compress=zstd,noatime "${ROOT_PARTITION}" "${MOUNTPOINT}"
        if [[ -n "${BTRFS_SUBVOLUMES:-}" ]]; then
            read -ra parts <<< "${BTRFS_SUBVOLUMES}"
            local idx
            for (( idx = 0; idx < ${#parts[@]}; idx += 2 )); do
                local subvol="${parts[$idx]}" mpoint="${parts[$((idx + 1))]}"
                [[ "${subvol}" == "@" ]] && continue
                mkdir -p "${MOUNTPOINT}${mpoint}"
                try "Mounting ${subvol}" mount -o "subvol=${subvol},compress=zstd,noatime" "${ROOT_PARTITION}" "${MOUNTPOINT}${mpoint}"
            done
        fi
    else
        try "Mounting root" mount "${ROOT_PARTITION}" "${MOUNTPOINT}"
    fi

    mkdir -p "${MOUNTPOINT}/boot"
    try "Mounting ESP" mount "${ESP_PARTITION}" "${MOUNTPOINT}/boot"

    [[ "${SWAP_TYPE:-}" == "partition" && -n "${SWAP_PARTITION:-}" ]] && try "Activating swap" swapon "${SWAP_PARTITION}"

    einfo "Filesystems mounted at ${MOUNTPOINT}"
}

unmount_filesystems() {
    einfo "Unmounting filesystems..."
    [[ "${DRY_RUN}" == "1" ]] && { einfo "[DRY-RUN] Would unmount"; return 0; }

    [[ "${SWAP_TYPE:-}" == "partition" && -n "${SWAP_PARTITION:-}" ]] && swapoff "${SWAP_PARTITION}" 2>/dev/null || true

    local -a mounts
    readarray -t mounts < <(mount | grep "${MOUNTPOINT}" | awk '{print $3}' | sort -r)
    local mnt; for mnt in "${mounts[@]}"; do umount -l "${mnt}" 2>/dev/null || true; done

    [[ "${ENCRYPTION:-none}" == "luks" ]] && cryptsetup close cryptroot 2>/dev/null || true

    einfo "Filesystems unmounted"
}

get_uuid()     { blkid -s UUID -o value "$1" 2>/dev/null; }
get_partuuid() { blkid -s PARTUUID -o value "$1" 2>/dev/null; }
