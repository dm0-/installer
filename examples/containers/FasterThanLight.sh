options=([arch]=x86_64 [distro]=fedora [nspawn]=1 [release]=30 [squash]=1)

packages+=(
        alsa-plugins-pulseaudio
        libGL
        libGLU
        mesa-dri-drivers
        which
)

packages_buildroot+=(tar)
function customize_buildroot() {
        ln FTL.1.5.4.tar.gz "$output/FTL.tgz"
}

function customize() {
        exclude_paths+=(
                root
                usr/{lib,share}/locale
                usr/lib/systemd
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
                var/'*'
        )

        tar --exclude=x86 -xf FTL.tgz -C root

        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/FasterThanLight" ] ||
mkdir -p "$XDG_DATA_HOME/FasterThanLight"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/FasterThanLight:/tmp/save" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/FTL \
    --hostname=FasterThanLight \
    --image="${IMAGE:-FasterThanLight.img}" \
    --link-journal=no \
    --machine="FasterThanLight-$USER" \
    --personality=x86-64 \
    --private-network \
    --read-only \
    --setenv="DISPLAY=$DISPLAY" \
    --setenv="HOME=/home/$USER" \
    --setenv=PULSE_COOKIE=/tmp/.pulse/cookie \
    --setenv=PULSE_SERVER=/tmp/.pulse/native \
    --tmpfs=/home \
    --user="$USER" \
    /bin/sh -euo pipefail /dev/stdin "$@" << 'END'
mkdir -p "$HOME/.local/share"
ln -fns /tmp/save "$HOME/.local/share/FasterThanLight"
exec ./FTL "$@"
END
EOF
}
