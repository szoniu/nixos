#!/usr/bin/env bash
# hardware.sh — Hardware detection: CPU, GPU (hybrid), disks, ESP, OS detection, peripherals
source "${LIB_DIR}/protection.sh"

# --- CPU Detection ---

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

# --- GPU Detection (Multi-GPU / Hybrid) ---

# _classify_gpu_vendor — Classify GPU vendor from PCI vendor ID
# Sets: vendor name, driver recommendation
_classify_gpu_vendor() {
    local vendor_id="$1"
    case "${vendor_id}" in
        "${GPU_VENDOR_NVIDIA}") echo "nvidia" ;;
        "${GPU_VENDOR_AMD}")    echo "amd" ;;
        "${GPU_VENDOR_INTEL}")  echo "intel" ;;
        *)                      echo "unknown" ;;
    esac
}

# detect_gpu — Detect all GPUs, classify iGPU/dGPU for hybrid setups
detect_gpu() {
    GPU_VENDOR=""
    GPU_DEVICE_ID=""
    GPU_DEVICE_NAME=""
    GPU_DRIVER=""
    GPU_NVIDIA_OPEN="no"
    HYBRID_GPU="no"
    IGPU_VENDOR=""
    IGPU_DEVICE_NAME=""
    DGPU_VENDOR=""
    DGPU_DEVICE_NAME=""
    IGPU_BUS_ID=""
    DGPU_BUS_ID=""

    # Collect all GPU lines
    local -a gpu_lines=()
    while IFS= read -r line; do
        [[ -n "${line}" ]] && gpu_lines+=("${line}")
    done < <(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' || true)

    if [[ ${#gpu_lines[@]} -eq 0 ]]; then
        ewarn "No GPU detected"
        GPU_VENDOR="unknown"
        export GPU_VENDOR GPU_DEVICE_ID GPU_DEVICE_NAME GPU_DRIVER GPU_NVIDIA_OPEN VIDEO_CARDS
        export HYBRID_GPU IGPU_VENDOR IGPU_DEVICE_NAME DGPU_VENDOR DGPU_DEVICE_NAME
        return
    fi

    if [[ ${#gpu_lines[@]} -eq 1 ]]; then
        # Single GPU
        _parse_single_gpu "${gpu_lines[0]}"
    else
        # Multiple GPUs — classify as hybrid
        _parse_hybrid_gpu "${gpu_lines[@]}"
    fi

    export GPU_VENDOR GPU_DEVICE_ID GPU_DEVICE_NAME GPU_DRIVER GPU_NVIDIA_OPEN
    export HYBRID_GPU IGPU_VENDOR IGPU_DEVICE_NAME DGPU_VENDOR DGPU_DEVICE_NAME
    export IGPU_BUS_ID DGPU_BUS_ID
}

# _parse_single_gpu — Parse a single GPU line
_parse_single_gpu() {
    local gpu_line="$1"

    einfo "GPU: ${gpu_line}"

    # Extract PCI IDs — use sed instead of grep -oP (PCRE not available everywhere)
    local pci_ids
    pci_ids=$(echo "${gpu_line}" | sed -n 's/.*\[\([0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\)\].*/\1/p' | tail -1) || true
    local vendor_id="${pci_ids%%:*}"
    GPU_DEVICE_ID="${pci_ids#*:}"
    GPU_DEVICE_NAME=$(echo "${gpu_line}" | sed 's/.*: //')

    GPU_VENDOR=$(_classify_gpu_vendor "${vendor_id}")

    case "${GPU_VENDOR}" in
        nvidia)
            GPU_DRIVER="nvidia"
            # Check for open kernel module support
            local dec_id=$(( 16#${GPU_DEVICE_ID} ))
            if (( dec_id >= 0x2700 )); then
                GPU_NVIDIA_OPEN="yes"  # Ada+
            elif (( dec_id >= 0x1e00 )); then
                GPU_NVIDIA_OPEN="supported"  # Turing/Ampere
            else
                GPU_NVIDIA_OPEN="no"  # Pre-Turing
            fi
            ;;
        amd)
            GPU_DRIVER="amdgpu"
            ;;
        intel)
            GPU_DRIVER="modesetting"
            ;;
        *)
            GPU_DRIVER=""
            ;;
    esac

    einfo "GPU: ${GPU_DEVICE_NAME} (${GPU_VENDOR}, driver: ${GPU_DRIVER})"
}

# _parse_hybrid_gpu — Parse multiple GPU lines for hybrid setup
_parse_hybrid_gpu() {
    local -a lines=("$@")

    einfo "Multiple GPUs detected (${#lines[@]}), classifying..."

    # Classify each GPU
    local -a vendors=() names=() device_ids=() buses=()
    local gpu_line
    for gpu_line in "${lines[@]}"; do
        einfo "GPU: ${gpu_line}"

        local pci_ids
        pci_ids=$(echo "${gpu_line}" | sed -n 's/.*\[\([0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\)\].*/\1/p' | tail -1) || true
        local vendor_id="${pci_ids%%:*}"
        local dev_id="${pci_ids#*:}"
        local dev_name
        dev_name=$(echo "${gpu_line}" | sed 's/.*: //')

        # Extract PCI bus number for iGPU/dGPU heuristic
        local bus_num
        bus_num=$(echo "${gpu_line}" | sed -n 's/^\([0-9a-fA-F]\{2\}\):.*/\1/p') || true

        vendors+=("$(_classify_gpu_vendor "${vendor_id}")")
        names+=("${dev_name}")
        device_ids+=("${dev_id}")
        buses+=("${bus_num}")
    done

    # Classify iGPU vs dGPU
    # Rules: NVIDIA = always dGPU; Intel = always iGPU
    # AMD: if paired with NVIDIA → iGPU, otherwise → look at PCI bus
    local igpu_idx=-1 dgpu_idx=-1
    local i
    for (( i = 0; i < ${#vendors[@]}; i++ )); do
        case "${vendors[i]}" in
            intel)
                igpu_idx=${i}
                ;;
            nvidia)
                dgpu_idx=${i}
                ;;
            amd)
                # AMD can be either — check if paired with NVIDIA
                local has_nvidia=0 j
                for (( j = 0; j < ${#vendors[@]}; j++ )); do
                    [[ "${vendors[j]}" == "nvidia" ]] && has_nvidia=1
                done
                if [[ ${has_nvidia} -eq 1 ]]; then
                    igpu_idx=${i}  # AMD iGPU + NVIDIA dGPU
                else
                    # AMD + AMD or AMD + Intel — use PCI bus heuristic
                    local bus_dec=$(( 16#${buses[i]:-0} ))
                    if (( bus_dec == 0 )); then
                        igpu_idx=${i}  # Bus 00 = on-die
                    else
                        dgpu_idx=${i}  # Higher bus = PCIe
                    fi
                fi
                ;;
        esac
    done

    # Fallback: if we couldn't classify, use first=iGPU, second=dGPU
    if [[ ${igpu_idx} -eq -1 && ${dgpu_idx} -eq -1 ]]; then
        igpu_idx=0; dgpu_idx=1
    elif [[ ${igpu_idx} -eq -1 ]]; then
        # Find first non-dGPU
        for (( i = 0; i < ${#vendors[@]}; i++ )); do
            [[ ${i} -ne ${dgpu_idx} ]] && { igpu_idx=${i}; break; }
        done
    elif [[ ${dgpu_idx} -eq -1 ]]; then
        for (( i = 0; i < ${#vendors[@]}; i++ )); do
            [[ ${i} -ne ${igpu_idx} ]] && { dgpu_idx=${i}; break; }
        done
    fi

    if [[ ${igpu_idx} -ge 0 && ${dgpu_idx} -ge 0 ]]; then
        HYBRID_GPU="yes"
        IGPU_VENDOR="${vendors[igpu_idx]}"
        IGPU_DEVICE_NAME="${names[igpu_idx]}"
        DGPU_VENDOR="${vendors[dgpu_idx]}"
        DGPU_DEVICE_NAME="${names[dgpu_idx]}"

        # Extract PCI bus IDs in NixOS format (PCI:bus:slot:func)
        local igpu_pci dgpu_pci
        igpu_pci=$(echo "${lines[igpu_idx]}" | sed -n 's/^\([0-9a-fA-F:\.]*\) .*/\1/p') || true
        dgpu_pci=$(echo "${lines[dgpu_idx]}" | sed -n 's/^\([0-9a-fA-F:\.]*\) .*/\1/p') || true
        # Convert "XX:YY.Z" to "PCI:X:Y:Z" (decimal)
        if [[ "${igpu_pci}" =~ ^([0-9a-fA-F]+):([0-9a-fA-F]+)\.([0-9a-fA-F]+)$ ]]; then
            IGPU_BUS_ID="PCI:$(( 16#${BASH_REMATCH[1]} )):$(( 16#${BASH_REMATCH[2]} )):$(( 16#${BASH_REMATCH[3]} ))"
        fi
        if [[ "${dgpu_pci}" =~ ^([0-9a-fA-F]+):([0-9a-fA-F]+)\.([0-9a-fA-F]+)$ ]]; then
            DGPU_BUS_ID="PCI:$(( 16#${BASH_REMATCH[1]} )):$(( 16#${BASH_REMATCH[2]} )):$(( 16#${BASH_REMATCH[3]} ))"
        fi

        # Primary GPU vendor = dGPU vendor (for driver selection)
        GPU_VENDOR="${DGPU_VENDOR}"
        GPU_DEVICE_ID="${device_ids[dgpu_idx]}"
        GPU_DEVICE_NAME="${DGPU_DEVICE_NAME}"

        case "${GPU_VENDOR}" in
            nvidia)
                GPU_DRIVER="nvidia"
                local dec_id=$(( 16#${GPU_DEVICE_ID} ))
                if (( dec_id >= 0x2700 )); then
                    GPU_NVIDIA_OPEN="yes"
                elif (( dec_id >= 0x1e00 )); then
                    GPU_NVIDIA_OPEN="supported"
                else
                    GPU_NVIDIA_OPEN="no"
                fi
                ;;
            amd) GPU_DRIVER="amdgpu" ;;
            *)   GPU_DRIVER="modesetting" ;;
        esac

        einfo "Hybrid GPU: ${IGPU_VENDOR} iGPU + ${DGPU_VENDOR} dGPU"
    else
        # Couldn't determine hybrid — treat first as single
        _parse_single_gpu "${lines[0]}"
    fi
}

# --- ASUS ROG Detection ---

detect_asus_rog() {
    ASUS_ROG_DETECTED=0

    local board_vendor="" product_name=""
    if [[ -f /sys/class/dmi/id/board_vendor ]]; then
        board_vendor=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null) || true
    fi
    if [[ -f /sys/class/dmi/id/product_name ]]; then
        product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null) || true
    fi

    if [[ "${board_vendor}" == *"ASUSTeK"* ]] && [[ "${product_name}" =~ (ROG|TUF) ]]; then
        ASUS_ROG_DETECTED=1
        einfo "ASUS ROG/TUF hardware detected: ${product_name}"
    fi

    export ASUS_ROG_DETECTED
}

# --- Peripheral Detection ---

detect_bluetooth() {
    BLUETOOTH_DETECTED=0
    if [[ -d /sys/class/bluetooth ]] && ls /sys/class/bluetooth/hci* &>/dev/null 2>&1; then
        BLUETOOTH_DETECTED=1
        einfo "Bluetooth hardware detected"
    fi
    export BLUETOOTH_DETECTED
}

detect_fingerprint() {
    FINGERPRINT_DETECTED=0
    if ! command -v lsusb &>/dev/null; then
        export FINGERPRINT_DETECTED; return 0
    fi
    local lsusb_out
    lsusb_out=$(lsusb 2>/dev/null) || true
    # 06cb=Synaptics, 27c6=Goodix, 147e=AuthenTec, 138a=Validity
    if echo "${lsusb_out}" | grep -qiE '06cb:|27c6:|147e:|138a:'; then
        FINGERPRINT_DETECTED=1
        einfo "Fingerprint reader detected"
    # 04f3=Elan (ambivalent — touchpads and fingerprint — look for "fingerprint" in description)
    elif echo "${lsusb_out}" | grep -qi '04f3:' && echo "${lsusb_out}" | grep -qi 'fingerprint\|fprint'; then
        FINGERPRINT_DETECTED=1
        einfo "Fingerprint reader detected (Elan)"
    fi
    export FINGERPRINT_DETECTED
}

detect_thunderbolt() {
    THUNDERBOLT_DETECTED=0
    if [[ -d /sys/bus/thunderbolt/devices ]] && ls /sys/bus/thunderbolt/devices/[0-9]* &>/dev/null 2>&1; then
        THUNDERBOLT_DETECTED=1
        einfo "Thunderbolt controller detected"
    elif lspci -nn 2>/dev/null | grep -qi 'thunderbolt\|USB4'; then
        THUNDERBOLT_DETECTED=1
        einfo "Thunderbolt controller detected (lspci)"
    fi
    export THUNDERBOLT_DETECTED
}

detect_sensors() {
    SENSORS_DETECTED=0
    if [[ -d /sys/bus/iio/devices ]]; then
        local dev
        for dev in /sys/bus/iio/devices/iio:device*; do
            [[ -d "${dev}" ]] || continue
            local dev_name
            dev_name=$(cat "${dev}/name" 2>/dev/null) || continue
            case "${dev_name}" in
                *accel*|*gyro*|*als*|*light*|*incli*)
                    SENSORS_DETECTED=1; einfo "IIO sensor detected: ${dev_name}"; break ;;
            esac
        done
    fi
    export SENSORS_DETECTED
}

detect_webcam() {
    WEBCAM_DETECTED=0
    if [[ -d /sys/class/video4linux ]]; then
        local dev
        for dev in /sys/class/video4linux/video*; do
            [[ -d "${dev}" ]] || continue
            local dev_name
            dev_name=$(cat "${dev}/name" 2>/dev/null) || true
            if [[ -n "${dev_name}" ]]; then
                WEBCAM_DETECTED=1; einfo "Webcam detected: ${dev_name}"; break
            fi
        done
    fi
    export WEBCAM_DETECTED
}

detect_wwan() {
    WWAN_DETECTED=0
    if lspci -nnd 8086:7360 2>/dev/null | grep -q .; then
        WWAN_DETECTED=1
        einfo "WWAN modem detected: Intel XMM7360 LTE Advanced"
    fi
    export WWAN_DETECTED
}

# --- Disk Detection ---

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

    if [[ ${#AVAILABLE_DISKS[@]} -eq 0 ]]; then
        ewarn "No suitable disks detected"
    fi
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

# --- ESP Detection ---

detect_esp() {
    declare -ga ESP_PARTITIONS=()
    WINDOWS_DETECTED="${WINDOWS_DETECTED:-0}"
    WINDOWS_ESP=""

    # Use lsblk PARTTYPE to find EFI System Partitions
    local part parttype
    while IFS=' ' read -r part parttype; do
        [[ -z "${part}" || -z "${parttype}" ]] && continue
        if [[ "${parttype,,}" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]]; then
            ESP_PARTITIONS+=("${part}")
            einfo "Found ESP: ${part}"

            # Check for Windows Boot Manager
            local tmp_mount
            tmp_mount=$(mktemp -d /tmp/esp-check-XXXXXX)
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
    done < <(lsblk -lno PATH,PARTTYPE 2>/dev/null)

    export ESP_PARTITIONS WINDOWS_DETECTED WINDOWS_ESP
}

# --- Installed OS Detection ---

detect_installed_oses() {
    declare -gA DETECTED_OSES=()
    LINUX_DETECTED=0

    einfo "Scanning for installed operating systems..."

    local part fstype
    while IFS=' ' read -r part fstype; do
        [[ -z "${part}" || -z "${fstype}" ]] && continue

        # Skip ESP partitions
        local esp
        for esp in "${ESP_PARTITIONS[@]}"; do
            [[ "${part}" == "${esp}" ]] && continue 2
        done

        case "${fstype}" in
            ext4|xfs)
                _detect_linux_on_partition "${part}" "${fstype}" ""
                ;;
            btrfs)
                _detect_linux_on_partition "${part}" "${fstype}" ""
                if [[ -z "${DETECTED_OSES[${part}]:-}" ]]; then
                    _detect_linux_on_partition "${part}" "${fstype}" "@"
                fi
                ;;
            ntfs)
                _detect_ntfs_on_partition "${part}"
                ;;
        esac
    done < <(lsblk -lno PATH,FSTYPE 2>/dev/null | awk '$2 != "" {print}')

    export LINUX_DETECTED DETECTED_OSES

    if [[ ${#DETECTED_OSES[@]} -gt 0 ]]; then
        local p
        for p in "${!DETECTED_OSES[@]}"; do
            einfo "Detected OS: ${p} -> ${DETECTED_OSES[${p}]}"
        done
    else
        einfo "No other operating systems detected"
    fi

    serialize_detected_oses
}

_detect_linux_on_partition() {
    local part="$1" fstype="$2" subvol="${3:-}"

    local existing_mount
    existing_mount=$(findmnt -n -o TARGET "${part}" 2>/dev/null | head -1) || true

    local tmp_mount="" needs_umount=0
    if [[ -n "${existing_mount}" ]]; then
        tmp_mount="${existing_mount}"
    else
        tmp_mount="/tmp/os-detect-$$"
        mkdir -p "${tmp_mount}"

        local mount_opts="-o ro"
        [[ -n "${subvol}" ]] && mount_opts="-o ro,subvol=${subvol}"

        if ! mount ${mount_opts} "${part}" "${tmp_mount}" 2>/dev/null; then
            rmdir "${tmp_mount}" 2>/dev/null || true
            return
        fi
        needs_umount=1
    fi

    if [[ -f "${tmp_mount}/etc/os-release" ]]; then
        local pretty_name
        pretty_name=$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "${tmp_mount}/etc/os-release" | head -1) || true
        if [[ -n "${pretty_name}" ]]; then
            DETECTED_OSES["${part}"]="${pretty_name}"
            LINUX_DETECTED=1
        fi
    fi

    if [[ "${needs_umount}" -eq 1 ]]; then
        umount "${tmp_mount}" 2>/dev/null || true
        rmdir "${tmp_mount}" 2>/dev/null || true
    fi
}

_detect_ntfs_on_partition() {
    local part="$1"

    local existing_mount
    existing_mount=$(findmnt -n -o TARGET "${part}" 2>/dev/null | head -1) || true

    local tmp_mount="" needs_umount=0
    if [[ -n "${existing_mount}" ]]; then
        tmp_mount="${existing_mount}"
    else
        tmp_mount="/tmp/os-detect-$$"
        mkdir -p "${tmp_mount}"

        if ! mount -o ro "${part}" "${tmp_mount}" 2>/dev/null; then
            rmdir "${tmp_mount}" 2>/dev/null || true
            return
        fi
        needs_umount=1
    fi

    if [[ -d "${tmp_mount}/Windows/System32" ]]; then
        DETECTED_OSES["${part}"]="Windows (system)"
        WINDOWS_DETECTED=1
        export WINDOWS_DETECTED
    fi

    if [[ "${needs_umount}" -eq 1 ]]; then
        umount "${tmp_mount}" 2>/dev/null || true
        rmdir "${tmp_mount}" 2>/dev/null || true
    fi
}

# --- OS Serialization ---

serialize_detected_oses() {
    local result="" part
    for part in "${!DETECTED_OSES[@]}"; do
        local name="${DETECTED_OSES[${part}]}"
        name="${name//|/-}"
        name="${name//=/-}"
        [[ -n "${result}" ]] && result+="|"
        result+="${part}=${name}"
    done
    DETECTED_OSES_SERIALIZED="${result}"
    export DETECTED_OSES_SERIALIZED
}

deserialize_detected_oses() {
    declare -gA DETECTED_OSES=()
    WINDOWS_DETECTED="${WINDOWS_DETECTED:-0}"
    LINUX_DETECTED="${LINUX_DETECTED:-0}"

    local serialized="${DETECTED_OSES_SERIALIZED:-}"
    [[ -z "${serialized}" ]] && return 0

    local IFS='|'
    local entry
    for entry in ${serialized}; do
        local part="${entry%%=*}"
        local name="${entry#*=}"
        [[ -z "${part}" || -z "${name}" ]] && continue
        DETECTED_OSES["${part}"]="${name}"

        if [[ "${name}" == *"Windows"* ]]; then
            WINDOWS_DETECTED=1
        else
            LINUX_DETECTED=1
        fi
    done

    export DETECTED_OSES WINDOWS_DETECTED LINUX_DETECTED
}

# --- Full Detection ---

detect_all_hardware() {
    einfo "=== Hardware Detection ==="
    detect_cpu
    detect_gpu
    detect_asus_rog
    detect_bluetooth
    detect_fingerprint
    detect_thunderbolt
    detect_sensors
    detect_webcam
    detect_wwan
    detect_disks
    detect_esp
    detect_installed_oses
    einfo "=== Hardware Detection Complete ==="
}

get_hardware_summary() {
    local s=""
    s+="CPU: ${CPU_MODEL:-unknown}\n"
    s+="  Vendor: ${CPU_MARCH:-generic}, Cores: ${CPU_CORES:-?}\n\n"

    if [[ "${HYBRID_GPU:-no}" == "yes" ]]; then
        s+="GPU: Hybrid (iGPU + dGPU)\n"
        s+="  iGPU: ${IGPU_DEVICE_NAME:-unknown} (${IGPU_VENDOR:-unknown})\n"
        s+="  dGPU: ${DGPU_DEVICE_NAME:-unknown} (${DGPU_VENDOR:-unknown})\n"
    else
        s+="GPU: ${GPU_DEVICE_NAME:-unknown}\n"
        s+="  Vendor: ${GPU_VENDOR:-unknown}, Driver: ${GPU_DRIVER:-none}\n"
    fi
    [[ "${GPU_VENDOR:-}" == "nvidia" ]] && s+="  Open kernel: ${GPU_NVIDIA_OPEN:-no}\n"
    [[ "${ASUS_ROG_DETECTED:-0}" == "1" ]] && s+="  ASUS ROG/TUF: detected\n"
    [[ "${BLUETOOTH_DETECTED:-0}" == "1" ]] && s+="  Bluetooth: detected\n"
    [[ "${FINGERPRINT_DETECTED:-0}" == "1" ]] && s+="  Fingerprint reader: detected\n"
    [[ "${THUNDERBOLT_DETECTED:-0}" == "1" ]] && s+="  Thunderbolt: detected\n"
    [[ "${SENSORS_DETECTED:-0}" == "1" ]] && s+="  IIO sensors: detected (2-in-1)\n"
    [[ "${WEBCAM_DETECTED:-0}" == "1" ]] && s+="  Webcam: detected\n"
    [[ "${WWAN_DETECTED:-0}" == "1" ]] && s+="  WWAN LTE: Intel XMM7360 detected\n"
    s+="\n"
    s+="Disks:\n"
    local entry
    for entry in "${AVAILABLE_DISKS[@]}"; do
        local name size model tran
        IFS='|' read -r name size model tran <<< "${entry}"
        s+="  /dev/${name}: ${size} ${model} (${tran})\n"
    done
    s+="\n"
    [[ ${#ESP_PARTITIONS[@]} -gt 0 ]] && s+="ESP: ${ESP_PARTITIONS[*]}\n"
    if [[ ${#DETECTED_OSES[@]} -gt 0 ]]; then
        s+="Detected operating systems:\n"
        local p
        for p in "${!DETECTED_OSES[@]}"; do
            s+="  ${p}: ${DETECTED_OSES[${p}]}\n"
        done
    else
        s+="Detected operating systems: none\n"
    fi
    echo -e "${s}"
}
