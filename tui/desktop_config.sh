#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_desktop_config() {
    dialog_msgbox "Desktop" \
        "The following will be installed:\n\n\
  KDE Plasma 6 Desktop\n\
  Display Manager: SDDM (Wayland)\n\
  Audio: PipeWire\n\
  Networking: NetworkManager\n\n\
Select additional applications below." || return "${TUI_ABORT}"

    local extras
    extras=$(dialog_checklist "Applications" \
        "firefox"          "Firefox web browser"        "on" \
        "thunderbird"      "Thunderbird email"          "off" \
        "kdePackages.kate" "Kate text editor"           "on" \
        "kdePackages.kcalc" "Calculator"               "off" \
        "kdePackages.gwenview" "Image viewer"          "on" \
        "kdePackages.okular"   "Document viewer"       "on" \
        "kdePackages.ark"      "Archive manager"       "on" \
        "kdePackages.spectacle" "Screenshot tool"      "on" \
        "vlc"              "VLC media player"           "off" \
        "libreoffice"      "LibreOffice suite"          "off" \
        "gimp"             "GIMP image editor"          "off" \
        "vscode"           "VS Code editor"             "off") || return "${TUI_BACK}"

    DESKTOP_EXTRAS="${extras}"
    export DESKTOP_EXTRAS

    # Extra toggles
    dialog_yesno "Flatpak" "Enable Flatpak support?" && ENABLE_FLATPAK="yes" || ENABLE_FLATPAK="no"
    dialog_yesno "Printing" "Enable printing support (CUPS)?" && ENABLE_PRINTING="yes" || ENABLE_PRINTING="no"
    dialog_yesno "Bluetooth" "Enable Bluetooth support?" && ENABLE_BLUETOOTH="yes" || ENABLE_BLUETOOTH="no"
    export ENABLE_FLATPAK ENABLE_PRINTING ENABLE_BLUETOOTH

    einfo "Desktop extras: ${DESKTOP_EXTRAS}"
    return "${TUI_NEXT}"
}
