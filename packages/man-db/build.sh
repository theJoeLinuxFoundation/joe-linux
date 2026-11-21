build() {
    # --disable-setuid, and no separate owner for the cache: the book gives
    # the system-wide database to the user "bin", which makes mandb change
    # owners and man-db.service run as that user. Neither is possible where a
    # joe image is assembled (a user namespace holding root alone), and the
    # trigger below runs mandb there. The cache belongs to root instead.
    # lynx, vgrind and grap are the paths those programs would have; none is
    # packaged. The database is gdbm, and groff and the decompressors run in
    # a seccomp sandbox.
    ./configure --prefix=/usr \
        --docdir=/usr/share/doc/man-db-2.13.1 \
        --sysconfdir=/etc \
        --disable-setuid \
        --disable-cache-owner \
        --with-db=gdbm \
        --with-libseccomp \
        --with-pager=/usr/bin/less \
        --with-browser=/usr/bin/lynx \
        --with-vgrind=/usr/bin/vgrind \
        --with-grap=/usr/bin/grap \
        --with-systemdtmpfilesdir=/usr/lib/tmpfiles.d \
        --with-systemdsystemunitdir=/usr/lib/systemd/system
    make
}

package() {
    make DESTDIR="$DESTDIR" install

    # man finds pages by searching the directories, with or without a
    # database; apropos, whatis and "man -k" need the database in
    # /var/cache/man. That directory is not packaged: "make install" ships
    # usr/lib/tmpfiles.d/man-db.conf, which creates it (and expires stale
    # formatted pages, never the database).
    test -f "$DESTDIR/usr/lib/tmpfiles.d/man-db.conf"

    # The database follows every change to the manual pages. Optional,
    # because the timer repeats the work and a failure to index must never
    # stop a transaction.
    install -d "$DESTDIR/usr/lib/dave/triggers"
    cat > "$DESTDIR/usr/lib/dave/triggers/50-man-db.zon" <<'EOF'
.{
    .name = "manual page database",
    .optional = true,
    .paths = .{"usr/share/man/"},
    .exec = .{ "/usr/bin/mandb", "--quiet" },
}
EOF

    # An upgrade is applied to a snapshot in which the shared /var is not
    # mounted, so the trigger cannot reach the database then. Upstream's
    # daily timer (Persistent=true: it catches up after boot) covers that
    # case, and is enabled the way every unit is: by shipping the symlink.
    # The indexer owns its cache and only needs readable manual pages.
    printf '\n[Service]\nCapabilityBoundingSet=\n' >> "$DESTDIR/usr/lib/systemd/system/man-db.service"
    install -d "$DESTDIR/usr/lib/systemd/system/timers.target.wants"
    ln -s ../man-db.timer "$DESTDIR/usr/lib/systemd/system/timers.target.wants/man-db.timer"
}
