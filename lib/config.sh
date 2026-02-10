#!/usr/bin/env bash
# config.sh — Save/load configuration using ${VAR@Q} quoting
source "${LIB_DIR}/protection.sh"

config_save() {
    local file="${1:-${CONFIG_FILE}}"
    mkdir -p "$(dirname "${file}")"
    {
        echo "#!/usr/bin/env bash"
        echo "# NixOS TUI Installer configuration"
        echo "# Generated: $(date -Iseconds)"
        echo "# Version: ${INSTALLER_VERSION}"
        echo ""
        local var
        for var in "${CONFIG_VARS[@]}"; do
            [[ -n "${!var+x}" ]] && echo "${var}=${!var@Q}"
        done
    } > "${file}"
    einfo "Configuration saved to ${file}"
}

config_load() {
    local file="${1:-${CONFIG_FILE}}"
    [[ -f "${file}" ]] || { eerror "Config not found: ${file}"; return 1; }

    local line_num=0
    while IFS= read -r line; do
        (( line_num++ )) || true
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
        [[ "${line}" =~ ^#! ]] && continue

        local var_name="${line%%=*}"
        var_name="${var_name%%[[:space:]]*}"
        local found=0
        local known_var
        for known_var in "${CONFIG_VARS[@]}"; do
            [[ "${var_name}" == "${known_var}" ]] && { found=1; break; }
        done
        [[ ${found} -eq 0 ]] && { ewarn "Unknown variable at line ${line_num}: ${var_name}"; continue; }
    done < "${file}"

    # shellcheck disable=SC1090
    source "${file}"
    einfo "Configuration loaded from ${file}"
}

config_get() { echo "${!1:-}"; }

config_set() {
    local var="$1" value="$2"
    printf -v "${var}" '%s' "${value}"
    export "${var}"
}

config_dump() {
    local var
    for var in "${CONFIG_VARS[@]}"; do
        [[ -n "${!var+x}" ]] && echo "${var}=${!var@Q}"
    done
}
