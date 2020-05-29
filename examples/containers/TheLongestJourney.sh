options+=([arch]=i686 [distro]=opensuse [executable]=1 [squash]=1)

packages+=(
        Mesa-dri{,-nouveau}
        wine
)

packages_buildroot+=(innoextract jq)
function customize_buildroot() {
        $sed -i -e '/^[# ]*rpm.install.excludedocs/s/^[# ]*//' "$buildroot/etc/zypp/zypp.conf"
        $cp "${1:-setup_the_longest_journey_142_lang_update_(24607).exe}" "$output/install.exe"
        $cp "${2:-setup_the_longest_journey_142_lang_update_(24607)-1.bin}" "$output/install-1.bin"
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

        (mkdir -p root/TLJ/Save ; cd root/TLJ ; exec innoextract ../../install.exe)
        rm -fr install.exe install-1.bin root/TLJ/{app,commonappdata,tmp}
        cp root/TLJ/preferences.ini root/TLJ/preferences.ini.orig
        wine_gog_script /TLJ < root/TLJ/goggame-1207658794.script > reg.sh
        sed -i -e 's/Z:/C:/g' reg.sh

        sed $'/^REG_SCRIPT/{rreg.sh\nd;}' << 'EOG' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/TheLongestJourney/Save" ] ||
mkdir -p "$XDG_DATA_HOME/TheLongestJourney/Save"

[ -e "$XDG_DATA_HOME/TheLongestJourney/preferences.ini" ] ||
touch "$XDG_DATA_HOME/TheLongestJourney/preferences.ini"

declare -r console=$(systemd-nspawn --help | grep -Foe --console=)

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/TheLongestJourney/Save:/TLJ/Save" \
    --bind="$XDG_DATA_HOME/TheLongestJourney/preferences.ini:/TLJ/preferences.ini" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/TLJ \
    ${console:+--console=pipe} \
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
    /bin/sh -euo pipefail /dev/stdin "$@" << 'EOF'
test -s preferences.ini || cat preferences.ini.orig > preferences.ini
(unset DISPLAY
REG_SCRIPT
)
ln -fst "$HOME/.wine/dosdevices/c:" /TLJ
exec wine explorer /desktop=virtual,640x480 /TLJ/game.exe "$@"
EOF
EOG
}
