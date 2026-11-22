# Not in the book: the newest upstream release, built with meson. Only the
# library, with its logind backend: on joe, systemd-logind owns the seat, so
# neither the seatd server nor libseat's own seatd backend is built.
# mundaneDE (Smithay) opens its devices through it.
build() {
    mkdir -p build
    cd build
    meson setup .. \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        -D libseat-logind=systemd \
        -D libseat-seatd=disabled \
        -D libseat-builtin=disabled \
        -D server=disabled \
        -D examples=disabled \
        -D man-pages=disabled
    ninja
}

package() {
    cd build
    DESTDIR="$DESTDIR" ninja install
}
