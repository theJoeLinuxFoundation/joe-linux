# joe Linux: top-level build and test entry points.
#
# Everything here runs as an ordinary user. Nothing needs root on the host.

DAVE := dave/zig-out/bin/dave
# The tests, and the images only they use, are run by neomake (neomake.tomlx,
# tests/*.tomlx); NEOMAKE=/path/to/neomake picks another binary.
NEOMAKE ?= neomake
# Tools image builds need that the host may not have are built here.
export PATH := $(CURDIR)/build/host-tools/bin:$(PATH)
# Images read joe's repository from build/repo and are configured to fetch from
# http://10.0.2.2:8643: this machine as a QEMU guest sees it (make serve-repo).
REPO := --repo joe,$(CURDIR)/build/repo,http://10.0.2.2:8643,$(CURDIR)/build/keys/joe.pub

.PHONY: help dave test scaffold test-boot-contract test-deployments \
        bootstrap packages image run test-joe test-security audit-security \
        desktop-image run-desktop test-desktop \
        release-image test-release vm run-vm serve-repo iso-tools iso run-iso test-live test-install container clean

help:
	@echo "dave"
	@echo "  make dave                 build the package manager"
	@echo "  make test                 unit tests and command-line tests (seconds)"
	@echo ""
	@echo "deployment mechanics on a throwaway scaffold image (minutes, needs KVM)"
	@echo "  make test-boot-contract   what the design assumes about systemd-boot"
	@echo "  make test-deployments     upgrade, rollback, power loss, broken upgrade"
	@echo ""
	@echo "joe Linux from source (about an hour on a 32-core machine)"
	@echo "  make bootstrap            cross toolchain and temporary tools"
	@echo "  make packages             build every recipe into build/repo"
	@echo "  make image                bootable image at build/images/joe.img"
	@echo "  make run                  boot that image in QEMU on this terminal"
	@echo "  make test-joe             the deployment tests on that image"
	@echo "  make test-security        the security module's rules, in a VM"
	@echo "  make audit-security       package seal and declaration audit"
	@echo ""
	@echo "the desktop (several more hours to build the first time)"
	@echo "  make desktop-image        bootable GNOME image at build/images/joe-desktop.img"
	@echo "  make run-desktop          boot it in a QEMU window (user joe, password joe)"
	@echo "  make test-desktop         session and applications, with and without enforcement"
	@echo ""
	@echo "a machine to keep (see README.md, 'Living in it')"
	@echo "  make release-image        the desktop without the test accounts: build/images/joe-release.img"
	@echo "  make test-release         its first boot: disk growth, first-run setup, sound, shared folder"
	@echo "  make vm                   a virtual machine with its own 64G disk in build/vm, made from that image"
	@echo "  make run-vm               boot it; what you do in it stays (VM_ARGS='--share DIR' passes options)"
	@echo "  make serve-repo           offer build/repo to that machine, for 'dave upgrade'"
	@echo ""
	@echo "the installation medium (image/live.zon)"
	@echo "  make iso                  build/images/joe-live.iso: a live session with the installer"
	@echo "  make run-iso              boot the newest ISO in a window beside an empty disk (ISO=FILE for another)"
	@echo "  make test-live            boot it as a CD and as a USB stick"
	@echo "  make test-install         install from it onto an empty disk, then boot that"
	@echo ""
	@echo "the container image (image/container.zon)"
	@echo "  make container            build/images/joe-container.tar, an OCI archive (docker load -i, podman load -i)"

$(DAVE): $(wildcard dave/src/*.zig dave/src/solver/*.zig) dave/build.zig
	cd dave && zig build -Doptimize=ReleaseSafe

dave: $(DAVE)

test:
	$(NEOMAKE) test unit 'cli-*'

MTOOLS := mtools-4.0.49
MTOOLS_SHA256 := 6fe5193583d6e7c59da75e63d7234f76c0b07caf33b103894f46f66a871ffc9f

build/host-tools/bin/mcopy:
	mkdir -p build/src build/host-tools
	cd build/src && [ -e $(MTOOLS).tar.bz2 ] || curl -fsSLO https://ftp.gnu.org/gnu/mtools/$(MTOOLS).tar.bz2
	cd build/src && echo "$(MTOOLS_SHA256)  $(MTOOLS).tar.bz2" | sha256sum -c --quiet
	cd build/src && rm -rf mtools && mkdir mtools && tar -xf $(MTOOLS).tar.bz2 -C mtools --strip-components=1
	cd build/src/mtools && ./configure --prefix=$(CURDIR)/build/host-tools --disable-floppyd && $(MAKE) && $(MAKE) install

# What a live ISO is made with: its compressed root (SquashFS) and the ISO itself.
XORRISO := xorriso-1.5.8.pl02
XORRISO_SHA256 := b1455ecafbf0692ddafe1d71002a96f2ce2d77f4deae602678261ce033f97bc8
SQUASHFS := squashfs-tools-4.7.5
SQUASHFS_SHA256 := 547b7b7f4d2e44bf91b6fc554664850c69563701deab9fd9cd7e21f694c88ea6

build/host-tools/bin/xorriso:
	mkdir -p build/src build/host-tools
	cd build/src && [ -e $(XORRISO).tar.gz ] || curl -fsSLO https://ftp.gnu.org/gnu/xorriso/$(XORRISO).tar.gz
	cd build/src && echo "$(XORRISO_SHA256)  $(XORRISO).tar.gz" | sha256sum -c --quiet
	cd build/src && rm -rf xorriso && mkdir xorriso && tar -xf $(XORRISO).tar.gz -C xorriso --strip-components=1
	cd build/src/xorriso && ./configure --prefix=$(CURDIR)/build/host-tools && $(MAKE) && $(MAKE) install

# mksquashfs and unsquashfs, with the xz and zstd compressors only: they need
# the host's xz and zstd libraries and headers, and nothing else.
build/host-tools/bin/mksquashfs:
	mkdir -p build/src build/host-tools/bin
	cd build/src && [ -e $(SQUASHFS).tar.gz ] || curl -fsSLO https://github.com/plougher/squashfs-tools/releases/download/$(subst squashfs-tools-,,$(SQUASHFS))/$(SQUASHFS).tar.gz
	cd build/src && echo "$(SQUASHFS_SHA256)  $(SQUASHFS).tar.gz" | sha256sum -c --quiet
	cd build/src && rm -rf squashfs-tools && mkdir squashfs-tools && tar -xf $(SQUASHFS).tar.gz -C squashfs-tools --strip-components=1
	$(MAKE) -C build/src/squashfs-tools/squashfs-tools GZIP_SUPPORT=0 LZO_SUPPORT=0 LZ4_SUPPORT=0 \
	    XZ_SUPPORT=1 ZSTD_SUPPORT=1 COMP_DEFAULT=xz INSTALL_DIR=$(CURDIR)/build/host-tools/bin INSTALL_MANPAGES_DIR= install

iso-tools: build/host-tools/bin/mcopy build/host-tools/bin/xorriso build/host-tools/bin/mksquashfs

# The scaffold image (tests/vm/machines.tomlx): rebuilt when dave, the
# bootstrap tarball or the scaffold's scripts change.
scaffold: build/host-tools/bin/mcopy
	$(NEOMAKE) run scaffold-image

test-boot-contract: build/host-tools/bin/mcopy
	$(NEOMAKE) test smoke boot-contract

test-deployments: build/host-tools/bin/mcopy
	$(NEOMAKE) test deployments

build/lfs/wget-list:
	mkdir -p build/lfs build/src
	curl -fsSL -o build/lfs/wget-list https://www.linuxfromscratch.org/lfs/view/systemd/wget-list
	curl -fsSL -o build/lfs/md5sums https://www.linuxfromscratch.org/lfs/view/systemd/md5sums
	cd build/src && xargs -P 8 -n 1 curl -fsSL --retry 3 -O < ../lfs/wget-list
	cd build/src && md5sum -c --quiet ../lfs/md5sums

bootstrap: build/lfs/wget-list
	bootstrap/stage1.sh
	bootstrap/stage2.sh

packages: $(DAVE)
	bootstrap/build-packages.sh

# Images are described by image/*.zon and built by `dave image build`.
# --test: root logs in on the serial console without a password, which is how
# the tests look inside and how a demonstration image is used.
image: build/host-tools/bin/mcopy $(DAVE)
	mkdir -p build/images
	$(DAVE) image build image/console.zon --test $(REPO) --out build/images/joe.img

run:
	image/run.sh

test-joe: build/host-tools/bin/mcopy
	$(NEOMAKE) test deployments-joe

test-security: build/host-tools/bin/mcopy
	$(NEOMAKE) test 'security*'

audit-security: $(DAVE)
	$(DAVE) repo audit build/repo

# Like `image`, a test image: it has a ready-made user (joe, password
# joe) who is logged in automatically.
desktop-image: build/host-tools/bin/mcopy $(DAVE)
	mkdir -p build/images
	$(DAVE) image build image/desktop.zon --test $(REPO) --out build/images/joe-desktop.img

run-desktop:
	image/run.sh --desktop

test-desktop: build/host-tools/bin/mcopy
	$(NEOMAKE) test 'desktop*'

# What a person would install: no test console, no ready-made account, root
# locked. The first boot asks who you are (gnome-initial-setup).
release-image: build/host-tools/bin/mcopy $(DAVE)
	mkdir -p build/images
	$(DAVE) image build image/release.zon $(REPO) --out build/images/joe-release.img

test-release: build/host-tools/bin/mcopy
	$(NEOMAKE) test 'release*'

# A machine that keeps its disk between runs. `make vm` never replaces an
# existing one; delete build/vm to start again from the release image.
vm:
	@[ -e build/vm/disk.img ] || [ -e build/images/joe-release.img ] || $(MAKE) release-image
	image/run.sh --persist build/vm --create

run-vm:
	image/run.sh --persist build/vm $(VM_ARGS)

# The image's repository is http://10.0.2.2:8643, which is this machine as a
# QEMU guest sees it. After building newer packages, `dave upgrade` in the
# guest finds them here.
# The installation medium. Like the other images it is configured for
# http://10.0.2.2:8643; the build machine makes the published one (joe-build
# iso) with the public repository's URL.
iso: iso-tools $(DAVE)
	mkdir -p build/images
	$(DAVE) image build image/live.zon $(REPO) --out build/images/joe-live.iso

# The medium in a window, with an empty disk to install onto: the newest ISO
# in build/images (make iso, a test's, or a release's), or ISO=FILE.
run-iso:
	@iso='$(ISO)'; [ -n "$$iso" ] || iso=$$(ls -t build/images/*.iso 2>/dev/null | head -n 1); \
	if [ -z "$$iso" ]; then echo "no ISO in build/images; build one with 'make iso'" >&2; exit 1; fi; \
	echo "booting $$iso ($$(date -r "$$iso" '+%F %H:%M'))"; \
	image/run.sh --iso "$$iso"

test-live: iso-tools
	$(NEOMAKE) test live

test-install: iso-tools
	$(NEOMAKE) test 'install*'

# joe as a container image. Inside it, dave takes packages from
# CONTAINER_URL; by default build/repo as make serve-repo offers it, which a
# container on the host's network (docker run --network host) reaches. The
# published image is made by .github/workflows/container.yml.
container: $(DAVE)
	mkdir -p build/images
	$(DAVE) image build image/container.zon --out build/images/joe-container.tar \
		--repo joe,$(CURDIR)/build/repo,$(or $(CONTAINER_URL),http://127.0.0.1:8643),$(CURDIR)/build/keys/joe.pub

serve-repo:
	@echo "serving build/repo on port 8643 (Ctrl-C to stop)"
	python3 -m http.server 8643 --bind 127.0.0.1 --directory build/repo

clean:
	rm -rf dave/.zig-cache dave/zig-out build/cli-test build/work build/neomake
