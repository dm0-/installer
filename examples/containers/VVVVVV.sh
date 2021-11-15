# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game VVVVVV.
#
# It compiles the free engine source and fetches the game assests.  Persistent
# game data paths are bound into the home directory of the calling user, so the
# container is interchangeable with a native installation of the game.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=35 [squash]=1)

packages+=(
        libXi
        pulseaudio-libs
        SDL2_mixer
)

packages_buildroot+=(cmake gcc-c++ ninja-build SDL2_mixer-devel)

function initialize_buildroot() if opt nvidia
then
        local -r suffix="-${options[nvidia]}xx"
        enable_repo_rpmfusion_nonfree
        packages+=("xorg-x11-drv-nvidia${suffix##-*[!0-9]*xx}-libs")
else packages+=(mesa-dri-drivers mesa-libGL)
fi

function customize_buildroot() {
        echo tsflags=nodocs >> /etc/dnf/dnf.conf

        # Build the game engine before installing packages into the image.
        curl -L 'https://github.com/TerryCavanagh/VVVVVV/archive/refs/tags/2.3.4.tar.gz' > VVVVVV.tgz
        [[ $(sha256sum VVVVVV.tgz) == 514b85ee21a3a8d9bfb9af00bc0cd56766d69f84c817799781da93506f30dd9c\ * ]]
        tar --transform='s,^/*[^/]*,VVVVVV,' -xf VVVVVV.tgz
        rm -f VVVVVV.tgz
        cmake -GNinja -S VVVVVV/desktop_version -B VVVVVV/desktop_version/build \
            -DCMAKE_INSTALL_PREFIX:PATH=/usr
        ninja -C VVVVVV/desktop_version/build -j"$(nproc)" all

        # Fetch the game assets.
        curl -L 'https://thelettervsixtim.es/makeandplay/data.zip' > data.zip
        [[ $(sha256sum data.zip) == 6fae3cdec06062d05827d4181c438153f3ea3900437a44db73bcd29799fe57e0\ * ]]
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

        cp -pt root VVVVVV/desktop_version/build/VVVVVV
        cp -pt root data.zip

        ln -fns VVVVVV root/init

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/VVVVVV" ] ||
mkdir -p "$XDG_DATA_HOME/VVVVVV"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/VVVVVV:/home/$USER/.local/share/VVVVVV" \
    --bind="+/tmp:/home/$USER/.cache" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/ \
    --hostname=VVVVVV \
    --image="${IMAGE:-VVVVVV.img}" \
    --link-journal=no \
    --machine="VVVVVV-$USER" \
    --personality=x86-64 \
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
