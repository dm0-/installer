options+=([arch]=i686 [distro]=fedora [nspawn]=1 [release]=30 [squash]=1)

packages+=(
        mesa-dri-drivers
        wine-core
        wine-pulseaudio
)

packages_buildroot+=(innoextract jq)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        $cp "${1:-setup_arx_fatalis_1.21_(21994).exe}" "$output/install.exe"
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

        (mkdir -p root/arx/Save ; cd root/arx ; exec innoextract ../../install.exe)
        rm -fr install.exe root/arx/{app,commonappdata,tmp}
        cp root/arx/cfg_default.ini root/arx/cfg_default.ini.orig
        wine_gog_script /arx < root/arx/goggame-1207658680.script > reg.sh

        sed $'/^REG_SCRIPT/{rreg.sh\nd;}' << 'EOG' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/arx/Save" ] ||
mkdir -p "$XDG_DATA_HOME/arx/Save"

[ -e "$XDG_DATA_HOME/arx/cfg_default.ini" ] ||
touch "$XDG_DATA_HOME/arx/cfg_default.ini"

exec sudo systemd-nspawn \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/arx \
    --hostname=ArxFatalis \
    --image="${IMAGE:-ArxFatalis.img}" \
    --link-journal=no \
    --machine="ArxFatalis-$USER" \
    --overlay="+/arx:$XDG_DATA_HOME/arx:/arx" \
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
test -s cfg_default.ini || cat cfg_default.ini.orig > cfg_default.ini
(unset DISPLAY
REG_SCRIPT
wine reg add 'HKEY_CURRENT_USER\Software\Wine\X11 Driver' /v GrabFullscreen /t REG_SZ /d Y /f
)
exec wine explorer /desktop=virtual,1920x1200 /arx/ARX.exe "$@"
EOF
EOG
}
