options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=32 [squash]=1)

packages+=(
        alsa-plugins-pulseaudio
        libGLU
        mesa-dri-drivers
        which
)

packages_buildroot+=(tar)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        $cp "${1:-FTL.1.5.4.tar.gz}" "$output/FTL.tgz"
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

        local -r drop=$(test "x${options[arch]}" = xi686 && echo amd64)
        tar --exclude="${drop:-x86}" -xf FTL.tgz -C root
        rm -f FTL.tgz

        cat << 'EOF' > root/init && chmod 0755 root/init
#!/bin/sh -eu
mkdir -p "$HOME/.local/share"
ln -fns /tmp/save "$HOME/.local/share/FasterThanLight"
exec ./FTL "$@"
EOF

        sed "${drop:+s/-64//}" << 'EOF' > launch.sh && chmod 0755 launch.sh
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
    /init "$@"
EOF
}
