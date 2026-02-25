#!/usr/bin/env bash
# utils.sh — Utility functions: try (interactive recovery), countdown, dependency checks
source "${LIB_DIR}/protection.sh"

# try — Execute a command with interactive recovery on failure
# LIVE_OUTPUT=1 → show output on terminal via tee (for long-running phases)
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

        local exit_code=0
        if [[ "${LIVE_OUTPUT:-0}" == "1" ]]; then
            "$@" 2>&1 | tee -a "${LOG_FILE}" || exit_code=$?
        else
            "$@" >> "${LOG_FILE}" 2>&1 || exit_code=$?
        fi

        if [[ ${exit_code} -eq 0 ]]; then
            einfo "Success: ${desc}"
            return 0
        fi
        eerror "Failed (exit ${exit_code}): ${desc}"

        if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
            die "Non-interactive mode — aborting on failure: ${desc}"
        fi

        # Restore stderr for dialog UI if redirected (fd 4 saved by screen_progress)
        local _stderr_redirected=0
        if { true >&4; } 2>/dev/null; then
            exec 2>&4
            _stderr_redirected=1
        fi

        local choice

        if command -v "${DIALOG_CMD:-dialog}" &>/dev/null; then
            choice=$(dialog_menu "Command Failed: ${desc}" \
                "retry"    "Retry the command" \
                "shell"    "Drop to a shell (type 'exit' to return)" \
                "continue" "Skip this step and continue" \
                "log"      "View last 50 lines of log" \
                "abort"    "Abort installation") || choice="abort"
        else
            echo "" >&2
            echo "=== FAILED: ${desc} ===" >&2
            echo "  (r)etry  | (s)hell  | (c)ontinue  | (a)bort" >&2
            local _reply=""
            read -r -p "Choice [r/s/c/a]: " _reply < /dev/tty || _reply="a"
            case "${_reply}" in
                r*) choice="retry" ;;
                s*) choice="shell" ;;
                c*) choice="continue" ;;
                *)  choice="abort" ;;
            esac
        fi

        case "${choice}" in
            retry)
                [[ ${_stderr_redirected} -eq 1 ]] && exec 2>>"${LOG_FILE}"
                continue
                ;;
            shell)
                PS1="(nixos-installer rescue) \w \$ " bash --norc --noprofile || true
                [[ ${_stderr_redirected} -eq 1 ]] && exec 2>>"${LOG_FILE}"
                continue
                ;;
            continue)
                ewarn "Skipping: ${desc}"
                [[ ${_stderr_redirected} -eq 1 ]] && exec 2>>"${LOG_FILE}"
                return 0
                ;;
            log)
                dialog_textbox "Log Output" "${LOG_FILE}" || true
                [[ ${_stderr_redirected} -eq 1 ]] && exec 2>>"${LOG_FILE}"
                continue
                ;;
            abort)
                die "Aborted by user after failure: ${desc}"
                ;;
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

# checkpoint_validate — Check if a checkpoint's artifact actually exists
checkpoint_validate() {
    local name="$1"
    case "${name}" in
        preflight)
            return 1 ;;  # always re-run
        disks)
            [[ -b "${ROOT_PARTITION:-}" ]] && mountpoint -q "${MOUNTPOINT}" 2>/dev/null ;;
        nixos_generate)
            [[ -f "${MOUNTPOINT}/etc/nixos/hardware-configuration.nix" ]] ;;
        nixos_config)
            [[ -f "${MOUNTPOINT}/etc/nixos/configuration.nix" ]] ;;
        nixos_install)
            [[ -f "${MOUNTPOINT}/etc/NIXOS" ]] ;;
        *)
            return 0 ;;
    esac
}

# checkpoint_migrate_to_target — Move checkpoints from /tmp to target disk
checkpoint_migrate_to_target() {
    local target_dir="${MOUNTPOINT}${CHECKPOINT_DIR_SUFFIX}"
    [[ "${CHECKPOINT_DIR}" == "${target_dir}" ]] && return 0
    mkdir -p "${target_dir}"
    [[ -d "${CHECKPOINT_DIR}" ]] && cp -a "${CHECKPOINT_DIR}/"* "${target_dir}/" 2>/dev/null || true
    rm -rf "${CHECKPOINT_DIR}"
    CHECKPOINT_DIR="${target_dir}"
    export CHECKPOINT_DIR
}

# cleanup_target_disk — Unmount partitions and deactivate swap before partitioning
cleanup_target_disk() {
    local disk="${TARGET_DISK:-}"
    [[ -z "${disk}" ]] && return 0
    [[ "${DRY_RUN:-0}" == "1" ]] && { einfo "[DRY-RUN] Would cleanup ${disk}"; return 0; }

    einfo "Cleaning up ${disk} before partitioning..."

    local swap_dev
    while IFS=' ' read -r swap_dev _; do
        [[ "${swap_dev}" == "${disk}"* ]] || continue
        ewarn "Deactivating swap on ${swap_dev}"
        swapoff "${swap_dev}" 2>/dev/null || true
    done < <(awk 'NR>1 {print $1}' /proc/swaps 2>/dev/null || true)

    local mnt_dev mnt_point
    while IFS=' ' read -r mnt_dev mnt_point _; do
        [[ "${mnt_dev}" == "${disk}"* ]] || continue
        ewarn "Unmounting ${mnt_point} (${mnt_dev})"
        umount -l "${mnt_point}" 2>/dev/null || true
    done < <(awk '{print $1, $2}' /proc/mounts 2>/dev/null | sort -k2 -r || true)

    if command -v cryptsetup &>/dev/null && [[ -b /dev/mapper/cryptroot ]]; then
        local backing
        backing=$(cryptsetup status cryptroot 2>/dev/null | awk '/device:/ {print $2}') || true
        if [[ "${backing}" == "${disk}"* ]]; then
            ewarn "Closing LUKS on cryptroot"
            cryptsetup close cryptroot 2>/dev/null || true
        fi
    fi
}

# --- Resume from disk ---

RESUME_FOUND_PARTITION=""
RESUME_FOUND_FSTYPE=""
RESUME_HAS_CONFIG=0

_scan_partition_for_resume() {
    local part="$1" fstype="$2"
    _SCAN_HAS_CHECKPOINTS=0
    _SCAN_HAS_CONFIG=0
    _SCAN_MOUNTPOINT=""

    if [[ -n "${_RESUME_TEST_DIR:-}" ]]; then
        local fake_mp="${_RESUME_TEST_DIR}/mnt/${part##*/}"
        if [[ -d "${fake_mp}${CHECKPOINT_DIR_SUFFIX}" ]] && ls "${fake_mp}${CHECKPOINT_DIR_SUFFIX}/"* &>/dev/null 2>&1; then
            _SCAN_HAS_CHECKPOINTS=1
            _SCAN_MOUNTPOINT="${fake_mp}"
        fi
        [[ -f "${fake_mp}/tmp/nixos-installer.conf" ]] && _SCAN_HAS_CONFIG=1
        return 0
    fi

    if findmnt -rn -S "${part}" &>/dev/null; then
        local existing_mp
        existing_mp=$(findmnt -rn -o TARGET -S "${part}" | head -1) || true
        if [[ -n "${existing_mp}" ]]; then
            if [[ -d "${existing_mp}${CHECKPOINT_DIR_SUFFIX}" ]] && ls "${existing_mp}${CHECKPOINT_DIR_SUFFIX}/"* &>/dev/null 2>&1; then
                _SCAN_HAS_CHECKPOINTS=1
                _SCAN_MOUNTPOINT="${existing_mp}"
            fi
            [[ -f "${existing_mp}/tmp/nixos-installer.conf" ]] && _SCAN_HAS_CONFIG=1
            return 0
        fi
    fi

    local mp
    mp=$(mktemp -d "${TMPDIR:-/tmp}/nixos-resume-scan.XXXXXX")
    local mounted=0
    if mount -o ro "${part}" "${mp}" 2>/dev/null; then
        mounted=1
    elif [[ "${fstype}" == "btrfs" ]]; then
        mount -o ro,subvol=@ "${part}" "${mp}" 2>/dev/null && mounted=1
    fi

    if [[ ${mounted} -eq 1 ]]; then
        if [[ -d "${mp}${CHECKPOINT_DIR_SUFFIX}" ]] && ls "${mp}${CHECKPOINT_DIR_SUFFIX}/"* &>/dev/null 2>&1; then
            _SCAN_HAS_CHECKPOINTS=1
        fi
        [[ -f "${mp}/tmp/nixos-installer.conf" ]] && _SCAN_HAS_CONFIG=1
        umount "${mp}" 2>/dev/null || true
    fi
    rmdir "${mp}" 2>/dev/null || true
    return 0
}

_recover_resume_data() {
    local part="$1" fstype="$2"

    if [[ -n "${_RESUME_TEST_DIR:-}" ]]; then
        local fake_mp="${_RESUME_TEST_DIR}/mnt/${part##*/}"
        mkdir -p "${CHECKPOINT_DIR}"
        cp -a "${fake_mp}${CHECKPOINT_DIR_SUFFIX}/"* "${CHECKPOINT_DIR}/" 2>/dev/null || true
        if [[ -f "${fake_mp}/tmp/nixos-installer.conf" ]]; then
            (umask 077; cp "${fake_mp}/tmp/nixos-installer.conf" "${CONFIG_FILE}")
        fi
        return 0
    fi

    local mp
    mp=$(mktemp -d "${TMPDIR:-/tmp}/nixos-resume-recover.XXXXXX")
    local mounted=0

    if findmnt -rn -S "${part}" &>/dev/null; then
        local existing_mp
        existing_mp=$(findmnt -rn -o TARGET -S "${part}" | head -1) || true
        [[ -n "${existing_mp}" ]] && { mp="${existing_mp}"; mounted=2; }
    fi

    if [[ ${mounted} -eq 0 ]]; then
        if mount -o ro "${part}" "${mp}" 2>/dev/null; then
            mounted=1
        elif [[ "${fstype}" == "btrfs" ]]; then
            mount -o ro,subvol=@ "${part}" "${mp}" 2>/dev/null && mounted=1
        fi
    fi

    if [[ ${mounted} -gt 0 ]]; then
        mkdir -p "${CHECKPOINT_DIR}"
        cp -a "${mp}${CHECKPOINT_DIR_SUFFIX}/"* "${CHECKPOINT_DIR}/" 2>/dev/null || true
        einfo "Recovered checkpoints from ${part}"
        if [[ -f "${mp}/tmp/nixos-installer.conf" ]]; then
            (umask 077; cp "${mp}/tmp/nixos-installer.conf" "${CONFIG_FILE}")
            einfo "Recovered config from ${part}"
        fi
        [[ ${mounted} -eq 1 ]] && umount "${mp}" 2>/dev/null || true
    fi
    [[ ${mounted} -ne 2 ]] && rmdir "${mp}" 2>/dev/null || true
    return 0
}

# try_resume_from_disk — Returns: 0=config+checkpoints, 1=only checkpoints, 2=nothing
try_resume_from_disk() {
    RESUME_FOUND_PARTITION=""
    RESUME_HAS_CONFIG=0
    einfo "Scanning partitions for previous installation data..."

    local found_part="" found_fstype="" found_config=0

    if [[ -n "${_RESUME_TEST_DIR:-}" ]]; then
        local part fstype
        while IFS=' ' read -r part fstype; do
            [[ -z "${part}" || -z "${fstype}" ]] && continue
            case "${fstype}" in ext4|ext3|xfs|btrfs) ;; *) continue ;; esac
            _scan_partition_for_resume "${part}" "${fstype}"
            if [[ ${_SCAN_HAS_CHECKPOINTS} -eq 1 ]]; then
                found_part="${part}"; found_fstype="${fstype}"; found_config=${_SCAN_HAS_CONFIG}; break
            fi
        done < "${_RESUME_TEST_DIR}/partitions.list"
    else
        local part fstype
        while IFS=' ' read -r part fstype; do
            [[ -z "${part}" || -z "${fstype}" ]] && continue
            case "${fstype}" in ext4|ext3|xfs|btrfs) ;; *) continue ;; esac
            _scan_partition_for_resume "${part}" "${fstype}"
            if [[ ${_SCAN_HAS_CHECKPOINTS} -eq 1 ]]; then
                found_part="${part}"; found_fstype="${fstype}"; found_config=${_SCAN_HAS_CONFIG}; break
            fi
        done < <(lsblk -lno PATH,FSTYPE 2>/dev/null || true)
    fi

    if [[ -z "${found_part}" ]]; then
        ewarn "No previous installation data found on any partition"
        return 2
    fi

    einfo "Found resume data on ${found_part} (${found_fstype})"
    RESUME_FOUND_PARTITION="${found_part}"
    RESUME_FOUND_FSTYPE="${found_fstype}"
    export RESUME_FOUND_PARTITION RESUME_FOUND_FSTYPE
    _recover_resume_data "${found_part}" "${found_fstype}"

    if [[ ${found_config} -eq 1 ]]; then
        RESUME_HAS_CONFIG=1; export RESUME_HAS_CONFIG
        einfo "Resume: config + checkpoints recovered from ${found_part}"
        return 0
    else
        RESUME_HAS_CONFIG=0; export RESUME_HAS_CONFIG
        ewarn "Resume: checkpoints recovered but no config found on ${found_part}"
        return 1
    fi
}

# --- Config inference ---

_partition_to_disk() {
    local part="$1"
    if [[ "${part}" =~ ^(/dev/nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then echo "${BASH_REMATCH[1]}"
    elif [[ "${part}" =~ ^(/dev/mmcblk[0-9]+)p[0-9]+$ ]]; then echo "${BASH_REMATCH[1]}"
    elif [[ "${part}" =~ ^(/dev/[a-z]+)[0-9]+$ ]]; then echo "${BASH_REMATCH[1]}"
    else echo "${part}"; fi
}

_resolve_uuid() {
    local uuid="$1"
    if [[ -n "${_INFER_UUID_MAP:-}" && -f "${_INFER_UUID_MAP}" ]]; then
        sed -n "s/^${uuid} //p" "${_INFER_UUID_MAP}" || true
    else
        blkid -U "${uuid}" 2>/dev/null || true
    fi
}

_infer_from_fstab() {
    local mp="$1" fstab="${mp}/etc/fstab"
    [[ -f "${fstab}" ]] || return 0
    local line dev mpoint fstype opts rest
    while IFS= read -r line; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*$ ]] && continue
        read -r dev mpoint fstype opts rest <<< "${line}" || true
        [[ -z "${dev}" || -z "${mpoint}" ]] && continue
        if [[ "${dev}" =~ ^UUID=(.+)$ ]]; then
            local resolved; resolved=$(_resolve_uuid "${BASH_REMATCH[1]}")
            [[ -n "${resolved}" ]] && dev="${resolved}"
        fi
        case "${mpoint}" in
            /)
                [[ -n "${dev}" && ! "${dev}" =~ ^UUID= ]] && { ROOT_PARTITION="${dev}"; export ROOT_PARTITION; }
                case "${fstype}" in
                    ext4|xfs) FILESYSTEM="${fstype}"; export FILESYSTEM ;;
                    btrfs) FILESYSTEM="btrfs"; export FILESYSTEM
                        [[ "${opts}" =~ subvol= ]] && { BTRFS_SUBVOLUMES="yes"; export BTRFS_SUBVOLUMES; } ;;
                esac ;;
            /boot/efi|/boot|/efi)
                [[ "${fstype}" == "vfat" && -n "${dev}" && ! "${dev}" =~ ^UUID= ]] && { ESP_PARTITION="${dev}"; export ESP_PARTITION; } ;;
        esac
        if [[ "${fstype}" == "swap" && -n "${dev}" && ! "${dev}" =~ ^UUID= ]]; then
            SWAP_PARTITION="${dev}"; SWAP_TYPE="partition"; export SWAP_PARTITION SWAP_TYPE
        fi
    done < "${fstab}"
}

_infer_from_hostname() {
    local mp="$1"
    if [[ -f "${mp}/etc/hostname" ]]; then
        local h; h=$(sed -n '/^[[:space:]]*$/d; /^[[:space:]]*#/d; p; q' "${mp}/etc/hostname") || true
        h="${h%%[[:space:]]*}"
        [[ -n "${h}" ]] && { HOSTNAME="${h}"; export HOSTNAME; }
    fi
}

_infer_from_timezone() {
    local mp="$1"
    if [[ -L "${mp}/etc/localtime" ]]; then
        local target; target=$(readlink "${mp}/etc/localtime" 2>/dev/null) || true
        [[ "${target}" == *zoneinfo/* ]] && { TIMEZONE="${target#*zoneinfo/}"; export TIMEZONE; return 0; }
    fi
}

_infer_from_keymap() {
    local mp="$1"
    if [[ -f "${mp}/etc/vconsole.conf" ]]; then
        local km; km=$(sed -n "s/^KEYMAP=[\"']*\([^\"']*\).*/\1/p; T; q" "${mp}/etc/vconsole.conf") || true
        [[ -n "${km}" ]] && { KEYMAP="${km}"; export KEYMAP; }
    fi
}

_infer_encryption() {
    local mp="$1"
    if [[ -f "${mp}/etc/crypttab" ]]; then
        local line
        while IFS= read -r line; do
            [[ "${line}" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line}" || "${line}" =~ ^[[:space:]]*$ ]] && continue
            ENCRYPTION="luks"; export ENCRYPTION; return 0
        done < "${mp}/etc/crypttab"
    fi
}

_infer_partition_scheme() {
    local esp_disk="" root_disk=""
    [[ -n "${ESP_PARTITION:-}" ]] && esp_disk=$(_partition_to_disk "${ESP_PARTITION}")
    [[ -n "${TARGET_DISK:-}" ]] && root_disk="${TARGET_DISK}"
    if [[ -n "${esp_disk}" && -n "${root_disk}" && "${esp_disk}" != "${root_disk}" ]]; then
        PARTITION_SCHEME="dual-boot"; ESP_REUSE="yes"; export PARTITION_SCHEME ESP_REUSE
    else
        PARTITION_SCHEME="auto"; export PARTITION_SCHEME
    fi
}

_infer_sufficient_config() {
    [[ -n "${ROOT_PARTITION:-}" ]] || return 1
    [[ -n "${ESP_PARTITION:-}" ]] || return 1
    [[ -n "${FILESYSTEM:-}" ]] || return 1
    [[ -n "${TARGET_DISK:-}" ]] || return 1
    return 0
}

# infer_config_from_partition — Returns: 0=sufficient, 1=insufficient
infer_config_from_partition() {
    local part="$1" fstype="$2" mp="" need_unmount=0

    ROOT_PARTITION="${part}"; FILESYSTEM="${fstype}"; TARGET_DISK=$(_partition_to_disk "${part}")
    export ROOT_PARTITION FILESYSTEM TARGET_DISK

    if [[ -n "${_RESUME_TEST_DIR:-}" ]]; then
        mp="${_RESUME_TEST_DIR}/mnt/${part##*/}"
    else
        if findmnt -rn -S "${part}" &>/dev/null; then
            mp=$(findmnt -rn -o TARGET -S "${part}" | head -1) || true
        fi
        if [[ -z "${mp}" ]]; then
            mp=$(mktemp -d "${TMPDIR:-/tmp}/nixos-infer.XXXXXX")
            if mount -o ro "${part}" "${mp}" 2>/dev/null; then need_unmount=1
            elif [[ "${fstype}" == "btrfs" ]]; then
                mount -o ro,subvol=@ "${part}" "${mp}" 2>/dev/null && need_unmount=1
            fi
        fi
    fi

    _infer_from_fstab "${mp}"
    _infer_from_hostname "${mp}"
    _infer_from_timezone "${mp}"
    _infer_from_keymap "${mp}"
    _infer_encryption "${mp}"
    _infer_partition_scheme

    if [[ ${need_unmount} -eq 1 ]]; then
        umount "${mp}" 2>/dev/null || true; rmdir "${mp}" 2>/dev/null || true
    elif [[ -z "${_RESUME_TEST_DIR:-}" && -d "${mp}" ]]; then
        rmdir "${mp}" 2>/dev/null || true
    fi

    if _infer_sufficient_config; then
        einfo "Config inference: sufficient configuration inferred from ${part}"; return 0
    else
        ewarn "Config inference: insufficient data from ${part}"; return 1
    fi
}

get_cpu_count() { nproc 2>/dev/null || echo 4; }
