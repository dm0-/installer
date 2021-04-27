# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game Arx Fatalis.  A
# single argument is required, the path to an installer that arx-install-data
# knows how to extract.
#
# It actually compiles the modernized GPL engine Arx Libertatis and only needs
# the proprietary game assets.  Persistent game data paths are bound into the
# home directory of the calling user, so the container is interchangeable with
# a native installation of the game.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.

options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=34 [squash]=1)

packages+=(
        freetype
        libepoxy
        libX{cursor,inerama,randr,ScrnSaver}
        openal-soft
        pulseaudio-libs
        SDL2
)

packages_buildroot+=(
        # Programs to fetch/configure/build Arx Libertatis
        cmake gcc-c++ git-core ninja-build
        # Library dependencies
        {boost,freetype,glm,libepoxy,openal-soft,SDL2}-devel
        # Utility dependencies
        ImageMagick inkscape optipng
        # Runtime dependencies of arx-install-data
        findutils innoextract
)

function initialize_buildroot() {
        $cp "${1:-setup_arx_fatalis_1.21_(21994).exe}" "$output/install.exe"

        # Support an option for running on a host with proprietary drivers.
        if opt nvidia
        then
                enable_rpmfusion +nonfree
                packages+=(xorg-x11-drv-nvidia-libs)
        else packages+=(libGL mesa-dri-drivers)
        fi
}

function customize_buildroot() {
        echo tsflags=nodocs >> /etc/dnf/dnf.conf

        # Build the game engine before installing packages into the image.
        git clone --branch=master https://github.com/arx/ArxLibertatis.git
        git -C ArxLibertatis reset --hard d9e2fc07eb82b3d5a9b7d1defccf27ef59debacb
        cmake -GNinja -S ArxLibertatis -B ArxLibertatis/build \
            -DBUILD_CRASHREPORTER:BOOL=OFF -DCMAKE_INSTALL_PREFIX:PATH=/usr
        ninja -C ArxLibertatis/build -j"$(nproc)" all
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

        DESTDIR="$PWD/root" ninja -C ArxLibertatis/build install
        root/usr/bin/arx-install-data --data-dir=root/usr/share/games/arx --source=install.exe
        rm -f install.exe

        ln -fns usr/bin/arx root/init

        sed "${options[nvidia]:+s, /dev/dri ,&/dev/nvidia* ,}" << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_CONFIG_HOME:=$HOME/.config}/arx" ] ||
mkdir -p "$XDG_CONFIG_HOME/arx"

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/arx" ] ||
mkdir -p "$XDG_DATA_HOME/arx"

exec sudo systemd-nspawn \
    --bind="$XDG_CONFIG_HOME/arx:/home/$USER/.config/arx" \
    --bind="$XDG_DATA_HOME/arx:/home/$USER/.local/share/arx" \
    --bind="+/tmp:/home/$USER/.cache" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir="/home/$USER" \
    --hostname=ArxFatalis \
    --image="${IMAGE:-ArxFatalis.img}" \
    --link-journal=no \
    --machine="ArxFatalis-$USER" \
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
