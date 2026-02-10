#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_welcome() {
    dialog_msgbox "Welcome" "Welcome to the ${INSTALLER_NAME} v${INSTALLER_VERSION}

This wizard will guide you through the complete installation
of NixOS with KDE Plasma 6 desktop.

What this installer will do:
  * Detect your hardware (CPU, GPU, disks)
  * Partition and format your disk
  * Generate configuration.nix
  * Run nixos-install
  * Set up KDE Plasma desktop with SDDM

Requirements:
  * Root access
  * UEFI boot mode
  * Working internet connection
  * At least 30 GiB free disk space

Press OK to check prerequisites and continue." || return "${TUI_ABORT}"

    local -a errors=() warnings=()

    is_root || errors+=("Not running as root.")
    is_efi  || errors+=("Not booted in UEFI mode.")
    has_network || warnings+=("No network connectivity detected.")
    command -v nixos-install &>/dev/null || errors+=("nixos-install not found. Are you on a NixOS live ISO?")

    local status_text="Prerequisite Check Results:\n\n"
    is_root 2>/dev/null && status_text+="  [OK] Running as root\n"
    is_efi 2>/dev/null && status_text+="  [OK] UEFI boot mode\n"
    has_network 2>/dev/null && status_text+="  [OK] Network connectivity\n"
    command -v nixos-install &>/dev/null && status_text+="  [OK] nixos-install available\n"
    status_text+="  [OK] Dialog backend: ${DIALOG_CMD:-unknown}\n"

    local w; for w in "${warnings[@]}"; do status_text+="\n  [!!] ${w}\n"; done
    local has_errors=0
    local e; for e in "${errors[@]}"; do status_text+="\n  [FAIL] ${e}\n"; has_errors=1; done

    if [[ ${has_errors} -eq 1 ]]; then
        status_text+="\nCritical errors found."
        dialog_msgbox "Prerequisites — FAILED" "${status_text}"
        [[ "${FORCE:-0}" != "1" ]] && return "${TUI_ABORT}"
        dialog_yesno "Force Mode" "Prerequisites failed but --force is set.\nContinue anyway?" || return "${TUI_ABORT}"
    else
        [[ ${#warnings[@]} -gt 0 ]] && status_text+="\nWarnings found but can proceed."
        dialog_msgbox "Prerequisites — OK" "${status_text}"
    fi

    return "${TUI_NEXT}"
}
