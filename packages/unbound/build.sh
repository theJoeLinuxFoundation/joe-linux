# Not in the book (Beyond LFS has dropped its page; blfs-systemd-units still
# carries the unit): the newest upstream release, built as its README says.
build() {
    # The trust anchor is kept in /var/lib/unbound, which every deployment
    # shares and unbound may write to (RFC 5011 updates). Built with
    # libevent, DNS over HTTPS (nghttp2), EDNS client subnet, TCP Fast Open,
    # and systemd notification. Off: the Python module and bindings (they
    # need SWIG), DNSCrypt (libsodium), dnstap, the Redis cache (hiredis)
    # and the ipset module.
    ./configure --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --disable-static \
        --with-conf-file=/etc/unbound/unbound.conf \
        --with-rootkey-file=/var/lib/unbound/root.key \
        --with-pidfile=/run/unbound.pid \
        --with-username=unbound \
        --with-ssl=/usr \
        --with-libexpat=/usr \
        --with-libevent=/usr \
        --with-libnghttp2=/usr \
        --enable-systemd \
        --enable-subnet \
        --enable-tfo-client \
        --enable-tfo-server \
        --without-pythonmodule \
        --without-pyunbound \
        --disable-dnscrypt \
        --disable-dnstap \
        --disable-cachedb \
        --disable-ipset
    make
}

package() {
    make DESTDIR="$DESTDIR" install

    # make install puts upstream's annotated example, every option commented
    # out, in place as the configuration. It is kept beside a short one that
    # turns on DNSSEC validation. The chroot (by default /etc/unbound) is
    # off because the trust anchor lives outside it.
    mv "$DESTDIR/etc/unbound/unbound.conf" "$DESTDIR/etc/unbound/unbound.conf.example"
    cat > "$DESTDIR/etc/unbound/unbound.conf" << "EOF"
# See unbound.conf(5). Every option, with its default, is described in
# /etc/unbound/unbound.conf.example.
server:
	# No chroot: the trust anchor below is outside /etc/unbound.
	chroot: ""
	# Validate DNSSEC. The root trust anchor is created and kept up to date
	# by unbound-anchor.service.
	auto-trust-anchor-file: "/var/lib/unbound/root.key"
EOF

    # The account unbound drops to after binding its sockets.
    install -d "$DESTDIR/usr/lib/sysusers.d"
    cat > "$DESTDIR/usr/lib/sysusers.d/unbound.conf" << "EOF"
g unbound 88
u unbound 88:88 "Unbound DNS Resolver" /var/lib/unbound /usr/bin/false
EOF

    # Upstream's unit (contrib/unbound.service) creates its state directory
    # as root, while the trust anchor must be writable by unbound. So the
    # anchor is fetched, as unbound, by a separate unit, which owns the
    # directory; unbound.service is the book's (blfs-systemd-units) with
    # systemd notification. Neither is enabled.
    install -d "$DESTDIR/usr/lib/systemd/system"
    install -Dm755 "$DESTDIR/usr/sbin/unbound-anchor" "$DESTDIR/usr/libexec/unbound-anchor"
    cat > "$DESTDIR/usr/lib/systemd/system/unbound-anchor.service" << "EOF"
[Unit]
Description=Update the DNSSEC root trust anchor for Unbound
Documentation=man:unbound-anchor(8)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=unbound
Group=unbound
StateDirectory=unbound
# The exit status is 1 when the anchor was updated, so it is not checked.
ExecStart=-/usr/libexec/unbound-anchor -a /var/lib/unbound/root.key
EOF
    cat > "$DESTDIR/usr/lib/systemd/system/unbound.service" << "EOF"
[Unit]
Description=Unbound DNS Resolver
Documentation=man:unbound(8)
Wants=network-online.target unbound-anchor.service
After=local-fs.target network-online.target unbound-anchor.service
Before=nss-lookup.target
Wants=nss-lookup.target

[Service]
Type=notify
# The resolver can use ordinary socket buffers within the kernel limits.
# ExecReload signals the daemon after it has dropped to unbound.
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_SETGID CAP_SETUID CAP_KILL
ExecStart=/usr/sbin/unbound -d -p
ExecReload=/usr/bin/kill -HUP $MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}
