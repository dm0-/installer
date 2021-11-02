# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game FTL.  A single
# argument is required, the path to a Linux installer from GOG.
#
# The container includes dependencies not bundled with the game.  Persistent
# game data paths are bound into the home directory of the calling user, so the
# container is interchangeable with a native installation of the game.
#
# Since the game archive includes both i686 and x86_64 binaries, this script
# supports using either depending on the given architecture option.  It also
# implements an option to demonstrate supporting the proprietary NVIDIA drivers
# on the host system.

options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=35 [squash]=1)

packages+=(
        alsa-plugins-pulseaudio
        libGLU
)

packages_buildroot+=(unzip)

function initialize_buildroot() {
        $cp "${1:-ftl_advanced_edition_1_6_12_2_35269.sh}" "$output/ftl.zip"

        # Support an option for running on a host with proprietary drivers.
        if opt nvidia
        then
                enable_repo_rpmfusion_nonfree
                packages+=(xorg-x11-drv-nvidia-libs)
        else packages+=(mesa-dri-drivers)
        fi
}

function customize_buildroot() {
        echo tsflags=nodocs >> /etc/dnf/dnf.conf
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

        local -r drop=$([[ ${options[arch]} == i?86 ]] && echo amd64)
        unzip -Cjd root ftl.zip 'data/noarch/game/data/FTL.*' -x "*FTL.${drop:-x86}" || [[ $? -eq 1 ]]
        mv root/FTL.* root/FTL
        rm -f ftl.zip

        cat << 'EOF' > root/init && chmod 0755 root/init
#!/bin/sh -eu
mkdir -p "$HOME/.local/share"
ln -fns /tmp/save "$HOME/.local/share/FasterThanLight"
exec /FTL "$@"
EOF

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,;}${drop:+s/-64//}" << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/FasterThanLight" ] ||
mkdir -p "$XDG_DATA_HOME/FasterThanLight"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/FasterThanLight:/tmp/save" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/ \
    --hostname=FasterThanLight \
    --image="${IMAGE:-FasterThanLight.img}" \
    --link-journal=no \
    --machine="FasterThanLight-$USER" \
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
