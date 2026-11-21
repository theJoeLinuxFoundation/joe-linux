# What makes the installed components a desktop: which services start, and
# who manages the network. Services are enabled by shipping the links
# `systemctl enable` would create, because packages have no install scripts.
package() {
    local system="$DESTDIR/usr/lib/systemd/system" user="$DESTDIR/usr/lib/systemd/user"

    # graphical.target, systemd's default, starts whatever is the display manager.
    install -d "$system/multi-user.target.wants"
    ln -s gdm.service "$system/display-manager.service"
    local unit
    for unit in NetworkManager accounts-daemon upower udisks2 ModemManager; do
        ln -s "../$unit.service" "$system/multi-user.target.wants/$unit.service"
    done
    # The desktop uses NetworkManager. Upstream's 90-systemd.preset enables
    # networkd and its wait-online unit on first boot of the console image.
    install -d "$DESTDIR/usr/lib/systemd/system-preset" "$system/network-online.target.wants"
    printf '%s\n' 'disable systemd-networkd.service' 'disable systemd-networkd-wait-online.service' \
        > "$DESTDIR/usr/lib/systemd/system-preset/80-joe-desktop-network.preset"
    ln -s ../NetworkManager-wait-online.service "$system/network-online.target.wants/NetworkManager-wait-online.service"

    # An upgrade preserves the old preset's link in /etc. Skip that wait
    # while the desktop's NetworkManager waiter is installed.
    install -d "$system/systemd-networkd-wait-online.service.d"
    cat > "$system/systemd-networkd-wait-online.service.d/10-joe-desktop.conf" <<'EOT'
[Unit]
ConditionPathExists=!/usr/lib/systemd/system/network-online.target.wants/NetworkManager-wait-online.service
EOT

    # Daemons that are also started over D-Bus: the alias `systemctl enable`
    # makes from the unit's Alias= line is the name D-Bus activates.
    ln -s ModemManager.service "$system/dbus-org.freedesktop.ModemManager1.service"
    install -d "$system/bluetooth.target.wants"
    ln -s ../bluetooth.service "$system/bluetooth.target.wants/bluetooth.service"
    ln -s bluetooth.service "$system/dbus-org.bluez.service"
    install -d "$system/sockets.target.wants"
    ln -s ../avahi-daemon.service "$system/multi-user.target.wants/avahi-daemon.service"
    ln -s ../avahi-daemon.socket "$system/sockets.target.wants/avahi-daemon.socket"
    ln -s avahi-daemon.service "$system/dbus-org.freedesktop.Avahi.service"

    # CUPS starts when something prints or a queue has work: the socket and
    # the spool watcher, as `systemctl enable cups` sets them up (Also=).
    ln -s ../cups.socket "$system/sockets.target.wants/cups.socket"
    ln -s ../cups.path "$system/multi-user.target.wants/cups.path"

    # Sound for every session: PipeWire, its PulseAudio front end, and the
    # session manager that connects devices.
    install -d "$user/sockets.target.wants" "$user/pipewire.service.wants"
    ln -s ../pipewire.socket "$user/sockets.target.wants/pipewire.socket"
    ln -s ../pipewire-pulse.socket "$user/sockets.target.wants/pipewire-pulse.socket"
    ln -s ../wireplumber.service "$user/pipewire.service.wants/wireplumber.service"

    # Sending files over Bluetooth: the session's OBEX daemon, started over
    # D-Bus by this alias.
    ln -s obex.service "$user/dbus-org.bluez.obex.service"

    # Desktop, Documents, Downloads and the rest, made at each login when
    # missing. xdg-user-dirs runs from this unit, and tells GNOME to skip its
    # older autostart entry; without the link, nobody gets the folders (and
    # the desktop icons have no ~/Desktop to show).
    install -d "$user/graphical-session-pre.target.wants"
    ln -s ../xdg-user-dirs.service "$user/graphical-session-pre.target.wants/xdg-user-dirs.service"

    # On a desktop NetworkManager runs the network, which is what GNOME's
    # network settings talk to. This file sorts before joe-base's rule and
    # tells systemd-networkd to leave wired interfaces alone.
    install -d "$DESTDIR/usr/lib/systemd/network"
    cat > "$DESTDIR/usr/lib/systemd/network/70-joe-desktop.network" <<'EOT'
[Match]
Type=ether
Kind=!*

[Link]
Unmanaged=yes
EOT

    # Default applications. GNOME's own list (gnome-mimeapps.list, from
    # gnome-session) names its browser and document viewer, which are not
    # what is installed; entries for programs that do not exist are skipped
    # and this list is consulted next.
    install -d "$DESTDIR/usr/share/applications"
    {
        echo '[Default Applications]'
        local type
        for type in text/html application/xhtml+xml x-scheme-handler/http x-scheme-handler/https; do
            echo "$type=firefox.desktop"
        done
        for type in application/pdf application/x-bzpdf application/x-gzpdf application/x-xzpdf application/x-ext-pdf; do
            echo "$type=org.gnome.Evince.desktop"
        done
    } > "$DESTDIR/usr/share/applications/mimeapps.list"

    # The defaults of a new account. Everything here is an ordinary setting
    # that Settings, Extensions and the extensions' own preferences change.
    #
    # - What is pinned to the taskbar. GNOME's default names mostly
    #   applications that are not installed.
    # - The layout, made only of upstream extensions: Dash to Panel's
    #   taskbar along the bottom, slightly translucent, holding ArcMenu's
    #   start menu on its left and the tray, clock and system menu on its
    #   right (its own applications button is hidden, as ArcMenu's replaces
    #   it); tray icons (AppIndicator) and icons on the desktop (DING).
    #   ArcMenu does not announce its own updates: they come with joe's.
    # - Minimize and maximize buttons on windows.
    # - The look: joe's teal accent, adw-gtk3 so GTK 3 applications match
    #   the rest, Papirus icons, and joe's wallpaper on the desktop and the
    #   lock screen.
    install -d "$DESTDIR/usr/share/glib-2.0/schemas"
    cat > "$DESTDIR/usr/share/glib-2.0/schemas/20_joe-desktop.gschema.override" <<'EOT'
[org.gnome.shell]
favorite-apps=['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.Calculator.desktop']
enabled-extensions=['dash-to-panel@jderose9.github.com', 'arcmenu@arcmenu.com', 'appindicatorsupport@rgcjonas.gmail.com', 'ding@rastersoft.com']

[org.gnome.shell.extensions.dash-to-panel]
trans-use-custom-opacity=true
trans-panel-opacity=0.8
panel-element-positions='{"0":[{"element":"showAppsButton","visible":false,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}]}'

[org.gnome.shell.extensions.arcmenu]
update-notifier-enabled=false

[org.gnome.desktop.wm.preferences]
button-layout='appmenu:minimize,maximize,close'

[org.gnome.desktop.interface]
accent-color='teal'
gtk-theme='adw-gtk3'
icon-theme='Papirus'

[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/joe/joe-l.svg'
picture-uri-dark='file:///usr/share/backgrounds/joe/joe-d.svg'
primary-color='#2a7a6f'
secondary-color='#1c574f'

[org.gnome.desktop.screensaver]
picture-uri='file:///usr/share/backgrounds/joe/joe-l.svg'
primary-color='#2a7a6f'
secondary-color='#1c574f'
EOT
}
