# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game Psychonauts.  A
# single argument is required, the path to a Linux installer from GOG.
#
# The container includes dependencies not bundled with the game.  Persistent
# game data paths are bound into the home directory of the calling user, so the
# container is interchangeable with a native installation of the game.

options+=([arch]=i686 [distro]=opensuse [gpt]=1 [squash]=1)

packages+=(
        alsa-plugins-pulse
        desktop-data-openSUSE
        libXcursor1
        Mesa-dri{,-nouveau}
        Mesa-libGL1
)

packages_buildroot+=(unzip)

function initialize_buildroot() {
        $cp "${1:-gog_psychonauts_2.0.0.4.sh}" "$output/psychonauts.zip"
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

        unzip psychonauts.zip -d /psychonauts -x data/noarch/game/{Documents/'*',icon.bmp,psychonauts.png} || [[ $? -eq 1 ]]
        mv /psychonauts/data/noarch/game root/psychonauts
        rm -f psychonauts.zip

        cat << 'EOF' > root/init && chmod 0755 root/init
#!/bin/sh -eu
mkdir -p "$HOME/.local/share"
ln -fns /tmp/save "$HOME/.local/share/Psychonauts"
test -e /tmp/save/DisplaySettings.ini ||
cp -t /tmp/save /psychonauts/DisplaySettings.ini
exec /psychonauts/Psychonauts "$@"
EOF

        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/Psychonauts" ] ||
mkdir -p "$XDG_DATA_HOME/Psychonauts"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/Psychonauts:/tmp/save" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
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
