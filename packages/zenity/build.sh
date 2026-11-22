# Not in the book: the newest upstream release, built with meson. mundaneDE's
# Settings uses it for simple dialogs. Without WebKitGTK (--html), and
# without the manual page, which help2man would generate.
build() {
    mkdir -p build
    cd build
    meson setup .. \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        -D webkitgtk=false \
        -D manpage=false
    ninja
}

package() {
    cd build
    DESTDIR="$DESTDIR" ninja install
}
