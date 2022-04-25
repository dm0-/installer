# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game Vampire: The
# Masquerade - Bloodlines.  Two arguments are required, the paths to both Inno
# Setup installer fragments from GOG (with the exe file first followed by the
# bin file).
#
# Since the game is only for Windows, this simply installs a 32-bit Wine
# container and extracts files from the installer.  Persistent game data is
# saved by mounting paths from the calling user's XDG config and data
# directories over the game files.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([arch]=i686 [distro]=ubuntu [gpt]=1 [release]=22.04 [squash]=1)

packages+=(
        dxvk
        libgl{1,u1}
        libxcomposite1
        wine-development
)

packages_buildroot+=(innoextract jq)

function initialize_buildroot() {
        $cp "${1:-setup_vampire_the_masquerade_-_bloodlines_1.2_(up_10.2)_(28160).exe}" "$output/install.exe"
        $cp "${2:-setup_vampire_the_masquerade_-_bloodlines_1.2_(up_10.2)_(28160)-1.bin}" "$output/install-1.bin"
}

function customize_buildroot() if opt nvidia
then packages+=(libnvidia-gl-${options[nvidia]/#*[!0-9]*/510})
fi

function customize() {
        exclude_paths+=(
                root
                usr/{include,lib/debug,local,src}
                usr/{lib,share}/locale
                usr/lib/{systemd,tmpfiles.d}
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
        )

        innoextract -md root/VTMB install.exe
        wine_gog_script /VTMB < root/VTMB/goggame-1207659240.script > reg.sh
        mv root/VTMB/Unofficial_Patch/cfg root/VTMB/Vampire/cfg.orig
        (
                cd root/VTMB/Unofficial_Patch
                exec find . -type d -exec mkdir -p ../Vampire/{} ';' -o -exec mv {} ../Vampire/{} ';'
        )
        rm -fr install{.exe,-1.bin} root/VTMB/{app,commonappdata,Docs,gog*,manual.pdf,__redist,Unofficial_Patch}
        mkdir -p root/VTMB/Vampire/{cfg,SAVE}

        sed $'/^REG_SCRIPT/{rreg.sh\nd;}' << 'EOF' > root/init ; chmod 0755 root/init
#!/bin/sh -eu
(unset DISPLAY
REG_SCRIPT
for r in ScreenBPP=32 ScreenHeight=600 ScreenWidth=800
do
        read -r x < "/VTMB/Vampire/cfg/${r%%=*}" && [ 0 -lt $((x)) ] || x=${r##*=}
        wine reg add 'HKEY_CURRENT_USER\Software\Troika\Vampire\ResPatch' /v "${r%%=*}" /t REG_DWORD /d "$x" /f
done
cd /VTMB/Vampire/cfg.orig
for r in *.cfg
do [ -e "../cfg/$r" ] || cp -at ../cfg "$r"
done
exec sleep 1)
wine /VTMB/vampire.exe "$@" && rc=0 || rc=$?
for r in ScreenBPP ScreenHeight ScreenWidth
do wine reg query 'HKEY_CURRENT_USER\Software\Troika\Vampire\ResPatch' /v "$r" | grep -o '0x[0-9A-Fa-f]*' > "/VTMB/Vampire/cfg/$r"
done
exit "$rc"
EOF

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_CONFIG_HOME:=$HOME/.config}/VampireTheMasqueradeBloodlines" ] ||
mkdir -p "$XDG_CONFIG_HOME/VampireTheMasqueradeBloodlines"

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/VampireTheMasqueradeBloodlines" ] ||
mkdir -p "$XDG_DATA_HOME/VampireTheMasqueradeBloodlines"

exec sudo systemd-nspawn \
    --bind="$XDG_CONFIG_HOME/VampireTheMasqueradeBloodlines:/VTMB/Vampire/cfg" \
    --bind="$XDG_DATA_HOME/VampireTheMasqueradeBloodlines:/VTMB/Vampire/SAVE" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/VTMB \
    --hostname=VampireTheMasqueradeBloodlines \
    --image="${IMAGE:-VampireTheMasqueradeBloodlines.img}" \
    --link-journal=no \
    --machine="VampireTheMasqueradeBloodlines-$USER" \
    --overlay=+/VTMB/Vampire/maps/graphs::/VTMB/Vampire/maps/graphs \
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
