# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game Grim Fandango.  A
# single argument is required, the path to a Linux installer from GOG.
#
# The container installs dependencies not included with the game.  Persistent
# game data paths are bound into the calling user's XDG data directory, so the
# players have their own private save files.

options+=([arch]=i686 [distro]=opensuse [gpt]=1 [squash]=1)

packages+=(
        alsa-plugins-pulse
        libGLU1
        libX{cursor1,i6,inerama1,randr2,ss1,xf86vm1}
        Mesa-dri{,-nouveau}
)

packages_buildroot+=(unzip)

function initialize_buildroot() {
        $cp "${1:-gog_grim_fandango_remastered_2.3.0.7.sh}" "$output/grim.sh"
}

function customize_buildroot() {
        sed -i -e '/^[# ]*rpm.install.excludedocs/s/^[# ]*//' /etc/zypp/zypp.conf
}

function customize() {
        exclude_paths+=(
                root
                usr/{include,lib/debug,local,src}
                usr/{lib,share}/locale
                usr/lib/{systemd,tmpfiles.d}
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
        )

        unzip grim.sh -d /grim -x data/noarch/game/bin/{runtime-README.txt,{amd64,i386,scripts}/'*'} || [ 1 -eq $? ]
        mv /grim/data/noarch/game/bin root/grim
        mkdir -p root/grim/Saves
        rm -f grim.sh

        ln -fns grim/GrimFandango root/init

        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/GrimFandango" ] ||
mkdir -p "$XDG_DATA_HOME/GrimFandango"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/GrimFandango:/grim/Saves" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/grim \
    --hostname=GrimFandango \
    --image="${IMAGE:-GrimFandango.img}" \
    --link-journal=no \
    --machine="GrimFandango-$USER" \
    --personality=x86 \
    --private-network \
    --read-only \
    --setenv="DISPLAY=$DISPLAY" \
    --setenv="HOME=/home/$USER" \
    --setenv=PULSE_COOKIE=/tmp/.pulse/cookie \
    --setenv=PULSE_SERVER=/tmp/.pulse/native \
    --tmpfs=/home \
    --user="$USER" \
    /init "$@"
EOF
}
