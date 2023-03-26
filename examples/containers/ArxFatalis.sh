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
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([distro]=fedora [gpt]=1 [release]=37 [squash]=1)

packages+=(
        freetype
        libepoxy
        libX{cursor,i,inerama,randr,ScrnSaver}
        openal-soft
        pulseaudio-libs
        SDL2
)

packages_buildroot+=(
        # Programs to configure and build Arx Libertatis
        cmake gcc-c++ ninja-build
        # Library dependencies
        {boost,freetype,glm,libepoxy,openal-soft,SDL2}-devel
        # Utility dependencies
        ImageMagick inkscape optipng
        # Runtime dependencies of arx-install-data
        findutils innoextract
)

function initialize_buildroot() {
        $cp "${1:-setup_arx_fatalis_1.21_(21994).exe}" "$output/install.exe"

        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        echo '%_install_langs %{nil}' >> "$buildroot/etc/rpm/macros"

        # Download, verify, and extract the Arx Libertatis source release.
        local -r source_url='https://github.com/arx/ArxLibertatis/releases/download/1.2.1/arx-libertatis-1.2.1.tar.xz'
        $curl -L "$source_url.sig" > "$output/arx.txz.sig"
        $curl -L "$source_url" > "$output/arx.txz"
        verify "$output"/arx.txz{.sig,}
        $tar --transform='s,^/*[^/]*,arx,' -C "$output" -xf "$output/arx.txz"
        $rm -f "$output"/arx.txz{.sig,}

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
        cmake -GNinja -S arx -B arx/build \
            -DBUILD_CRASHREPORTER:BOOL=OFF -DCMAKE_INSTALL_PREFIX:PATH=/usr
        ninja -C arx/build -j"$(nproc)" all
}

function customize() {
        exclude_paths+=(
                root
                usr/bin/arx-install-data
                usr/{include,lib/debug,local,src}
                usr/{lib,share}/locale
                usr/lib/{sysimage,systemd,tmpfiles.d}
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
        )

        DESTDIR="$PWD/root" ninja -C arx/build install
        root/usr/bin/arx-install-data --data-dir=root/usr/share/games/arx --source=install.exe
        rm -f install.exe

        ln -fns usr/bin/arx root/init

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
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
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    --bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}" \
    --chdir="/home/$USER" \
    --hostname=ArxFatalis \
    --image="${IMAGE:-ArxFatalis.img}" \
    --link-journal=no \
    --machine="ArxFatalis-$USER" \
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

function verify() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1" "$2"
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

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
=ooDC
-----END PGP PUBLIC KEY BLOCK-----
EOF
