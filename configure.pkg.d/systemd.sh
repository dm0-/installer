# SPDX-License-Identifier: GPL-3.0-or-later
# Unit configuration should happen in /usr while building the image.
rm -fr root/etc/systemd/system/*

# Ignore the laptop lid, and kill all user processes on logout.
test -s root/etc/systemd/logind.conf &&
sed -i \
    -e 's/^[# ]*\(HandleLidSwitch\)=.*/\1=ignore/' \
    -e 's/^[# ]*\(KillUserProcesses\)=.*/\1=yes/' \
    root/etc/systemd/logind.conf

# Always start a login prompt on tty1.
mkdir -p root/usr/lib/systemd/system/getty.target.wants
ln -fns ../getty@.service \
    root/usr/lib/systemd/system/getty.target.wants/getty@tty1.service

# Configure a default font and keymap for the console.
rm -f root/etc/vconsole.conf
local font=eurlatgr ; opt double_display_scale && font=latarcyrheb-sun32
compgen -G "root/usr/share/kbd/consolefonts/$font.*" ||
compgen -G "root/???/*/consolefonts/$font.*" &&
echo "FONT=\"$font\"" >> root/etc/vconsole.conf
compgen -G 'root/usr/*/kbd/keymaps/legacy/i386/qwerty/emacs2.*' ||
compgen -G 'root/usr/share/kbd/keymaps/i386/qwerty/emacs2.*' ||
compgen -G 'root/usr/share/keymaps/i386/qwerty/emacs2.*' &&
echo 'KEYMAP="emacs2"' >> root/etc/vconsole.conf

# Select a dbus.service unit if one was not installed.
test -s root/usr/lib/systemd/system/dbus.service ||
ln -fns dbus-broker.service root/usr/lib/systemd/system/dbus.service

# Select a preferred display manager when it is installed.
local dm ; for dm in gdm lxdm xdm
do
        if test -s "root/usr/lib/systemd/system/$dm.service"
        then
                ln -fns "$dm.service" \
                    root/usr/lib/systemd/system/display-manager.service
                break
        fi
done

# Define a default target on boot.
test -s root/usr/lib/systemd/system/display-manager.service &&
ln -fns graphical.target root/usr/lib/systemd/system/default.target ||
ln -fns multi-user.target root/usr/lib/systemd/system/default.target

# Save pstore files to the journal on boot.
test -s root/etc/systemd/pstore.conf &&
sed -i -e 's/^[# ]*\(Storage\)=.*/\1=journal/' root/etc/systemd/pstore.conf
mkdir -p root/usr/lib/systemd/system/basic.target.wants
test -s root/usr/lib/systemd/system/systemd-pstore.service &&
ln -fst root/usr/lib/systemd/system/basic.target.wants \
    ../systemd-pstore.service

# Work around Linux 5.10 breaking BLKDISCARD in systemd-repart.
test -s root/usr/lib/systemd/system/systemd-repart.service &&
sed -i -e 's,^ExecStart=.*systemd-repart.*,& --discard=no,' \
    root/usr/lib/systemd/system/systemd-repart.service

# Use systemd to configure networking and DNS when requested.
if opt networkd
then
        mkdir -p root/usr/lib/systemd/system/multi-user.target.wants
        ln -fst root/usr/lib/systemd/system/multi-user.target.wants \
            ../systemd-networkd.service ../systemd-resolved.service

        # Make the network-online.target unit functional.
        mkdir -p root/usr/lib/systemd/system/network-online.target.wants
        ln -fst root/usr/lib/systemd/system/network-online.target.wants \
            ../systemd-networkd-wait-online.service

        # Have all unconfigured network interfaces default to DHCP.
        mkdir -p root/usr/lib/systemd/network
        cat << 'EOF' > root/usr/lib/systemd/network/99-dhcp.network
[Match]
Name=*

[Network]
DHCP=yes

[DHCP]
UseDomains=yes
UseMTU=yes
EOF

        # Disable the DNS stub listener by default.
        sed -i \
            -e '/^#*DNSStubListener=/{s/#*//;s/=.*/=no/;}' \
            root/etc/systemd/resolved.conf
        ln -fst root/etc ../run/systemd/resolve/resolv.conf
fi

# Sync the clock with NTP by default when networkd is enabled.
if opt networkd && test -s root/usr/lib/systemd/system/systemd-timesyncd.service
then
        test -s root/usr/lib/systemd/system/dbus-org.freedesktop.timesync1.service ||
        ln -fns systemd-timesyncd.service \
            root/usr/lib/systemd/system/dbus-org.freedesktop.timesync1.service
        mkdir -p root/usr/lib/systemd/system/sysinit.target.wants
        ln -fst root/usr/lib/systemd/system/sysinit.target.wants \
            ../systemd-timesyncd.service
fi
