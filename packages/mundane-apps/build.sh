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
    # Clocks resumes scheduled alarms at login through this entry.
    for f in apps/*/data/autostart/*.desktop; do
        [[ -e $f ]] && install -Dm644 "$f" "$DESTDIR/etc/xdg/autostart/${f##*/}"
    done

    # The suite opens files by default in a mundaneDE session only
    # (XDG_CURRENT_DESKTOP=mundane reads mundane-mimeapps.list); GNOME keeps
    # its own applications. Each type goes to the first entry declaring it.
    python3 - "$DESTDIR/usr/share/applications" <<'EOF'
import configparser, glob, os, sys
apps = sys.argv[1]
defaults = {}
for path in sorted(glob.glob(os.path.join(apps, "org.joelinux.mundane.*.desktop"))):
    entry = configparser.ConfigParser(interpolation=None, strict=False)
    entry.optionxform = str
    entry.read(path, encoding="utf-8")
    for mime in entry.get("Desktop Entry", "MimeType", fallback="").split(";"):
        if mime and mime not in defaults:
            defaults[mime] = os.path.basename(path)
with open(os.path.join(apps, "mundane-mimeapps.list"), "w", encoding="utf-8") as out:
    out.write("[Default Applications]\n")
    for mime in sorted(defaults):
        out.write(f"{mime}={defaults[mime]}\n")
EOF

    install -Dm644 LICENSE "$DESTDIR/usr/share/licenses/mundane-apps/LICENSE"
    for f in LICENSES/*; do
        install -Dm644 "$f" "$DESTDIR/usr/share/licenses/mundane-apps/$f"
    done
}
