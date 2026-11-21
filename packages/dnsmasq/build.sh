# Not in the book: the newest upstream release, built as its Makefile and
# src/config.h describe.
#
# Optional parts are chosen with COPTS: the D-Bus interface, IDN (libidn2),
# DNSSEC validation (nettle and GMP) and nftables sets (libnftables). Not
# built: conntrack marking (libnetfilter_conntrack), Lua scripts, ubus.
_copts="-DHAVE_DBUS -DHAVE_LIBIDN2 -DHAVE_DNSSEC -DHAVE_NFTSET"

build() {
    make PREFIX=/usr BINDIR=/usr/sbin COPTS="$_copts" all-i18n
}

package() {
    make PREFIX=/usr BINDIR=/usr/sbin COPTS="$_copts" DESTDIR="$DESTDIR" install-i18n

    # Upstream's example configuration, all commented out, as the
    # configuration; the DNSSEC root trust anchors, for conf-file=.
    install -Dm644 dnsmasq.conf.example "$DESTDIR/etc/dnsmasq.conf"
    install -Dm644 trust-anchors.conf "$DESTDIR/usr/share/dnsmasq/trust-anchors.conf"

    # The D-Bus policy lets root own dnsmasq's name. dnsmasq.service below
    # runs it as the dnsmasq user, which needs the same.
    install -d "$DESTDIR/usr/share/dbus-1/system.d"
    sed 's|<policy user="root">|<policy user="dnsmasq">\
		<allow own="uk.org.thekelleys.dnsmasq"/>\
		<allow send_destination="uk.org.thekelleys.dnsmasq"/>\
	</policy>\
	&|' dbus/dnsmasq.conf > "$DESTDIR/usr/share/dbus-1/system.d/dnsmasq.conf"
    grep -q 'policy user="dnsmasq"' "$DESTDIR/usr/share/dbus-1/system.d/dnsmasq.conf"

    # dnsmasq drops to this account (upstream's default is nobody). The
    # DHCP lease file is /var/lib/misc/dnsmasq.leases.
    install -d "$DESTDIR/usr/lib/sysusers.d" "$DESTDIR/usr/lib/tmpfiles.d"
    cat > "$DESTDIR/usr/lib/sysusers.d/dnsmasq.conf" << "EOF"
g dnsmasq 49
u dnsmasq 49:49 "dnsmasq daemon" /var/lib/misc /usr/bin/false
EOF
    cat > "$DESTDIR/usr/lib/tmpfiles.d/dnsmasq.conf" << "EOF"
d /var/lib/misc 0755 root root -
EOF

    # Upstream's unit (contrib/systemd/dnsmasq.service), which waits for
    # dnsmasq to take its D-Bus name, with the switches that make it do so
    # and run as dnsmasq, and without a PID file. It is not enabled.
    install -d "$DESTDIR/usr/lib/systemd/system"
    # NetworkManager starts the public executable with per-interface lease files.
    install -Dm755 "$DESTDIR/usr/sbin/dnsmasq" "$DESTDIR/usr/libexec/dnsmasq"
    cat > "$DESTDIR/usr/lib/systemd/system/dnsmasq.service" << "EOF"
[Unit]
Description=dnsmasq - A lightweight DHCP and caching DNS server
Documentation=man:dnsmasq(8)
After=network.target
Before=network-online.target nss-lookup.target
Wants=nss-lookup.target

[Service]
Type=dbus
BusName=uk.org.thekelleys.dnsmasq
ExecStartPre=/usr/libexec/dnsmasq --test
ExecStart=/usr/libexec/dnsmasq -k --enable-dbus --user=dnsmasq --pid-file
ExecReload=/usr/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
EOF
}
