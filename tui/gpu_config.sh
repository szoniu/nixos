#!/usr/bin/env bash
# tui/gpu_config.sh — GPU driver configuration with hybrid GPU support
source "${LIB_DIR}/protection.sh"

screen_gpu_config() {
    local vendor="${GPU_VENDOR:-unknown}"

    # Build info text
    local info=""
    if [[ "${HYBRID_GPU:-no}" == "yes" ]]; then
        info+="Hybrid GPU detected:\n"
        info+="  iGPU: ${IGPU_DEVICE_NAME:-unknown} (${IGPU_VENDOR:-unknown})\n"
        info+="  dGPU: ${DGPU_DEVICE_NAME:-unknown} (${DGPU_VENDOR:-unknown})\n"
        info+="  NixOS will configure PRIME render offload.\n\n"
    else
        info+="Detected GPU: ${GPU_DEVICE_NAME:-unknown}\n"
        info+="Vendor: ${vendor}\n\n"
    fi

    case "${vendor}" in
        nvidia) info+="NixOS will configure NVIDIA proprietary drivers.\n"
                [[ "${GPU_NVIDIA_OPEN:-}" == "yes" ]] && info+="Open kernel module: recommended (Ada+)\n"
                [[ "${GPU_NVIDIA_OPEN:-}" == "supported" ]] && info+="Open kernel module: supported (Turing/Ampere)\n" ;;
        amd)    info+="NixOS will use AMDGPU (open source).\n" ;;
        intel)  info+="NixOS will use Intel graphics.\n" ;;
        *)      info+="No specific GPU detected.\n" ;;
    esac

    dialog_msgbox "GPU Information" "${info}" || true

    # Vendor override
    local choice
    choice=$(dialog_menu "GPU Driver" \
        "auto"   "Use detected driver (${GPU_DRIVER:-auto})" \
        "nvidia" "NVIDIA proprietary" \
        "amdgpu" "AMD open source" \
        "intel"  "Intel open source" \
        "none"   "No GPU driver") || return "${TUI_BACK}"

    case "${choice}" in
        auto)   ;; # keep detected
        nvidia) GPU_VENDOR="nvidia"; GPU_DRIVER="nvidia"
                dialog_yesno "NVIDIA Open" \
                    "Use open-source NVIDIA kernel module?\n(Recommended for RTX 20xx and newer)" \
                    && GPU_NVIDIA_OPEN="yes" || GPU_NVIDIA_OPEN="no" ;;
        amdgpu) GPU_VENDOR="amd"; GPU_DRIVER="amdgpu"; GPU_NVIDIA_OPEN="no" ;;
        intel)  GPU_VENDOR="intel"; GPU_DRIVER="modesetting"; GPU_NVIDIA_OPEN="no" ;;
        none)   GPU_VENDOR="none"; GPU_DRIVER=""; GPU_NVIDIA_OPEN="no" ;;
    esac

    export GPU_VENDOR GPU_DRIVER GPU_NVIDIA_OPEN
    export HYBRID_GPU IGPU_VENDOR IGPU_DEVICE_NAME DGPU_VENDOR DGPU_DEVICE_NAME
    einfo "GPU: ${GPU_VENDOR}, driver: ${GPU_DRIVER}"
    return "${TUI_NEXT}"
}
