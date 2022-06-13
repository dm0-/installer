# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game Psychonauts.  A
# single argument is required, the path to a Linux installer from GOG.
#
# The container includes dependencies not bundled with the game.  Persistent
# game data paths are bound into the home directory of the calling user, so the
# container is interchangeable with a native installation of the game.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([arch]=i686 [distro]=ubuntu [gpt]=1 [release]=22.04 [squash]=1)

packages+=(
        libasound2-plugins
        libgl1
        libxcursor1
)

packages_buildroot+=(unzip)

function initialize_buildroot() {
        $cp "${1:-gog_psychonauts_2.0.0.4.sh}" "$output/psychonauts.zip"
}

function customize_buildroot() if opt nvidia
then packages+=(libnvidia-gl-${options[nvidia]/#*[!0-9]*/510})
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

        unzip psychonauts.zip -d root/root -x data/noarch/game/{Documents/'*',icon.bmp,psychonauts.png} || [[ $? -eq 1 ]]
        mv root/root/data/noarch/game root/psychonauts
        rm -f psychonauts.zip

        cat << 'EOF' > root/init ; chmod 0755 root/init
#!/bin/sh -eu
mkdir -p "$HOME/.local/share"
ln -fns /tmp/save "$HOME/.local/share/Psychonauts"
test -e /tmp/save/DisplaySettings.ini ||
cp -t /tmp/save /psychonauts/DisplaySettings.ini
exec /psychonauts/Psychonauts "$@"
EOF

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/Psychonauts" ] ||
mkdir -p "$XDG_DATA_HOME/Psychonauts"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/Psychonauts:/tmp/save" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    --bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}" \
    --chdir="/home/$USER" \
    --hostname=Psychonauts \
    --image="${IMAGE:-Psychonauts.img}" \
    --link-journal=no \
    --machine="Psychonauts-$USER" \
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
