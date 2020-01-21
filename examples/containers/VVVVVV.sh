options+=([arch]=x86_64 [distro]=fedora [executable]=1 [release]=31 [squash]=1)

packages+=(
        pulseaudio-libs
        SDL2_mixer
)

packages_buildroot+=(cmake gcc-c++ git-core ninja-build p7zip SDL2_mixer-devel)
function customize_buildroot() {
        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        script << 'EOF'
curl -L 'http://www.flibitijibibo.com/vvvvvv-mp-11192019-bin' > vvvvvv-mp.bin
test x$(sha256sum vvvvvv-mp.bin | sed -n '1s/ .*//p') = \
    x9f7307e111b4f8e19c02d6a0fbf4b43b93a17f341468993fa4fa0c4eae42fc4a
7za -ovvvvvv-mp x vvvvvv-mp.bin
git clone --branch=master https://github.com/TerryCavanagh/VVVVVV.git
mkdir VVVVVV/desktop_version/build ; cd VVVVVV/desktop_version/build
git reset --hard b6ca9ea039a47027b6e59d087e89e242583833ad
cmake -GNinja -DCMAKE_INSTALL_PREFIX:PATH=/usr ..
exec ninja -j$(nproc) all
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
        cp -pt root vvvvvv-mp/data/data.zip

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
    /VVVVVV "$@"
EOF
}
