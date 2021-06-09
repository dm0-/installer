# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game Kerbal Space
# Program.  A single argument is required, the path to a Linux binary release
# archive.
#
# The container installs dependencies not included with the game.  Persistent
# game data is saved by mounting a path from the calling user's XDG data
# directory as an overlay over the game's installation path.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.

options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=34 [squash]=1)

packages+=(
        gtk2
        libX{cursor,i,inerama,randr,ScrnSaver,xf86vm}
        pulseaudio-libs
        setxkbmap
)

packages_buildroot+=(unzip)

function initialize_buildroot() {
        $cp "${1:-ksp-linux-1.11.2.zip}" "$output/KSP.zip"

        # Support an option for running on a host with proprietary drivers.
        if opt nvidia
        then
                enable_repo_rpmfusion +nonfree
                packages+=(xorg-x11-drv-nvidia-libs)
        else packages+=(mesa-dri-drivers mesa-libGL)
        fi
}

function customize_buildroot() {
        echo tsflags=nodocs >> /etc/dnf/dnf.conf
}

function customize() {
        exclude_paths+=(
                KSP_linux/KSPLauncher'*'
                root
                usr/{include,lib/debug,local,src}
                usr/{lib,share}/locale
                usr/lib/{systemd,tmpfiles.d}
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
        )

        unzip -d root KSP.zip
        rm -f KSP.zip

        cat << 'EOF' > root/init && chmod 0755 root/init
#!/bin/sh -eu
mkdir -p "$HOME/.config/unity3d/Squad"
ln -fns /tmp/save "$HOME/.config/unity3d/Squad/Kerbal Space Program"
exec ./KSP.x86_64 "$@"
EOF

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_CONFIG_HOME:=$HOME/.config}/unity3d/Squad/Kerbal Space Program" ] ||
mkdir -p "$XDG_CONFIG_HOME/unity3d/Squad/Kerbal Space Program"

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/KerbalSpaceProgram" ] ||
mkdir -p "$XDG_DATA_HOME/KerbalSpaceProgram"

exec sudo systemd-nspawn \
    --ambient-capability=CAP_DAC_OVERRIDE \
    --bind="$XDG_CONFIG_HOME/unity3d/Squad/Kerbal Space Program:/tmp/save" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --capability=CAP_DAC_OVERRIDE \
    --chdir=/KSP_linux \
    --hostname=KerbalSpaceProgram \
    --image="${IMAGE:-KerbalSpaceProgram.img}" \
    --link-journal=no \
    --machine="KerbalSpaceProgram-$USER" \
    --overlay="+/KSP_linux:$XDG_DATA_HOME/KerbalSpaceProgram:/KSP_linux" \
    --personality=x86-64 \
    --private-network \
    --read-only \
    --setenv="DISPLAY=$DISPLAY" \
    --setenv="HOME=/home/$USER" \
    --setenv=LC_ALL=C \
    --setenv=PULSE_COOKIE=/tmp/.pulse/cookie \
    --setenv=PULSE_SERVER=/tmp/.pulse/native \
    --tmpfs=/home \
    --user="$USER" \
    /init "$@"
EOF
}
