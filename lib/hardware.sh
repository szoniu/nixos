#!/usr/bin/env bash
# hardware.sh — Hardware detection: CPU, GPU, disks, ESP/Windows
source "${LIB_DIR}/protection.sh"

detect_cpu() {
    CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}') || CPU_VENDOR="unknown"
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | awk -F': ' '{print $2}') || CPU_MODEL="unknown"
    CPU_CORES=$(nproc 2>/dev/null) || CPU_CORES=4

    # NixOS uses nixpkgs.hostPlatform or hardware.cpu.*.enable
    case "${CPU_VENDOR}" in
        AuthenticAMD) CPU_MARCH="amd" ;;
        GenuineIntel) CPU_MARCH="intel" ;;
        *)            CPU_MARCH="generic" ;;
    esac

    export CPU_VENDOR CPU_MODEL CPU_CORES CPU_MARCH
    einfo "CPU: ${CPU_MODEL} (${CPU_MARCH}, ${CPU_CORES} cores)"
}

detect_gpu() {
    GPU_VENDOR=""
    GPU_DEVICE_ID=""
    GPU_DEVICE_NAME=""
    GPU_DRIVER=""
    VIDEO_CARDS=""

    local gpu_line
    gpu_line=$(lspci -nn 2>/dev/null | grep -i 'vga\|3d\|display' | head -1) || true

    if [[ -z "${gpu_line}" ]]; then
        ewarn "No GPU detected"
        GPU_VENDOR="unknown"
        export GPU_VENDOR GPU_DEVICE_ID GPU_DEVICE_NAME GPU_DRIVER VIDEO_CARDS
        return
    fi

    einfo "GPU: ${gpu_line}"

    local pci_ids
    pci_ids=$(echo "${gpu_line}" | grep -oP '\[\w{4}:\w{4}\]' | tail -1) || true
    local vendor_id
    vendor_id=$(echo "${pci_ids}" | tr -d '[]' | cut -d: -f1)
    GPU_DEVICE_ID=$(echo "${pci_ids}" | tr -d '[]' | cut -d: -f2)
    GPU_DEVICE_NAME=$(echo "${gpu_line}" | sed 's/.*: //')

    case "${vendor_id}" in
        10de)
            GPU_VENDOR="nvidia"
            GPU_DRIVER="nvidia"
            # Check if Turing+ (>=0x1e00) for open kernel module
            local dec_id=$(( 16#${GPU_DEVICE_ID} ))
            if (( dec_id >= 0x2700 )); then
                GPU_NVIDIA_OPEN="yes"  # Ada+
            elif (( dec_id >= 0x1e00 )); then
                GPU_NVIDIA_OPEN="supported"  # Turing/Ampere
            else
                GPU_NVIDIA_OPEN="no"  # Pre-Turing
            fi
            ;;
        1002)
            GPU_VENDOR="amd"
            GPU_DRIVER="amdgpu"
            GPU_NVIDIA_OPEN="no"
            ;;
        8086)
            GPU_VENDOR="intel"
            GPU_DRIVER="modesetting"
            GPU_NVIDIA_OPEN="no"
            ;;
        *)
            GPU_VENDOR="unknown"
            GPU_DRIVER=""
            GPU_NVIDIA_OPEN="no"
            ;;
    esac

    export GPU_VENDOR GPU_DEVICE_ID GPU_DEVICE_NAME GPU_DRIVER GPU_NVIDIA_OPEN
    einfo "GPU: ${GPU_DEVICE_NAME} (${GPU_VENDOR}, driver: ${GPU_DRIVER})"
}

detect_disks() {
    declare -ga AVAILABLE_DISKS=()
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        local name size model tran
        read -r name size model tran <<< "${line}"
        AVAILABLE_DISKS+=("${name}|${size}|${model:-unknown}|${tran:-unknown}")
        einfo "Disk: /dev/${name} — ${size} — ${model:-unknown} (${tran:-unknown})"
    done < <(lsblk -dno NAME,SIZE,MODEL,TRAN 2>/dev/null | grep -v '^loop\|^sr\|^rom\|^ram\|^zram')
    export AVAILABLE_DISKS
}

get_disk_list_for_dialog() {
    local entry
    for entry in "${AVAILABLE_DISKS[@]}"; do
        local name size model tran
        IFS='|' read -r name size model tran <<< "${entry}"
        echo "/dev/${name}"
        echo "${size} ${model} (${tran})"
    done
}

detect_esp() {
    declare -ga ESP_PARTITIONS=()
    WINDOWS_DETECTED=0
    WINDOWS_ESP=""

    while IFS= read -r part; do
        local parttype
        parttype=$(blkid -o value -s PART_ENTRY_TYPE "${part}" 2>/dev/null) || continue
        if [[ "${parttype,,}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]]; then
            ESP_PARTITIONS+=("${part}")
            einfo "Found ESP: ${part}"

            local tmp_mount="/tmp/esp-check-$$"
            mkdir -p "${tmp_mount}"
            if mount -o ro "${part}" "${tmp_mount}" 2>/dev/null; then
                if [[ -d "${tmp_mount}/EFI/Microsoft/Boot" ]]; then
                    WINDOWS_DETECTED=1
                    WINDOWS_ESP="${part}"
                    einfo "Windows Boot Manager found on ${part}"
                fi
                umount "${tmp_mount}" 2>/dev/null
            fi
            rmdir "${tmp_mount}" 2>/dev/null || true
        fi
    done < <(lsblk -lno PATH,FSTYPE 2>/dev/null | awk '$2=="vfat"{print $1}')

    export ESP_PARTITIONS WINDOWS_DETECTED WINDOWS_ESP
}

detect_all_hardware() {
    einfo "=== Hardware Detection ==="
    detect_cpu
    detect_gpu
    detect_disks
    detect_esp
    einfo "=== Hardware Detection Complete ==="
}

get_hardware_summary() {
    local s=""
    s+="CPU: ${CPU_MODEL:-unknown}\n"
    s+="  Vendor: ${CPU_MARCH:-generic}, Cores: ${CPU_CORES:-?}\n\n"
    s+="GPU: ${GPU_DEVICE_NAME:-unknown}\n"
    s+="  Vendor: ${GPU_VENDOR:-unknown}, Driver: ${GPU_DRIVER:-none}\n"
    [[ "${GPU_VENDOR:-}" == "nvidia" ]] && s+="  Open kernel: ${GPU_NVIDIA_OPEN:-no}\n"
    s+="\nDisks:\n"
    local entry
    for entry in "${AVAILABLE_DISKS[@]}"; do
        local name size model tran
        IFS='|' read -r name size model tran <<< "${entry}"
        s+="  /dev/${name}: ${size} ${model} (${tran})\n"
    done
    s+="\n"
    [[ "${WINDOWS_DETECTED:-0}" == "1" ]] && s+="Windows: Detected (ESP: ${WINDOWS_ESP})\n" || s+="Windows: Not detected\n"
    [[ ${#ESP_PARTITIONS[@]} -gt 0 ]] && s+="ESP: ${ESP_PARTITIONS[*]}\n"
    echo -e "${s}"
}
