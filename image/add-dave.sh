#!/bin/bash
# Installs dave and its systemd integration into a root tree. In joe Linux
# proper these files come from the `dave` package; this script puts the same
# files into the scaffold root used for development.
#
#   add-dave.sh ROOTFS DAVE_BINARY
set -euo pipefail
rootfs=$1
binary=$2
system=$(cd "$(dirname "$0")/../system" && pwd)
share=$(cd "$(dirname "$0")/../dave/share" && pwd)
units=$rootfs/usr/lib/systemd/system

install -Dm755 "$binary" "$rootfs/usr/bin/dave"
install -Dm644 "$system/dave-boot-check.service" "$units/dave-boot-check.service"
install -Dm644 "$system/dave-finalize.service" "$units/dave-finalize.service"
install -Dm644 "$system/boot-complete-dave.conf" "$units/boot-complete.target.d/10-dave.conf"
install -Dm644 "$system/dave-seal.service" "$units/dave-seal.service"
install -Dm644 "$system/dave-status.service" "$units/dave-status.service"
install -Dm644 "$system/dave-refresh.service" "$units/dave-refresh.service"
install -Dm644 "$system/dave-refresh.timer" "$units/dave-refresh.timer"

install -Dm644 "$system/dave-tmpfiles.conf" "$rootfs/usr/lib/tmpfiles.d/dave.conf"

# Enabled by shipping the links, not by a post-install step.
mkdir -p "$units/boot-complete.target.requires" "$units/multi-user.target.wants" "$units/sysinit.target.wants" "$units/timers.target.wants"
ln -sf ../dave-seal.service "$units/sysinit.target.wants/dave-seal.service"
ln -sf ../dave-boot-check.service "$units/boot-complete.target.requires/dave-boot-check.service"
ln -sf ../dave-finalize.service "$units/multi-user.target.wants/dave-finalize.service"
ln -sf ../dave-status.service "$units/multi-user.target.wants/dave-status.service"
ln -sf ../dave-refresh.timer "$units/timers.target.wants/dave-refresh.timer"

install -Dm644 "$share/dave.8" "$rootfs/usr/share/man/man8/dave.8"
install -Dm644 "$share/completion.bash" "$rootfs/usr/share/bash-completion/completions/dave"
install -Dm644 "$share/completion.zsh" "$rootfs/usr/share/zsh/site-functions/_dave"
install -Dm644 "$share/completion.fish" "$rootfs/usr/share/fish/vendor_completions.d/dave.fish"

mkdir -p "$rootfs/etc/dave/keys" "$rootfs/usr/lib/dave/db" "$rootfs/usr/lib/dave/triggers"
