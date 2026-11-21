build() {
    # The book's switches, with its recommended and optional dependencies
    # that are packaged stated: statistics in JSON and XML (json-c,
    # libxml2), DNS over HTTPS (nghttp2), the new-zone database (LMDB),
    # GSS-TSIG (MIT Kerberos), IDN in dig (libidn2), line editing in
    # nsupdate (readline). No GeoIP ACLs (libmaxminddb), no dnstap (fstrm),
    # no jemalloc, no unit tests (cmocka). The manual pages ship ready-made;
    # only the HTML manual needs Sphinx.
    ./configure --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --mandir=/usr/share/man \
        --disable-static \
        --with-json-c \
        --with-libxml2 \
        --with-libnghttp2 \
        --with-lmdb \
        --with-gssapi \
        --with-libidn2 \
        --with-readline=readline \
        --with-zlib \
        --disable-geoip \
        --without-maxminddb \
        --disable-dnstap \
        --without-jemalloc \
        --without-cmocka
    make
}

package() {
    make DESTDIR="$DESTDIR" install

    # The account the book creates (groupadd -g 20, useradd -u 20).
    install -d "$DESTDIR/usr/lib/sysusers.d" "$DESTDIR/usr/lib/tmpfiles.d"
    cat > "$DESTDIR/usr/lib/sysusers.d/bind.conf" << "EOF"
g named 20
u named 20:20 "BIND Owner" /var/named /usr/bin/false
EOF

    # The book runs named in a chroot under /srv/named. It runs unconfined
    # here, with the book's configuration at its usual paths: named.conf in
    # /etc, the root hints and the loopback zone in /etc/named, and a
    # working directory in /var that named may write to (named.run, managed
    # keys, cache dumps).
    cat > "$DESTDIR/usr/lib/tmpfiles.d/bind.conf" << "EOF"
d /var/named 0770 root named -
d /run/named 0755 named named -
EOF

    install -d "$DESTDIR/etc/named/pz"
    cat > "$DESTDIR/etc/named.conf" << "EOF"
options {
    directory "/var/named";
    pid-file "/run/named/named.pid";
    statistics-file "/run/named/named.stats";

};
zone "." {
    type hint;
    file "/etc/named/root.hints";
};
zone "0.0.127.in-addr.arpa" {
    type master;
    file "/etc/named/pz/127.0.0";
};

// Bind 9 now logs by default through syslog (except debug).
// These are the default logging rules.

logging {
    category default { default_syslog; default_debug; };
    category unmatched { null; };

  channel default_syslog {
      syslog daemon;                      // send to syslog's daemon
                                          // facility
      severity info;                      // only send priority info
                                          // and higher
  };

  channel default_debug {
      file "named.run";                   // write to named.run in
                                          // the working directory
                                          // Note: stderr is used instead
                                          // of "named.run"
                                          // if the server is started
                                          // with the '-f' option.
      severity dynamic;                   // log at the server's
                                          // current debug level
  };

  channel default_stderr {
      stderr;                             // writes to stderr
      severity info;                      // only send priority info
                                          // and higher
  };

  channel null {
      null;                               // toss anything sent to
                                          // this channel
  };
};
EOF

    cat > "$DESTDIR/etc/named/pz/127.0.0" << "EOF"
$TTL 3D
@      IN      SOA     ns.local.domain. hostmaster.local.domain. (
                        1       ; Serial
                        8H      ; Refresh
                        2H      ; Retry
                        4W      ; Expire
                        1D)     ; Minimum TTL
                NS      ns.local.domain.
1               PTR     localhost.
EOF

    cat > "$DESTDIR/etc/named/root.hints" << "EOF"
.                       6D  IN      NS      A.ROOT-SERVERS.NET.
.                       6D  IN      NS      B.ROOT-SERVERS.NET.
.                       6D  IN      NS      C.ROOT-SERVERS.NET.
.                       6D  IN      NS      D.ROOT-SERVERS.NET.
.                       6D  IN      NS      E.ROOT-SERVERS.NET.
.                       6D  IN      NS      F.ROOT-SERVERS.NET.
.                       6D  IN      NS      G.ROOT-SERVERS.NET.
.                       6D  IN      NS      H.ROOT-SERVERS.NET.
.                       6D  IN      NS      I.ROOT-SERVERS.NET.
.                       6D  IN      NS      J.ROOT-SERVERS.NET.
.                       6D  IN      NS      K.ROOT-SERVERS.NET.
.                       6D  IN      NS      L.ROOT-SERVERS.NET.
.                       6D  IN      NS      M.ROOT-SERVERS.NET.
A.ROOT-SERVERS.NET.     6D  IN      A       198.41.0.4
A.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:503:ba3e::2:30
B.ROOT-SERVERS.NET.     6D  IN      A       170.247.170.2
B.ROOT-SERVERS.NET.     6D  IN      AAAA    2801:1b8:10::b
C.ROOT-SERVERS.NET.     6D  IN      A       192.33.4.12
C.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:500:2::c
D.ROOT-SERVERS.NET.     6D  IN      A       199.7.91.13
D.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:500:2d::d
E.ROOT-SERVERS.NET.     6D  IN      A       192.203.230.10
E.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:500:a8::e
F.ROOT-SERVERS.NET.     6D  IN      A       192.5.5.241
F.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:500:2f::f
G.ROOT-SERVERS.NET.     6D  IN      A       192.112.36.4
G.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:500:12::d0d
H.ROOT-SERVERS.NET.     6D  IN      A       198.97.190.53
H.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:500:1::53
I.ROOT-SERVERS.NET.     6D  IN      A       192.36.148.17
I.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:7fe::53
J.ROOT-SERVERS.NET.     6D  IN      A       192.58.128.30
J.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:503:c27::2:30
K.ROOT-SERVERS.NET.     6D  IN      A       193.0.14.129
K.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:7fd::1
L.ROOT-SERVERS.NET.     6D  IN      A       199.7.83.42
L.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:500:9f::42
M.ROOT-SERVERS.NET.     6D  IN      A       202.12.27.33
M.ROOT-SERVERS.NET.     6D  IN      AAAA    2001:dc3::35
EOF

    # The unit of blfs-systemd-units ("make install-named") without the
    # chroot. The book makes the rndc key while installing (rndc-confgen
    # -a); a key belongs to a machine, so the unit makes it on first start.
    # It is not enabled.
    install -d "$DESTDIR/usr/lib/systemd/system"
    # The standalone rndc-confgen -a -c can create keys at other paths.
    install -Dm755 "$DESTDIR/usr/sbin/rndc-confgen" "$DESTDIR/usr/libexec/rndc-confgen"
    cat > "$DESTDIR/usr/lib/systemd/system/named-rndc-key.service" << "EOF"
[Unit]
Description=Create the local BIND control key
ConditionPathExists=!/etc/rndc.key

[Service]
Type=oneshot
ExecStart=/usr/libexec/rndc-confgen -a -u named
EOF
    cat > "$DESTDIR/usr/lib/systemd/system/named.service" << "EOF"
[Unit]
Description=Internet domain name server
Requires=named-rndc-key.service
After=network.target named-rndc-key.service

[Service]
ExecStart=/usr/sbin/named -f -u named -c /etc/named.conf
ExecReload=/usr/sbin/rndc reload
ExecStop=/usr/sbin/rndc stop

[Install]
WantedBy=multi-user.target
EOF
}
