# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

joe Linux is an independent distribution built from source. These parts are original and live here; everything else is deliberately ordinary (glibc, systemd, usr-merge, GNOME), so prefer the conventional option when unsure.

1. **dave** (`dave/`): a package manager and deployment tool in Zig, with a PubGrub solver. It also builds every image (`dave image build`) and installs systems (`dave install-system`).
2. **Transactional upgrades on a writable root**: btrfs snapshots plus systemd-boot boot counting.
3. **The joe security module** (`packages/linux/joe-lsm/joe.c`): an LSM that restricts privileged processes to signed ("sealed") code and declared operations.
4. **The installer** (`installer/`): a Qt Quick front end to `dave install-system`, run from the live medium (`image/live.zon`).

README.md explains the design; `packages/README.md` is the recipe-writing reference. Read the latter before touching anything in `packages/`.

## Hard constraints

- **Nothing runs as root on the host, and sudo is not available.** Root-owned trees are made with `unshare --map-root-user`, build chroots with `bwrap`, disk images with `mkfs.btrfs --rootdir` and mtools (never mounted), and anything that truly needs root runs inside QEMU/KVM. Do not introduce steps that need sudo or docker.
- **Zig 0.17.1.** It uses `pub fn main(init: std.process.Init)` and the `std.Io` interface; older idioms do not compile. Check the std source (`zig env` gives the lib dir) rather than relying on memory. Known traps: a directory opened without `.iterate = true` is path-only and ioctls on it fail with EBADF; `Io.Dir.readFileAlloc` returns 0 bytes for some procfs files; std has zstd decompression only, which is why writing packages pipes through the `zstd` program.
- `build/` must be on btrfs (reflink copies, subvolumes). All generated state lives there and is git-ignored.
- The VM harness uses Arch's OVMF paths (`/usr/share/edk2/x64/OVMF_*.4m.fd`). For `image/run.sh`, set `OVMF_CODE` and `OVMF_VARS` to select another firmware image and variables template.
- **Installed joe systems boot without an initramfs** (only the live medium has one), so the kernel mounts the root itself and, until udev has processed the partition, btrfs reports the root's device as `/dev/root`. Anything that needs the root's block device early in boot (systemd-repart, systemd-growfs) must run after udev; `packages/joe-base/build.sh` ships the drop-ins that arrange this.

## Commands

```
make dave                  build dave/zig-out/bin/dave (ReleaseSafe, static, no libc)
make test                  Zig unit tests + the command-line tests (tests/cli.tomlx); takes seconds, no VM
make test-boot-contract    smoke + systemd-boot assumptions, in a VM on the scaffold image
make test-deployments      upgrade/rollback/power-loss scenarios on the scaffold image
make bootstrap             LFS cross toolchain and temporary tools (stage1 + stage2)
make packages              build every recipe into build/repo
make image / make run      build/images/joe.img; boot it on this terminal (Ctrl-A X to leave)
make test-joe              deployment scenarios on an image built from joe's own packages
make test-security         the security module's three rules, in a VM
make desktop-image / run-desktop / test-desktop     the GNOME image
make release-image / test-release                   the desktop without test accounts; its first boot, in a VM
make vm / run-vm / serve-repo                       a VM that keeps its disk (build/vm), and build/repo served to it
make iso-tools             xorriso and squashfs-tools (and mtools) into build/host-tools
make iso                   build/images/joe-live.iso, the installation medium
make test-live             boot the medium as a CD and as a USB stick
make test-install          install from the medium onto an empty disk, then boot and check that
make container             build/images/joe-container.tar, joe as an OCI container image
```

A subset of unit tests (the filter matches test names and file paths such as `solver.version`):

```
cd dave && zig test src/main.zig -target x86_64-linux-none --test-filter "version"
```

Tests run with [neomake](https://github.com/theJoeLinuxFoundation/neomake): `neomake.tomlx` and the files it includes, `tests/cli.tomlx` and `tests/vm/*.tomlx`, define the tests, the images only tests use, the machines and the repositories served to them; the Makefile's test targets call it (`NEOMAKE=/path/to/neomake` picks the binary). `neomake test NAME...` runs tests and what they depend on (`'cli-*'`, `deployments`), `neomake list --tests -v` shows every test and whether this machine can run it, `neomake test --dry-run` what a run would do, `neomake check` validates the files. A test whose tool, KVM or `build/repo` is missing is skipped with the reason, not failed. Every run keeps its logs, `report.json` and each test's files in `build/neomake/runs/<time>/` (`latest` is the newest; `neomake log NAME` prints one); a VM test's directory has `console.log` and, when it failed, its disk. A failure names the step and its line.

The command-line tests (`tests/cli.tomlx`) are one chain of tests sharing `build/cli-test`, each depending on the one before; `DAVE=/path/to/dave` overrides the binary. The network tests serve the repository from `127.0.0.1` over HTTP and HTTPS on free ports (neomake's file server, `services.cli-net`), with a throwaway CA laid over `/etc/ssl` with `bwrap`, so they need `openssl` and `bwrap`; the container test needs `python3`.

Build specific packages (in dependency order, into the shared build root):

```
bootstrap/build-packages.sh NAME...
```

This is resumable by file name: a package whose `NAME-VERSION-rRELEASE-x86_64.dave` already exists in `build/repo` is skipped. After changing a recipe, bump `.release` in its `package.zon` (or delete the file) or nothing is rebuilt. A failed build's full log is `build/work/NAME/build.log`.

Other tools: `bootstrap/order.py [NAME...]` prints the build order and reports missing recipes and cycles; `bootstrap/enter.sh [--net] CMD` runs a command inside the build root; `packages/.build/book.py [--blfs] PAGE` prints an LFS/BLFS page's commands for writing a recipe.

The VM tests are neomake tests (`tests/vm/*.tomlx`): `smoke`, `boot-contract` and `deployments` on the scaffold; `deployments-joe`, `security` and `security-share` on joe's console image; `desktop` and `desktop-enforcing`; `release` and `release-share`; `live[media=cd]` and `live[media=usb]`; `install`, `install-enforcing`, `install-import` and `install-beside`. `desktop-enforcing` and `install-enforcing` fail on anything the security module denied, so a new privileged service needs its declaration (`.operations`) before it ships. Steps run in the machine over its serial console, on the host (`host`: to publish packages while the machine runs, with `tests/lib/repo.sh`, to read what it wrote to a shared directory, or to check JSON it printed with `jq`), or drive the machine (`reboot`, `power_cut`, `expect`, `send`, `screenshot`, `kill`, `detach`). Their images are built by neomake tasks. The deployment and security images are rebuilt on every run, each with a fresh repository of test packages (`build/vm-repo-scaffold` served on 8642, `build/vm-repo-joe` on 8644, `build/vm-repo-security`; `build/repo` is served on 8643). The desktop, release and live images are rebuilt only when `image/`, `build/repo/repo.zon`, the keys or dave change. The tests that share a host directory over virtiofs are tests of their own (`*-share`), so a host without virtiofsd skips only them. The live medium's system runs the *packaged* dave, so a dave change reaches `live` and `install` only after the `dave` package is rebuilt. What a test's machine printed, its screenshots and (if it failed) its disks are in `build/neomake/runs/latest/tests/NAME/`.

## Images

Every image is a specification in `image/*.zon` built by `dave image build SPEC --out FILE [--test] --repo NAME,DIR,URL,KEY [--with PKG] [--tree DIR]` (`dave/src/image.zig`; the layout is `provision.zig`, shared with `dave install-system`). Specs are parsed strictly: an unknown field is an error. Repository URLs are always given on the command line, never written in a spec. `image/mkjoe.sh` is a compatibility wrapper for the build machine's `joe-build`, to be removed once that is redeployed.

- The **scaffold** (`image/scaffold.zon`, tree prepared by `image/mkscaffold*.sh`) is the host's kernel and systemd-boot plus a stock Arch userspace with dave added. It exists so deployment mechanics can be tested in minutes without building the distribution. Nothing from it ships, and it has no security module.
- The **joe images** (`console.zon`, `desktop.zon`) are one `dave install` transaction of `joe-base` (or `joe-desktop`) into an empty directory, laid out as a raw GPT disk without mounting anything. They need `make bootstrap` and `make packages` first, which take an hour or more (the desktop set several hours).
- The **release image** (`release.zon`) is `joe-desktop` alone: no test console, no ready-made user, root locked. GDM starts gnome-initial-setup because no account exists. `tests/vm/release.tomlx` boots the same package set plus `joe-test-console` (`--test`), because the tests have no other way in.
- The **live medium** (`live.zon`, `.format = .iso`, `dave/src/iso.zig`) is a hybrid UEFI ISO: the root as an xz-compressed SquashFS image with a tmpfs overlay (`joe-live` package: live user, masks), an initramfs made by a second dave transaction plus `image/initrd/`'s mount units, and what the installer installs (`joe/install.zon`). The installer copies those packages out of the live root image (`/run/live/lower`) by the manifests in its database (`txn.Copy`), so the medium carries no package files; the files the live root changed are kept as packaged in `joe/originals/<sha256>`, and the build fails if the live root lacks part of the payload. Nothing on it is sealed, so it runs the security module in log mode (`joe=log` on its command line). It also carries pour and Julia (`packages/pour`, `packages/julia`, upstream's binary), for `dave install-system --import`; neither is installed onto a disk.
- The **container image** (`container.zon`, `.format = .oci`, `dave/src/oci.zig`) is an OCI image layout archived with tar, one gzip layer. `.github/workflows/container.yml` builds it from the published repository (the repository variables `JOE_REPO_URL` and `JOE_REPO_KEY`) and pushes it to `ghcr.io/<owner>/joe`; it is run by hand after a release. `make container` builds it from build/repo.

`--test` images add `joe-test-console`: root is logged in on ttyS0 with the prompt `joe# `, which the VM tests (`tests/vm/*.tomlx`) depend on. A `--test` medium also gets `console=ttyS0,115200` and puts `joe-test-console` in what it installs; `dave install-system` copies only `console=` arguments from the live command line into the installed system.

## Architecture

### dave (`dave/src/`)

One static binary serves as package manager, build tool, repository tool and boot-time service. `main.zig` dispatches; each module opens with a `//!` comment stating its design, and those comments are the documentation. `cli.zig` holds two tables, the commands and the options (with the commands each applies to), from which argument parsing, `dave help` (`help.zig`) and the shell completions (the hidden `dave complete`) are all made: a new command or option is one table entry, plus its line in `dave/share/dave.8`, which `tests/cli.tomlx` checks (`cli-manual`). What a person sees on a terminal is decided in `ui.zig`: colour and the redrawn progress line are off for pipes, `--json` and `TERM=dumb` (which the test console sets), and `NO_COLOR` turns colour off. `install` and `remove` ask `Continue? [Y/n]` when they would change more than was named, whenever standard input and output are terminals, and the VM harness's serial console is one: a VM test must install and remove exactly what it names, or pass `-y`.

The flow of a change: `etc/dave/world` is the only statement of intent (the Alpine model). `resolve.zig` solves world against the signed repository indexes (`repo.zig`) with `solver/pubgrub.zig`, and the transaction is the difference from what is installed (`db.zig`). `solver/report.zig` turns a failed solve into the prose explanation users see. `txn.zig` applies a transaction to a root directory; it has no undo log and relies on being pointed at a snapshot that can be thrown away.

A system installed beside another (`dave install-system --beside`) shares the disk's ESP, which then holds only systemd-boot, and keeps its entries and kernels on an XBOOTLDR partition mounted at `/boot`: `deploy.System.bootDir()` is where entries live, `esp` only where the loader is. Nothing of another system's on the shared ESP may be replaced, the firmware's fallback `EFI/BOOT/BOOTX64.EFI` included.

`install` and `remove` apply live after taking a bootable snapshot. Only `upgrade` is deferred: `deploy.zig` stages a plan, and `dave finalize` at shutdown snapshots the root as it then is, applies the plan to the snapshot, and writes the boot entry last. `boot.zig` keeps no state of its own: priority and health are encoded in systemd-boot entry file names (`joe-<id>+3.conf`), and those assumptions are pinned by `tests/vm/boot-contract.tomlx`.

Invariants that span files:

- The package database is at `usr/lib/dave/db` *inside* the root so every snapshot carries its own. `/etc` belongs to the deployment; `/var` and `/home` are shared subvolumes. That is why nothing under `/var` may be packaged and why system users need fixed ids.
- The manifest (`manifest.zig`) is authoritative for all file metadata; the archive (`archive.zig`) carries regular-file contents only.
- There are no install scripts. Post-install work is a declarative trigger file under `usr/lib/dave/triggers/` (`triggers.zig`).
- `dave build` (`builder.zig`) runs `packages/.build/driver.sh` inside the build root. The driver sources the recipe's `build.sh`, then strips binaries and removes `.la` files, docs and `var`/`run`/`tmp` for every package.

### Seals and the security module

`dave/src/seal.zig` (userspace) and `packages/linux/joe-lsm/joe.c` (kernel) must agree byte for byte on the seal format: fs-verity digest plus a `security.joe` xattr holding the declared operations and a signature over both. Change one and you must change the other, then run `make test-security`.

- The module is not a kernel fork. `packages/linux/joe-lsm/install.sh` copies it into the unpacked kernel tree and splices it in with anchored `sed` edits that fail loudly when a kernel update moves an anchor.
- `joe_keys.h` is generated by `bootstrap/build-packages.sh` from `build/keys/joe-code.pub`. The kernel therefore trusts only packages sealed with this build directory's key; a new key means rebuilding `linux`.
- bash and Python carry patches (`packages/bash/joe-sealed-scripts.patch`, `packages/python/joe-sealed-code.patch`) that ask the module, via an ioctl on the open script, before running it.
- Operations are declared per program in `package.zon` (`.operations`); the vocabulary is validated in `seal.zig`. A program no declaration covers is sealed `undeclared`; `dave repo audit build/repo` (or `make audit-security`) finds those and invalid seals.
- Images are assembled unprivileged and so cannot be sealed at build time; `dave-seal.service` does it on first boot. `dave install-system` runs as root and seals while installing, so an installed system's first boot has nothing to seal.
- The module only logs unless the kernel is booted with `joe=enforce`.

### Packages and build order

`packages/NAME/` holds `package.zon` and `build.sh` (sourced, so nothing at top level). The base system builds in the hand-written order of `packages/ORDER`, because those packages replace the bootstrap's temporary tools one by one. Every other recipe is ordered by `bootstrap/order.py` from `depends` and `build_depends`, which must therefore be complete. All recipes build in one shared build root, `build/bootstrap/root`, which dave itself manages; each package is installed into it after being built unless marked build-only.

Recipes follow Linux From Scratch and Beyond LFS (systemd, development branch). Take versions, URLs and flags from the book page, not from memory.

### Files that exist in more than one place

- dave's systemd units are in `system/`. They are installed by both `packages/dave/build.sh` (real images) and `image/add-dave.sh` (scaffold); adding or renaming a unit means editing both. Units are enabled by shipping symlinks.
- `packages/joe-installer/files/` is likewise populated with a copy of `installer/`.
- `packages/joe-release/build.sh` holds the kernel's and dave's versions, because releases are named J<revision>-<kernel>-<dave>[-<stage>] (README.md, "Releases"). Changing either version means changing it there too and bumping `joe-release`'s `.release`; `tests/vm/live.tomlx` checks they agree.
- `packages/gcc-fortran` builds the same GCC source as `packages/gcc` and pins `gcc =VERSION` in its `depends`; changing gcc's version means changing both. `packages/libxml2-python` does the same with `packages/libxml2`.
- `packages/linux-firmware-extra` builds the same source as `packages/linux-firmware` and holds exactly what that leaves out (Qualcomm Arm SoCs, server network and switch chips); the list of paths is in both `build.sh` files, and the versions must match.
- `dave/share/` holds dave's manual page and its bash, zsh and fish completions. Like the units, they are installed by both `packages/dave/build.sh` and `image/add-dave.sh`.
- `packages/dave/files/` is populated by `build-packages.sh` with the freshly built binary, `system/*` and `dave/share/*`. joe packages Zig 0.17.1. The dave recipe still takes the static binary cross-built on the host. A dave change reaches an image only after the `dave` package is rebuilt, which needs a `.release` bump in `packages/dave/package.zon`.
## Git

- Commit messages: `area: imperative summary`, lowercase, no trailing period.
- Never add `Co-Authored-By`, `Generated-with`, `Assisted-by` or any similar
  trailer. Not once, not for a small change. Treat it as a rule violation.
- The author line is the human who committed it.