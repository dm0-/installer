# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game Grim Fandango.  A
# single argument is required, the path to a Linux installer from GOG.
#
# The container includes dependencies not bundled with the game.  Persistent
# game data paths are bound into the calling user's XDG data directory, so the
# players have their own private save files.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([arch]=i686 [distro]=ubuntu [gpt]=1 [release]=22.10 [squash]=1)

packages+=(
        libasound2-plugins
        libgl{1,u1}
        libx{cursor1,i6,inerama1,randr2,ss1,xf86vm1}
)

packages_buildroot+=(unzip)

function initialize_buildroot() {
        $cp "${1:-gog_grim_fandango_remastered_2.3.0.7.sh}" "$output/grim.zip"
}

function customize_buildroot() if opt nvidia
then packages+=(libnvidia-gl-${options[nvidia]/#*[!0-9]*/525})
fi

function customize() {
        exclude_paths+=(
                root
                usr/{include,lib/debug,local,src}
                usr/{lib,share}/locale
                usr/lib/{systemd,tmpfiles.d}
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
        )

        unzip grim.zip -d root/root -x data/noarch/game/bin/{runtime-README.txt,{amd64,i386,scripts}/'*'} || [[ $? -eq 1 ]]
        mv root/root/data/noarch/game/bin root/grim
        rm -f grim.zip
        mkdir -p root/grim/Saves

        ln -fns grim/GrimFandango root/init

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/GrimFandango" ] ||
mkdir -p "$XDG_DATA_HOME/GrimFandango"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/GrimFandango:/grim/Saves" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    --bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}" \
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
