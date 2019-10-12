options+=([arch]=i686 [distro]=fedora [executable]=1 [release]=30 [squash]=1)

packages+=(
        mesa-dri-drivers
        wine-core
        wine-pulseaudio
)

packages_buildroot+=(innoextract jq)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        $cp "${1:-setup_ghost_master_20171020_(15806).exe}" "$output/install.exe"
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

        (cd root/root ; exec innoextract ../../install.exe)
        rm -f install.exe
        wine_gog_script /GM < root/root/app/goggame-1207658687.script > reg.sh
        mv root/root/app/GhostData root/GM

        sed $'/^REG_SCRIPT/{rreg.sh\nd;}' << 'EOG' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

for dir in SaveGames ScreenShots
do
        [ -e "${XDG_DATA_HOME:=$HOME/.local/share}/GhostMaster/$dir" ] ||
        mkdir -p "$XDG_DATA_HOME/GhostMaster/$dir"
done

exec sudo systemd-nspawn \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/GM \
    --hostname=GhostMaster \
    --image="${IMAGE:-GhostMaster.img}" \
    --link-journal=no \
    --machine="GhostMaster-$USER" \
    --overlay="+/GM:$XDG_DATA_HOME/GhostMaster:/GM" \
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
(unset DISPLAY
REG_SCRIPT
ln -fns /GM "$HOME/.wine/dosdevices/c:/users/Public/Documents/Ghost Master"
)
exec wine explorer /desktop=virtual,1600x1200 /GM/ghost.exe "$@"
EOF
EOG
}
