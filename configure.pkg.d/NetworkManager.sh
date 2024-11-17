# SPDX-License-Identifier: GPL-3.0-or-later
opt networkd || if [[ -s root/usr/lib/systemd/system/NetworkManager.service ]]
then
        # Start NetworkManager when it's installed and networkd isn't used.
        mkdir -p root/usr/lib/systemd/system/multi-user.target.wants
        ln -fst root/usr/lib/systemd/system/multi-user.target.wants \
            ../NetworkManager.service

        # Make the network-online.target unit functional.
        mkdir -p root/usr/lib/systemd/system/network-online.target.wants
        ln -fst root/usr/lib/systemd/system/network-online.target.wants \
            ../NetworkManager-wait-online.service

        # Use NetworkManager's DNS settings.
        ln -fst root/etc ../run/NetworkManager/resolv.conf
fi
