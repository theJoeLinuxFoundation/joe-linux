# The joe Linux installer

A Qt Quick front end to `dave install-system`, which does all of the work.
It runs in the live session of the installation medium (image/live.zon),
opened automatically by the joe-live package.

- `dave install-system --list --json` (as the live user) lists the disks:
  whether each can be erased (`usable`, `reason`), its partitions with where
  they lie (`partitions`: `start`, `size`, `kind`), and whether joe fits in
  its free space beside what is there (`beside`: `possible`, `reason`,
  `start`, `size`, `systems`). The top-level `min_disk_size` and
  `min_beside_size` give the required whole-disk and free-space sizes in bytes.
- `pour scan --json` (as the live user) finds the Linux systems mounted on
  the computer, whose accounts could be brought over: `{"event":"system",
  "device":...,"root":...,"name":...}` lines. The live system and the
  medium's root image are left out.
- `dave install-system --disk PATH [--beside] [--enforce] [--import ROOT]
  --json` (as root, through pkexec, inside systemd-inhibit) erases the disk,
  or with `--beside` adds joe's partitions to its free space, and installs
  what the medium's
  joe/install.zon names, one JSON object per line on standard output:
  `{"event":"step"|"progress"|"done"|"error","message":...,"fraction":...}`.

The installer asks only which disk to use, and on a disk joe can share,
whether to go beside what is there (the default) or erase it. The
confirmation page also offers "Enforce the security module", off unless
ticked: with it the installed system boots with `joe=enforce` (`--enforce`).
When another Linux system is mounted (opened in Files), it offers to bring
its accounts and homes over instead of creating one at first start
(`--import`, which runs pour: packages/pour). Such a system is always on
another disk, since a disk with a file system in use cannot be installed
onto. Language,
keyboard, time zone and the account are asked by GNOME's initial setup on
the installed system's first boot.

`joe-installer --autotest DISK [--beside] [--enforce] [--import ROOT]` goes through the same pages
unattended and exits 0 when the installation succeeded; tests/vm/install.tomlx
uses it.

Built by packages/joe-installer, whose build copies this directory into the
recipe (bootstrap/build-packages.sh).

## Translations

The installer uses the session's UI language and falls back to its English
source strings. From this directory, create a Qt Linguist catalog with
`mkdir -p i18n` and `lupdate src qml -ts i18n/joe-installer_LANG.ts`,
replacing `LANG` with the locale code. CMake compiles and embeds the
catalogs. On a configured build, the `update_translations` target refreshes
their source strings.
