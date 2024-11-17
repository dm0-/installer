# SPDX-License-Identifier: GPL-3.0-or-later
if [[ -x root/usr/bin/vlc ]]
then
        mkdir -p root/etc/skel/.config/vlc

        # Enable the advanced buttons, and fit them on one toolbar.
        cat << 'EOF' > root/etc/skel/.config/vlc/vlc-qt-interface.conf
[MainWindow]
MainToolbar1="64;64;38;65"
MainToolbar2="0-2;64;3;1;4;64;7;9;64;10;20;19;64-4;39;37;65;35-4;"
adv-controls=4
EOF

        # Disable sending your data over the network and prompting for it.
        cat << 'EOF' > root/etc/skel/.config/vlc/vlcrc
[qt]
qt-privacy-ask=0
[core]
metadata-network-access=0
[libbluray]
bluray-region=A
EOF
fi
