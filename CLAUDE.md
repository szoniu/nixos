# CLAUDE.md — Kontekst projektu dla Claude Code

## Co to jest

Interaktywny TUI installer NixOS w Bashu. Cel: boot z NixOS Live ISO, sklonować repo, `./install.sh` — i dostać działający desktop KDE Plasma 6.

Kluczowa różnica vs Gentoo installer: NixOS to deklaratywna konfiguracja (`configuration.nix`), binarne paczki, `nixos-install` zamiast stage3+chroot+emerge.

## Architektura

### Jednoprocesowy model

W przeciwieństwie do Gentoo (outer + chroot), NixOS installer jest prostszy:
1. Wizard TUI → konfiguracja
2. Partycjonowanie dysku
3. `nixos-generate-config` → hardware-configuration.nix
4. Generowanie `configuration.nix` z wyborów użytkownika
5. `nixos-install` (robi cały chroot/emerge automatycznie)
6. Ustawienie haseł

### Struktura plików

```
install.sh              — Entry point, parsowanie argumentów, orchestracja
configure.sh            — Wrapper: exec install.sh --configure

lib/
├── protection.sh       — Guard: sprawdza $_NIXOS_INSTALLER
├── constants.sh        — Stałe, ścieżki, CONFIG_VARS[]
├── logging.sh          — elog/einfo/ewarn/eerror/die/die_trace
├── utils.sh            — try (interactive recovery, text fallback, LIVE_OUTPUT via tee), checkpoint_set/reached/validate/migrate_to_target, cleanup_target_disk, try_resume_from_disk, infer_config_from_partition, is_root/is_efi/has_network
├── dialog.sh           — Wrapper dialog/whiptail, wizard runner
├── config.sh           — config_save/load/set/get (${VAR@Q})
├── hardware.sh         — detect_cpu/gpu/disks/esp
├── disk.sh             — Dwufazowe: plan → cleanup_target_disk + execute, mount/unmount, LUKS support
├── nixos_config.sh     — KLUCZOWY: generate_nixos_config(), _write_configuration_nix()
├── hooks.sh            — maybe_exec 'before_X' / 'after_X'
└── preset.sh           — preset_export/import (hardware overlay)

tui/
├── welcome.sh          — Prerequisites (root, UEFI, sieć, nixos-install)
├── preset_load.sh      — skip/file/browse
├── hw_detect.sh        — detect_all_hardware + summary
├── channel_select.sh   — stable/unstable + flakes toggle
├── disk_select.sh      — dysk + scheme (auto/dual-boot/manual)
├── filesystem_select.sh — ext4/btrfs/xfs + LUKS encryption
├── swap_config.sh      — zram/partition/none
├── network_config.sh   — hostname
├── locale_config.sh    — timezone + locale + keymap
├── kernel_select.sh    — default/latest/lts/zen
├── gpu_config.sh       — nvidia(+open)/amd/intel/none
├── desktop_config.sh   — KDE apps + flatpak/printing/bluetooth toggles
├── user_config.sh      — root pwd, user, grupy, SSH
├── extra_packages.sh   — wolne pole nix packages
├── preset_save.sh      — eksport
├── summary.sh          — podsumowanie + YES + countdown
└── progress.sh         — resume detection + infobox (krótkie fazy) + live terminal (nixos-install)

presets/                — desktop-nvidia.conf, desktop-amd.conf, desktop-intel-encrypted.conf
hooks/                  — *.sh.example
tests/                  — test_config, test_disk, test_nixos_config, test_infer_config, shellcheck
```

### lib/nixos_config.sh — najważniejszy moduł

Ten moduł generuje `configuration.nix` z wyborów TUI. Składa się z:
- `_write_configuration_nix()` — główna funkcja, woła pod-generatory
- `_nix_bootloader()` — systemd-boot, LUKS
- `_nix_networking()` — hostname, NetworkManager, SSH
- `_nix_locale()` — timezone, locale, keymap
- `_nix_users()` — user z grupami
- `_nix_desktop()` — Plasma 6, SDDM, printing, bluetooth
- `_nix_gpu()` — NVIDIA (proprietary/open), AMD (amdvlk), Intel
- `_nix_audio()` — PipeWire
- `_nix_packages()` — systemPackages z extras + extra_packages
- `_nix_services()` — fwupd
- `_nix_settings()` — flakes, gc, allowUnfree

### Konwencje (identyczne jak w Gentoo)

- Ekrany TUI: `screen_*()` zwracają 0=next, 1=back, 2=abort
- `try` — interaktywne recovery na błędach, text fallback gdy brak dialog
- Checkpointy — wznowienie po awarii, `checkpoint_validate()` weryfikuje artefakty
- `${VAR@Q}` — bezpieczny quoting w configach
- `(( var++ )) || true` — pod set -e
- `_NIXOS_INSTALLER` — guard w protection.sh
- `--resume` — `try_resume_from_disk()` skanuje partycje, zwraca 0/1/2
- Config inference — `infer_config_from_partition()` odczytuje fstab, hostname, timezone, keymap, crypttab

### Różnice vs Gentoo installer

- Brak `lib/stage3.sh`, `lib/portage.sh`, `lib/kernel.sh`, `lib/bootloader.sh`, `lib/desktop.sh`, `lib/system.sh`, `lib/swap.sh`, `lib/chroot.sh` — NixOS to wszystko robi przez `configuration.nix` + `nixos-install`
- Dodany `lib/nixos_config.sh` — generuje cały Nix config
- Dodany `tui/channel_select.sh` — stable/unstable + flakes
- Ekran filesystem ma LUKS encryption toggle
- ESP montowany na `/boot` (nie `/efi`) — konwencja NixOS/systemd-boot
- Brak init system choice — NixOS = systemd always

## Testy

```bash
bash tests/test_config.sh          # 12 assertions
bash tests/test_disk.sh            # 8 assertions
bash tests/test_nixos_config.sh    # 22 assertions — najważniejszy test
bash tests/test_infer_config.sh    # 36 assertions — resume config inference
```

## Znane wzorce i pułapki

- **stderr redirect a dialog UI**: Gdy stderr jest przekierowany do log file (`exec 2>>LOG`), `dialog` jest niewidoczny. `try()` musi tymczasowo przywrócić stderr (fd 4). Wzorzec: `if { true >&4; } 2>/dev/null; then exec 2>&4; fi`.
- **`try_resume_from_disk()` zwraca 0/1/2, nie boolean**: 0 = config + checkpointy, 1 = tylko checkpointy, 2 = nic. Nie używać `if try_resume_from_disk` — zawsze `rc=0; try_resume_from_disk || rc=$?; case ${rc}`.
- **Checkpointy na dysku docelowym**: Po zamontowaniu dysku checkpointy migrują z `/tmp` na `${MOUNTPOINT}/tmp/nixos-installer-checkpoints/`. Reformatowanie dysku kasuje checkpointy. `checkpoint_validate()` weryfikuje artefakty.
- **`cleanup_target_disk()`**: Odmontowuje partycje i swap przed `sfdisk`. Bez tego `sfdisk` odmawia zapisu na dysk w użyciu.
- **Config inference testowanie**: `_RESUME_TEST_DIR` + `_INFER_UUID_MAP` pozwalają testować bez prawdziwego mount/blkid.

## Jak dodawać opcje do configuration.nix

1. Dodaj zmienną do `CONFIG_VARS[]` w `lib/constants.sh`
2. Dodaj ekran TUI lub rozszerz istniejący
3. Dodaj logikę w odpowiedniej `_nix_*()` funkcji w `lib/nixos_config.sh`
4. Dodaj test w `tests/test_nixos_config.sh`
