# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game VVVVVV.
#
# It fetches the free game assets and compiles the engine from Git.  Persistent
# game data paths are bound into the home directory of the calling user, so the
# container is interchangeable with a native installation of the game.

options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=33 [squash]=1)

packages+=(
        pulseaudio-libs
        SDL2_mixer
)

packages_buildroot+=(cmake gcc-c++ git-core ninja-build SDL2_mixer-devel)

function customize_buildroot() {
        echo tsflags=nodocs >> /etc/dnf/dnf.conf

        # Fetch the game assets.
        curl -L 'https://thelettervsixtim.es/makeandplay/data.zip' > data.zip
        test x$(sha256sum data.zip | sed -n '1s/ .*//p') = \
            x6fae3cdec06062d05827d4181c438153f3ea3900437a44db73bcd29799fe57e0

        # Build the game engine before installing packages into the image.
        git clone --branch=master https://github.com/TerryCavanagh/VVVVVV.git
        git -C VVVVVV reset --hard e70586b15425e384c833aee9a5acb9d4401af278
        cmake -GNinja -S VVVVVV/desktop_version -B VVVVVV/desktop_version/build \
            -DCMAKE_INSTALL_PREFIX:PATH=/usr
        ninja -C VVVVVV/desktop_version/build -j"$(nproc)" all
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

        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/VVVVVV" ] ||
mkdir -p "$XDG_DATA_HOME/VVVVVV"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/VVVVVV:/home/$USER/.local/share/VVVVVV" \
    --bind=/dev/dri \
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
