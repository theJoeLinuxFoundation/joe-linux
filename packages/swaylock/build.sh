# Not in the book: the newest upstream release, built with meson. mundaneDE
# locks the session with it. It authenticates through PAM (its pam.d file
# includes login), as the person who is locked out; the manual page needs
# scdoc, which joe does not package.
build() {
    mkdir -p build
    cd build
    meson setup .. \
        --prefix=/usr \
        --libdir=lib \
        --sysconfdir=/etc \
        --buildtype=release \
        -D pam=enabled \
        -D gdk-pixbuf=enabled \
        -D man-pages=disabled \
        -D zsh-completions=false \
        -D fish-completions=false
    ninja
}

package() {
    cd build
    DESTDIR="$DESTDIR" ninja install
}
