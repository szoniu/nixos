#!/usr/bin/env bash
# utils.sh — Utility functions: try (interactive recovery), countdown, dependency checks
source "${LIB_DIR}/protection.sh"

# try — Execute a command with interactive recovery on failure
try() {
    local desc="$1"
    shift

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        einfo "[DRY-RUN] Would execute: $*"
        return 0
    fi

    while true; do
        einfo "Running: ${desc}"
        elog "Command: $*"

        if "$@" >> "${LOG_FILE}" 2>&1; then
            einfo "Success: ${desc}"
            return 0
        fi

        local exit_code=$?
        eerror "Failed (exit ${exit_code}): ${desc}"

        if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
            die "Non-interactive mode — aborting on failure: ${desc}"
        fi

        local choice
        choice=$(dialog_menu "Command Failed: ${desc}" \
            "retry"    "Retry the command" \
            "shell"    "Drop to a shell (type 'exit' to return)" \
            "continue" "Skip this step and continue" \
            "log"      "View last 50 lines of log" \
            "abort"    "Abort installation") || choice="abort"

        case "${choice}" in
            retry)    continue ;;
            shell)    PS1="(nixos-installer rescue) \w \$ " bash --norc --noprofile || true; continue ;;
            continue) ewarn "Skipping: ${desc}"; return 0 ;;
            log)      dialog_textbox "Log Output" "${LOG_FILE}" || true; continue ;;
            abort)    die "Aborted by user after failure: ${desc}" ;;
        esac
    done
}

countdown() {
    local seconds="${1:-${COUNTDOWN_DEFAULT}}"
    local msg="${2:-Continuing in}"
    [[ "${NON_INTERACTIVE:-0}" == "1" ]] && return 0
    local i
    for ((i = seconds; i > 0; i--)); do
        printf "\r%s %d seconds... " "${msg}" "${i}" >&2
        sleep 1
    done
    printf "\r%s\n" "$(printf '%-60s' '')" >&2
}

check_dependencies() {
    local -a missing=()
    local -a required_deps=(bash parted mount umount blkid lsblk nixos-install nixos-generate-config)

    local dep
    for dep in "${required_deps[@]}"; do
        command -v "${dep}" &>/dev/null || missing+=("${dep}")
    done

    if ! command -v dialog &>/dev/null && ! command -v whiptail &>/dev/null; then
        missing+=("dialog|whiptail")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        eerror "Missing required dependencies:"
        local m; for m in "${missing[@]}"; do eerror "  - ${m}"; done
        return 1
    fi

    einfo "All dependencies satisfied"
    return 0
}

is_efi()      { [[ -d /sys/firmware/efi ]]; }
is_root()     { [[ "$(id -u)" -eq 0 ]]; }
has_network() { ping -c 1 -W 3 nixos.org &>/dev/null || ping -c 1 -W 3 cache.nixos.org &>/dev/null; }

checkpoint_set()     { mkdir -p "${CHECKPOINT_DIR}"; touch "${CHECKPOINT_DIR}/$1"; einfo "Checkpoint set: $1"; }
checkpoint_reached() { [[ -f "${CHECKPOINT_DIR}/$1" ]]; }
checkpoint_clear()   { rm -rf "${CHECKPOINT_DIR}"; einfo "All checkpoints cleared"; }

get_cpu_count() { nproc 2>/dev/null || echo 4; }
