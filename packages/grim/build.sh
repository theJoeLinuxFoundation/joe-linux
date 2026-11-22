# Not in the book: the newest upstream release, built with meson. mundaneDE's
# screenshot path uses it through xdg-desktop-portal-wlr. The manual page
# needs scdoc, which joe does not package.
build() {
    mkdir -p build
    cd build
    meson setup .. \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        -D jpeg=enabled \
        -D man-pages=disabled
    ninja
}

package() {
    cd build
    DESTDIR="$DESTDIR" ninja install
}
