#!/usr/bin/env bash
# dialog.sh — Dialog/whiptail wrapper, navigation stack, wizard runner
source "${LIB_DIR}/protection.sh"

_detect_dialog_backend() {
    if command -v dialog &>/dev/null; then
        DIALOG_CMD="dialog"
    elif command -v whiptail &>/dev/null; then
        DIALOG_CMD="whiptail"
    else
        die "Neither dialog nor whiptail found."
    fi
    export DIALOG_CMD
}

readonly DIALOG_HEIGHT=22
readonly DIALOG_WIDTH=76
readonly DIALOG_LIST_HEIGHT=14

init_dialog() {
    _detect_dialog_backend
    einfo "Using dialog backend: ${DIALOG_CMD}"
}

# --- Primitives ---

dialog_msgbox() {
    local title="$1" text="$2"
    "${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
        --title "${title}" --msgbox "${text}" "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}"
}

dialog_yesno() {
    local title="$1" text="$2"
    "${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
        --title "${title}" --yesno "${text}" "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}"
}

dialog_inputbox() {
    local title="$1" text="$2" default="${3:-}"
    local result
    if [[ "${DIALOG_CMD}" == "dialog" ]]; then
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --inputbox "${text}" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" "${default}" 2>&1 >/dev/tty) || return $?
    else
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --inputbox "${text}" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" "${default}" 3>&1 1>&2 2>&3) || return $?
    fi
    echo "${result}"
}

dialog_passwordbox() {
    local title="$1" text="$2"
    local result
    if [[ "${DIALOG_CMD}" == "dialog" ]]; then
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --insecure --passwordbox "${text}" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" 2>&1 >/dev/tty) || return $?
    else
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --passwordbox "${text}" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" 3>&1 1>&2 2>&3) || return $?
    fi
    echo "${result}"
}

dialog_menu() {
    local title="$1"; shift
    local result
    if [[ "${DIALOG_CMD}" == "dialog" ]]; then
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --menu "Choose an option:" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" "${DIALOG_LIST_HEIGHT}" "$@" 2>&1 >/dev/tty) || return $?
    else
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --menu "Choose an option:" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" "${DIALOG_LIST_HEIGHT}" "$@" 3>&1 1>&2 2>&3) || return $?
    fi
    echo "${result}"
}

dialog_radiolist() {
    local title="$1"; shift
    local result
    if [[ "${DIALOG_CMD}" == "dialog" ]]; then
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --radiolist "Select one:" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" "${DIALOG_LIST_HEIGHT}" "$@" 2>&1 >/dev/tty) || return $?
    else
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --radiolist "Select one:" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" "${DIALOG_LIST_HEIGHT}" "$@" 3>&1 1>&2 2>&3) || return $?
    fi
    echo "${result}"
}

dialog_checklist() {
    local title="$1"; shift
    local result
    if [[ "${DIALOG_CMD}" == "dialog" ]]; then
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --checklist "Select items:" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" "${DIALOG_LIST_HEIGHT}" "$@" 2>&1 >/dev/tty) || return $?
    else
        result=$("${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
            --title "${title}" --checklist "Select items:" \
            "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}" "${DIALOG_LIST_HEIGHT}" "$@" 3>&1 1>&2 2>&3) || return $?
    fi
    echo "${result}"
}

dialog_gauge() {
    local title="$1" text="$2" percent="${3:-0}"
    "${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
        --title "${title}" --gauge "${text}" 8 "${DIALOG_WIDTH}" "${percent}"
}

dialog_textbox() {
    local title="$1" file="$2"
    "${DIALOG_CMD}" --backtitle "${INSTALLER_NAME} v${INSTALLER_VERSION}" \
        --title "${title}" --textbox "${file}" "${DIALOG_HEIGHT}" "${DIALOG_WIDTH}"
}

# --- Wizard navigation ---

declare -a _WIZARD_SCREENS=()
_WIZARD_INDEX=0

register_wizard_screens() { _WIZARD_SCREENS=("$@"); _WIZARD_INDEX=0; }

run_wizard() {
    local total=${#_WIZARD_SCREENS[@]}
    [[ ${total} -eq 0 ]] && die "No wizard screens registered"

    while (( _WIZARD_INDEX < total )); do
        local screen_func="${_WIZARD_SCREENS[${_WIZARD_INDEX}]}"
        elog "Wizard screen ${_WIZARD_INDEX}/${total}: ${screen_func}"

        local rc=0
        "${screen_func}" || rc=$?

        case ${rc} in
            0) (( _WIZARD_INDEX++ )) || true ;;
            1) if (( _WIZARD_INDEX > 0 )); then (( _WIZARD_INDEX-- )) || true; else ewarn "Already at first screen"; fi ;;
            2) dialog_yesno "Abort Installation" "Are you sure you want to abort?" && die "Aborted by user" ;;
            *) eerror "Unknown return code ${rc} from ${screen_func}" ;;
        esac
    done
    einfo "Wizard completed"
}
