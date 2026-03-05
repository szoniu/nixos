#!/usr/bin/env bash
# gpu_database.sh — GPU driver recommendations for NixOS
# NixOS supports both proprietary NVIDIA and open-source drivers.
source "${LIB_DIR}/protection.sh"

# nvidia_generation — Determine NVIDIA GPU generation from PCI device ID
# Returns: ada, ampere, turing, pascal, maxwell, kepler, or unknown
nvidia_generation() {
    local device_id="$1"
    local dec_id=$(( 16#${device_id} ))

    if (( dec_id >= 0x2900 )); then
        echo "blackwell"
    elif (( dec_id >= 0x2700 )); then
        echo "ada"
    elif (( dec_id >= 0x2200 )); then
        echo "ampere"
    elif (( dec_id >= 0x1e00 )); then
        echo "turing"
    elif (( dec_id >= 0x1580 )); then
        echo "pascal"
    elif (( dec_id >= 0x1340 )); then
        echo "maxwell"
    elif (( dec_id >= 0x0fc0 )); then
        echo "kepler"
    else
        echo "unknown"
    fi
}

# get_gpu_recommendation — Get NixOS GPU driver recommendation
# Args: vendor device_id
# Prints recommended nix config driver
get_gpu_recommendation() {
    local vendor="$1" device_id="${2:-}"

    case "${vendor}" in
        nvidia)
            echo "nvidia"
            ;;
        amd)
            echo "amdgpu"
            ;;
        intel)
            echo "modesetting"
            ;;
        *)
            echo ""
            ;;
    esac
}

# get_hybrid_gpu_recommendation — Get NixOS nix config for hybrid GPU
# Args: igpu_vendor dgpu_vendor
# Prints recommended videoDrivers list
get_hybrid_gpu_recommendation() {
    local igpu="$1" dgpu="$2"

    # NixOS handles hybrid GPU via PRIME
    case "${dgpu}" in
        nvidia)
            # NVIDIA PRIME offload
            echo "nvidia"
            ;;
        amd)
            # AMD + AMD hybrid is rare but possible
            echo "amdgpu"
            ;;
        *)
            echo "modesetting"
            ;;
    esac
}

# get_nvidia_open_recommendation — Should we use NVIDIA open kernel module?
# Args: device_id
# Prints: yes (Ada+ — recommended), supported (Turing/Ampere), no (pre-Turing)
get_nvidia_open_recommendation() {
    local device_id="${1:-}"
    [[ -z "${device_id}" ]] && { echo "no"; return; }

    local gen
    gen=$(nvidia_generation "${device_id}")

    case "${gen}" in
        blackwell|ada) echo "yes" ;;       # Blackwell/Ada+ — recommended
        ampere|turing) echo "supported" ;; # Supported but not default
        *)             echo "no" ;;        # Not supported
    esac
}
