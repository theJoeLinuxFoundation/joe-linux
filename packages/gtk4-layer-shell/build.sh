# Not in the book: the newest upstream release, built with meson, with its
# introspection data: mundaneDE's panel, launcher and Quick Settings are
# Python programs that use it through PyGObject.
build() {
    mkdir -p build
    cd build
    meson setup .. \
        --prefix=/usr \
        --libdir=lib \
        --buildtype=release \
        -D examples=false \
        -D docs=false \
        -D tests=false \
        -D introspection=true \
        -D vapi=true
    ninja
}

package() {
    cd build
    DESTDIR="$DESTDIR" ninja install
}
