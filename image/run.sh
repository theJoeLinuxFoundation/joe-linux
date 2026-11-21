#!/bin/bash
# Boots a joe Linux image in QEMU.
#
#   run.sh [IMAGE]              serial console on this terminal
#                               (default image: build/images/joe.img; leave with Ctrl-A X)
#   run.sh --desktop [IMAGE]    a window with the graphical session
#                               (default image: build/images/joe-desktop.img)
#   run.sh --persist DIR [IMAGE]
#                               a machine that keeps its disk: DIR/disk.img is
#                               made from IMAGE the first time (default image:
#                               build/images/joe-release.img) and booted, as it
#                               then is, every time after. Implies --desktop.
#   run.sh --iso ISO            a computer with an empty disk and the
#                               installation medium ISO in its CD drive, in a
#                               window: the live session and its installer.
#                               The machine is kept in build/images/run-iso,
#                               so after installing, it starts the installed
#                               system (delete that directory to start over).
#
# Without --persist the image is not modified: the VM runs on a copy that the
# next run replaces.
#
# Options:
#   --create           with --persist: make DIR/disk.img and stop
#   --disk-size SIZE   with --persist: size of a new disk (default 64G, sparse);
#                      the guest grows its root file system to fill it
#   --share DIR        share a host directory with the guest (needs virtiofsd).
#                      In the guest: mount -t virtiofs host /mnt
#   --sound MODEL      hda (default) or virtio
#   --no-gl            do not use the host's GPU for the guest's 3D
#   --memory SIZE, --cpus N
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
ovmf_code=${OVMF_CODE:-/usr/share/edk2/x64/OVMF_CODE.4m.fd}
ovmf_vars=${OVMF_VARS:-/usr/share/edk2/x64/OVMF_VARS.4m.fd}
qemu=${QEMU:-qemu-system-x86_64}
desktop=0 persist= create=0 disk_size=64G share= sound=hda gl=auto memory= cpus= iso=
while [[ $# -gt 0 ]]; do
    case $1 in
        --desktop) desktop=1; shift ;;
        --persist) persist=$2; desktop=1; shift 2 ;;
        --iso) iso=$2; desktop=1; shift 2 ;;
        --create) create=1; shift ;;
        --disk-size) disk_size=$2; shift 2 ;;
        --share) share=$2; shift 2 ;;
        --sound) sound=$2; shift 2 ;;
        --no-gl) gl=no; shift ;;
        --memory) memory=$2; shift 2 ;;
        --cpus) cpus=$2; shift 2 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
[[ $create -eq 0 || -n $persist ]] || { echo "--create needs --persist DIR" >&2; exit 2; }

default=joe.img
[[ $desktop -eq 1 ]] && default=joe-desktop.img
[[ -n $persist ]] && default=joe-release.img
image=${1:-$top/build/images/$default}

if [[ -n $iso ]]; then
    [[ -e $iso ]] || { echo "no ISO at $iso; build one with 'make iso'" >&2; exit 1; }
    iso=$(realpath "$iso")
    work=$top/build/images/run-iso
    if [[ ! -e $work/disk.img ]]; then
        mkdir -p "$work"
        truncate -s "$disk_size" "$work/disk.img"
        cp "$ovmf_vars" "$work/OVMF_VARS.fd"
        echo "new machine in $work: an empty $disk_size disk"
    fi
elif [[ -n $persist ]]; then
    work=$persist
    if [[ ! -e $work/disk.img ]]; then
        [[ -e $image ]] || { echo "no image at $image; build it first (see 'make help')" >&2; exit 1; }
        mkdir -p "$work"
        cp --reflink=auto --sparse=always "$image" "$work/disk.img.new"
        # Only the disk grows here. The guest moves the partition table's
        # backup to the new end and extends its root on the next boot
        # (usr/lib/repart.d, systemd-growfs-root.service).
        truncate -s "$disk_size" "$work/disk.img.new"
        cp "$ovmf_vars" "$work/OVMF_VARS.fd"
        mv "$work/disk.img.new" "$work/disk.img"
        echo "new machine in $work ($disk_size disk, from $(basename "$image"))"
    elif [[ $create -eq 1 ]]; then
        echo "$work/disk.img already exists; delete $work to start over"
    fi
    [[ $create -eq 0 ]] || exit 0
else
    [[ -e $image ]] || { echo "no image at $image; build it first (see 'make help')" >&2; exit 1; }
    work=$top/build/images/run
    mkdir -p "$work"
    cp --reflink=auto --sparse=always "$image" "$work/disk.img"
    cp "$ovmf_vars" "$work/OVMF_VARS.fd"
fi

if [[ $desktop -eq 1 ]]; then
    : "${memory:=6G}" "${cpus:=8}"
else
    : "${memory:=2G}" "${cpus:=4}"
fi

args=(
    -enable-kvm -cpu host -machine q35 -m "$memory" -smp "$cpus"
    -drive if=pflash,format=raw,readonly=on,file="$ovmf_code"
    -drive if=pflash,format=raw,file="$work/OVMF_VARS.fd"
    -drive file="$work/disk.img",format=raw,if=virtio
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0
)
# No boot order is imposed: the firmware tries what it has been told about
# first (the installed system, once there is one) and then the devices, the
# empty disk and the CD, as a computer would.
[[ -z $iso ]] || args+=(-drive if=none,id=medium,format=raw,media=cdrom,readonly=on,file="$iso" -device ide-cd,drive=medium)

if [[ -n $share ]]; then
    [[ -d $share ]] || { echo "--share: $share is not a directory" >&2; exit 1; }
    virtiofsd=$(command -v virtiofsd || true)
    [[ -n $virtiofsd ]] || virtiofsd=/usr/lib/virtiofsd
    [[ -x $virtiofsd ]] || { echo "--share needs virtiofsd, which is not installed" >&2; exit 1; }
    # A socket's path may be about a hundred characters at most, so it goes
    # somewhere short rather than next to the disk.
    runtime=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/joe-share.XXXXXX")
    trap 'kill "${daemon:-}" 2>/dev/null; rm -rf "${runtime:?}"' EXIT
    socket=$runtime/virtiofs.sock
    # virtiofsd runs as the invoking user, in a user namespace of its own, so
    # the guest can do in the directory exactly what that user can. Whoever
    # writes in the guest writes as that user, and in the guest every file
    # appears to belong to the first account (uid 1000).
    "$virtiofsd" --socket-path "$socket" --shared-dir "$share" \
        --translate-uid squash-guest:0:0:4294967295 --translate-gid squash-guest:0:0:4294967295 \
        --translate-uid squash-host:0:1000:4294967295 --translate-gid squash-host:0:1000:4294967295 \
        >"$work/virtiofsd.log" 2>&1 &
    daemon=$!
    for _ in $(seq 50); do [[ -S $socket ]] && break; sleep 0.1; done
    [[ -S $socket ]] || { echo "virtiofsd did not start; see $work/virtiofsd.log" >&2; exit 1; }
    # vhost-user devices need the guest's memory to be shared with the daemon.
    args+=(
        -object memory-backend-memfd,id=mem,size="$memory",share=on -numa node,memdev=mem
        -chardev socket,id=vfs,path="$socket"
        -device vhost-user-fs-pci,chardev=vfs,tag=host
    )
fi

if [[ $desktop -eq 0 ]]; then
    "$qemu" "${args[@]}" -nographic
    exit
fi

# 3D in the guest is drawn by the host's GPU through virgl when QEMU has the
# device and a GL display; otherwise the guest renders in software.
if [[ $gl == auto ]]; then
    gl=no
    if "$qemu" -device help 2>/dev/null | grep -q '"virtio-vga-gl"' &&
        [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
        gl=yes
    fi
fi
if [[ $gl == yes ]]; then
    args+=(-device virtio-vga-gl -display gtk,gl=on)
else
    args+=(-device virtio-vga -display gtk)
fi

case $sound in
    hda) args+=(-device intel-hda -device hda-duplex) ;;
    virtio) args+=(-device virtio-sound-pci) ;;
    *) echo "--sound: hda or virtio" >&2; exit 2 ;;
esac

"$qemu" "${args[@]}" \
    -device virtio-keyboard-pci -device virtio-tablet-pci \
    -serial mon:stdio
