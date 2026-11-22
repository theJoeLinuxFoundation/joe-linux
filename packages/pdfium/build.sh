# The third recipe that packages an upstream binary instead of building from
# source (after bun and Julia), by decision: PDFium builds only with Google's
# GN and depot_tools, fetching several dozen repositories. This is the
# release build of bblanchon/pdfium-binaries (chromium/8165) without V8 and
# XFA, as mundane-apps' Document Viewer was tested with: the viewer opens
# untrusted files, and a PDF engine without a JavaScript engine is the
# smaller one to trust. Update by moving to a newer weekly build.

# Already stripped by upstream.
NOSTRIP=1

# The archive has no top directory to strip.
unpack() {
    bsdtar -xf "$SOURCES/pdfium-linux-x64-8165.tgz" --no-same-owner --no-same-permissions
}

package() {
    install -Dm755 lib/libpdfium.so "$DESTDIR/usr/lib/libpdfium.so"
    local f
    install -Dm644 LICENSE "$DESTDIR/usr/share/licenses/pdfium/LICENSE"
    for f in licenses/*; do
        install -Dm644 "$f" "$DESTDIR/usr/share/licenses/pdfium/$f"
    done
}
