# joe Linux

<a href="https://www.linuxlinks.com/joe-linux-from-scratch-based-distribution/"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://www.linuxlinks.com/badges/linuxlinks-badge-black.png">
  <img alt="Featured on LinuxLinks" width="240" height="80" src="https://www.linuxlinks.com/badges/linuxlinks-badge-white.png">
</picture></a>

An independent Linux distribution whose goal is to be as boring as possible for
the person using it. Three things about it are new; everything else is ordinary
(glibc, systemd, a usr-merged file system, GNOME).

1. **Transactional upgrades on a system that is not immutable.** An upgrade is
   applied to a btrfs snapshot and takes effect on reboot. If the new system
   does not boot, the machine returns to the previous one by itself. The
   running root stays an ordinary writable file system.
2. **dave**, a package manager written in Zig with a PubGrub solver, designed
   around that update model from the start.
3. **A security model for root.** A privileged process runs only code that the
   distribution has signed, cannot generate code at run time, and is held to
   the operations its program declares. One kernel security module enforces it.

The idea of snapshot-based upgrades without immutability comes from
[Arch-silverblue](https://github.com/sinisterMage/Arch-silverblue).

## Status

joe Linux builds from source into two systems that boot in a virtual machine:

- a **console system**, with doas (which answers to `sudo` at a prompt),
  an editor, the manual and ssh, whose upgrade, rollback and recovery
  behaviour is exercised end to end by `make test-joe`;
- a **GNOME desktop**: GDM, GNOME Shell on Wayland,
  Firefox, Files, Terminal, Text Editor, Settings and the usual small
  applications (documents, images, video, music, archives, disks, maps,
  weather, clocks, calculator), with fonts for most scripts, spell checking
  and the common media codecs, and printing, Bluetooth (headsets included)
  and mobile broadband. `make test-desktop` starts every one of them, with
  the security module both logging and enforcing. It is laid out like
  Windows, entirely with upstream GNOME Shell extensions and ordinary
  settings: a taskbar along the bottom (Dash to Panel) with a start menu
  (ArcMenu) and tray icons (AppIndicator), icons on the desktop (DING),
  minimize and maximize buttons, Papirus icons, GTK 3 applications styled
  to match the rest (adw-gtk3), and joe's teal accent and wallpaper. Each
  piece is an ordinary extension or setting, which `gnome-extensions
  disable` or Settings turns back to plain GNOME.

The repository also provides packages beyond those images, a `dave install`
away. That covers development tools and
toolchains (gdb, valgrind, Go, Zig, OpenJDK, GHC, uv, ripgrep, ShellCheck),
servers (PostgreSQL, BIND, unbound, nginx, Samba, NFS, WireGuard, nftables)
and applications such as LibreOffice, GIMP, Inkscape, VLC, Audacity,
Remmina and KeePassXC.

Optional servers are off by default on new systems. After configuring one,
use `systemctl enable --now UNIT` to opt in; installing its package alone
does not start it. Core services, SSH and the GNOME desktop have explicit
defaults.

The desktop can be lived in as a virtual machine that keeps its disk: the
first boot asks who you are, and upgrades come from the build machine. See
[Living in it](#living-in-it). It can also be installed, from a live medium
whose installer puts it beside Windows (or another system) in free space, or
on a whole disk; see [Installing](#installing). Real
computers are a work in progress; see [Not done yet](#not-done-yet).

## How it behaves

```
dave install tree     Installs now. The system as it was is kept as a
                      bootable deployment first, so there is a way back. When
                      more would change than you named (dependencies come in,
                      other packages are upgraded or removed), dave shows the
                      plan and asks first; -y answers for you.

dave upgrade          Works out and downloads the upgrade and proves it applies
                      cleanly to a copy of the system. Changes nothing you can
                      see. The upgrade is applied when the machine shuts down.

dave upgrade --check  What an upgrade would change, without preparing it.

dave rollback         The previous system starts on the next boot, and on every
                      boot after it. Says so if someone has been given an
                      account since that system was made: accounts live in
                      /etc, which belongs to each system.

dave status           What is running, what will start next, what is pending.

dave info tree        Installed and available versions, licence, sizes, what it
                      needs, what needs it, and why it is installed.

dave search a b       The packages matching every word; name matches first.

dave why zlib         The shortest chain from something you asked for.

dave owns /bin/sh     The package a file belongs to, resolving /bin and /lib
                      as the system does. dave files lists a package's files.

dave help install     Every command explains itself; dave(8) has the rest, and
                      bash, zsh and fish complete commands and package names.
```

Only changing the system needs root: status, list, info, search, files, owns,
why, deployments and `upgrade --check` work for everyone. Before anything
changes, dave shows the plan:

```
Install
  babl  0.1.128-r1  (dependency)
  gegl  0.4.72-r2   (dependency)
  gimp  3.2.8-r2

3 to install. 27.0 MiB to download; 112.4 MiB more disk space will be used.
Continue? [Y/n]
```

On a terminal there is colour, and a line that shows downloads and progress
as they happen; `NO_COLOR` turns the colour off. Output to a pipe or a file
stays plain lines.

When a request cannot be satisfied, dave says why:

```
dave: this cannot be done.

Because editor 1.0-r1 depends on libui >=2 and editor has no version other than 1.0-r1, editor requires libui >=2.
And because no version of libui matches >=2, editor cannot be installed.
So, because you asked for editor, what you asked for cannot be installed.
```

## How it works

**Deployments.** The root file system is a btrfs subvolume `joe/deploy/<id>`.
`/home` and `/var` are separate subvolumes shared by every deployment; `/etc`
belongs to the deployment, so configuration rolls back with the system. dave's
database lives under `/usr/lib/dave/db`, inside the deployment, so each
snapshot carries the database that describes exactly its own contents.

**Upgrades lose nothing.** `dave upgrade` only records a plan. At shutdown,
`dave-finalize.service` snapshots the root *as it is at that moment* and
applies the plan to the snapshot. Anything changed between `dave upgrade` and
the reboot is therefore in the new system; there is no merge step. The boot
entry for the new deployment is written last, so a power cut at any earlier
point boots the old system with the upgrade still pending. A newer
systemd-boot in the upgraded system replaces the one on the EFI system
partition at the same moment, and only ever a newer one, because every
deployment is started by the same loader. Package triggers run in the new
deployment with an empty tmpfs on `/var` and `/home`, where the shared
subvolumes will be mounted, so nothing they write is left hidden under them.

**The boot loader keeps the health record.** Each deployment has one
systemd-boot entry. Entries are ordered by a priority that is bumped whenever a
deployment is chosen, so activating an upgrade and rolling back are the same
operation, and a rollback is persistent. A new deployment starts with three
boot attempts. `dave-boot-check.service` runs before systemd marks the boot
good; if the check fails the machine reboots, and when the attempts run out
systemd-boot returns to whatever was chosen before. A root that cannot be
mounted at all takes the same path through the kernel's panic timeout.

**Packages** are zstd-compressed tar files beginning with a manifest that is
authoritative for all file metadata. Repositories are signed with Ed25519; the
signed index carries the SHA-256 of every package. They are fetched over HTTPS
(checked against the system's certificate store), HTTP, or from a local
directory; the signature is what is trusted either way. Packages have no install
scripts: a package may declare a trigger (rebuild the linker cache when
libraries change), and that is all.

**Seals.** Every packaged file that is not configuration is *sealed* when it
is installed: fs-verity makes its contents immutable and gives the kernel a
digest of them, and an extended attribute carries a signature over that digest
together with the operations the package declares for the file. The public
half of the signing key is compiled into the kernel. A sealed file can be
replaced or deleted, never modified.

**What the security module does.** It concerns privileged processes only: any
user id of 0, or any capability, in the initial user namespace. Ordinary users
are not affected.

1. *Sealed code only.* The program, every library it maps, every kernel module
   it loads and every script it runs must be sealed. bash and Python ask the
   module before reading a script file; commands typed at a prompt and `-c`
   strings are not files and are allowed.
2. *No code made at run time.* No anonymous executable memory, no writable
   executable mappings, no making modified memory executable. A just-in-time
   compiler cannot work under these rules, so none can run as root. A debugger
   cannot write another process's executable pages either: ptrace, process-vm
   and `/proc/PID/mem` writes are covered as well as `mmap` and `mprotect`.
3. *Declared operations.* A recipe states what its privileged programs do:
   which capabilities, whether the network, where they write, what they run.

   ```zon
   .operations = .{
       .{ .programs = .{"usr/bin/mount"}, .allow = .{ "mount", "cap:sys_admin" } },
   },
   ```

   The declaration is part of what is signed, and the module refuses the rest.
   `root-ipc` covers signals and SysV IPC between root processes. `none` is an
   explicit empty declaration. A program no declaration covers is `undeclared`:
   an `all` caller gives it `all`, and otherwise it is reported and refused when
   enforcing. Global root stays confined when it creates a user namespace. A
   process whose only global privilege is its capability set cannot create one,
   because replacing that set would discard its confinement.

The module logs by default and enforces when booted with `joe=enforce`. The
installer offers that as a choice, "Enforce the security module", which is off
unless it is ticked (`dave install-system --enforce`). One consequence worth
knowing: a root shell does not read `/etc/profile` or
`~/.bashrc`, because files you can edit are not sealed.

The programs where privilege starts declare `all`: systemd's PID 1 and the
executor that starts every service, root's bash, the programs that start
another user's shell (doas, su, pkexec, ksu), root's sftp-server, dave,
mount, and the programs the kernel itself starts (modprobe,
systemd-coredump, request-key). Every other service and set-uid program the
desktop runs with privilege declares its own operations, taken from the
capabilities its upstream unit bounds it to and from what it was seen to do
in log mode: the systemd daemons (journald, logind, udevd and the helpers
its rules run, userdbd, nsresourced, networkd, resolved, timesyncd,
hostnamed, localed, timedated), D-Bus, NetworkManager and wpa_supplicant,
ModemManager, accounts-daemon and shadow's account tools, udisks and the
file system tools it runs, upower, gdm and its session worker, bluetoothd,
geoclue, avahi, cups, sshd, agetty and login, and the set-uid tools
(passwd and its kin, newuidmap, ping, fusermount3, unix_chkpwd, the polkit
agent's helper). NetworkManager, for one, may use the network, load
modules and write `/etc` and its state, and nothing else. `true` and
`false` declare `none`. Everything else is `undeclared`, so it acts with the
authority of the shell or service that runs it. The desktop, a fresh
installation and its first boot are tested enforcing, and fail on anything
denied (`make test-desktop`, `make test-install`).

The details are in the source, which is commented for readers:
[packages/linux/joe-lsm/joe.c](packages/linux/joe-lsm/joe.c), [dave/src/seal.zig](dave/src/seal.zig),
[dave/src/deploy.zig](dave/src/deploy.zig), [dave/src/boot.zig](dave/src/boot.zig),
[dave/src/txn.zig](dave/src/txn.zig), [dave/src/solver/pubgrub.zig](dave/src/solver/pubgrub.zig).

## Building and testing

The tests are run by [neomake](https://github.com/theJoeLinuxFoundation/neomake)
(`cargo install --git https://github.com/theJoeLinuxFoundation/neomake neomake`),
from `neomake.tomlx` and `tests/`; the Makefile's test targets call it.
`neomake list --tests -v` shows every test and whether this machine can run
it: a test whose tool, KVM or prerequisite is missing is skipped with the
reason. Each run's logs, report and test files are kept in
`build/neomake/runs/`, and a failure names the step and the line it is
written on.

GitHub Actions runs `neomake test unit 'cli-*'` on pull requests and pushes
to `main` and `beta*` branches, using Zig 0.17.1 on Ubuntu. Unit tests that
need btrfs or fs-verity skip when those features are unavailable.

Requirements on the build machine: Zig 0.17.1, neomake, a C toolchain, QEMU
with KVM, OVMF firmware, btrfs-progs 6.12 or newer, bubblewrap, zstd,
Python 3, OpenSSL, and a build directory on btrfs. Nothing needs root.

```
make test                  unit tests and command-line tests, in seconds
make test-boot-contract    what the design assumes about systemd-boot, in a VM
make test-deployments      upgrade, rollback, power loss and recovery, in a VM
```

Those two VM tests use a *scaffold*: a throwaway image made from the build
machine's kernel and a stock Arch userspace, so the deployment mechanics can be
exercised without building a distribution first. Nothing from it ships.

```
make bootstrap             cross toolchain and temporary tools
make packages              every recipe in packages/, into build/repo
make image                 a bootable image, build/images/joe.img
make run                   boot it in QEMU on this terminal (leave with Ctrl-A X)
make test-joe              the same deployment tests on that image
make test-security         the security module's three rules
make audit-security        package seal and declaration audit
```

```
make desktop-image         a GNOME image, build/images/joe-desktop.img
make run-desktop           boot it in a QEMU window (user joe, password joe)
make test-desktop          session, every application, a web page; logging and enforcing
```

Building the desktop packages takes several hours the first time; LLVM, Rust,
Firefox, Node.js and SpiderMonkey are the long ones.

These are test images: root is logged in on the serial console without a
password, and the desktop image has a ready-made user, because that is how
the tests look inside. The release image below has neither.

## Installing

```
make iso                   build/images/joe-live.iso, the installation medium
make run-iso               boot the newest medium in a window, beside an empty disk
make test-live             boot it as a CD and as a USB stick, in a VM
make test-install          install from it onto an empty disk, then boot that
```

The medium is a hybrid ISO for UEFI computers (Secure Boot off): write it to a
USB stick or attach it to a virtual machine as a CD. It starts a GNOME session
from a compressed image of the desktop (SquashFS, xz), with a layer in memory
for changes, and opens the installer. The installer asks which disk to use,
and how:

- **Beside another system**, in the disk's largest free space (22 GB or
  more). Nothing that is there is moved, shrunk or erased, so the room is made
  first, in the other system: Windows' Disk Management shrinks its volume. joe
  shares the disk's EFI system partition, adding only systemd-boot to it
  (never replacing Windows' files, the firmware's fallback loader included),
  and keeps its kernels and boot entries on a boot partition of its own
  (XBOOTLDR) at the start of the free space. The boot menu then lists joe and
  Windows, which systemd-boot finds by itself, for five seconds; joe starts
  unless another is chosen.
- **On the whole disk**, erased: a new GPT with an EFI system partition and a
  btrfs root laid out exactly as an image's.

The packages are installed from the medium itself, by one dave
transaction, and sealed as they are installed. The medium carries each
package once: the transaction copies it out of the live session's own root
image, where it is installed already, and checks every file against the
package's manifest, as it would a file from a package. The few files the live
session changes (its host name, its automatic login, the accounts it adds)
are on the medium as packaged as well. The installed system boots without an
initramfs, like every joe system, and its first boot runs GNOME's initial
setup.

The installer (`installer/`) is a Qt Quick front end; all of its work is done by
`dave install-system`, which can be run by hand on the medium:

```
dave install-system --list                          the disks, and what each allows
dave install-system --disk /dev/nvme0n1 --beside    install in its free space
dave install-system --disk /dev/nvme0n1             erase it and install
dave install-system --disk /dev/nvme0n1 --enforce   and boot it enforcing the security module
dave install-system --disk /dev/nvme0n1 --import /mnt/old   and bring over the accounts of the
                                                    system mounted there
```

With `--import` (in the installer: another Linux system opened in Files),
[pour](https://github.com/theJoeLinuxFoundation/pour) carries that system's
accounts into the new one with their passwords, groups and homes, and those
who administered it administer the new one; the first-run setup is then not
needed. The other system must be on another disk.

Images and media are described by specifications in `image/*.zon` and built by
`dave image build`; each Makefile target above names one. The build machine
publishes the medium with the repository, at
[joelinux.io/downloads](https://joelinux.io/downloads/).

## In a container

joe's command line, with dave to install the rest, is also a container image
(`image/container.zon`, an OCI image of one layer):

```
docker run -it ghcr.io/thejoelinuxfoundation/joe
dave install git
```

`make container` builds it from build/repo as `build/images/joe-container.tar`
(`docker load -i` or `podman load -i` it). The published image is built from
the published repository by a GitHub workflow, `.github/workflows/container.yml`,
run by hand after a release. A container is not a deployment, so dave
installs into it directly, without a snapshot to return to.

## Releases

A release is named **J*X*-*Y*-*Z***, with a stage such as `-alpha1` before it
is final:

| Part | Is | In J1-7.3.1-0.4.0-beta2 |
|------|----|--------------------------|
| J | joe, the distribution | J |
| *X* | the system revision | 1 |
| *Y* | the kernel's version | 7.3.1 |
| *Z* | dave's version | 0.4.0 |

`packages/joe-release` writes the name into `os-release` and the build machine
names the installation medium after it. Its package version is the revision
and stage alone (`1beta2`), which dave orders before the final `1`.

## Living in it

```
make release-image         the desktop as a person gets it, build/images/joe-release.img
make test-release          its first boot: disk growth, first-run setup, sound, shared folder
make vm                    a virtual machine with a 64G disk of its own, in build/vm
make run-vm                boot it; what you do in it is still there next time
make serve-repo            offer build/repo to that machine
```

The release image has no accounts and root has no password. On the first boot
GDM starts GNOME's initial setup, which asks for a language, keyboard layout
and time zone and creates your account. That account is an administrator (a
member of `wheel`), so `doas` works, and so does `sudo` at a prompt, which
runs doas. The root file system grows to fill the disk it finds itself on.

`make run-vm` uses the host's GPU for the guest's 3D when QEMU can (virgl),
gives the guest a sound card, and takes options through `VM_ARGS`: `--share
DIR` shares a host directory (`mount -t virtiofs host /mnt` in the guest),
`--sound virtio`, `--no-gl`, `--memory`, `--cpus`. Delete `build/vm` to start
again from the image.

To change the system you are running, as its developer:

```
edit packages/NAME, bump .release in its package.zon
bootstrap/build-packages.sh NAME      on the build machine
make serve-repo                       leave it running

doas dave upgrade                     in the virtual machine
reboot
```

`dave install NAME` in the machine takes a package from the same place.

The bootstrap follows Linux From Scratch, and the desktop Beyond Linux From
Scratch (systemd, development branches), with the same package versions. Recipes are described in [packages/README.md](packages/README.md).

## Layout

| Path | What it is |
|------|------------|
| `dave/` | The package manager and deployment tool |
| `packages/` | One recipe per package, and the build order |
| `bootstrap/` | Scripts that build the first toolchain and then every package |
| `system/` | dave's systemd units |
| `image/` | Image and live medium specifications, and the scaffold's scripts |
| `installer/` | The graphical installer |
| `tests/` | Command-line tests and VM scenarios, as neomake tests (`*.tomlx`) |
| `.github/workflows/` | The unit and command-line tests for pushes and pull requests, and the container image |

## Not done yet

- **Declarations beyond the desktop.** The privileged services and set-uid
  programs of the desktop, the boot helpers systemd-tmpfiles, sysusers,
  repart and growfs, the manual page indexer, nginx and the rsync daemon
  hold declarations of their own. The optional PostgreSQL, Unbound, chrony,
  BIND, dnsmasq, HAProxy, Valkey, nftables and OpenVPN units also start
  programs with explicit declarations. An undeclared privileged server can
  still inherit `all` from systemd. The make-ca updater, wg-quick and
  Postfix's service control script run with the shell's declaration.
  Printing, Bluetooth, modems and ssh logins have declarations based on
  their upstream units. Their service workloads still need tests. `dave repo audit
  build/repo` lists the undeclared programs and any invalid or missing
  seals.
- **D-Bus services without a unit.** dbus-daemon-launch-helper is not
  set-uid (files are root's, and a recipe may not give it to messagebus), so
  a system bus service that systemd does not start, cups-pk-helper among
  them, cannot be started over D-Bus.
- **The rest of the trust chain.** Kernel modules are checked by the module
  but not by the kernel's own signature enforcement; there is no kernel
  lockdown and no Secure Boot, so root can still replace the kernel or its
  command line. There is no way yet to sign software built on the machine.
  Interpreters other than bash and Python (awk, sed, perl) do not ask before
  running a script.
- **Real hardware.** Firmware, processor microcode, Wi-Fi (through
  NetworkManager and wpa_supplicant) and the Intel, AMD and NVIDIA graphics
  drivers are there, but have been tried on few machines. Mesa also supplies
  Vulkan drivers for Intel, AMD, virtio and software rendering. The lavapipe
  software path has been smoke-tested; hardware Vulkan remains unverified.
  Video is decoded on the GPU through VA-API with Mesa's drivers (AMD, nouveau,
  virtual machines), but Intel's VA-API driver is not packaged.
  The kernel boots without an initramfs, which is enough for internal disks
  but not for encrypted or multi-device roots. The installer neither
  encrypts nor resizes: beside another system it needs free space made
  beforehand. There is no Secure Boot.
- **Desktop gaps.** No graphical front end to dave. Only the English (US)
  locale is built, so that is the one language the first-run setup offers.
  No mail client. LibreOffice is in the repository but not installed by
  default. WebKitGTK and its applications, Chromium, QtWebEngine and
  Thunderbird are not built yet.
- **Split packages.** A package is everything its upstream installs, so the
  base image carries the compiler because programs need its run-time libraries.
- **Builds are not isolated from each other.** Every recipe builds in one
  shared build root. A fresh, minimal build root per package, chosen by the
  solver, comes later. Recipes marked `.network = true` fetch their locked
  Rust, Go, Haskell, JavaScript or Java dependencies from the network while
  building, until those are kept as sources of their own. Rust, Go, GHC and
  OpenJDK are each first compiled by a prebuilt compiler: their upstream's,
  or for OpenJDK the book's.
  The TypeScript compiler (needed to build one application) is its upstream's
  already-compiled release, and bun and Julia (which only the installation
  medium has, to run pour) are upstream's binaries, repackaged.
- **Building dave inside joe.** joe packages Zig 0.17.1 now, but the dave
  package is still the static binary cross-built on the build machine.
- Virtual packages (`provides`), and changing the kernel on a running system
  (use `dave upgrade`).

## Licence

joe Linux's own code is under the [MIT License](LICENSE). The security module
is GPL-2.0-only, as part of the kernel, and the patches to other projects
(bash's and Python's among them) are under those projects' licences. The
recipes follow Linux From Scratch and Beyond LFS.
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) has the details, including
what to know before distributing an image built from these recipes.
