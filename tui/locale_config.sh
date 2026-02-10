#!/usr/bin/env bash
source "${LIB_DIR}/protection.sh"

screen_locale_config() {
    local tz
    tz=$(dialog_inputbox "Timezone" "Enter timezone (e.g., Europe/Warsaw):" "${TIMEZONE:-Europe/Warsaw}") || return "${TUI_BACK}"
    TIMEZONE="${tz}"; export TIMEZONE

    local locale_choice
    locale_choice=$(dialog_menu "System Locale" \
        "en_US.UTF-8" "English (US)" \
        "en_GB.UTF-8" "English (UK)" \
        "de_DE.UTF-8" "German" \
        "fr_FR.UTF-8" "French" \
        "es_ES.UTF-8" "Spanish" \
        "pl_PL.UTF-8" "Polish" \
        "pt_BR.UTF-8" "Portuguese (Brazil)" \
        "ja_JP.UTF-8" "Japanese" \
        "zh_CN.UTF-8" "Chinese (Simplified)" \
        "custom"       "Enter custom locale") || return "${TUI_BACK}"
    [[ "${locale_choice}" == "custom" ]] && { locale_choice=$(dialog_inputbox "Custom Locale" "Locale:" "en_US.UTF-8") || return "${TUI_BACK}"; }
    LOCALE="${locale_choice}"; export LOCALE

    local km
    km=$(dialog_menu "Console Keymap" \
        "us" "US English" "uk" "UK English" "de" "German" "fr" "French" \
        "es" "Spanish" "pl" "Polish" "br" "Brazilian" "ru" "Russian" \
        "jp106" "Japanese" "custom" "Enter custom") || return "${TUI_BACK}"
    [[ "${km}" == "custom" ]] && { km=$(dialog_inputbox "Custom Keymap" "Keymap:" "us") || return "${TUI_BACK}"; }
    KEYMAP="${km}"; export KEYMAP

    einfo "Timezone: ${TIMEZONE}, Locale: ${LOCALE}, Keymap: ${KEYMAP}"
    return "${TUI_NEXT}"
}
