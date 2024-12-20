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

options+=([distro]=fedora [gpt]=1 [release]=41 [squash]=1)

packages+=(
        libXi
        pulseaudio-libs
        SDL2_mixer
)

packages_buildroot+=(cmake gcc-c++ ninja-build SDL2_mixer-devel unzip)

function initialize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        echo '%_install_langs %{nil}' >> "$buildroot/etc/rpm/macros"

        # Support an option for running on a host with proprietary drivers.
        if opt nvidia
        then
                local -r suffix="-${options[nvidia]}xx"
                enable_repo_rpmfusion_nonfree
                packages+=("xorg-x11-drv-nvidia${suffix##-*[!0-9]*xx}-libs")
        else packages+=(mesa-dri-drivers mesa-libGL)
        fi
}

function customize_buildroot() {
        # Build the game engine before installing packages into the image.
        curl -L 'https://github.com/TerryCavanagh/VVVVVV/releases/download/2.4.1/VVVVVV-2.4.1.zip' > VVVVVV.zip
        [[ $(sha256sum VVVVVV.zip) == c453373cfa29456318c2ece7d452b2e971595004c1b353cd7073f6912b3c3d12\ * ]]
        unzip VVVVVV.zip
        rm -f VVVVVV.zip
        CFLAGS=-Wno-error=implicit-function-declaration \
        cmake -GNinja -S VVVVVV/desktop_version -B VVVVVV/desktop_version/build \
            -DCMAKE_INSTALL_PREFIX:PATH=/usr
        ninja -C VVVVVV/desktop_version/build -j"$(nproc)" all

        # Fetch the game assets.
        curl -L 'https://thelettervsixtim.es/makeandplay/data.zip' > data.zip
        [[ $(sha256sum data.zip) == c767809594f6472da9f56136e76657e38640d584164a46112250ac6293ecc0ea\ * ]]
}

function customize() {
        exclude_paths+=(
                root
                usr/{include,lib/debug,local,src}
                usr/{lib,share}/locale
                usr/lib/{sysimage,systemd,tmpfiles.d}
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
        )

        cp -pt root VVVVVV/desktop_version/build/VVVVVV
        cp -pt root data.zip

        ln -fns VVVVVV root/init

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/VVVVVV" ] ||
mkdir -p "$XDG_DATA_HOME/VVVVVV"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/VVVVVV:/home/$USER/.local/share/VVVVVV" \
    --bind="+/tmp:${XDG_RUNTIME_DIR:=/run/user/$UID}" \
    --bind="+/tmp:/home/$USER/.cache" \
    $(for dev in /dev/dri/* ; do echo "--bind=$dev" ; done) \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    ${DISPLAY:+--bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}"} \
    ${WAYLAND_DISPLAY:+--bind-ro="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"} \
    ${XAUTHORITY:+--bind-ro="$XAUTHORITY:/tmp/.Xauthority"} \
    --chdir=/ \
    --hostname=VVVVVV \
    --image="${IMAGE:-VVVVVV.img}" \
    --link-journal=no \
    --machine="VVVVVV-$USER" \
    --private-network \
    --read-only \
    --setenv="HOME=/home/$USER" \
    --setenv=PULSE_COOKIE=/tmp/.pulse/cookie \
    --setenv=PULSE_SERVER=/tmp/.pulse/native \
    ${DISPLAY:+--setenv="DISPLAY=$DISPLAY"} \
    ${WAYLAND_DISPLAY:+--setenv="WAYLAND_DISPLAY=$WAYLAND_DISPLAY"} \
    ${XAUTHORITY:+--setenv=XAUTHORITY=/tmp/.Xauthority} \
    ${XDG_RUNTIME_DIR:+--setenv="XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"} \
    --tmpfs=/home \
    --user="$USER" \
    /init "$@"
EOF
}
