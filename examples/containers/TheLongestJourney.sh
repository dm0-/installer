# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game The Longest Journey.
# Two arguments are required, the paths to both Inno Setup installer fragments
# from GOG (with the exe file first followed by the bin file).
#
# The container is just a wrapper for SCUMMVM to run the game.  Persistent game
# data is saved in its own path under the calling user's XDG data directory to
# keep it isolated from any native SCUMMVM saved games.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([distro]=fedora [gpt]=1 [release]=40 [squash]=1)

packages+=(scummvm)

packages_buildroot+=(innoextract)

function initialize_buildroot() {
        $cp "${1:-setup_the_longest_journey_142_lang_update_(24607).exe}" "$output/install.exe"
        $cp "${2:-setup_the_longest_journey_142_lang_update_(24607)-1.bin}" "$output/install-1.bin"

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

        innoextract -md root/TLJ install.exe
        rm -fr install{.exe,-1.bin} root/TLJ/{app,commonappdata,gog*,manual.pdf,__redist,tlj_faq*}

        cat << 'EOF' > root/init ; chmod 0755 root/init
#!/bin/sh -eu
mkdir -p "$HOME/.config" "$HOME/.local/share"
ln -fns /tmp/save "$HOME/.local/share/scummvm"
ln -fst "$HOME/.config" ../.local/share/scummvm
exec scummvm --auto-detect --fullscreen "$@"
EOF

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/TheLongestJourney" ] ||
mkdir -p "$XDG_DATA_HOME/TheLongestJourney"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/TheLongestJourney:/tmp/save" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    --bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}" \
    --chdir=/TLJ \
    --hostname=TheLongestJourney \
    --image="${IMAGE:-TheLongestJourney.img}" \
    --link-journal=no \
    --machine="TheLongestJourney-$USER" \
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
