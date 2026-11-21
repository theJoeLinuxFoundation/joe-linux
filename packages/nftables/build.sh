# Not in the book: the newest upstream release, built as its INSTALL says.
build() {
    # The interactive mode (nft -i) uses readline: upstream's default,
    # libedit, is not packaged. JSON input and output use jansson. No
    # iptables-nft translation (libxtables) and no Python module (py/ is a
    # separate setuptools project). The manual pages ship ready-made in the
    # tarball, so asciidoc is not needed.
    #
    # --with-unitdir installs nftables.service, which loads
    # /etc/nftables/rules/main.nft if the administrator writes one. It is
    # not enabled.
    ./configure --prefix=/usr \
        --sysconfdir=/etc \
        --disable-static \
        --with-cli=readline \
        --with-json \
        --without-xtables \
        --with-unitdir=/usr/lib/systemd/system
    make
}

package() {
    make DESTDIR="$DESTDIR" install
    install -Dm755 "$DESTDIR/usr/sbin/nft" "$DESTDIR/usr/libexec/nft"
    sed -i 's|=/usr/sbin/nft |=/usr/libexec/nft |' "$DESTDIR/usr/lib/systemd/system/nftables.service"
}
