# Not in the book: the newest upstream release, built with meson. Its
# wlr.portal serves only the desktops it names (wlroots, sway and the like),
# so GNOME's portals are unchanged; mundaneDE chooses it for ScreenCast and
# Screenshot in its own portals.conf. The manual page needs scdoc, which
# joe does not package.
build() {
    mkdir -p build
    cd build
    meson setup .. \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        -D sd-bus-provider=libsystemd \
        -D systemd=enabled \
        -D man-pages=disabled
    ninja
}

package() {
    cd build
    DESTDIR="$DESTDIR" ninja install
}
