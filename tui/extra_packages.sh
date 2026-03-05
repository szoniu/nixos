#!/usr/bin/env bash
# tui/extra_packages.sh — Extra packages + conditional hardware items
source "${LIB_DIR}/protection.sh"

screen_extra_packages() {
    # Build checklist items
    local -a items=()

    # Standard extras
    items+=("fastfetch"    "System info tool"           "off")
    items+=("btop"         "Resource monitor"           "off")
    items+=("kitty"        "GPU-accelerated terminal"   "off")
    items+=("neovim"       "Text editor"                "off")
    items+=("tmux"         "Terminal multiplexer"       "off")
    items+=("ripgrep"      "Fast text search"           "off")
    items+=("fd"           "Fast file finder"           "off")
    items+=("bat"          "Cat with syntax highlight"  "off")
    items+=("v4l-utils"    "Video4Linux utilities"      "off")

    # Conditional hardware items (visible only when hardware detected)
    if [[ "${FINGERPRINT_DETECTED:-0}" == "1" ]]; then
        items+=("fprintd" "Fingerprint reader support" "off")
    fi
    if [[ "${THUNDERBOLT_DETECTED:-0}" == "1" ]]; then
        items+=("bolt" "Thunderbolt device manager" "off")
    fi
    if [[ "${SENSORS_DETECTED:-0}" == "1" ]]; then
        items+=("iio-sensor-proxy" "IIO sensor proxy (2-in-1)" "off")
    fi
    if [[ "${WWAN_DETECTED:-0}" == "1" ]]; then
        items+=("modemmanager" "WWAN/LTE modem support" "off")
    fi

    # Services toggles
    items+=("flatpak"   "Flatpak app store"   "$( [[ "${ENABLE_FLATPAK:-no}" == "yes" ]] && echo "on" || echo "off" )")
    items+=("printing"  "CUPS printing"       "$( [[ "${ENABLE_PRINTING:-no}" == "yes" ]] && echo "on" || echo "off" )")
    items+=("bluetooth" "Bluetooth support"   "$( [[ "${ENABLE_BLUETOOTH:-no}" == "yes" || "${BLUETOOTH_DETECTED:-0}" == "1" ]] && echo "on" || echo "off" )")

    local selected
    selected=$(dialog_checklist "Extra Packages & Services" "${items[@]}") \
        || return "${TUI_BACK}"

    # Parse selections
    ENABLE_FLATPAK="no"
    ENABLE_PRINTING="no"
    ENABLE_BLUETOOTH="no"
    ENABLE_FINGERPRINT="no"
    ENABLE_THUNDERBOLT="no"
    ENABLE_SENSORS="no"
    ENABLE_WWAN="no"
    local -a extra_pkgs=()

    local pkg
    for pkg in ${selected}; do
        case "${pkg}" in
            flatpak)           ENABLE_FLATPAK="yes" ;;
            printing)          ENABLE_PRINTING="yes" ;;
            bluetooth)         ENABLE_BLUETOOTH="yes" ;;
            fprintd)           ENABLE_FINGERPRINT="yes" ;;
            bolt)              ENABLE_THUNDERBOLT="yes" ;;
            iio-sensor-proxy)  ENABLE_SENSORS="yes" ;;
            modemmanager)      ENABLE_WWAN="yes" ;;
            *)                 extra_pkgs+=("${pkg}") ;;
        esac
    done

    # Free-form extra packages input
    local more_pkgs
    more_pkgs=$(dialog_inputbox "Additional Packages" \
        "Additional nix packages (space-separated).\n\n\
Examples: neovim tmux ripgrep fd bat\n\n\
Leave empty to skip:" \
        "${EXTRA_PACKAGES:-}") || true

    # Merge
    local all_extras="${extra_pkgs[*]}"
    [[ -n "${more_pkgs}" ]] && all_extras+=" ${more_pkgs}"
    EXTRA_PACKAGES="${all_extras## }"

    export ENABLE_FLATPAK ENABLE_PRINTING ENABLE_BLUETOOTH
    export ENABLE_FINGERPRINT ENABLE_THUNDERBOLT ENABLE_SENSORS ENABLE_WWAN
    export EXTRA_PACKAGES

    einfo "Extras: flatpak=${ENABLE_FLATPAK}, printing=${ENABLE_PRINTING}, bluetooth=${ENABLE_BLUETOOTH}"
    [[ "${ENABLE_FINGERPRINT}" == "yes" ]] && einfo "Fingerprint: enabled"
    [[ "${ENABLE_THUNDERBOLT}" == "yes" ]] && einfo "Thunderbolt: enabled"
    [[ "${ENABLE_SENSORS}" == "yes" ]] && einfo "IIO sensors: enabled"
    [[ "${ENABLE_WWAN}" == "yes" ]] && einfo "WWAN/LTE: enabled"
    [[ -n "${EXTRA_PACKAGES}" ]] && einfo "Extra packages: ${EXTRA_PACKAGES}"
    return "${TUI_NEXT}"
}
