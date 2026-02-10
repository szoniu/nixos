#!/usr/bin/env bash
# preset.sh — Export/import presets with hardware overlay
source "${LIB_DIR}/protection.sh"

readonly -a PRESET_HW_VARS=(
    CPU_MARCH CPU_VENDOR CPU_MODEL CPU_CORES
    GPU_VENDOR GPU_DEVICE_ID GPU_DEVICE_NAME GPU_DRIVER GPU_NVIDIA_OPEN
    VIDEO_CARDS TARGET_DISK ESP_PARTITION ROOT_PARTITION SWAP_PARTITION ESP_REUSE LUKS_PARTITION
)

preset_export() {
    local file="$1"
    mkdir -p "$(dirname "${file}")"
    {
        echo "#!/usr/bin/env bash"
        echo "# NixOS TUI Installer Preset"
        echo "# Exported: $(date -Iseconds)"
        echo "# Version: ${INSTALLER_VERSION}"
        echo "#"
        echo "# Hardware-specific (re-detected on import):"
        local hw; for hw in "${PRESET_HW_VARS[@]}"; do
            [[ -n "${!hw+x}" ]] && echo "# ${hw}=${!hw@Q}"
        done
        echo ""
        echo "# --- Portable configuration ---"
        local var; for var in "${CONFIG_VARS[@]}"; do
            local is_hw=0
            local hw2; for hw2 in "${PRESET_HW_VARS[@]}"; do [[ "${var}" == "${hw2}" ]] && { is_hw=1; break; }; done
            [[ ${is_hw} -eq 1 ]] && continue
            [[ -n "${!var+x}" ]] && echo "${var}=${!var@Q}"
        done
    } > "${file}"
    einfo "Preset exported to ${file}"
}

preset_import() {
    local file="$1"
    [[ -f "${file}" ]] || { eerror "Preset not found: ${file}"; return 1; }

    local -A saved_hw=()
    local hw; for hw in "${PRESET_HW_VARS[@]}"; do
        [[ -n "${!hw+x}" ]] && saved_hw["${hw}"]="${!hw}"
    done

    config_load "${file}"

    for hw in "${PRESET_HW_VARS[@]}"; do
        if [[ -n "${saved_hw[${hw}]+x}" ]]; then
            printf -v "${hw}" '%s' "${saved_hw[${hw}]}"
            export "${hw}"
        fi
    done
    einfo "Preset imported from ${file}"
}
