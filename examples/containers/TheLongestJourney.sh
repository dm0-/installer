# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game The Longest Journey.
# Two arguments are required, the paths to both Inno Setup installer fragments
# from GOG (with the exe file first followed by the bin file).
#
# Since the game is only for Windows, this simply installs a 32-bit Wine
# container and extracts files from the installer.  Persistent game data is
# saved by binding paths from the calling user's XDG data directory over the
# game's save directory and configuration files.

options+=([arch]=i686 [distro]=opensuse [gpt]=1 [squash]=1)

packages+=(
        Mesa-dri{,-nouveau}
        wine
)

packages_buildroot+=(innoextract jq)

function initialize_buildroot() {
        $cp "${1:-setup_the_longest_journey_142_lang_update_(24607).exe}" "$output/install.exe"
        $cp "${2:-setup_the_longest_journey_142_lang_update_(24607)-1.bin}" "$output/install-1.bin"
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

        innoextract -md root/TLJ install.exe
        wine_gog_script /TLJ < root/TLJ/goggame-1207658794.script | sed 's/Z:/C:/g' > reg.sh
        rm -fr install{.exe,-1.bin} root/TLJ/{app,commonappdata,goggame*,manual.pdf,__redist,tlj_faq*}
        mkdir -p root/TLJ/Save
        cp root/TLJ/preferences.ini root/TLJ/preferences.ini.orig

        sed $'/^REG_SCRIPT/{rreg.sh\nd;}' << 'EOF' > root/init && chmod 0755 root/init
#!/bin/sh -eu
test -s preferences.ini || cat preferences.ini.orig > preferences.ini
(unset DISPLAY
REG_SCRIPT
)
ln -fst "$HOME/.wine/dosdevices/c:" /TLJ
exec wine explorer /desktop=virtual,640x480 /TLJ/game.exe "$@"
EOF

        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/TheLongestJourney/Save" ] ||
mkdir -p "$XDG_DATA_HOME/TheLongestJourney/Save"

[ -e "$XDG_DATA_HOME/TheLongestJourney/preferences.ini" ] ||
touch "$XDG_DATA_HOME/TheLongestJourney/preferences.ini"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/TheLongestJourney/Save:/TLJ/Save" \
    --bind="$XDG_DATA_HOME/TheLongestJourney/preferences.ini:/TLJ/preferences.ini" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/TLJ \
    --hostname=TheLongestJourney \
    --image="${IMAGE:-TheLongestJourney.img}" \
    --link-journal=no \
    --machine="TheLongestJourney-$USER" \
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
