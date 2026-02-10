#!/usr/bin/env bash
# hooks.sh — Hook system: maybe_exec 'before_X' / 'after_X'
source "${LIB_DIR}/protection.sh"

HOOKS_DIR="${HOOKS_DIR:-${SCRIPT_DIR}/hooks}"

maybe_exec() {
    local hook_name="$1"
    local hook_file="${HOOKS_DIR}/${hook_name}.sh"
    local hook_dir="${HOOKS_DIR}/${hook_name}"

    if [[ -f "${hook_file}" && -x "${hook_file}" ]]; then
        einfo "Running hook: ${hook_name}"
        "${hook_file}" || ewarn "Hook failed: ${hook_name} (continuing)"
        return 0
    fi

    if [[ -d "${hook_dir}" ]]; then
        local f; for f in "${hook_dir}"/*.sh; do
            [[ -f "${f}" && -x "${f}" ]] || continue
            einfo "Running hook: ${hook_name}/$(basename "${f}")"
            "${f}" || ewarn "Hook failed: ${hook_name}/$(basename "${f}") (continuing)"
        done
        return 0
    fi
    return 0
}
