prepare() {
    # Groups joe does not define.
    sed -e 's/GROUP="render"/GROUP="video"/' \
        -e 's/GROUP="sgx", //' \
        -i rules.d/50-udev-default.rules.in
}

build() {
    mkdir -p build
    cd build
    # bootloader=enabled makes a missing dependency of systemd-boot an error
    # instead of silently building without it: joe cannot boot without it.
    # The distribution's Secure Boot revocation entry (sbat-distro) is left out
    # until joe signs its boot chain and has a project URL to put in it.
    meson setup .. \
        --prefix=/usr \
        --buildtype=release \
        -D mode=release \
        -D bootloader=enabled \
        -D efi=true \
        -D sbat-distro= \
        -D default-dnssec=no \
        -D firstboot=false \
        -D install-tests=false \
        -D ldconfig=false \
        -D rpmmacrosdir=no \
        -D homed=disabled \
        -D man=disabled \
        -D pam=enabled \
        -D pamconfdir=/etc/pam.d \
        -D dev-kvm-mode=0660 \
        -D nobody-group=nogroup \
        -D sysupdate=disabled \
        -D ukify=disabled \
        -D tpm2=disabled \
        -D vconsole=false
    ninja
}

package() {
    cd build
    DESTDIR="$DESTDIR" ninja install

    # Match the boot helpers' declared capabilities. In particular, their
    # journal sockets can use the normal send buffer without CAP_NET_ADMIN.
    local unit caps
    for unit in systemd-tmpfiles-{setup,setup-dev,setup-dev-early,clean} \
                systemd-sysusers systemd-repart{,@} systemd-growfs{-root,@}; do
        case "$unit" in
            systemd-tmpfiles-*) caps="CAP_CHOWN CAP_DAC_OVERRIDE CAP_DAC_READ_SEARCH CAP_FOWNER CAP_FSETID CAP_MKNOD CAP_SYS_ADMIN" ;;
            systemd-sysusers)   caps="CAP_CHOWN CAP_DAC_OVERRIDE CAP_FOWNER" ;;
            *)                  caps="CAP_SYS_ADMIN" ;;
        esac
        printf '\n[Service]\nCapabilityBoundingSet=%s\n' "$caps" >> "$DESTDIR/usr/lib/systemd/system/$unit.service"
    done

    # Packages have no install scripts. These triggers do, once per
    # transaction, what such scripts would: create the accounts and the files
    # under /var that newly installed packages declare, and rebuild the
    # hardware database.
    install -dm755 "$DESTDIR/usr/lib/dave/triggers"
    cat > "$DESTDIR/usr/lib/dave/triggers/11-sysusers.zon" << "EOF"
.{
    .name = "system accounts",
    .paths = .{"usr/lib/sysusers.d/"},
    .exec = .{"/usr/bin/systemd-sysusers"},
}
EOF
    cat > "$DESTDIR/usr/lib/dave/triggers/12-tmpfiles.zon" << "EOF"
.{
    .name = "declared files and directories",
    // Repeated at every boot by systemd-tmpfiles-setup.service, and unable to
    // set owners where an image is assembled in a user namespace.
    .optional = true,
    .paths = .{"usr/lib/tmpfiles.d/"},
    .exec = .{ "/usr/bin/systemd-tmpfiles", "--create", "--exclude-prefix=/dev", "--exclude-prefix=/proc", "--exclude-prefix=/sys", "--exclude-prefix=/run" },
}
EOF
    cat > "$DESTDIR/usr/lib/dave/triggers/13-hwdb.zon" << "EOF"
.{
    .name = "hardware database",
    .paths = .{"usr/lib/udev/hwdb.d/"},
    .exec = .{ "/usr/bin/systemd-hwdb", "--usr", "update" },
}
EOF

    # The PAM stack of the per-user service manager (Beyond LFS, "systemd").
    install -dm755 "$DESTDIR/etc/pam.d"
    cat > "$DESTDIR/etc/pam.d/systemd-user" << "EOF"
account  required    pam_access.so
account  include     system-account

session  required    pam_env.so
session  required    pam_limits.so
session  required    pam_loginuid.so
session  optional    pam_keyinit.so force revoke
session  optional    pam_systemd.so

auth     required    pam_deny.so
password required    pam_deny.so
EOF
}
