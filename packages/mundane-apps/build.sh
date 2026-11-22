# Not in the book: built as upstream's packaging notes describe (docs/plan.md,
# "Vendored source archive"), offline from the vendored archive: one Cargo
# workspace, eighteen programs.
build() {
    export CARGO_HOME="$PWD/.cargo-home"
    cargo build --release --locked --offline
}

package() {
    local f
    for f in target/release/mundane-*; do
        [[ -f $f && -x $f ]] && install -Dm755 "$f" "$DESTDIR/usr/bin/${f##*/}"
    done
    for f in apps/*/data/*.desktop; do
        install -Dm644 "$f" "$DESTDIR/usr/share/applications/${f##*/}"
    done
    install -Dm644 LICENSE "$DESTDIR/usr/share/licenses/mundane-apps/LICENSE"
    for f in LICENSES/*; do
        install -Dm644 "$f" "$DESTDIR/usr/share/licenses/mundane-apps/$f"
    done
}
