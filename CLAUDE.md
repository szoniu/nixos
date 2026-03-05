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
├── dialog.sh           — Wrapper gum/dialog/whiptail, primitives, wizard runner, bundled gum extraction
├── config.sh           — config_save/load/set/get (${VAR@Q}), validate_config()
├── hardware.sh         — detect_cpu/gpu(multi-GPU/hybrid)/disks/esp/installed_oses, detect_asus_rog, detect_bluetooth/fingerprint/thunderbolt/sensors/webcam/wwan, serialize/deserialize_detected_oses
├── disk.sh             — Dwufazowe: plan → cleanup_target_disk + execute, mount/unmount, LUKS support, shrink helpers (disk_plan_shrink via parted)
├── nixos_config.sh     — KLUCZOWY: generate_nixos_config(), _write_configuration_nix(), _nix_peripherals()
├── hooks.sh            — maybe_exec 'before_X' / 'after_X'
└── preset.sh           — preset_export/import (hardware overlay)

tui/
├── welcome.sh          — Prerequisites (root, UEFI, sieć, nixos-install)
├── preset_load.sh      — skip/file/browse
├── hw_detect.sh        — detect_all_hardware + summary
├── channel_select.sh   — stable/unstable + flakes toggle
├── disk_select.sh      — dysk + scheme (auto/dual-boot/manual) + _shrink_wizard()
├── filesystem_select.sh — ext4/btrfs/xfs + LUKS encryption
├── swap_config.sh      — zram/partition/none
├── network_config.sh   — hostname
├── locale_config.sh    — timezone + locale + keymap
├── kernel_select.sh    — default/latest/lts/zen
├── gpu_config.sh       — nvidia(+open)/amd/intel/none + hybrid GPU display
├── desktop_config.sh   — KDE apps + flatpak/printing/bluetooth toggles
├── user_config.sh      — root pwd, user, grupy, SSH
├── extra_packages.sh   — checklist (extras + conditional hw items) + wolne pole nix packages
├── preset_save.sh      — eksport
├── summary.sh          — validate_config + podsumowanie + YES + countdown
└── progress.sh         — resume detection + infobox (krótkie fazy) + live terminal (nixos-install)

data/                   — Static databases + bundled assets
├── gpu_database.sh     — nvidia_generation(), get_gpu_recommendation(), get_hybrid_gpu_recommendation()
├── dialogrc            — Dark TUI theme (loaded by DIALOGRC in init_dialog)
└── gum.tar.gz          — Bundled gum v0.17.0 binary (static ELF x86-64, ~4.5 MB)

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
- `_nix_gpu()` — NVIDIA (proprietary/open + PRIME offload), AMD (amdvlk), Intel
- `_nix_audio()` — PipeWire
- `_nix_packages()` — systemPackages z extras + extra_packages
- `_nix_services()` — fwupd
- `_nix_peripherals()` — fprintd, bolt, iio-sensor-proxy, ModemManager
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

### gum TUI backend

Third TUI backend alongside `dialog` and `whiptail`. Static binary bundled as `data/gum.tar.gz` (gum v0.17.0, ~4.5 MB). Zero network dependencies.

- Detection priority: gum > dialog > whiptail. Opt-out: `GUM_BACKEND=0`
- Desc→tag mapping via parallel arrays (gum 0.17.0 `--label-delimiter` is broken)
- Phantom ESC detection: `EPOCHREALTIME` with 150ms threshold, 3 retries then text fallback
- Terminal response handling: `COLORFGBG="15;0"`, `stty -echo`, `_gum_drain_tty()`

### Hybrid GPU detection

`detect_gpu()` scans ALL GPUs from `lspci -nn` (not just `head -1`). Classification:
- NVIDIA = always dGPU; Intel = always iGPU; AMD — if NVIDIA also present then iGPU, otherwise single
- PCI slot heuristic: bus `00` = iGPU, `01+` = dGPU
- When 2 GPUs: `HYBRID_GPU=yes`, `IGPU_*`, `DGPU_*` set, `GPU_VENDOR`=dGPU vendor
- NixOS config: `hardware.nvidia.prime.offload` for hybrid NVIDIA

ASUS ROG detection: `detect_asus_rog()` — DMI sysfs. Sets `ASUS_ROG_DETECTED=0/1`.

### Peripheral detection

6 detection functions in `lib/hardware.sh`, called from `detect_all_hardware()`:
- `detect_bluetooth()` — `/sys/class/bluetooth/hci*`
- `detect_fingerprint()` — USB vendor IDs (06cb, 27c6, 147e, 138a, 04f3)
- `detect_thunderbolt()` — sysfs + lspci
- `detect_sensors()` — IIO sysfs
- `detect_webcam()` — `/sys/class/video4linux/video*/name`
- `detect_wwan()` — `lspci -nnd 8086:7360`

Configured via nix attributes in `_nix_peripherals()`:
- `services.fprintd.enable = true` — fingerprint
- `services.hardware.bolt.enable = true` — thunderbolt
- `hardware.sensor.iio.enable = true` — IIO sensors
- `networking.networkmanager.enableModemManager = true` — WWAN

Opt-in via checklist in `tui/extra_packages.sh` (visible only when hardware detected).

### Multi-OS detection

`detect_installed_oses()` scans partitions for Windows (NTFS bootmgfw.efi) and Linux (/etc/os-release). Results in `DETECTED_OSES[]` assoc array, serialized to `DETECTED_OSES_SERIALIZED` for config save/load.

### Partition shrink wizard

When dual-boot selected and not enough free space, `_shrink_wizard()` in `tui/disk_select.sh` offers to shrink an existing partition:
- Supported: NTFS, ext4, btrfs (XFS cannot be shrunk)
- Safety: 1 GiB margin, minimum NIXOS_MIN_SIZE_MIB (10 GiB)
- Helpers in `lib/disk.sh`: `disk_get_free_space_mib()`, `disk_plan_shrink()` (uses `parted resizepart`)

### Config validation

`validate_config()` in `lib/config.sh` — validates config BEFORE install. Called at entry to `screen_summary()`.
Checks: required variables, enum values (ENCRYPTION ∈ {none, luks}, FILESYSTEM ∈ {ext4, btrfs, xfs}), hostname RFC 1123, block device existence, cross-field consistency.

### New CONFIG_VARS

```
HYBRID_GPU, IGPU_VENDOR, IGPU_DEVICE_NAME, DGPU_VENDOR, DGPU_DEVICE_NAME
ASUS_ROG_DETECTED, ENABLE_ASUSCTL, GPU_NVIDIA_OPEN
BLUETOOTH_DETECTED, FINGERPRINT_DETECTED, ENABLE_FINGERPRINT
THUNDERBOLT_DETECTED, ENABLE_THUNDERBOLT, SENSORS_DETECTED, ENABLE_SENSORS
WEBCAM_DETECTED, WWAN_DETECTED, ENABLE_WWAN
WINDOWS_DETECTED, LINUX_DETECTED, DETECTED_OSES_SERIALIZED
SHRINK_PARTITION, SHRINK_PARTITION_FSTYPE, SHRINK_NEW_SIZE_MIB
```

## Testy

```bash
bash tests/test_config.sh          # Config round-trip
bash tests/test_disk.sh            # Disk planning
bash tests/test_nixos_config.sh    # configuration.nix generation
bash tests/test_infer_config.sh    # Config inference from installed system
bash tests/test_hybrid_gpu.sh      # Hybrid GPU + recommendation
bash tests/test_validate.sh        # Config validation before install
bash tests/test_peripherals.sh     # Peripheral detection + config vars
```

## Znane wzorce i pułapki

- **stderr redirect a dialog UI**: Gdy stderr jest przekierowany do log file (`exec 2>>LOG`), `dialog` jest niewidoczny. `try()` musi tymczasowo przywrócić stderr (fd 4). Wzorzec: `if { true >&4; } 2>/dev/null; then exec 2>&4; fi`.
- **`try_resume_from_disk()` zwraca 0/1/2, nie boolean**: 0 = config + checkpointy, 1 = tylko checkpointy, 2 = nic. Nie używać `if try_resume_from_disk` — zawsze `rc=0; try_resume_from_disk || rc=$?; case ${rc}`.
- **Checkpointy na dysku docelowym**: Po zamontowaniu dysku checkpointy migrują z `/tmp` na `${MOUNTPOINT}/tmp/nixos-installer-checkpoints/`. Reformatowanie dysku kasuje checkpointy. `checkpoint_validate()` weryfikuje artefakty.
- **`cleanup_target_disk()`**: Odmontowuje partycje i swap przed `sfdisk`. Bez tego `sfdisk` odmawia zapisu na dysk w użyciu.
- **Config inference testowanie**: `_RESUME_TEST_DIR` + `_INFER_UUID_MAP` pozwalają testować bez prawdziwego mount/blkid.
- **POSIX grep (no PCRE)**: NixOS Live may not have `grep -P`. All `grep -oP` replaced with `sed` POSIX equivalents (e.g. `sed -n 's/.*\[\([0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\)\].*/\1/p'`).
- **gum TUI backend**: `data/gum.tar.gz` extracted to `/tmp/nixos-installer-gum/`. Opt-out: `GUM_BACKEND=0`. Priority: gum > dialog > whiptail.

## Jak dodawać opcje do configuration.nix

1. Dodaj zmienną do `CONFIG_VARS[]` w `lib/constants.sh`
2. Dodaj ekran TUI lub rozszerz istniejący
3. Dodaj logikę w odpowiedniej `_nix_*()` funkcji w `lib/nixos_config.sh`
4. Dodaj test w `tests/test_nixos_config.sh`
