#!/usr/bin/env bash
# disk.sh — Two-phase disk operations (plan -> execute), UUID persistence, shrink helpers
source "${LIB_DIR}/protection.sh"

declare -ga DISK_ACTIONS=()

disk_plan_reset() { DISK_ACTIONS=(); }

disk_plan_add() {
    local desc="$1"; shift
    local cmd
    cmd=$(printf '%q ' "$@")
    DISK_ACTIONS+=("${desc}|||${cmd}")
}

disk_plan_show() {
    einfo "Planned disk operations:"
    local i
    for (( i = 0; i < ${#DISK_ACTIONS[@]}; i++ )); do
        einfo "  $((i + 1)). ${DISK_ACTIONS[$i]%%|||*}"
    done
}

_plan_luks_setup() {
    local part="$1"
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        disk_plan_add "Setup LUKS encryption on ${part}" \
            bash -c "echo '[DRY-RUN] Would setup LUKS on ${part}'"
        return 0
    fi
    local current_type
    current_type=$(blkid -s TYPE -o value "${part}" 2>/dev/null) || true
    if [[ "${current_type}" == "crypto_LUKS" ]]; then
        einfo "Partition ${part} already has LUKS — skipping luksFormat"
        disk_plan_add "Open existing LUKS partition ${part}" \
            bash -c "if [ -b /dev/mapper/cryptroot ]; then echo 'LUKS already open'; else cryptsetup open '${part}' cryptroot; fi"
    else
        disk_plan_add "Setup LUKS encryption on ${part}" \
            cryptsetup luksFormat --type luks2 "${part}"
        disk_plan_add "Open LUKS partition" \
            cryptsetup open "${part}" cryptroot
    fi
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

    if [[ "${ENCRYPTION:-none}" == "luks" ]]; then
        LUKS_PARTITION="${ROOT_PARTITION}"
        _plan_luks_setup "${ROOT_PARTITION}"
        ROOT_PARTITION="/dev/mapper/cryptroot"
    fi

    case "${fs}" in
        ext4)  disk_plan_add "Format root as ext4"  mkfs.ext4 -L nixos "${ROOT_PARTITION}" ;;
        btrfs) disk_plan_add "Format root as btrfs" mkfs.btrfs -f -L nixos "${ROOT_PARTITION}" ;;
        xfs)   disk_plan_add "Format root as XFS"   mkfs.xfs -f -L nixos "${ROOT_PARTITION}" ;;
    esac

    export ESP_PARTITION ROOT_PARTITION SWAP_PARTITION LUKS_PARTITION
    einfo "Auto-partition plan generated for ${disk}"
}

disk_plan_dualboot() {
    local fs="${FILESYSTEM:-ext4}"
    disk_plan_reset

    einfo "Reusing existing ESP: ${ESP_PARTITION}"

    # Shrink step (if configured)
    if [[ -n "${SHRINK_PARTITION:-}" ]]; then
        disk_plan_shrink
    fi

    if [[ -z "${ROOT_PARTITION:-}" ]]; then
        local part_prefix="${TARGET_DISK}"
        [[ "${TARGET_DISK}" =~ [0-9]$ ]] && part_prefix="${TARGET_DISK}p"

        # Count existing partitions to determine new partition number
        local existing_parts
        existing_parts=$(lsblk -lno NAME "${TARGET_DISK}" 2>/dev/null | grep -cv "^$(basename "${TARGET_DISK}")$") || existing_parts=0
        local new_part_num=$(( existing_parts + 1 ))
        ROOT_PARTITION="${part_prefix}${new_part_num}"

        # Find free space start: end of last partition
        local free_start
        free_start=$(parted -s "${TARGET_DISK}" unit MiB print free 2>/dev/null \
            | awk '/Free Space/ {start=$1} END {print start}') || free_start=""
        : "${free_start:=0MiB}"

        disk_plan_add "Create NixOS root partition (${new_part_num})" \
            parted -s "${TARGET_DISK}" mkpart "Linux filesystem" "${free_start}" "100%"
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

# --- Shrink helpers ---

# disk_get_free_space_mib — Get free (unpartitioned) space on a disk
disk_get_free_space_mib() {
    local disk="$1"

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        echo "0"
        return 0
    fi

    local total_free=0
    local size_str
    while IFS= read -r size_str; do
        [[ -z "${size_str}" ]] && continue
        local mib="${size_str%%MiB*}"
        mib="${mib%%.*}"
        [[ "${mib}" =~ ^[0-9]+$ ]] && (( total_free += mib )) || true
    done < <(parted -s "${disk}" unit MiB print free 2>/dev/null | awk '/Free Space/ {print $3}' || true)

    echo "${total_free}"
}

# disk_get_partition_size_mib — Get size of a partition in MiB
disk_get_partition_size_mib() {
    local part="$1"
    local size_bytes
    size_bytes=$(lsblk -bno SIZE "${part}" 2>/dev/null | head -1) || true
    [[ -z "${size_bytes}" ]] && { echo "0"; return; }
    echo "$(( size_bytes / 1048576 ))"
}

# disk_get_partition_used_mib — Get used space on a partition
disk_get_partition_used_mib() {
    local part="$1" fstype="$2"

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        echo "0"
        return 0
    fi

    case "${fstype}" in
        ntfs)
            if command -v ntfsresize &>/dev/null; then
                local min_bytes
                min_bytes=$(ntfsresize --info --force --no-progress-bar "${part}" 2>/dev/null \
                    | grep -i 'resize at' | sed 's/.*: *//; s/ bytes.*//' | tr -d ' ') || true
                if [[ -n "${min_bytes}" && "${min_bytes}" =~ ^[0-9]+$ ]]; then
                    echo "$(( min_bytes / 1048576 ))"
                    return
                fi
            fi
            echo "0"
            ;;
        ext4)
            if command -v dumpe2fs &>/dev/null; then
                local block_size free_blocks block_count
                local dump_out
                dump_out=$(dumpe2fs -h "${part}" 2>/dev/null) || true
                block_size=$(echo "${dump_out}" | sed -n 's/^Block size: *//p') || true
                block_count=$(echo "${dump_out}" | sed -n 's/^Block count: *//p') || true
                free_blocks=$(echo "${dump_out}" | sed -n 's/^Free blocks: *//p') || true
                if [[ -n "${block_size}" && -n "${block_count}" && -n "${free_blocks}" ]]; then
                    local used_blocks=$(( block_count - free_blocks ))
                    echo "$(( used_blocks * block_size / 1048576 ))"
                    return
                fi
            fi
            echo "0"
            ;;
        btrfs)
            local tmp_mp
            tmp_mp=$(mktemp -d /tmp/btrfs-check-XXXXXX)
            if mount -o ro "${part}" "${tmp_mp}" 2>/dev/null; then
                local used_bytes
                used_bytes=$(btrfs filesystem usage -b "${tmp_mp}" 2>/dev/null \
                    | sed -n 's/.*Used: *//p' | head -1) || true
                umount "${tmp_mp}" 2>/dev/null || true
                rmdir "${tmp_mp}" 2>/dev/null || true
                if [[ -n "${used_bytes}" && "${used_bytes}" =~ ^[0-9]+$ ]]; then
                    echo "$(( used_bytes / 1048576 ))"
                    return
                fi
            fi
            rmdir "${tmp_mp}" 2>/dev/null || true
            echo "0"
            ;;
        *)
            echo "0"
            ;;
    esac
}

# disk_can_shrink_fstype — Check if a filesystem type supports shrinking
disk_can_shrink_fstype() {
    local fstype="$1"
    case "${fstype}" in
        ntfs|ext4|btrfs) return 0 ;;
        *) return 1 ;;
    esac
}

# disk_plan_shrink — Add shrink operations to the disk plan
# Uses parted resizepart (NixOS installer uses parted)
disk_plan_shrink() {
    local part="${SHRINK_PARTITION}"
    local fstype="${SHRINK_PARTITION_FSTYPE}"
    local new_size_mib="${SHRINK_NEW_SIZE_MIB}"

    einfo "Planning shrink: ${part} (${fstype}) -> ${new_size_mib} MiB"

    # Step 1: Shrink the filesystem
    case "${fstype}" in
        ntfs)
            disk_plan_add "Shrink NTFS filesystem on ${part}" \
                ntfsresize --force --no-progress-bar --size "${new_size_mib}M" "${part}"
            ;;
        ext4)
            disk_plan_add "Check ext4 filesystem on ${part}" \
                e2fsck -f -y "${part}"
            disk_plan_add "Shrink ext4 filesystem on ${part}" \
                resize2fs "${part}" "${new_size_mib}M"
            ;;
        btrfs)
            disk_plan_add "Shrink btrfs filesystem on ${part}" \
                bash -c "tmp=\$(mktemp -d /tmp/btrfs-shrink-XXXXXX) && mount '${part}' \"\${tmp}\" && btrfs filesystem resize '${new_size_mib}m' \"\${tmp}\"; umount \"\${tmp}\"; rmdir \"\${tmp}\""
            ;;
    esac

    # Step 2: Shrink the partition (parted resizepart)
    local disk="${TARGET_DISK}"
    local part_num
    part_num=$(echo "${part}" | sed 's/.*[^0-9]//')

    disk_plan_add "Resize partition ${part} to ${new_size_mib} MiB" \
        parted -s "${disk}" resizepart "${part_num}" "${new_size_mib}MiB"
}
