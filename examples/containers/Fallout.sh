# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game Fallout.  A single
# argument is required, the path to an Inno Setup installer from GOG.
#
# Since the game is only for Windows, this simply installs a 32-bit Wine
# container and extracts files from the installer.  Persistent game data is
# saved by mounting a path from the calling user's XDG data directory as an
# overlay over the game's Wine drive path and binding configuration files.

options+=([arch]=i686 [distro]=opensuse [gpt]=1 [squash]=1)

packages+=(
        Mesa-dri{,-nouveau}
        wine
)

packages_buildroot+=(innoextract)

function initialize_buildroot() {
        $cp "${1:-setup_fallout_2.1.0.18.exe}" "$output/install.exe"

        echo '%_install_langs %{nil}' >> "$buildroot/etc/rpm/macros"
        $sed -i -e '/^[# ]*rpm.install.excludedocs/s/^[# ]*//' "$buildroot/etc/zypp/zypp.conf"
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

        innoextract -md root/root install.exe
        rm -f install.exe
        mv root/root/app root/fallout
        sed '/^UAC_AWARE=/s/=1/=0/' root/fallout/f1_res.ini > root/fallout/f1_res.ini.orig
        cp root/fallout/fallout.cfg root/fallout/fallout.cfg.orig

        cat << 'EOF' > root/init ; chmod 0755 root/init
#!/bin/sh -eu
for file in f1_res.ini fallout.cfg
do test -s "$file" || cat "$file.orig" > "$file"
done
DISPLAY= wine hostname
exec wine explorer /desktop=virtual,1900x1200 /fallout/falloutwHR.exe "$@"
EOF

        cat << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/Fallout/SAVEGAME" ] ||
mkdir -p "$XDG_DATA_HOME/Fallout/SAVEGAME"

for file in f1_res.ini fallout.cfg
do
        [ -e "$XDG_DATA_HOME/Fallout/$file" ] ||
        touch "$XDG_DATA_HOME/Fallout/$file"
done

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/Fallout/SAVEGAME:/fallout/DATA/SAVEGAME" \
    --bind="$XDG_DATA_HOME/Fallout/f1_res.ini:/fallout/f1_res.ini" \
    --bind="$XDG_DATA_HOME/Fallout/fallout.cfg:/fallout/fallout.cfg" \
    --bind=/dev/dri \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    --bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}" \
    --chdir=/fallout \
    --hostname=Fallout \
    --image="${IMAGE:-Fallout.img}" \
    --link-journal=no \
    --machine="Fallout-$USER" \
    --overlay="+/fallout/DATA/MAPS:$XDG_DATA_HOME/Fallout/SAVEGAME:/fallout/DATA/MAPS" \
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
