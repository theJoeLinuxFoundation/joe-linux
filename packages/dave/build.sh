# dave is a static binary with no libc, cross-built by Zig on the build host.
# joe also packages Zig. bootstrap/build-packages.sh
# places the binary, the unit files from system/, and the manual page and
# shell completions from dave/share/ in this recipe's files/ directory before
# the build.
NOSTRIP=1

package() {
    local units="$DESTDIR/usr/lib/systemd/system"
    install -Dm755 /recipe/files/dave "$DESTDIR/usr/bin/dave"
    install -Dm644 /recipe/files/dave-boot-check.service "$units/dave-boot-check.service"
    install -Dm644 /recipe/files/dave-finalize.service "$units/dave-finalize.service"
    install -Dm644 /recipe/files/boot-complete-dave.conf "$units/boot-complete.target.d/10-dave.conf"
    install -Dm644 /recipe/files/dave-seal.service "$units/dave-seal.service"
    install -Dm644 /recipe/files/dave-status.service "$units/dave-status.service"

    # The units are enabled by shipping the links: there are no install scripts.
    install -d "$units/boot-complete.target.requires" "$units/multi-user.target.wants" "$units/sysinit.target.wants"
    ln -s ../dave-seal.service "$units/sysinit.target.wants/dave-seal.service"
    ln -s ../dave-boot-check.service "$units/boot-complete.target.requires/dave-boot-check.service"
    ln -s ../dave-finalize.service "$units/multi-user.target.wants/dave-finalize.service"
    ln -s ../dave-status.service "$units/multi-user.target.wants/dave-status.service"

    install -Dm644 /recipe/files/dave-tmpfiles.conf "$DESTDIR/usr/lib/tmpfiles.d/dave.conf"

    # Each shell finds these when it completes `dave`; they ask dave itself.
    local share="$DESTDIR/usr/share"
    install -Dm644 /recipe/files/dave.8 "$share/man/man8/dave.8"
    install -Dm644 /recipe/files/completion.bash "$share/bash-completion/completions/dave"
    install -Dm644 /recipe/files/completion.zsh "$share/zsh/site-functions/_dave"
    install -Dm644 /recipe/files/completion.fish "$share/fish/vendor_completions.d/dave.fish"

    # How a desktop program has dave change the installed software, after
    # a person authenticates; dave itself narrows what it will then do.
    install -Dm644 /recipe/files/io.joelinux.dave.policy "$share/polkit-1/actions/io.joelinux.dave.policy"
}
