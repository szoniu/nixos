# NixOS TUI Installer

Interaktywny installer NixOS z interfejsem TUI (gum/dialog). Przeprowadza za rękę przez cały proces instalacji — od partycjonowania dysku po działający desktop KDE Plasma 6. Po awarii: `./install.sh --resume` skanuje dyski i wznawia od ostatniego checkpointu.

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

## Alternatywne sposoby uruchomienia

```bash
# Tylko konfiguracja (generuje plik .conf, nic nie instaluje)
./install.sh --configure

# Instalacja z gotowego configa (bez wizarda)
./install.sh --config moj-config.conf --install

# Wznów po awarii (skanuje dyski w poszukiwaniu checkpointów)
./install.sh --resume

# Dry-run — przechodzi cały flow BEZ dotykania dysków
./install.sh --dry-run
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
| 3 | Hardware | Podgląd wykrytego CPU, GPU (hybrid), dysków, peryferiów, Windows/Linux |
| 4 | Channel | NixOS stable/unstable + Flakes |
| 5 | Dysk | Wybór dysku + schemat (auto/dual-boot/manual) |
| 6 | Filesystem | ext4 / btrfs / XFS + opcjonalne LUKS szyfrowanie |
| 7 | Swap | zram / partycja / brak |
| 8 | Sieć | Hostname |
| 9 | Locale | Timezone, język, keymap |
| 10 | Bootloader | systemd-boot (domyślny) / GRUB (multi-boot z os-prober) |
| 11 | Kernel | Default / Latest / LTS / Zen |
| 12 | GPU | NVIDIA (auto open-kernel) / AMD / Intel |
| 13 | Desktop | KDE Plasma 6 + aplikacje + Flatpak/drukowanie/Bluetooth |
| 14 | Użytkownicy | Root, user, grupy, SSH |
| 15 | Pakiety | Dodatkowe pakiety nix + Hyprland ecosystem + opcje sprzętowe (fingerprint, Thunderbolt, itp.) |
| 16 | Preset save | Eksport konfiguracji |
| 17 | Podsumowanie | Przegląd + potwierdzenie YES |

Po potwierdzeniu installer:
1. Partycjonuje dysk (opcjonalnie z LUKS)
2. Uruchamia `nixos-generate-config` (hardware detection)
3. Generuje `configuration.nix` z Twoimi wyborami
4. Uruchamia `nixos-install`
5. Ustawia hasła

## Dual-boot z Windows/Linux

- Auto-wykrywanie ESP z Windows Boot Manager i innych Linuksów
- ESP nigdy nie jest formatowany
- systemd-boot automatycznie widzi Windows
- Wizard do zmniejszania partycji jeśli brak wolnego miejsca (NTFS, ext4, btrfs)
- Ostrzeżenia o istniejących OS-ach na wybranych partycjach

## Presety

```
presets/desktop-nvidia.conf           # NVIDIA + ext4
presets/desktop-amd.conf              # AMD + btrfs
presets/desktop-intel-encrypted.conf  # Intel + LUKS
```

Presety przenośne — sprzęt re-wykrywany przy imporcie.

## Co jeśli coś pójdzie nie tak

### Recovery menu

Gdy komenda się nie powiedzie, installer wyświetli menu recovery:

- **(r)etry** — ponów komendę (np. po naprawieniu problemu w shellu)
- **(s)hell** — wejdź do shella, napraw ręcznie, wpisz `exit` żeby wrócić
- **(c)ontinue** — pomiń ten krok i kontynuuj (ostrożnie!)
- **(l)og** — pokaż log błędu
- **(a)bort** — przerwij instalację

### Wznowienie po awarii (`--resume`)

Jeśli instalacja została przerwana (OOM kill, zawieszenie, utrata SSH, przerwa w prądzie), możesz wznowić jedną komendą:

```bash
./install.sh --resume
```

`--resume` automatycznie:
1. Skanuje wszystkie partycje (ext4/btrfs/xfs) w poszukiwaniu danych z poprzedniej instalacji
2. Odzyskuje checkpointy (informacje o ukończonych fazach) i plik konfiguracji
3. Jeśli config nie przetrwał — próbuje go **odtworzyć z zainstalowanego systemu** (fstab, hostname, timezone, keymap, itp.)
4. Pomija już ukończone fazy i kontynuuje od miejsca przerwania

Co przetrwało na dysku docelowym:
- **Checkpointy** — pliki w `/tmp/nixos-installer-checkpoints/` na partycji docelowej
- **Config** — `/tmp/nixos-installer.conf` na partycji docelowej (zapisywany po fazie partycjonowania)

### Drugie TTY — twój najlepszy przyjaciel

Podczas instalacji masz dostęp do wielu konsol. Przełączaj się przez **Ctrl+Alt+F1**...**F6**:

- **TTY1** — installer
- **TTY2-6** — wolne konsole do debugowania

Na drugim TTY możesz:

```bash
# Podgląd co się dzieje
top

# Log installera
tail -f /tmp/nixos-installer.log

# Sprawdź czy coś nie zawiesiło się
ps aux | grep -E "tee|nix"
```

### Zdalna instalacja przez SSH

Na maszynie docelowej (bootowanej z NixOS Live ISO):

```bash
# 1. Ustaw hasło root (NixOS Live domyślnie nie ma hasła)
passwd root

# 2. Sprawdź czy sshd działa (na NixOS Live ISO powinien być domyślnie)
systemctl status sshd

# 3. Jeśli nie działa — uruchom
systemctl start sshd

# 4. Sprawdź IP
ip -4 addr show | grep inet
```

Z innego komputera:

```bash
ssh -o PubkeyAuthentication=no root@<IP-live-ISO>
nix-shell -p git
git clone https://github.com/szoniu/nixos.git
cd nixos
./install.sh
```

Installer działa normalnie przez SSH — TUI renderuje się w terminalu SSH.

> **"Connection refused"?** Sprawdź czy `sshd` działa: `systemctl status sshd`.
>
> **"WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"?** Po restarcie Live ISO klucze SSH hosta się zmieniają. Usuń stary klucz i połącz się ponownie:
> ```bash
> ssh-keygen -R <IP-live-ISO>
> ssh -o PubkeyAuthentication=no root@<IP-live-ISO>
> ```

#### Monitorowanie z drugiego połączenia

```bash
ssh root@<IP-live-ISO>

# Logi w czasie rzeczywistym
tail -f /tmp/nixos-installer.log

# Co się instaluje
top
```

### Typowe problemy

#### Przed instalacją

- **`git clone` — SSL certificate not yet valid** — zegar systemowy jest przestarzały. Ustaw datę: `date -s "2026-03-09 12:00:00"` (wstaw aktualną).
- **`git clone` — Permission denied (publickey)** — użyj HTTPS: `git clone https://github.com/szoniu/nixos.git`, nie SSH (`git@github.com:...`).
- **Preflight: "Network connectivity required"** — installer pinguje `nixos.org` i `google.com`. Jeśli sieć działa ale DNS nie, dodaj ręcznie: `echo "nameserver 8.8.8.8" >> /etc/resolv.conf`.

#### W trakcie instalacji

- **nixos-install — "Name or service not known"** — DNS przestał działać. Na innym TTY (`Ctrl+Alt+F2`) wpisz: `echo "nameserver 8.8.8.8" >> /etc/resolv.conf`, wróć na TTY1 i wybierz `r` (retry).
- **Installer zawisł, nic się nie dzieje** — sprawdź na TTY2 (`Ctrl+Alt+F2`) czy `nix-build` lub `nix-store` działają w `top`. Jeśli tak — pobieranie/instalacja trwa, po prostu czekaj.
- **Przerwa w prądzie / reboot** — uruchom `./install.sh --resume`, automatycznie wznowi od ostatniego checkpointu.
- **Menu "retry / shell / continue / abort"** — installer napotkał błąd. `r` = spróbuj ponownie, `s` = otwórz shell i napraw ręcznie (potem `exit`), `c` = pomiń ten krok, `a` = przerwij instalację.

#### Ogólne

- **Log** — pełny log instalacji: `/tmp/nixos-installer.log`
- **Coś jest nie tak z konfiguracją** — użyj `./install.sh --configure` żeby przejść wizarda ponownie

## Interfejs TUI

Installer ma trzy backendy TUI (w kolejności priorytetu):

1. **gum** (domyślny) — nowoczesny, zaszyty w repo jako `data/gum.tar.gz` (~4.5 MB). Ekstrahowany automatycznie do `/tmp` na starcie. Zero dodatkowych zależności.
2. **dialog** — klasyczny TUI, dostępny na większości live ISO
3. **whiptail** — fallback gdy brak `dialog`

Backend jest wybierany automatycznie. Żeby wymusić fallback na `dialog`/`whiptail`:

```bash
GUM_BACKEND=0 ./install.sh
```

### Aktualizacja gum

Żeby zaktualizować bundlowaną wersję gum:

```bash
# 1. Pobierz nowy tarball (podmień wersję)
curl -fSL -o data/gum.tar.gz \
  "https://github.com/charmbracelet/gum/releases/download/v0.18.0/gum_0.18.0_Linux_x86_64.tar.gz"

# 2. Zaktualizuj GUM_VERSION w lib/constants.sh (musi pasować)
#    : "${GUM_VERSION:=0.18.0}"
```

## Hooki (zaawansowane)

Własne skrypty uruchamiane przed/po fazach instalacji:

```bash
cp hooks/before_install.sh.example hooks/before_install.sh
chmod +x hooks/before_install.sh
# Edytuj hook...
```

Dostępne hooki: `before_preflight`, `after_preflight`, `before_disks`, `after_disks`, `before_generate`, `after_generate`, `before_config`, `after_config`, `before_install`, `after_install`, `before_finalize`, `after_finalize`.

Hooki mają dostęp do wszystkich zmiennych konfiguracyjnych (`TARGET_DISK`, `FILESYSTEM`, `HOSTNAME`, `GPU_VENDOR`, itp.) oraz `MOUNTPOINT`, `LOG_FILE`, `SCRIPT_DIR`, `CONFIG_FILE`, `DRY_RUN`.

## Opcje CLI

```
./install.sh [OPCJE] [POLECENIE]

Polecenia:
  (domyślnie)      Pełna instalacja (wizard + install)
  --configure       Tylko wizard konfiguracyjny
  --install         Tylko instalacja (wymaga configa)
  --resume          Wznów po awarii (skanuje dyski)

Opcje:
  --config PLIK     Użyj podanego pliku konfiguracji
  --dry-run         Symulacja bez destrukcyjnych operacji
  --force           Kontynuuj mimo nieudanych prereq
  --non-interactive Przerwij na każdym błędzie (bez recovery menu)
  --help            Pokaż pomoc

Zmienne środowiskowe:
  GUM_BACKEND=0     Wymuś fallback na dialog/whiptail (pomiń gum)
```

## Wykrywanie sprzętu

Installer automatycznie wykrywa i konfiguruje:

- **CPU** — Intel/AMD, microcode
- **GPU** — NVIDIA (proprietary + open-kernel), AMD, Intel + hybrid GPU (PRIME offload)
- **ASUS ROG/TUF** — wykrywanie przez DMI, opcjonalny `asusd` (asusctl) w `configuration.nix`
- **Bluetooth** — auto-wykrywany, konfigurowany w ekranie Desktop
- **Czytnik linii papilarnych** — fprintd (Synaptics, Goodix, Elan, AuthenTec, Validity)
- **Thunderbolt** — bolt daemon
- **Sensory IIO** — akcelerometr, żyroskop, czujnik światła (laptopy 2-in-1)
- **Kamera** — wykrywanie webcam
- **WWAN LTE** — ModemManager (Intel XMM7360)

Wykryte peryferiale pojawiają się jako opcje w ekranie "Pakiety" — można je włączyć jednym kliknięciem.

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
bash tests/test_config.sh          # Config round-trip
bash tests/test_disk.sh            # Disk planning
bash tests/test_nixos_config.sh    # configuration.nix generation
bash tests/test_infer_config.sh    # Config inference from installed system
bash tests/test_hybrid_gpu.sh      # Hybrid GPU + recommendation
bash tests/test_validate.sh        # Config validation before install
bash tests/test_peripherals.sh     # Peripheral detection + config vars
bash tests/test_checkpoint.sh      # Checkpoint set/reached/validate/migrate
bash tests/test_resume.sh          # Resume from disk scanning + recovery
bash tests/test_multiboot.sh       # Multi-OS serialize/deserialize
bash tests/test_shrink.sh          # Partition shrink helpers
bash tests/shellcheck.sh           # Lint
```

Wszystkie testy są standalone — nie wymagają root ani hardware. Używają `DRY_RUN=1` i `NON_INTERACTIVE=1`.

## Struktura

```
install.sh              — Główny entry point
configure.sh            — Wrapper: tylko wizard TUI

lib/                    — Moduły biblioteczne (sourcowane, nie uruchamiane)
tui/                    — Ekrany TUI (każdy = funkcja, return 0/1/2)
data/                   — GPU database, motyw TUI, bundled gum binary
presets/                — Gotowe presety
hooks/                  — Hooki (*.sh.example)
tests/                  — Testy
```

## FAQ

**P: Jak długo trwa instalacja?**
~15-30 minut (binarne paczki). Zależy od prędkości internetu.

**P: Mogę na VM?**
Tak, UEFI mode. VirtualBox: Settings → System → Enable EFI. W QEMU: dodaj `-bios /usr/share/ovmf/OVMF.fd`.

**P: Mogę potem zmienić konfigurację?**
Tak! `sudo nano /etc/nixos/configuration.nix` → `sudo nixos-rebuild switch`. To kwintesencja NixOS.

**P: Co z Secure Boot?**
Wyłącz w BIOS. NVIDIA drivers nie są podpisane.

**P: Jak wrócić do poprzedniej konfiguracji?**
W menu systemd-boot możesz wybrać starszą generację. `sudo nixos-rebuild switch --rollback` też działa.

**P: Mogę użyć innego live ISO niż NixOS?**
Tak, dowolne live ISO z Linuxem zadziała, pod warunkiem że ma `bash`, `nixos-install`, `sfdisk`. Installer ma zaszyty `gum` jako backend TUI, więc `dialog`/`whiptail` nie jest wymagany.

**P: Co jeśli `gum` nie działa?**
Installer automatycznie użyje `dialog` lub `whiptail` jako fallback. Możesz też wymusić fallback: `GUM_BACKEND=0 ./install.sh`.

**P: Mam laptopa ASUS ROG/TUF — czy installer to wspiera?**
Tak. Installer automatycznie wykrywa hardware ASUS ROG/TUF przez DMI i oferuje instalację `asusd` (asusctl) do zarządzania podświetleniem, trybami wydajności i profilami GPU.

**P: Mam multi-boot (kilka Linuxów). Po aktualizacji kernela inne systemy zniknęły z menu boot.**
Jeśli używasz **GRUB** (wybierany w wizardzie dla multi-boot), odśwież konfigurację:

```bash
sudo nixos-rebuild switch
```

NixOS z `boot.loader.grub.useOSProber = true` automatycznie wykryje inne systemy przy każdym `nixos-rebuild`.

Jeśli używasz **systemd-boot** — nie wykrywa innych Linuxów. Przełącz na GRUB w `/etc/nixos/configuration.nix`:

```nix
boot.loader.systemd-boot.enable = false;
boot.loader.grub.enable = true;
boot.loader.grub.device = "nodev";
boot.loader.grub.efiSupport = true;
boot.loader.grub.useOSProber = true;
```

Potem: `sudo nixos-rebuild switch`.

**P: Zapomniałem odświeżyć GRUB i po restarcie nie widzę innych systemów.**
Systemy dalej są na dysku — nic nie zostało usunięte. Wystarczy:

1. Uruchom dowolny z widocznych systemów
2. Uruchom `sudo grub-mkconfig -o /boot/grub/grub.cfg` (lub `sudo nixos-rebuild switch` z NixOS)
3. Restart — wszystkie systemy powinny być widoczne

Jeśli żaden system nie startuje (uszkodzony GRUB), boot z Live USB i napraw z chroot:

```bash
mount /dev/<root-partycja> /mnt
mount /dev/<esp> /mnt/boot
mount --rbind /dev /mnt/dev && mount --rbind /sys /mnt/sys && mount -t proc /proc /mnt/proc
chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
```
