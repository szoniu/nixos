#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_desktop_config() {
    local desktop="${DESKTOP_TYPE:-kde}"

    if [[ "${desktop}" == "gnome" ]]; then
        _desktop_config_gnome
    else
        _desktop_config_kde
    fi
}

_desktop_config_kde() {
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

    einfo "Desktop extras: ${DESKTOP_EXTRAS}"
    return "${TUI_NEXT}"
}

_desktop_config_gnome() {
    dialog_msgbox "Desktop" \
        "The following will be installed:\n\n\
  GNOME Desktop\n\
  Display Manager: GDM (Wayland)\n\
  Audio: PipeWire\n\
  Networking: NetworkManager\n\n\
Select additional applications below." || return "${TUI_ABORT}"

    local extras
    extras=$(dialog_checklist "Applications" \
        "gnome-tweaks"     "GNOME Tweaks"               "on" \
        "gnome-calendar"   "Calendar"                   "off" \
        "gnome-weather"    "Weather"                    "off" \
        "gnome-maps"       "Maps"                       "off" \
        "gnome-boxes"      "Virtual machines"           "off" \
        "firefox"          "Firefox web browser"        "on" \
        "vlc"              "VLC media player"           "off" \
        "libreoffice"      "LibreOffice suite"          "off" \
        "gimp"             "GIMP image editor"          "off" \
        "vscode"           "VS Code editor"             "off") || return "${TUI_BACK}"

    DESKTOP_EXTRAS="${extras}"
    export DESKTOP_EXTRAS

    einfo "Desktop extras: ${DESKTOP_EXTRAS}"
    return "${TUI_NEXT}"
}
