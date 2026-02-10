# NixOS TUI Installer

Interaktywny installer NixOS z interfejsem TUI (dialog). Przeprowadza za rękę przez cały proces instalacji — od partycjonowania dysku po działający desktop KDE Plasma 6.

W przeciwieństwie do Gentoo — tu nic się nie kompiluje. Binarne paczki z cache.nixos.org, instalacja w ~15-30 minut.

## Krok po kroku

### 1. Przygotuj bootowalny pendrive

Pobierz NixOS ISO (Plasma Desktop edition ma wszystko co trzeba):

- https://nixos.org/download/ → **NixOS: Plasma Desktop**

Nagraj na pendrive:

```bash
# UWAGA: /dev/sdX to pendrive, nie dysk systemowy!
sudo dd if=nixos-plasma-*.iso of=/dev/sdX bs=4M status=progress
sync
```

Na Windows: [Rufus](https://rufus.ie) lub [balenaEtcher](https://etcher.balena.io).

### 2. Bootuj z pendrive

- BIOS/UEFI: F2, F12, lub Del przy starcie
- **Wyłącz Secure Boot** (potrzebne dla NVIDIA drivers)
- Boot z USB w trybie **UEFI**

### 3. Połącz się z internetem

#### Kabel LAN

Powinno działać od razu:

```bash
ping -c 3 nixos.org
```

#### WiFi

**`nmcli`** (NetworkManager — dostępny na NixOS Live):

```bash
nmcli device wifi list
nmcli device wifi connect "NazwaSieci" password "TwojeHaslo"
```

**`iwctl`** (iwd — alternatywa):

```bash
iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "NazwaSieci"
exit
```

**`wpa_supplicant`** (manual fallback):

```bash
ip link set wlan0 up
wpa_supplicant -B -i wlan0 -c <(wpa_passphrase "NazwaSieci" "Haslo")
dhcpcd wlan0
```

Sprawdź: `ping -c 3 nixos.org`

### 4. Sklonuj repo i uruchom

```bash
sudo su
nix-shell -p git
git clone https://github.com/szoniu/nixos.git
cd nixos
./install.sh
```

Albo bez git:

```bash
sudo su
curl -L https://github.com/szoniu/nixos/archive/main.tar.gz | tar xz
cd nixos-main
./install.sh
```

### 5. Po instalacji

Wyjmij pendrive, reboot. Zobaczysz systemd-boot, potem SDDM z KDE Plasma 6.

Po zalogowaniu możesz edytować konfigurację:

```bash
sudo nano /etc/nixos/configuration.nix
sudo nixos-rebuild switch
```

## Alternatywne uruchomienie

```bash
./install.sh                    # Pełna instalacja (wizard + install)
./install.sh --configure        # Tylko wizard (generuje config)
./install.sh --config plik.conf --install   # Z gotowego configa
./install.sh --dry-run          # Symulacja bez dotykania dysków
```

## Wymagania

- Komputer z **UEFI** (nie Legacy BIOS)
- **Secure Boot wyłączony**
- Minimum **30 GiB** wolnego miejsca na dysku
- Internet (LAN lub WiFi)
- NixOS Live ISO (lub dowolne live z `nixos-install` i `dialog`)

## Co robi installer

| # | Ekran | Co konfigurujesz |
|---|-------|-------------------|
| 1 | Welcome | Sprawdzenie wymagań (root, UEFI, sieć, nixos-install) |
| 2 | Preset | Opcjonalne załadowanie gotowej konfiguracji |
| 3 | Hardware | Podgląd wykrytego CPU, GPU, dysków, Windows |
| 4 | Channel | NixOS stable/unstable + Flakes |
| 5 | Dysk | Wybór dysku + schemat (auto/dual-boot/manual) |
| 6 | Filesystem | ext4 / btrfs / XFS + opcjonalne LUKS szyfrowanie |
| 7 | Swap | zram / partycja / brak |
| 8 | Sieć | Hostname |
| 9 | Locale | Timezone, język, keymap |
| 10 | Kernel | Default / Latest / LTS / Zen |
| 11 | GPU | NVIDIA (auto open-kernel) / AMD / Intel |
| 12 | Desktop | KDE Plasma 6 + aplikacje + Flatpak/drukowanie/Bluetooth |
| 13 | Użytkownicy | Root, user, grupy, SSH |
| 14 | Pakiety | Dodatkowe pakiety nix |
| 15 | Preset save | Eksport konfiguracji |
| 16 | Podsumowanie | Przegląd + potwierdzenie YES |

Po potwierdzeniu installer:
1. Partycjonuje dysk (opcjonalnie z LUKS)
2. Uruchamia `nixos-generate-config` (hardware detection)
3. Generuje `configuration.nix` z Twoimi wyborami
4. Uruchamia `nixos-install`
5. Ustawia hasła

## Dual-boot z Windows

- Auto-wykrywanie ESP z Windows Boot Manager
- ESP nigdy nie jest formatowany
- systemd-boot automatycznie widzi Windows

## Presety

```
presets/desktop-nvidia.conf           # NVIDIA + ext4
presets/desktop-amd.conf              # AMD + btrfs
presets/desktop-intel-encrypted.conf  # Intel + LUKS
```

Presety przenośne — sprzęt re-wykrywany przy imporcie.

## Co jeśli coś pójdzie nie tak

- **Błąd** — menu: Retry / Shell / Continue / Log / Abort
- **Awaria** — checkpointy faz, wznowienie od ostatniego kroku
- **Log** — `/tmp/nixos-installer.log`

## Różnice vs Gentoo installer

| | NixOS | Gentoo |
|---|-------|--------|
| Czas instalacji | ~15-30 min | 3-8h |
| Kompilacja | Nie (binarne) | Tak (ze źródeł) |
| Konfiguracja | configuration.nix | make.conf + emerge |
| Rollback | Wbudowany | Brak (chyba btrfs) |
| Szyfrowanie LUKS | Wbudowane w installer | Do zrobienia |

## Testy

```bash
bash tests/test_config.sh          # Config round-trip (12 assertions)
bash tests/test_disk.sh            # Disk planning (8 assertions)
bash tests/test_nixos_config.sh    # configuration.nix generation (22 assertions)
bash tests/shellcheck.sh           # Lint
```

## Struktura

```
install.sh              — Entry point
configure.sh            — Wrapper: tylko wizard
lib/                    — Moduły (constants, logging, dialog, hardware, disk, nixos_config...)
tui/                    — 16 ekranów TUI
presets/                — Gotowe presety
hooks/                  — before/after hooks
tests/                  — Testy
```

## FAQ

**P: Jak długo trwa instalacja?**
~15-30 minut (binarne paczki). Zależy od prędkości internetu.

**P: Mogę na VM?**
Tak, UEFI mode. VirtualBox: Settings → System → Enable EFI.

**P: Mogę potem zmienić konfigurację?**
Tak! `sudo nano /etc/nixos/configuration.nix` → `sudo nixos-rebuild switch`. To kwintesencja NixOS.

**P: Co z Secure Boot?**
Wyłącz w BIOS. NVIDIA drivers nie są podpisane.

**P: Jak wrócić do poprzedniej konfiguracji?**
W menu systemd-boot możesz wybrać starszą generację. `sudo nixos-rebuild switch --rollback` też działa.
