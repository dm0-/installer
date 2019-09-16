options+=([arch]=i686 [distro]=fedora [nspawn]=1 [release]=30 [squash]=1)

packages+=(
        mesa-dri-drivers
        wine-core
        wine-pulseaudio
)

packages_buildroot+=(innoextract jq)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        $cp "${1:-setup_rollercoaster_tycoon_deluxe_1.20.015_(17822).exe}" "$output/install.exe"
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
        wine_gog_script /RCT < root/root/app/goggame-1207658945.script > reg.sh
        mv root/root/app root/RCT

        sed $'/^REG_SCRIPT/{rreg.sh\nd;}' << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

for dir in Data 'Saved Games' Scenarios Tracks
do
        [ -e "${XDG_DATA_HOME:=$HOME/.local/share}/RollerCoasterTycoon/$dir" ] ||
        mkdir -p "$XDG_DATA_HOME/RollerCoasterTycoon/$dir"
done

exec sudo systemd-nspawn \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/RCT \
    --hostname=RollerCoasterTycoon \
    --image="${IMAGE:-RollerCoasterTycoon.img}" \
    --link-journal=no \
    --machine="RollerCoasterTycoon-$USER" \
    --overlay="+/RCT:$XDG_DATA_HOME/RollerCoasterTycoon:/RCT" \
    --personality=x86 \
    --private-network \
    --read-only \
    --setenv="DISPLAY=$DISPLAY" \
    --setenv="HOME=/home/$USER" \
    --setenv=PULSE_COOKIE=/tmp/.pulse/cookie \
    --setenv=PULSE_SERVER=/tmp/.pulse/native \
    --tmpfs=/home \
    --user="$USER" \
    /bin/sh -euo pipefail /dev/stdin "$@" << 'END'
(unset DISPLAY
REG_SCRIPT
)
exec wine explorer /desktop=virtual,1024x768 /RCT/RCT.EXE "$@"
END
EOF
}
