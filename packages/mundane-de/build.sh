# Not in the book: built as upstream's packaging handoff describes
# (docs/plan.md, "joe packaging handoff"), offline from the vendored archive.
# Its .cargo/config.toml points both workspaces (the compositor at the top,
# Settings in settings-panel/) at the one vendor/ directory.
build() {
    export CARGO_HOME="$PWD/.cargo-home"
    cargo build --release --locked --offline
    (cd settings-panel && cargo build --release --locked --offline)
}

package() {
    # The compositor, the session launcher and units, the shell, the
    # wayland-sessions entry that offers it at GDM beside GNOME, the portal
    # configuration and the GSettings override.
    PREFIX=/usr DESTDIR="$DESTDIR" session/install.sh target/release/mundane-de
    install -Dm755 settings-panel/target/release/mundane-settings "$DESTDIR/usr/bin/mundane-settings"
    local f
    for f in LICENSE THIRD-PARTY-NOTICES.md licenses/Smithay-MIT.txt settings-panel/LICENSE; do
        install -Dm644 "$f" "$DESTDIR/usr/share/licenses/mundane-de/$f"
    done
}
