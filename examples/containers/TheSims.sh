# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game The Sims: Complete
# Collection.  Seven arguments are required, the paths to the installer header
# plus its five CAB files and the path to a no-CD executable.
#
# Since the game is only for Windows, this simply installs a 32-bit Wine
# container and extracts files from the installer.  Persistent game data is
# saved by mounting a path from the calling user's XDG data directory as an
# overlay over the game files.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([arch]=i686 [distro]=ubuntu [gpt]=1 [release]=23.10 [squash]=1)

packages+=(
        libgl1
        ${options[nvidia]:+libnvidia-gl-${options[nvidia]/#*[!0-9]*/535}}
        wine
)

packages_buildroot+=(unshield)

function initialize_buildroot() {
        $cp "${1:-data1.hdr}" "$output/data1.hdr" ; shift "0${1+1}"
        local -i i ; for (( i=1 ; i<=5 ; i++ ))
        do $cp "${!i:-data$i.cab}" "$output/data$i.cab"
        done
        $cp "${!i:-Sims.exe}" "$output/nocd.exe"
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

        # Extract the installer files.
        unshield -d root/root x data1.hdr
        rm -f data1.hdr data[1-5].cab

        # Restructure the extracted files as the installer would.
        local d ; for d in GameData Music SoundData
        do
                mkdir -p "root/sims/$d"
                mv -t "root/sims/$d" "root/root/$d"_*/*
        done
        mv -t root/sims root/root/{Debug_Support/*,Downloads,Expansion*,Template*,UIGraphics}
        mv root/sims/ExpansionPack{1,}
        mv root/sims/{ExpansionPackGOLD,Deluxe}
        mv root/sims/TemplateMagic{T,t}own
        cp -a root/sims/TemplateFamilyUnleashed root/sims/TemplateUserData/Patch
        cp -t root/sims/TemplateUserData/Houses root/sims/Template*/{{??,Neighborhood}Desc,House[2-9]?}.iff
        cp -t root/sims/TemplateUserData root/sims/TemplateMagictown/{Lot{Locations,Zoning},StreetNames}.iff
        mv nocd.exe root/sims/Sims.exe  # Use the given no-CD EXE instead.

        # Allow user data to be initialized in an overlay.
        mkdir -p root/sims/.seed
        mv -t root/sims/.seed root/root/UserData{,2}
        chmod -R a+rX root/sims

        # Write the registry settings from the installer.
        cat << 'EOF' > root/install.reg
Windows Registry Editor Version 5.00
[HKLM\Software\Maxis\The Sims]
"EP2Installed"="1"
"EP3Installed"="1"
"EP3Patch"="2"
"EP4Installed"="1"
"EP5Installed"="1"
"EP5Patch"="1"
"EP6Installed"="1"
"EP7Installed"="1"
"EP8Installed"="1"
"EPDInstalled"="1"
"EPDPatch"="1"
"EPInstalled"="1"
"Installed"="1"
"InstallPath"="Z:\\sims"
"Language"=dword:00000409
"SIMS_CURRENT_NEIGHBORHOOD_NUM"="1"
"SIMS_CURRENT_NEIGHBORHOOD_PATH"="UserData"
"SIMS_DATA"="Z:\\sims"
"SIMS_GAME_EDITION"="255"
"SIMS_LANGUAGE"="USEnglish"
"SIMS_MUSIC"="Z:\\sims"
"SIMS_SKU"=dword:00000001
"SIMS_SOUND"="Z:\\sims\\SoundData"
"TELEPORT"="1"
"Version"="1.2"
EOF

        cat << 'EOF' > root/init ; chmod 0755 root/init
#!/bin/bash -eu
DISPLAY= wine reg import /install.reg
for d in UserData UserData{2..3}
do
        [[ -e $d ]] && continue
        cp -r TemplateUserData "$d"
        [[ ! -e .seed/$d ]] || cp -rt . ".seed/$d"
done
exec wine explorer /desktop=virtual,1024x768 Sims.exe -skip_intro -r1024x768 "$@"
EOF

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/TheSims" ] ||
mkdir -p "$XDG_DATA_HOME/TheSims"

exec sudo systemd-nspawn \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    --bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}" \
    --chdir=/sims \
    --hostname=TheSims \
    --image="${IMAGE:-TheSims.img}" \
    --link-journal=no \
    --machine="TheSims-$USER" \
    --overlay="+/sims:$XDG_DATA_HOME/TheSims:/sims" \
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
