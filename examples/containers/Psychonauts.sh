options+=([arch]=i686 [distro]=opensuse [executable]=1 [squash]=1)

packages+=(
        alsa-plugins-pulse
        desktop-data-openSUSE
        libXcursor1
        Mesa-dri{,-nouveau}
        Mesa-libGL1
)

packages_buildroot+=(expect)
function customize_buildroot() {
        $sed -i -e '/^[# ]*rpm.install.excludedocs/s/^[# ]*//' "$buildroot/etc/zypp/zypp.conf"
        $cp "${1:-psychonauts-linux-05062013-bin}" "$output/install"
        $chmod 0755 "$output/install"
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

        cp install root/install
        expect << 'EOF'
set timeout -1
spawn chroot root /install
expect "> "
send -- "/psychonauts\n"
expect eof
EOF
        rm -f root/install install

        cat << 'EOG' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/Psychonauts" ] ||
mkdir -p "$XDG_DATA_HOME/Psychonauts"

declare -r console=$(systemd-nspawn --help | grep -Foe --console=)

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/Psychonauts:/tmp/save" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir="/home/$USER" \
    ${console:+--console=pipe} \
    --hostname=Psychonauts \
    --image="${IMAGE:-Psychonauts.img}" \
    --link-journal=no \
    --machine="Psychonauts-$USER" \
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
mkdir -p "$HOME/.local/share"
ln -fns /tmp/save "$HOME/.local/share/Psychonauts"
test -e /tmp/save/DisplaySettings.ini ||
cp -t /tmp/save /psychonauts/DisplaySettings.ini
exec /psychonauts/Psychonauts "$@"
EOF
EOG
}
