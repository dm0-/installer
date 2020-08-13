options+=([arch]=x86_64 [distro]=fedora [executable]=1 [release]=32 [squash]=1)

packages+=(
        pulseaudio-libs
        SDL2_mixer
)

packages_buildroot+=(cmake gcc-c++ git-core ninja-build SDL2_mixer-devel)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        script << 'EOF'
curl -L 'https://thelettervsixtim.es/makeandplay/data.zip' > data.zip
test x$(sha256sum data.zip | sed -n '1s/ .*//p') = \
    x6fae3cdec06062d05827d4181c438153f3ea3900437a44db73bcd29799fe57e0
git clone --branch=master https://github.com/TerryCavanagh/VVVVVV.git
mkdir VVVVVV/desktop_version/build ; cd VVVVVV/desktop_version/build
git reset --hard 76b326aac336158607137fe772152db0994ce4a7
cmake -GNinja -DCMAKE_INSTALL_PREFIX:PATH=/usr ..
exec ninja -j"$(nproc)" all
EOF
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

        cp -pt root VVVVVV/desktop_version/build/VVVVVV
        cp -pt root data.zip

        ln -fns VVVVVV root/init

        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/VVVVVV" ] ||
mkdir -p "$XDG_DATA_HOME/VVVVVV"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/VVVVVV:/home/$USER/.local/share/VVVVVV" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/ \
    --hostname=VVVVVV \
    --image="${IMAGE:-VVVVVV.img}" \
    --link-journal=no \
    --machine="VVVVVV-$USER" \
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
