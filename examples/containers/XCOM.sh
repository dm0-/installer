# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game X-COM: UFO Defense.
# A single argument is required, the path to an Inno Setup installer from GOG.
#
# The container is just a wrapper for DOSBox to run the game.  Persistent game
# data is saved by mounting a path from the calling user's XDG data directory
# as an overlay over the game's install path.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=37 [squash]=1)

packages+=(
        dosbox
        libXi
)

packages_buildroot+=(innoextract)

function initialize_buildroot() {
        $cp "${1:-setup_x-com_ufo_defense_1.2_(28046).exe}" "$output/install.exe"

        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        echo '%_install_langs %{nil}' >> "$buildroot/etc/rpm/macros"

        # Support an option for running on a host with proprietary drivers.
        if opt nvidia
        then
                local -r suffix="-${options[nvidia]}xx"
                enable_repo_rpmfusion_nonfree
                packages+=("xorg-x11-drv-nvidia${suffix##-*[!0-9]*xx}-libs")
        else packages+=(mesa-dri-drivers)
        fi
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

        innoextract -md root/XCOM install.exe
        mv root/XCOM/__support/app/dosbox_xcomud.conf root/XCOM/dosbox.conf
        rm -fr install.exe root/XCOM/{app,commonappdata,DOSBOX,gog*,README.TXT,__redist,__support}

        cat << 'EOF' > root/init ; chmod 0755 root/init
#!/bin/sh -eu
exec dosbox -exit GO.BAT "$@"
EOF

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/bash -eu

for dir in GAME_{1..10} MISSDAT
do
        [ -e "${XDG_DATA_HOME:=$HOME/.local/share}/XCOM/$dir" ] ||
        mkdir -p "$XDG_DATA_HOME/XCOM/$dir"
done

exec sudo systemd-nspawn \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    --bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}" \
    --chdir=/XCOM \
    --hostname=XCOM \
    --image="${IMAGE:-XCOM.img}" \
    --link-journal=no \
    --machine="XCOM-$USER" \
    --overlay="+/XCOM:$XDG_DATA_HOME/XCOM:/XCOM" \
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
