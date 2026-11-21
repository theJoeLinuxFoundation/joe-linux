build() {
    # xxhash is not packaged. The manual pages ship prebuilt in the tarball,
    # so md2man (python-commonmark) is not needed.
    ./configure --prefix=/usr \
        --disable-xxhash \
        --without-included-zlib \
        --without-included-popt \
        --enable-openssl \
        --enable-zstd \
        --enable-lz4 \
        --enable-acl-support \
        --enable-xattr-support \
        --enable-idn \
        --disable-md2man
    make
}

package() {
    make DESTDIR="$DESTDIR" install

    # Only the copy launched by the units has the daemon's declaration.
    # Root's general-purpose rsync also copies local files and runs ssh.
    install -Dm755 "$DESTDIR/usr/bin/rsync" "$DESTDIR/usr/libexec/rsyncd"

    # The daemon. Nothing is enabled; rsync over ssh needs none of this.
    # The book's `make install-rsyncd` comes from blfs-systemd-units; these
    # are upstream's own units under the names the book uses.
    install -Dm644 packaging/systemd/rsync.service "$DESTDIR/usr/lib/systemd/system/rsyncd.service"
    install -Dm644 packaging/systemd/rsync.socket "$DESTDIR/usr/lib/systemd/system/rsyncd.socket"
    install -Dm644 packaging/systemd/rsync@.service "$DESTDIR/usr/lib/systemd/system/rsyncd@.service"
    sed -i 's/rsync\.service/rsyncd.service/; s/rsync@\.service/rsyncd@.service/' \
        "$DESTDIR"/usr/lib/systemd/system/rsyncd*

    sed -i 's|/usr/bin/rsync --daemon|/usr/libexec/rsyncd --daemon|' \
        "$DESTDIR"/usr/lib/systemd/system/rsyncd{,@}.service

    # The account the book creates (groupadd -g 48, useradd -u 48).
    install -d "$DESTDIR/usr/lib/sysusers.d"
    cat > "$DESTDIR/usr/lib/sysusers.d/rsync.conf" <<'EOT'
g rsyncd 48
u rsyncd 48:48 "rsyncd Daemon" /home/rsync /usr/bin/false
EOT

    # The book's example configuration. /home/rsync is not created: /home is
    # shared between deployments and most machines never run the daemon, so
    # whoever enables it creates the directory or points the module elsewhere.
    install -d "$DESTDIR/etc"
    cat > "$DESTDIR/etc/rsyncd.conf" <<'EOT'
# This is a basic rsync configuration file
# It exports a single module without user authentication.

motd file = /home/rsync/welcome.msg
use chroot = yes

[localhost]
    path = /home/rsync
    comment = Default rsync module
    read only = yes
    list = yes
    uid = rsyncd
    gid = rsyncd

EOT
}
