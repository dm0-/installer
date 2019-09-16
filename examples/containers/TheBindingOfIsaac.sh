options+=([arch]=x86_64 [distro]=fedora [nspawn]=1 [release]=30 [squash]=1)

packages+=(
        alsa-plugins-pulseaudio
        gtk2
        libcurl
        libGL
        nss
)

packages_buildroot+=(tar unzip)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        $cp "${1:-the_binding_of_isaac_wrath_of_the_lamb-linux-1.48-1355426233.swf.zip}" "$output/BOI.zip"
        test -n "${2-}" && $cp "$2" "$output/flashplayer.tgz" ||
        $curl -L https://fpdownload.macromedia.com/pub/flashplayer/updaters/32/flash_player_sa_linux.x86_64.tar.gz > "$output/flashplayer.tgz"
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

        tar -C root/usr/bin -xzf flashplayer.tgz flashplayer
        mkdir -p root/etc/adobe
        cat << 'EOF' > root/etc/adobe/mms.cfg
AutoUpdateDisable = 1
AVHardwareDisable = 1
OverrideGPUValidation = 1
EOF
        unzip -p BOI.zip -x '__MACOSX/*' > root/boiwotl.swf

        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/TheBindingOfIsaac" ] ||
mkdir -p "$XDG_DATA_HOME/TheBindingOfIsaac"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/TheBindingOfIsaac:/tmp/save" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir="/home/$USER" \
    --hostname=TheBindingOfIsaac \
    --image="${IMAGE:-TheBindingOfIsaac.img}" \
    --link-journal=no \
    --machine="TheBindingOfIsaac-$USER" \
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
mkdir -p "$HOME/.macromedia"
ln -fns /tmp/save "$HOME/.macromedia/Flash_Player"
exec flashplayer /boiwotl.swf "$@"
END
EOF
}
